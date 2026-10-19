/// Pruebas del cliente HTTP de Steam con un cliente simulado.
///
/// Comprueban, entre otras cosas, que la única credencial es el token de
/// sesión (que viaja como `access_token` hacia `api.steampowered.com` y jamás
/// hacia `steamcommunity.com`), que los perfiles públicos se leen del XML de
/// Steam Community **sin ninguna credencial**, que un 429 abre una ventana de
/// espera, que la interpretación de 401/403 depende del endpoint y que se
/// evitan solicitudes duplicadas.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/data/steam/steam_api_client.dart';
import 'package:watap_mobile/data/steam/steam_api_errors.dart';

import '../helpers/test_support.dart';

const String _token = 'token-de-sesion-prueba-123';

const String _recentJson =
    '{"response":{"total_count":1,"games":[{"appid":570,"name":"Dota 2",'
    '"playtime_2weeks":100,"playtime_forever":1000}]}}';

SteamApiClient _client(
  FakeHttpClient fake, {
  String? token = _token,
  int maxConcurrent = 3,
  Duration timeout = const Duration(seconds: 5),
}) {
  final SteamApiClient client = SteamApiClient(
    httpClient: fake.build(),
    timeout: timeout,
    maxConcurrentRequests: maxConcurrent,
    maxTransientRetries: 0,
  );
  client.setAccessToken(token);
  return client;
}

Matcher _throwsSteamError(SteamApiErrorKind kind) => throwsA(
      isA<SteamApiException>().having((SteamApiException e) => e.kind, 'kind', kind),
    );

