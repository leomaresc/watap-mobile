/// Pruebas del cliente HTTP de Steam con un cliente simulado.
///
/// Comprueban, entre otras cosas, que la clave viaja en el encabezado y nunca en
/// la URL, que un 429 abre una ventana de espera, que la interpretación de
/// 401/403 depende del endpoint y que se evitan solicitudes duplicadas.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watap_mobile/data/steam/steam_api_client.dart';
import 'package:watap_mobile/data/steam/steam_api_errors.dart';

import '../helpers/test_support.dart';

const String _key = 'clave-de-prueba-1234567890abcdef';

String _summariesJson(List<String> ids, {int visibility = 3}) => jsonEncode(
      <String, Object?>{
        'response': <String, Object?>{
          'players': ids
              .map((String id) => <String, Object?>{
                    'steamid': id,
                    'personaname': 'Jugador $id',
                    'communityvisibilitystate': visibility,
                  })
              .toList(),
        },
      },
    );

const String _recentJson =
    '{"response":{"total_count":1,"games":[{"appid":570,"name":"Dota 2",'
    '"playtime_2weeks":100,"playtime_forever":1000}]}}';

SteamApiClient _client(
  FakeHttpClient fake, {
  String? key = _key,
  int maxConcurrent = 3,
  Duration timeout = const Duration(seconds: 5),
}) {
  final SteamApiClient client = SteamApiClient(
    httpClient: fake.build(),
    timeout: timeout,
    maxConcurrentRequests: maxConcurrent,
    maxTransientRetries: 0,
  );
  client.setApiKey(key);
  return client;
}

Matcher _throwsSteamError(SteamApiErrorKind kind) => throwsA(
      isA<SteamApiException>().having((SteamApiException e) => e.kind, 'kind', kind),
    );

void main() {
  group('encabezado y secreto', () {
    test('envía la clave en x-webapi-key y nunca en la URL', () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request request) => jsonResponse(_summariesJson(<String>['76561198000000000'])));
      final SteamApiClient client = _client(fake);

      await client.fetchPlayerSummaries(<String>['76561198000000000']);

      final RecordedRequest recorded = fake.requests.single;
      expect(recorded.apiKeyHeader, _key);
      expect(recorded.hasKeyInUrl, isFalse);
      expect(recorded.uri.toString(), isNot(contains(_key)));
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

  group('configuración incompleta', () {
    test('sin clave no se envía ninguna solicitud', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => jsonResponse('{}'));
      final SteamApiClient client = _client(fake, key: null);

      await expectLater(
        client.fetchPlayerSummaries(<String>['76561198000000000']),
        _throwsSteamError(SteamApiErrorKind.incompleteConfiguration),
      );
      expect(fake.callCount, 0);
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
    test('401 en GetPlayerSummaries significa clave inválida', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => http.Response('', 401));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchPlayerSummaries(<String>['76561198000000000']),
        _throwsSteamError(SteamApiErrorKind.invalidApiKey),
      );
    });

    test('403 en GetPlayerSummaries significa clave inválida', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => http.Response('', 403));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchPlayerSummaries(<String>['76561198000000000']),
        _throwsSteamError(SteamApiErrorKind.invalidApiKey),
      );
    });

    test('401 en GetRecentlyPlayedGames significa privacidad o no disponible', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => http.Response('', 401));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchRecentlyPlayedGames('76561198000000000'),
        _throwsSteamError(SteamApiErrorKind.privateOrUnavailable),
      );
    });
  });

  group('otros códigos', () {
    test('400 se interpreta como perfil no válido', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => http.Response('', 400));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchPlayerSummaries(<String>['76561198000000000']),
        _throwsSteamError(SteamApiErrorKind.invalidProfile),
      );
    });

    test('500 se marca como error HTTP sin filtrar el cuerpo', () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => http.Response('detalle interno', 500));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchPlayerSummaries(<String>['76561198000000000']),
        _throwsSteamError(SteamApiErrorKind.http),
      );
    });

    test('una respuesta 200 vacía falla al interpretarse', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => jsonResponse(''));
      final SteamApiClient client = _client(fake);

      await expectLater(
        client.fetchPlayerSummaries(<String>['76561198000000000']),
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
            '76561198000000${i.toString().padLeft(3, '0')}',
          ),
        ),
      );

      expect(fake.callCount, 5);
      expect(fake.maxConcurrentSeen, lessThanOrEqualTo(2));
    });
  });

  group('verifyApiKey', () {
    test('sin clave no realiza ninguna consulta', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => jsonResponse('{}'));
      final SteamApiClient client = _client(fake, key: null);

      final ApiKeyCheckResult result = await client.verifyApiKey();

      expect(result.keyAccepted, isFalse);
      expect(fake.callCount, 0);
    });

    test('con clave usa un perfil público conocido como sonda', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request request) => jsonResponse(
          _summariesJson(
            (request.url.queryParameters['steamids'] ?? '').split(','),
          ),
        ),
      );
      final SteamApiClient client = _client(fake);

      final ApiKeyCheckResult result = await client.verifyApiKey();

      expect(result.keyAccepted, isTrue);
      expect(fake.requestsTo('/ISteamUser/GetPlayerSummaries/'), hasLength(1));
    });

    test('un 401 se interpreta como clave rechazada', () async {
      final FakeHttpClient fake = FakeHttpClient((http.Request _) => http.Response('', 401));
      final SteamApiClient client = _client(fake);

      final ApiKeyCheckResult result = await client.verifyApiKey();

      expect(result.keyAccepted, isFalse);
      expect(result.technicalDetail, contains('401'));
    });

    test('informa si el perfil indicado existe o no', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) => jsonResponse(_summariesJson(<String>['76561198000000000'])),
      );
      final SteamApiClient client = _client(fake);

      final ApiKeyCheckResult found =
          await client.verifyApiKey(steamId64: '76561198000000000');
      expect(found.keyAccepted, isTrue);
      expect(found.profileFound, isTrue);

      final ApiKeyCheckResult missing =
          await client.verifyApiKey(steamId64: '76561198000000099');
      expect(missing.keyAccepted, isTrue);
      expect(missing.profileFound, isFalse);
    });
  });
}
