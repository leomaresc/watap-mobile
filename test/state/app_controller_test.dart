/// Pruebas del controlador de la aplicación con dependencias simuladas.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/data/repositories/preferences_repository.dart';
import 'package:watap_mobile/state/app_controller.dart';

import '../helpers/test_support.dart';

const String _key = 'clave-de-prueba-1234567890abcdef';
const String _id = '76561198000000000';

const String _recentJson =
    '{"response":{"total_count":1,"games":[{"appid":570,"name":"Dota 2",'
    '"playtime_2weeks":100,"playtime_forever":1000}]}}';

http.Response _dispatch(http.Request request) {
  final String path = request.url.path;
  if (path.contains('GetPlayerSummaries')) {
    final List<String> ids = (request.url.queryParameters['steamids'] ?? '')
        .split(',')
        .where((String s) => s.isNotEmpty)
        .toList(growable: false);
    return jsonResponse(
      jsonEncode(<String, Object?>{
        'response': <String, Object?>{
          'players': ids
              .map((String id) => <String, Object?>{
                    'steamid': id,
                    'personaname': 'Jugador $id',
                    'communityvisibilitystate': 3,
                  })
              .toList(),
        },
      }),
    );
  }
  if (path.contains('GetRecentlyPlayedGames')) return jsonResponse(_recentJson);
  if (path.contains('ResolveVanityURL')) {
    final String vanity = request.url.queryParameters['vanityurl'] ?? '';
    if (vanity == 'ana') {
      return jsonResponse('{"response":{"success":1,"steamid":"$_id"}}');
    }
    return jsonResponse('{"response":{"success":42,"message":"No match"}}');
  }
  return jsonResponse('{}');
}

FakeHttpClient _fake() => FakeHttpClient(_dispatch);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabaseFactory();

  group('configuración inicial', () {
    test('sin clave la app no está lista', () async {
      final TestEnvironment env = await buildTestEnvironment(httpClient: _fake());
      addTearDown(env.dispose);

      expect(env.controller.hasApiKey, isFalse);
      expect(env.controller.onboardingComplete, isFalse);
      expect(env.controller.profiles, isEmpty);
    });

    test('con clave la app está lista', () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);

      expect(env.controller.hasApiKey, isTrue);
      expect(env.controller.onboardingComplete, isTrue);
    });
  });

  group('integrantes', () {
    test('añadir por SteamID64 guarda el perfil y su nombre público', () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);

      final OperationResult result = await env.controller.addProfile(_id);

      expect(result.success, isTrue);
      expect(result.steamId64, _id);
      expect(env.controller.profiles, hasLength(1));
      expect(env.controller.profiles.single.personaName, 'Jugador $_id');
    });

    test('no se puede añadir dos veces el mismo perfil', () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);
      await env.controller.addProfile(_id);

      final OperationResult result = await env.controller.addProfile(_id);

      expect(result.success, isFalse);
      expect(result.messageEs, contains('ya está'));
      expect(env.controller.profiles, hasLength(1));
    });

    test('resolver un nombre personalizado exige clave de API', () async {
      final TestEnvironment env = await buildTestEnvironment(httpClient: _fake());
      addTearDown(env.dispose);

      final OperationResult result = await env.controller.addProfile('ana');

      expect(result.success, isFalse);
      expect(result.messageEs, contains('clave'));
    });

    test('con clave, un nombre personalizado se resuelve y se añade', () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);

      final OperationResult result = await env.controller.addProfile('ana');

      expect(result.success, isTrue);
      expect(env.controller.profiles.single.steamId64, _id);
    });

    test('un nombre personalizado inexistente devuelve un error claro', () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);

      final OperationResult result =
          await env.controller.addProfile('desconocido');

      expect(result.success, isFalse);
      expect(result.messageEs, contains('No existe'));
    });

    test('eliminar un integrante lo quita de la lista', () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);
      await env.controller.addProfile(_id);

      final OperationResult result = await env.controller.deleteProfile(_id);

      expect(result.success, isTrue);
      expect(env.controller.profiles, isEmpty);
    });
  });

  group('importación masiva', () {
    test('importar una lista añade los perfiles válidos', () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);

      // 'ana' resuelve al mismo SteamID64 que _id, así que se omite como
      // duplicado. 'no-existe' (vanity inexistente) y 'entrada mala con
      // espacios' (inválida) se descartan.
      final ImportResult result = await env.controller.importMembers(
        <String>[_id, 'ana', 'no-existe', 'entrada mala con espacios'],
      );

      expect(result.added, 1);
      expect(result.failed, 2);
      expect(env.controller.profiles, hasLength(1));
      expect(env.controller.profiles.single.steamId64, _id);
    });

    test('sin clave, la importación se rechaza', () async {
      final TestEnvironment env = await buildTestEnvironment(httpClient: _fake());
      addTearDown(env.dispose);

      final ImportResult result =
          await env.controller.importMembers(<String>[_id]);

      expect(result.isError, isTrue);
      expect(result.added, 0);
      expect(result.messageEs, contains('clave'));
    });
  });

  group('clave de API', () {
    test('se guarda en el almacén seguro y activa el estado', () async {
      const String secret = 'clave-secreta-para-la-prueba-0001';
      final TestEnvironment env = await buildTestEnvironment(httpClient: _fake());
      addTearDown(env.dispose);
      expect(env.controller.hasApiKey, isFalse);

      final OperationResult result = await env.controller.saveApiKey(secret);

      expect(result.success, isTrue);
      expect(env.controller.hasApiKey, isTrue);
      expect(env.client.hasApiKey, isTrue);
      expect(await env.keyStore.loadApiKey(), secret);
    });

    test('eliminar la clave la borra del almacén seguro', () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);
      expect(env.controller.hasApiKey, isTrue);

      final OperationResult result = await env.controller.deleteApiKey();

      expect(result.success, isTrue);
      expect(env.controller.hasApiKey, isFalse);
      expect(await env.keyStore.loadApiKey(), isNull);
    });
  });

  group('actualización y caché', () {
    test('refreshProfile guarda la actividad consultada', () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);
      await env.controller.addProfile(_id);

      await env.controller.refreshProfile(_id);

      final ProfileActivity? activity = env.controller.activityFor(_id);
      expect(activity, isNotNull);
      expect(activity!.status, FetchStatus.ok);
      expect(env.controller.gamesStoredCount, 1);
    });

    test('clearActivityCache borra la actividad y conserva los integrantes',
        () async {
      final TestEnvironment env =
          await buildTestEnvironment(httpClient: _fake(), apiKey: _key);
      addTearDown(env.dispose);
      await env.controller.addProfile(_id);
      await env.controller.refreshProfile(_id);
      expect(env.controller.gamesStoredCount, greaterThan(0));

      final OperationResult result = await env.controller.clearActivityCache();

      expect(result.success, isTrue);
      expect(env.controller.gamesStoredCount, 0);
      expect(env.controller.profiles, hasLength(1));
    });

    test('cambiar de sección se persiste en las preferencias', () async {
      final TestEnvironment env = await buildTestEnvironment(httpClient: _fake());
      addTearDown(env.dispose);

      env.controller.setSection(AppSection.overview);

      final Preferences stored =
          await PreferencesRepository(env.database).load();
      expect(env.controller.section, AppSection.overview);
      expect(stored.lastSection, 'overview');
    });
  });
}