void main() {
  group('autenticación por token de sesión', () {
    test('hasAccessToken refleja si hay token configurado', () {
      final SteamApiClient client = _client(
        FakeHttpClient((http.Request _) => jsonResponse('{}')),
      );
      expect(client.hasAccessToken, isTrue);
      client.setAccessToken(null);
      expect(client.hasAccessToken, isFalse);
      client.dispose();
    });

    test('el token viaja como access_token hacia api.steampowered.com',
        () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => jsonResponse(_recentJson));
      final SteamApiClient client = _client(fake);

      await client.fetchRecentlyPlayedGames('76561198000000000');

      final RecordedRequest recorded = fake.requests.single;
      expect(recorded.uri.host, 'api.steampowered.com');
      expect(recorded.uri.queryParameters['access_token'], _token);
      expect(recorded.apiKeyHeader, isNull,
          reason: 'WATAP no envía ninguna cabecera de credencial.');
      expect(recorded.hasKeyInUrl, isFalse);
      client.dispose();
    });

    test('los perfiles públicos se leen del XML sin ninguna credencial',
        () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) => xmlResponse(communityProfileXmlBody()),
      );
      final SteamApiClient client = _client(fake);

      final List<SteamPlayerSummary> profiles =
          await client.fetchPublicProfiles(<String>['76561198000000000']);

      // ISteamUser exige key= (WATAP no usa claves): se consulta el XML.
      final RecordedRequest recorded = fake.requests.single;
      expect(recorded.uri.host, 'steamcommunity.com');
      expect(recorded.uri.path, '/profiles/76561198000000000');
      expect(recorded.uri.queryParameters['xml'], '1');
      expect(recorded.uri.queryParameters.containsKey('access_token'), isFalse,
          reason: 'El token jamás se envía a steamcommunity.com.');
      expect(recorded.apiKeyHeader, isNull);
      expect(profiles.single.personaName, 'Ana');
      expect(profiles.single.communityVisibilityState, 3);
      expect(profiles.single.avatarUrl, isNotNull);
      client.dispose();
    });

    test('un perfil inexistente en el XML se omite sin tumbar el lote', () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => xmlResponse(communityProfileNotFoundXml));
      final SteamApiClient client = _client(fake);

      final List<SteamPlayerSummary> profiles =
          await client.fetchPublicProfiles(<String>['76561198000000000']);

      expect(profiles, isEmpty,
          reason: 'El llamador mostrará «perfil no encontrado» con el vacío.');
      client.dispose();
    });

    test('un XML inesperado se traduce como respuesta malformada, no como '
        'perfil inválido', () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => xmlResponse('<html>?</html>'));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchPublicProfiles(<String>['76561198000000000']),
        _throwsSteamError(SteamApiErrorKind.malformedResponse),
      );
      client.dispose();
    });

    test('un 401 del XML público es un bloqueo del servidor, no la sesión',
        () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => http.Response('', 401));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchPublicProfiles(<String>['76561198000000000']),
        _throwsSteamError(SteamApiErrorKind.http),
      );
      client.dispose();
    });

    test('el nombre personalizado se resuelve con el XML público', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) =>
            xmlResponse(communityProfileXmlBody(steamId64: '76561198000000077')),
      );
      final SteamApiClient client = _client(fake);

      final VanityResolution result = await client.resolveVanityUrl('ana');

      expect(result.success, isTrue);
      expect(result.steamId64, '76561198000000077');
      final RecordedRequest recorded = fake.requests.single;
      expect(recorded.uri.host, 'steamcommunity.com');
      expect(recorded.uri.path, '/id/ana');
      expect(recorded.uri.queryParameters['xml'], '1');
      expect(recorded.uri.queryParameters.containsKey('access_token'), isFalse,
          reason: 'El token jamás se envía a steamcommunity.com.');
      client.dispose();
    });

    test('un nombre personalizado inexistente da un mensaje claro', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) => xmlResponse(communityProfileNotFoundXml),
      );
      final SteamApiClient client = _client(fake);

      final VanityResolution result = await client.resolveVanityUrl('nadie');

      expect(result.success, isFalse);
      expect(result.messageEs, contains('No existe ningún perfil'));
      client.dispose();
    });

    test('sin sesión, la consulta de actividad se bloquea antes de salir',
        () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => jsonResponse('{}'));
      final SteamApiClient client = _client(fake, token: null);

      await expectLater(
        client.fetchRecentlyPlayedGames('76561198000000000'),
        _throwsSteamError(SteamApiErrorKind.incompleteConfiguration),
      );
      expect(fake.callCount, 0);
      client.dispose();
    });

    test('un 401 en la actividad indica privacidad o datos no disponibles',
        () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => http.Response('', 401));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchRecentlyPlayedGames('76561198000000000'),
        _throwsSteamError(SteamApiErrorKind.privateOrUnavailable),
      );
      client.dispose();
    });
  });

  group('consultas correctas', () {
    test('fetchRecentlyPlayedGames interpreta los juegos', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => jsonResponse(_recentJson));
      final SteamApiClient client = _client(fake);

      final result = await client.fetchRecentlyPlayedGames('76561198000000000');

      expect(result.isUsable, isTrue);
      expect(result.games.single.appId, 570);
      expect(result.games.single.playtime2Weeks, 100);
    });
  });

  group('limitación de solicitudes (429)', () {
    test('abre una ventana y no vuelve a llamar mientras esté activa', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) => http.Response('', 429, headers: <String, String>{'retry-after': '45'}),
      );
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchRecentlyPlayedGames('76561198000000000'),
        throwsA(
          isA<SteamApiException>()
              .having((SteamApiException e) => e.kind, 'kind', SteamApiErrorKind.rateLimited)
              .having((SteamApiException e) => e.retryAfter, 'retryAfter', const Duration(seconds: 45)),
        ),
      );
      expect(client.rateLimitedUntil, isNotNull);

      final int callsAfterFirst = fake.callCount;
      await expectLater(
        client.fetchRecentlyPlayedGames('76561198000000001'),
        _throwsSteamError(SteamApiErrorKind.rateLimited),
      );
      expect(fake.callCount, callsAfterFirst);
    });
  });

  group('interpretación de 401/403 por endpoint', () {
    test('401 en la actividad significa privacidad o no disponible', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => http.Response('', 401));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchRecentlyPlayedGames('76561198000000000'),
        _throwsSteamError(SteamApiErrorKind.privateOrUnavailable),
      );
    });

    test('403 en la actividad significa privacidad o no disponible', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => http.Response('', 403));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchRecentlyPlayedGames('76561198000000000'),
        _throwsSteamError(SteamApiErrorKind.privateOrUnavailable),
      );
    });

    test('401/403 en el XML público es error HTTP genérico', () async {
      for (final int status in <int>[401, 403]) {
        final FakeHttpClient fake =
            FakeHttpClient((http.Request _) => http.Response('', status));
        final SteamApiClient client = _client(fake);

        await expectLater(
          client.fetchPublicProfiles(<String>['76561198000000000']),
          _throwsSteamError(SteamApiErrorKind.http),
        );
        client.dispose();
      }
    });
  });

  group('otros códigos', () {
    test('400 se interpreta como petición rechazada', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => http.Response('', 400));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchPublicProfiles(<String>['76561198000000000']),
        throwsA(
          isA<SteamApiException>()
              .having((SteamApiException e) => e.kind, 'kind', SteamApiErrorKind.http)
              .having((SteamApiException e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });

    test('500 se marca como error HTTP sin filtrar el cuerpo', () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => http.Response('detalle interno', 500));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchRecentlyPlayedGames('76561198000000000'),
        throwsA(
          isA<SteamApiException>()
              .having((SteamApiException e) => e.kind, 'kind', SteamApiErrorKind.http)
              .having((SteamApiException e) => e.technicalDetail, 'technicalDetail', isNull),
        ),
      );
    });

    test('una respuesta 200 vacía falla al interpretarse', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => jsonResponse(''));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchPublicProfiles(<String>['76561198000000000']),
        _throwsSteamError(SteamApiErrorKind.malformedResponse),
      );
    });
  });

  group('deduplicación y concurrencia', () {
    test('dos consultas idénticas simultáneas comparten una sola solicitud', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => jsonResponse(_recentJson))
        ..delay = const Duration(milliseconds: 60);
      final SteamApiClient client = _client(fake);

      final List<Object?> results = await Future.wait(<Future<Object?>>[
        client.fetchRecentlyPlayedGames('76561198000000000'),
        client.fetchRecentlyPlayedGames('76561198000000000'),
      ]);

      expect(results, hasLength(2));
      expect(fake.callCount, 1);
    });

    test('respeta el límite de solicitudes simultáneas', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => jsonResponse(_recentJson))
        ..delay = const Duration(milliseconds: 40);
      final SteamApiClient client = _client(fake, maxConcurrent: 2);

      await Future.wait<Object?>(
        List<Future<Object?>>.generate(
          5,
          (int i) => client.fetchRecentlyPlayedGames(
            '7656119800000${i.toString().padLeft(4, '0')}',
          ),
        ),
      );

      expect(fake.callCount, 5);
      expect(fake.maxConcurrentSeen, lessThanOrEqualTo(2));
    });
  });
}
