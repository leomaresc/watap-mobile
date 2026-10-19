/// Utilidades compartidas por las pruebas automatizadas.
///
/// Ninguna prueba realiza llamadas reales a Steam: todas usan un cliente HTTP
/// simulado (`MockClient`) y una base de datos SQLite en memoria.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:watap_mobile/app.dart';
import 'package:watap_mobile/data/local/app_database.dart';
import 'package:watap_mobile/data/local/secure_api_key_store.dart';
import 'package:watap_mobile/data/local/steam_token_store.dart';
import 'package:watap_mobile/data/repositories/activity_repository.dart';
import 'package:watap_mobile/data/repositories/preferences_repository.dart';
import 'package:watap_mobile/data/repositories/profiles_repository.dart';
import 'package:watap_mobile/data/steam/family_groups_client.dart';
import 'package:watap_mobile/data/steam/steam_api_client.dart';
import 'package:watap_mobile/services/family_group_sync.dart';
import 'package:watap_mobile/services/refresh_coordinator.dart';
import 'package:watap_mobile/state/app_controller.dart';
import 'package:watap_mobile/widgets/network_image_policy.dart';

/// Prepara SQLite para las pruebas (memoria, sin emulador).
///
/// Se usa la variante **sin isolate**: en `testWidgets` el cuerpo se ejecuta con
/// un reloj simulado y las respuestas que llegan desde otro isolate nunca se
/// procesan, por lo que la prueba se quedaría esperando indefinidamente. Sin
/// isolate, todas las operaciones se resuelven con microtareas y funcionan tanto
/// en `test` como en `testWidgets`.
void initTestDatabaseFactory() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
}

/// Petición HTTP recibida por el cliente simulado.
class RecordedRequest {
  RecordedRequest(this.request);

  final http.Request request;

  Uri get uri => request.url;

  Map<String, String> get headers => request.headers;

  /// Cuerpo de la solicitud (formularios `POST`).
  String get body => request.body;

  String? get apiKeyHeader =>
      request.headers[SteamApiHeaderNames.headerName] ?? request.headers['x-webapi-key'];

  bool get hasKeyInUrl =>
      request.url.queryParameters.containsKey('key');
}

/// Nombres de encabezado usados en las pruebas.
class SteamApiHeaderNames {
  const SteamApiHeaderNames._();

  static const String headerName = 'x-webapi-key';
}

/// Cliente HTTP simulado que registra las peticiones y permite controlar
/// respuestas, retardos y concurrencia.
class FakeHttpClient {
  FakeHttpClient(this._responder);

  final FutureOr<http.Response> Function(http.Request request) _responder;

  final List<RecordedRequest> requests = <RecordedRequest>[];

  /// Máximo de peticiones simultáneas observado.
  int maxConcurrentSeen = 0;
  int _active = 0;

  /// Retardo artificial aplicado a cada respuesta.
  Duration delay = Duration.zero;

  http.Client build() {
    return MockClient((http.Request request) async {
      requests.add(RecordedRequest(request));
      _active++;
      if (_active > maxConcurrentSeen) maxConcurrentSeen = _active;
      try {
        if (delay > Duration.zero) {
          await Future<void>.delayed(delay);
        }
        return await _responder(request);
      } finally {
        _active--;
      }
    });
  }

  int get callCount => requests.length;

  List<RecordedRequest> requestsTo(String pathFragment) => requests
      .where((RecordedRequest r) => r.uri.path.contains(pathFragment))
      .toList(growable: false);
}

/// Respuesta JSON lista para usar en las pruebas.
http.Response jsonResponse(
  String body, {
  int status = 200,
  Map<String, String> headers = const <String, String>{
    'content-type': 'application/json; charset=utf-8',
  },
}) =>
    http.Response(body, status, headers: headers);

/// Respuesta XML lista para usar en las pruebas (perfil de Steam Community).
http.Response xmlResponse(String body, {int status = 200}) => http.Response(
      body,
      status,
      headers: const <String, String>{
        'content-type': 'application/xml; charset=utf-8',
      },
    );

