/// Pruebas de widgets: estados vacío, de carga y de error, arranque en modo
/// demostración y visualización de datos en caché.
///
/// Ninguna prueba descarga imágenes ni consulta Steam: las imágenes remotas
/// están desactivadas y el cliente HTTP es simulado.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watap_mobile/state/app_controller.dart';
import 'package:watap_mobile/widgets/error_state.dart';
import 'package:watap_mobile/widgets/loading_state.dart';

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
  return jsonResponse('{}');
}

/// Construye el entorno de prueba y lo registra para cerrarlo al terminar.
Future<TestEnvironment> _buildEnvironment({
  required FakeHttpClient httpClient,
  String? apiKey,
}) async {
  final TestEnvironment env =
      await buildTestEnvironment(httpClient: httpClient, apiKey: apiKey);
  addTearDown(env.dispose);
  return env;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  initTestDatabaseFactory();

  testWidgets('LoadingState muestra el mensaje y el indicador',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: LoadingState(message: 'Cargando datos…')),
    ));
    expect(find.text('Cargando datos…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('ErrorState permite reintentar', (WidgetTester tester) async {
    int retries = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ErrorState(
          title: 'No se pudo abrir el almacenamiento',
          message: 'Detalle del problema.',
          onRetry: () => retries++,
        ),
      ),
    ));
    expect(find.text('No se pudo abrir el almacenamiento'), findsOneWidget);

    await tester.tap(find.text('Reintentar'));
    await tester.pump();

    expect(retries, 1);
  });

  testWidgets('sin clave ni integrantes la app arranca en modo demostración',
      (WidgetTester tester) async {
    final FakeHttpClient fake =
        FakeHttpClient((http.Request _) => jsonResponse('{}'));
    final TestEnvironment env =
        await _buildEnvironment(httpClient: fake);

    await pumpWatapApp(tester, env.controller);

    expect(env.controller.demoMode, isTrue);
    expect(find.textContaining('DEMOSTRACIÓN'), findsWidgets);
    expect(find.text('DEMO'), findsWidgets);
    expect(find.text('Dota 2'), findsWidgets);
    expect(fake.callCount, 0);
  });

  testWidgets('con clave y sin integrantes se muestra el estado vacío',
      (WidgetTester tester) async {
    final TestEnvironment env = await _buildEnvironment(
      httpClient: FakeHttpClient(_dispatch),
      apiKey: _key,
    );

    await pumpWatapApp(tester, env.controller);

    expect(find.text('Todavía no hay integrantes'), findsOneWidget);
    expect(find.text('Añadir un integrante'), findsOneWidget);
  });

  testWidgets('la navegación inferior cambia de sección',
      (WidgetTester tester) async {
    final TestEnvironment env = await _buildEnvironment(
      httpClient: FakeHttpClient(_dispatch),
      apiKey: _key,
    );
    await pumpWatapApp(tester, env.controller);

    await tester.tap(find.text('Ajustes'));
    await tester.pumpAndSettle();

    expect(env.controller.section, AppSection.settings);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      AppSection.settings.index,
    );
  });

  testWidgets('tras un fallo de red se muestran los datos guardados como caché',
      (WidgetTester tester) async {
    bool failing = false;
    final FakeHttpClient fake = FakeHttpClient((http.Request request) {
      if (failing) throw http.ClientException('sin conexión');
      return _dispatch(request);
    });
    final TestEnvironment env = await _buildEnvironment(
      httpClient: fake,
      apiKey: _key,
    );

    await env.controller.addProfileFromInput(_id);
    await env.controller.refreshProfile(_id);
    failing = true;
    await env.controller.refreshProfile(_id);

    await pumpWatapApp(tester, env.controller);

    expect(
      find.text('Se muestran los datos guardados de la última consulta correcta.'),
      findsOneWidget,
    );
    expect(find.text('Dota 2'), findsWidgets);
  });
}
