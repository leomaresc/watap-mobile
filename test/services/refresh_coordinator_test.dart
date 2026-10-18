/// Pruebas del coordinador de actualizaciones.
///
/// Ninguna prueba realiza llamadas reales: el cliente HTTP está simulado y la
/// base de datos es SQLite en memoria.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/data/local/app_database.dart';
import 'package:watap_mobile/data/repositories/activity_repository.dart';
import 'package:watap_mobile/data/repositories/profiles_repository.dart';
import 'package:watap_mobile/data/steam/steam_api_client.dart';
import 'package:watap_mobile/services/refresh_coordinator.dart';

import '../helpers/test_support.dart';

const String _key = 'clave-de-prueba-1234567890abcdef';
const String _id = '76561198000000000';

const String _recentJson =
    '{"response":{"total_count":1,"games":[{"appid":570,"name":"Dota 2",'
    '"playtime_2weeks":100,"playtime_forever":1000}]}}';
const String _emptyRecentJson = '{"response":{"total_count":0,"games":[]}}';

/// Respuesta de `GetPlayerSummaries` que refleja los identificadores pedidos.
http.Response _summaries(http.Request request, {int visibility = 3}) {
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
                  'communityvisibilitystate': visibility,
                })
            .toList(),
      },
    }),
  );
}

/// Enrutado por defecto: resúmenes públicos y un juego reciente.
http.Response _dispatch(http.Request request) {
  final String path = request.url.path;
  if (path.contains('GetPlayerSummaries')) return _summaries(request);
  if (path.contains('GetRecentlyPlayedGames')) return jsonResponse(_recentJson);
  return jsonResponse('{}');
}

class _Env {
  _Env({
    required this.database,
    required this.profiles,
    required this.activities,
    required this.client,
    required this.coordinator,
    required this.fake,
  });

  final AppDatabase database;
  final ProfilesRepository profiles;
  final ActivityRepository activities;
  final SteamApiClient client;
  final RefreshCoordinator coordinator;
  final FakeHttpClient fake;

  Future<void> dispose() async {
    coordinator.dispose();
    client.dispose();
    await database.close();
  }
}

Future<_Env> _env({
  FakeHttpClient? httpClient,
  String? apiKey = _key,
  int maxConcurrent = 3,
}) async {
  final FakeHttpClient fake = httpClient ?? FakeHttpClient(_dispatch);
  final AppDatabase database = await AppDatabase.open(inMemory: true);
  final ProfilesRepository profiles = ProfilesRepository(database);
  final ActivityRepository activities = ActivityRepository(database);
  final SteamApiClient client = SteamApiClient(
    httpClient: fake.build(),
    timeout: const Duration(seconds: 5),
    maxTransientRetries: 0,
  );
  client.setApiKey(apiKey);
  final RefreshCoordinator coordinator = RefreshCoordinator(
    api: client,
    activities: activities,
    profiles: profiles,
    maxConcurrent: maxConcurrent,
  );
  return _Env(
    database: database,
    profiles: profiles,
    activities: activities,
    client: client,
    coordinator: coordinator,
    fake: fake,
  );
}

Profile _profile(String id) => Profile(steamId64: id, createdAtUnix: 1);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabaseFactory();

  test('sin clave configurada se informa y no se llama a la red', () async {
    final _Env env = await _env(apiKey: null);
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.incompleteConfiguration);
    expect(env.fake.callCount, 0);
  });

  test('un perfil público con juegos devuelve estado ok', () async {
    final _Env env = await _env();
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.ok);
    expect(result.games.single.appId, 570);
    expect(env.fake.callCount, 2);
    // El nombre público se actualiza en el perfil almacenado.
    expect((await env.profiles.findById(_id))!.personaName, 'Jugador $_id');
  });

  test('un perfil privado no consulta los juegos recientes', () async {
    final _Env env = await _env(
      httpClient: FakeHttpClient((http.Request r) => _summaries(r, visibility: 1)),
    );
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.privateOrUnavailable);
    expect(env.fake.requestsTo('GetRecentlyPlayedGames'), isEmpty);
  });

  test('una respuesta válida sin juegos se marca como noRecentGames', () async {
    final _Env env = await _env(
      httpClient: FakeHttpClient(
        (http.Request r) => r.url.path.contains('GetPlayerSummaries')
            ? _summaries(r)
            : jsonResponse(_emptyRecentJson),
      ),
    );
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.noRecentGames);
    expect(result.games, isEmpty);
  });

  test('un SteamID64 desconocido se marca como perfil no válido', () async {
    final _Env env = await _env(
      httpClient: FakeHttpClient(
        (http.Request _) => jsonResponse('{"response":{"players":[]}}'),
      ),
    );
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.invalidProfile);
  });

  test('un fallo de red conserva la actividad anterior como caché', () async {
    bool failing = false;
    final FakeHttpClient fake = FakeHttpClient((http.Request request) {
      if (failing) throw http.ClientException('sin conexión');
      return _dispatch(request);
    });
    final _Env env = await _env(httpClient: fake);
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity first = await env.coordinator.refreshProfile(profile);
    expect(first.status, FetchStatus.ok);

    failing = true;
    final ProfileActivity second =
        await env.coordinator.refreshProfile(profile, previous: first);

    expect(second.status, FetchStatus.networkError);
    expect(second.fromCache, isTrue);
    expect(second.games, hasLength(1));
  });

  test('refreshAll emite una actividad por perfil y limita la concurrencia',
      () async {
    final FakeHttpClient fake = FakeHttpClient(_dispatch)
      ..delay = const Duration(milliseconds: 30);
    final _Env env = await _env(httpClient: fake, maxConcurrent: 2);
    addTearDown(env.dispose);

    final List<Profile> profiles = List<Profile>.generate(
      4,
      (int i) => _profile('76561198000000${i.toString().padLeft(3, '0')}'),
    );
    for (final Profile profile in profiles) {
      await env.profiles.upsert(profile);
    }

    final List<ProfileActivity> emitted =
        await env.coordinator.refreshAll(profiles).toList();

    expect(emitted, hasLength(4));
    expect(emitted.every((ProfileActivity a) => a.status == FetchStatus.ok), isTrue);
    expect(fake.maxConcurrentSeen, lessThanOrEqualTo(2));
  });
}
