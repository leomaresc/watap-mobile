/// Pruebas del cliente, los parsers y la sincronización del grupo familiar.
///
/// Ninguna prueba realiza llamadas reales a Steam: el cliente HTTP está
/// simulado y la base de datos es SQLite en memoria.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/data/steam/family_groups_client.dart';
import 'package:watap_mobile/data/steam/steam_api_errors.dart';
import 'package:watap_mobile/data/steam/steam_json_parsers.dart';
import 'package:watap_mobile/services/family_group_sync.dart';
import 'package:watap_mobile/state/app_controller.dart';

import '../helpers/test_support.dart';

const String _token = 'tok-de-una-sesion-9';
const String _groupId = '12345678901234567';

/// Respuesta de `GetFamilyGroupForUser` con grupo.
const String _forUserJson =
    '{"response":{"family_groupid":"$_groupId"}}';

/// Respuesta de `GetFamilyGroup` con dos integrantes.
const String _groupJson = '''
{"response":{"name":"Familia Salazar","members":[
  {"steamid":"76561198000000000","role":1,"time_joined":1700000000},
  {"steamid":"76561198000000009","role":0},
  {"steamid":"76561198000000000"},
  {"steamid":"abc"}
],"free_spots":3}}
''';

/// Respuestas de `GetPlayerSummaries` para los dos integrantes.
const String _summariesJson =
    '{"response":{"players":['
    '{"steamid":"76561198000000000","personaname":"Ana",'
    '"avatarfull":"https://a/1.jpg"},'
    '{"steamid":"76561198000000009","personaname":"Bruno"}'
    ']}}';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabaseFactory();

  // --- Parsers --------------------------------------------------------------

  group('parseFamilyGroupForUser', () {
    test('devuelve el identificador del grupo', () {
      final FamilyGroupForUser result = parseFamilyGroupForUser(_forUserJson);
      expect(result.hasGroup, isTrue);
      expect(result.familyGroupId, _groupId);
    });

    test('una cuenta sin grupo devuelve null', () {
      final FamilyGroupForUser result =
          parseFamilyGroupForUser('{"response":{}}');
      expect(result.hasGroup, isFalse);
      expect(result.familyGroupId, isNull);
    });

    test('un JSON inválido lanza error tipado', () {
      expect(
        () => parseFamilyGroupForUser('esto no es json'),
        throwsA(
          isA<SteamApiException>().having(
            (SteamApiException e) => e.kind,
            'kind',
            SteamApiErrorKind.malformedResponse,
          ),
        ),
      );
    });
  });

  group('parseFamilyGroup', () {
    test('extrae nombre, integrantes y descarta duplicados e inválidos', () {
      final FamilyGroup group =
          parseFamilyGroup(_groupJson, familyGroupId: _groupId);
      expect(group.name, 'Familia Salazar');
      expect(group.members, hasLength(2));
      expect(group.memberSteamIds, <String>[
        '76561198000000000',
        '76561198000000009',
      ]);
      expect(group.members.first.role, 1);
      expect(group.members.first.timeJoinedUnix, 1700000000);
      expect(group.freeSpots, 3);
    });

    test('una respuesta sin integrantes queda vacía', () {
      final FamilyGroup group =
          parseFamilyGroup('{"response":{}}', familyGroupId: _groupId);
      expect(group.members, isEmpty);
      expect(group.name, isNull);
    });
  });

  // --- Cliente ---------------------------------------------------------------

  group('FamilyGroupsClient', () {
    test('Steam exige GET: el token viaja en la URL, sin clave ni cuerpo', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) => jsonResponse(_forUserJson),
      );
      final FamilyGroupsClient client =
          FamilyGroupsClient(httpClient: fake.build());

      await client.getFamilyGroupForUser(_token);
      client.dispose();

      final RecordedRequest request = fake.requests.single;
      expect(request.request.method, 'GET',
          reason: 'El POST responde HTTP 405 en este servicio.');
      expect(request.uri.path, contains('GetFamilyGroupForUser'));
      expect(request.uri.queryParameters['access_token'], _token);
      expect(request.uri.queryParameters['format'], 'json');
      expect(request.hasKeyInUrl, isFalse,
          reason: 'Este servicio no acepta claves de Web API.');
      expect(request.body, isEmpty, reason: 'Un GET no lleva cuerpo.');
    });

    test('GetFamilyGroup envía token e identificador en la URL', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) => jsonResponse(_groupJson),
      );
      final FamilyGroupsClient client =
          FamilyGroupsClient(httpClient: fake.build());

      final FamilyGroup group = await client.getFamilyGroup(
        accessToken: _token,
        familyGroupId: _groupId,
      );
      client.dispose();

      expect(group.members, hasLength(2));
      final RecordedRequest request = fake.requests.single;
      expect(request.request.method, 'GET');
      expect(request.uri.queryParameters['access_token'], _token);
      expect(request.uri.queryParameters['family_groupid'], _groupId);
      expect(request.hasKeyInUrl, isFalse);
    });

    test('401/403 se traducen a token caducado', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) => jsonResponse('{"error":"nope"}', status: 401),
      );
      final FamilyGroupsClient client =
          FamilyGroupsClient(httpClient: fake.build());

      await expectLater(
        client.getFamilyGroupForUser(_token),
        throwsA(
          isA<SteamApiException>().having(
            (SteamApiException e) => e.kind,
            'kind',
            SteamApiErrorKind.invalidCredentials,
          ),
        ),
      );
      client.dispose();
    });

    test('eresult de token expirado en cuerpo con HTTP 200 se detecta', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) => jsonResponse(jsonEncode(<String, Object?>{
          'eresult': 21,
        })),
      );
      final FamilyGroupsClient client =
          FamilyGroupsClient(httpClient: fake.build());

      await expectLater(
        client.getFamilyGroupForUser(_token),
        throwsA(
          isA<SteamApiException>().having(
            (SteamApiException e) => e.kind,
            'kind',
            SteamApiErrorKind.invalidCredentials,
          ),
        ),
      );
      client.dispose();
    });

    test('405 explica que los endpoints pueden haber cambiado', () async {
      final FakeHttpClient fake = FakeHttpClient(
        (http.Request _) => jsonResponse('{}', status: 405),
      );
      final FamilyGroupsClient client =
          FamilyGroupsClient(httpClient: fake.build());

      await expectLater(
        client.getFamilyGroupForUser(_token),
        throwsA(
          isA<SteamApiException>()
              .having((SteamApiException e) => e.statusCode, 'statusCode', 405)
              .having(
                (SteamApiException e) => e.messageEs,
                'messageEs',
                contains('405'),
              ),
        ),
      );
      client.dispose();
    });
  });

  // --- Sincronización --------------------------------------------------------

  group('FamilyGroupSyncService', () {
    test('importa los integrantes con nombre y avatar', () async {
      final TestEnvironment env = await buildTestEnvironment(
        httpClient: FakeHttpClient(
          (http.Request request) {
            final String path = request.url.path;
            if (path.contains('GetFamilyGroupForUser')) {
              return jsonResponse(_forUserJson);
            }
            if (path.contains('GetFamilyGroup')) {
              return jsonResponse(_groupJson);
            }
            if (path.contains('GetPlayerSummaries')) {
              return jsonResponse(_summariesJson);
            }
            return jsonResponse('{}');
          },
        ),
        apiKey: 'clave-de-prueba-1234567890abcdef',
        steamToken: _token,
      );
      addTearDown(env.dispose);

      final FamilySyncOutcome outcome =
          await env.controller.syncFamilyGroup();

      expect(outcome.success, isTrue);
      expect(outcome.total, 2);
      expect(outcome.added, 2);
      expect(outcome.groupName, 'Familia Salazar');
      expect(env.controller.profiles, hasLength(2));
      expect(
        env.controller.profiles.every((Profile p) => p.isFamilyMember),
        isTrue,
      );
      // El resumen completo se aplica a un solo integrante; el otro queda con
      // el identificador.
      final Profile? named = env.controller.profiles
          .cast<Profile?>()
          .firstWhere((Profile? p) => p!.steamId64 == '76561198000000000');
      expect(named!.personaName, 'Ana');
    });

    test('sin token no se consulta nada y se pide conectar', () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => jsonResponse('{}'));
      final TestEnvironment env = await buildTestEnvironment(
        httpClient: fake,
        apiKey: 'clave-de-prueba-1234567890abcdef',
      );
      addTearDown(env.dispose);

      final FamilySyncOutcome outcome =
          await env.controller.syncFamilyGroup();

      expect(outcome.success, isFalse);
      expect(outcome.requiresConnect, isTrue);
      expect(fake.callCount, 0);
    });

    test('una cuenta sin grupo familiar lo indica sin borrar datos', () async {
      final TestEnvironment env = await buildTestEnvironment(
        httpClient: FakeHttpClient(
          (http.Request request) {
            if (request.url.path.contains('GetFamilyGroupForUser')) {
              return jsonResponse('{"response":{}}');
            }
            return jsonResponse('{}');
          },
        ),
        apiKey: 'clave-de-prueba-1234567890abcdef',
        steamToken: _token,
      );
      addTearDown(env.dispose);
      await env.controller.addProfile('76561198000000000');

      final FamilySyncOutcome outcome =
          await env.controller.syncFamilyGroup();

      expect(outcome.success, isFalse);
      expect(outcome.noGroup, isTrue);
      expect(env.controller.profiles, hasLength(1));
    });

    test('un grupo vacío no borra los integrantes existentes', () async {
      final TestEnvironment env = await buildTestEnvironment(
        httpClient: FakeHttpClient(
          (http.Request request) {
            if (request.url.path.contains('GetFamilyGroupForUser')) {
              return jsonResponse(_forUserJson);
            }
            if (request.url.path.contains('GetFamilyGroup')) {
              return jsonResponse('{"response":{"members":[]}}');
            }
            return jsonResponse('{}');
          },
        ),
        apiKey: 'clave-de-prueba-1234567890abcdef',
        steamToken: _token,
      );
      addTearDown(env.dispose);
      await env.controller.addProfile('76561198000000000');

      final FamilySyncOutcome outcome =
          await env.controller.syncFamilyGroup();

      expect(outcome.success, isFalse);
      expect(env.controller.profiles, hasLength(1),
          reason: 'Una respuesta vacía no debe vaciar la lista.');
    });

    test('los integrantes que salen del grupo se retiran', () async {
      bool first = true;
      final TestEnvironment env = await buildTestEnvironment(
        httpClient: FakeHttpClient(
          (http.Request request) {
            final String path = request.url.path;
            if (path.contains('GetFamilyGroupForUser')) {
              return jsonResponse(_forUserJson);
            }
            if (path.contains('GetFamilyGroup')) {
              // La primera vez hay dos; después, solo uno.
              final String body = first ? _groupJson : '''
{"response":{"name":"Familia Salazar","members":[
  {"steamid":"76561198000000000","role":1}
]}}
''';
              first = false;
              return jsonResponse(body);
            }
            return jsonResponse('{"response":{"players":[]}}');
          },
        ),
        apiKey: 'clave-de-prueba-1234567890abcdef',
        steamToken: _token,
      );
      addTearDown(env.dispose);

      await env.controller.syncFamilyGroup();
      expect(env.controller.profiles, hasLength(2));

      final FamilySyncOutcome second =
          await env.controller.syncFamilyGroup();

      expect(second.success, isTrue);
      expect(second.removed, 1);
      expect(env.controller.profiles, hasLength(1));
      expect(env.controller.profiles.single.steamId64, '76561198000000000');
    });

    test('los perfiles añadidos a mano no se eliminan', () async {
      bool first = true;
      final TestEnvironment env = await buildTestEnvironment(
        httpClient: FakeHttpClient(
          (http.Request request) {
            final String path = request.url.path;
            if (path.contains('GetFamilyGroupForUser')) {
              return jsonResponse(_forUserJson);
            }
            if (path.contains('GetFamilyGroup')) {
              final String body = first ? _groupJson : '''
{"response":{"name":"Familia Salazar","members":[
  {"steamid":"76561198000000000","role":1}
]}}
''';
              first = false;
              return jsonResponse(body);
            }
            return jsonResponse('{"response":{"players":[]}}');
          },
        ),
        apiKey: 'clave-de-prueba-1234567890abcdef',
        steamToken: _token,
      );
      addTearDown(env.dispose);

      await env.controller.addProfile('76561198000000111');
      await env.controller.syncFamilyGroup();

      final FamilySyncOutcome second =
          await env.controller.syncFamilyGroup();

      expect(second.success, isTrue);
      final List<String> ids =
          env.controller.profiles.map((Profile p) => p.steamId64).toList();
      expect(ids, contains('76561198000000111'),
          reason: 'Un perfil manual no debe borrarse al re-sincronizar.');
    });

    test('token caducado limpia el token y pide reconectar', () async {
      final TestEnvironment env = await buildTestEnvironment(
        httpClient: FakeHttpClient(
          (http.Request _) => jsonResponse('{"error":"x"}', status: 401),
        ),
        apiKey: 'clave-de-prueba-1234567890abcdef',
        steamToken: _token,
      );
      addTearDown(env.dispose);
      expect(env.controller.hasFamilyToken, isTrue);

      final FamilySyncOutcome outcome =
          await env.controller.syncFamilyGroup();

      expect(outcome.requiresConnect, isTrue);
      expect(env.controller.hasFamilyToken, isFalse,
          reason: 'Un token rechazado debe borrarse para no reintentar en vano.');
      expect(await env.tokenStore.load(), isNull);
    });

    test('una sincronización correcta da por superado el asistente', () async {
      final TestEnvironment env = await buildTestEnvironment(
        httpClient: FakeHttpClient(
          (http.Request request) {
            final String path = request.url.path;
            if (path.contains('GetFamilyGroupForUser')) {
              return jsonResponse(_forUserJson);
            }
            if (path.contains('GetFamilyGroup')) {
              return jsonResponse(_groupJson);
            }
            return jsonResponse('{"response":{"players":[]}}');
          },
        ),
        apiKey: 'clave-de-prueba-1234567890abcdef',
        steamToken: _token,
      );
      addTearDown(env.dispose);

      await env.controller.syncFamilyGroup();

      expect(env.controller.preferences.familySetupDone, isTrue);
      expect(env.controller.onboardingComplete, isTrue);
      expect(env.controller.lastFamilySyncUnix, isNotNull);
      expect(env.controller.familyGroupName, 'Familia Salazar');
    });
  });

  // --- Almacén del token -----------------------------------------------------

  group('controlador: token', () {
    test('guardar y desconectar el token', () async {
      final FakeHttpClient fake =
          FakeHttpClient((http.Request _) => jsonResponse('{}'));
      final TestEnvironment env = await buildTestEnvironment(httpClient: fake);
      addTearDown(env.dispose);

      await env.controller.saveFamilyToken('  tok-abc  ');
      expect(env.controller.hasFamilyToken, isTrue);
      expect(await env.tokenStore.load(), 'tok-abc');

      final OperationResult result = await env.controller.disconnectSteam();
      expect(result.success, isTrue);
      expect(env.controller.hasFamilyToken, isFalse);
      expect(await env.tokenStore.load(), isNull);
    });
  });
}
