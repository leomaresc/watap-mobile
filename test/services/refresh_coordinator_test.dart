/// Pruebas del coordinador de actualizaciones.
///
/// Ninguna prueba realiza llamadas reales: el cliente HTTP está simulado y la
/// base de datos es SQLite en memoria. La única credencial simulada es el
/// token de sesión; los perfiles públicos se leen del XML de Steam Community.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watap_mobile/core/models.dart';
import 'package:watap_mobile/data/local/app_database.dart';
import 'package:watap_mobile/data/repositories/activity_repository.dart';
import 'package:watap_mobile/data/repositories/profiles_repository.dart';
import 'package:watap_mobile/data/steam/steam_api_client.dart';
import 'package:watap_mobile/services/refresh_coordinator.dart';

import '../helpers/test_support.dart';

const String _token = 'tok-de-prueba-9';
const String _id = '76561198000000000';

const String _recentJson =
    '{"response":{"total_count":1,"games":[{"appid":570,"name":"Dota 2",'
    '"playtime_2weeks":100,"playtime_forever":1000}]}}';
const String _emptyRecentJson = '{"response":{"total_count":0,"games":[]}}';

/// Respuesta del XML público de perfil, con nombre e visibilidad pedidos.
///
/// El identificador se lee de la ruta (`/profiles/{id}`).
http.Response _profileXml(
  http.Request request, {
  int visibility = 3,
  String namePrefix = 'Jugador',
}) {
  final String id = request.url.pathSegments.isEmpty
      ? _id
      : request.url.pathSegments.last;
  return xmlResponse(
    communityProfileXmlBody(
      steamId64: id,
      name: '$namePrefix $id',
      visibilityState: visibility,
    ),
  );
}

/// Enrutado por defecto: perfil público en XML y un juego reciente.
http.Response _dispatch(http.Request request) {
  if (request.url.host == 'steamcommunity.com') return _profileXml(request);
  if (request.url.path.contains('GetRecentlyPlayedGames')) {
    return jsonResponse(_recentJson);
  }
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
  String? steamToken = _token,
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
  client.setAccessToken(steamToken);
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

  test('sin sesión configurada se informa y no se llama a la red', () async {
    final _Env env = await _env(steamToken: null);
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
    // El nombre público del XML se actualiza en el perfil almacenado.
    expect((await env.profiles.findById(_id))!.personaName, 'Jugador $_id');
  });

  test('un perfil privado no consulta los juegos recientes', () async {
    final _Env env = await _env(
      httpClient: FakeHttpClient(
        (http.Request r) => _profileXml(r, visibility: 1),
      ),
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
        (http.Request r) => r.url.host == 'steamcommunity.com'
            ? _profileXml(r)
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
        (http.Request _) => xmlResponse(communityProfileNotFoundXml),
      ),
    );
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.invalidProfile);
  });

  test('nombre y visibilidad vienen del XML público y hay juegos', () async {
    final _Env env = await _env(httpClient: FakeHttpClient(_dispatch));
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.ok);
    expect(result.personaName, 'Jugador $_id');
    expect(result.games.single.appId, 570);
    expect((await env.profiles.findById(_id))!.personaName, 'Jugador $_id',
        reason: 'El nombre del XML se guarda en el perfil.');
    // El token jamás viaja a steamcommunity.com.
    for (final RecordedRequest r in env.fake.requests) {
      if (r.uri.host == 'steamcommunity.com') {
        expect(r.uri.queryParameters.containsKey('access_token'), isFalse);
      }
    }
  });

  test('un perfil privado según el XML no consulta los juegos', () async {
    final _Env env = await _env(
      httpClient: FakeHttpClient(
        (http.Request request) => request.url.host == 'steamcommunity.com'
            ? xmlResponse(communityProfileXmlBody(
                steamId64: _id, name: 'Ana', visibilityState: 1))
            : jsonResponse(_recentJson),
      ),
    );
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.privateOrUnavailable);
    expect(env.fake.requestsTo('GetRecentlyPlayedGames'), isEmpty);
  });

  test('perfil público pero juegos rechazados: se informa con honestidad en '
      'lugar de culpar solo a la privacidad', () async {
    final _Env env = await _env(
      httpClient: FakeHttpClient(
        (http.Request request) => request.url.host == 'steamcommunity.com'
            ? xmlResponse(communityProfileXmlBody(steamId64: _id, name: 'Ana'))
            : http.Response('', 403),
      ),
    );
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.incompleteConfiguration);
    expect(result.statusMessage, contains('Detalles del juego'));
    expect(result.statusMessage, contains('Vuelve a conectar'));
  });

  test('un perfil inexistente en el XML se marca como no válido', () async {
    final _Env env = await _env(
      httpClient: FakeHttpClient(
        (http.Request _) => xmlResponse(communityProfileNotFoundXml),
      ),
    );
    addTearDown(env.dispose);
    final Profile profile = _profile(_id);
    await env.profiles.upsert(profile);

    final ProfileActivity result = await env.coordinator.refreshProfile(profile);

    expect(result.status, FetchStatus.invalidProfile);
    expect(env.fake.requestsTo('GetRecentlyPlayedGames'), isEmpty,
        reason: 'Ni se consulta la actividad de un perfil inexistente.');
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