/// Cuerpo del XML público de un perfil, con valores envueltos en CDATA como
/// hace Steam de verdad (`steamID`, `avatarFull`, …).
String communityProfileXmlBody({
  String steamId64 = '76561198000000000',
  String name = 'Ana',
  int visibilityState = 3,
  String privacyState = 'public',
  String? avatarUrl = 'https://avatars.example/anafull.jpg',
}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<profile>'
    '<steamID64>$steamId64</steamID64>'
    '<steamID><![CDATA[$name]]></steamID>'
    '<privacyState>$privacyState</privacyState>'
    '<visibilityState>$visibilityState</visibilityState>'
    '${avatarUrl == null ? '' : '<avatarFull><![CDATA[$avatarUrl]]></avatarFull>'}'
    '</profile>';

/// Respuesta de Steam para un perfil inexistente.
const String communityProfileNotFoundXml =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<response><error><![CDATA[The specified profile could not be found.]]>'
    '</error></response>';

/// Entorno de prueba con base de datos en memoria y cliente simulado.
class TestEnvironment {
  TestEnvironment({
    required this.database,
    required this.controller,
    required this.client,
    required this.httpClient,
    required this.activityRepository,
    required this.profilesRepository,
    required this.keyStore,
    required this.tokenStore,
    required this.familyGroupsClient,
  });

  final AppDatabase database;
  final AppController controller;
  final SteamApiClient client;
  final FakeHttpClient httpClient;
  final ActivityRepository activityRepository;
  final ProfilesRepository profilesRepository;
  final ApiKeyStore keyStore;
  final SteamTokenStore tokenStore;
  final FamilyGroupsClient familyGroupsClient;

  Future<void> dispose() async {
    controller.dispose();
    await database.close();
  }
}

/// Construye un entorno completo de prueba.
Future<TestEnvironment> buildTestEnvironment({
  required FakeHttpClient httpClient,
  String? apiKey,
  String? steamToken,
  Duration timeout = const Duration(seconds: 2),
  int maxConcurrentRequests = 3,
}) async {
  final AppDatabase database = await AppDatabase.open(inMemory: true);
  final SteamApiClient client = SteamApiClient(
    httpClient: httpClient.build(),
    timeout: timeout,
    maxConcurrentRequests: maxConcurrentRequests,
    maxTransientRetries: 0,
  );
  client.setApiKey(apiKey);

  final ProfilesRepository profilesRepository = ProfilesRepository(database);
  final ActivityRepository activityRepository = ActivityRepository(database);
  final PreferencesRepository preferencesRepository =
      PreferencesRepository(database);

  final ApiKeyStore keyStore = InMemoryApiKeyStore(apiKey);
  final SteamTokenStore tokenStore = InMemorySteamTokenStore(steamToken);
  final FamilyGroupsClient familyGroupsClient = FamilyGroupsClient(
    httpClient: httpClient.build(),
    timeout: timeout,
  );

  final FamilyGroupSyncService familySyncService = FamilyGroupSyncService(
    groups: familyGroupsClient,
    api: client,
    profiles: profilesRepository,
  );

  final RefreshCoordinator coordinator = RefreshCoordinator(
    api: client,
    activities: activityRepository,
    profiles: profilesRepository,
  );

  final AppController controller = AppController(
    database: database,
    profilesRepository: profilesRepository,
    activityRepository: activityRepository,
    preferencesRepository: preferencesRepository,
    apiKeyStore: keyStore,
    tokenStore: tokenStore,
    apiClient: client,
    familyGroupsClient: familyGroupsClient,
    familySyncService: familySyncService,
    refreshCoordinator: coordinator,
  );
  await controller.initialize();

  return TestEnvironment(
    database: database,
    controller: controller,
    client: client,
    httpClient: httpClient,
    activityRepository: activityRepository,
    profilesRepository: profilesRepository,
    keyStore: keyStore,
    tokenStore: tokenStore,
    familyGroupsClient: familyGroupsClient,
  );
}

/// Monta la interfaz de WATAP con un controlador ya construido.
Future<void> pumpWatapApp(
  WidgetTester tester,
  AppController controller, {
  Size size = const Size(420, 900),
}) async {
  watapRemoteImagesEnabled = false;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(WatapApp(controller: controller));
  await tester.pumpAndSettle();
}