/// Pruebas de widgets: asistente de configuración, estados vacío, de carga y
/// de error, y visualización de datos en caché.
///
/// Ninguna prueba descarga imágenes ni consulta Steam: las imágenes remotas
/// están desactivadas y el cliente HTTP es simulado.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:watap_mobile/state/app_controller.dart';
import 'package:watap_mobile/widgets/error_state.dart';
import 'package:watap_mobile/widgets/loading_state.dart';

import '../helpers/test_support.dart';

const String _id = '76561198000000000';
const String _token = 'token-de-prueba-123';

const String _recentJson =
    '{"response":{"total_count":1,"games":[{"appid":570,"name":"Dota 2",'
    '"playtime_2weeks":100,"playtime_forever":1000}]}}';

/// Enrutado simulado: XML público de perfil y juegos recientes.
http.Response _dispatch(http.Request request) {
  if (request.url.host == 'steamcommunity.com') {
    final String id = request.url.pathSegments.isEmpty
        ? _id
        : request.url.pathSegments.last;
    return xmlResponse(
      communityProfileXmlBody(steamId64: id, name: 'Jugador $id'),
    );
  }
  if (request.url.path.contains('GetRecentlyPlayedGames')) {
    return jsonResponse(_recentJson);
  }
  return jsonResponse('{}');
}

/// Construye el entorno de prueba y lo registra para cerrarlo al terminar.
Future<TestEnvironment> _buildEnvironment({
  required FakeHttpClient httpClient,
  String? steamToken,
}) async {
  final TestEnvironment env = await buildTestEnvironment(
    httpClient: httpClient,
    steamToken: steamToken,
  );
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

  testWidgets('sin credenciales se muestra el asistente de configuración',
      (WidgetTester tester) async {
    final FakeHttpClient fake =
        FakeHttpClient((http.Request _) => jsonResponse('{}'));
    final TestEnvironment env =
        await _buildEnvironment(httpClient: fake);

    await pumpWatapApp(tester, env.controller);

    expect(env.controller.onboardingComplete, isFalse);
    expect(find.text('Configuración inicial'), findsOneWidget);
    expect(find.text('Conectar con Steam'), findsWidgets);
    expect(fake.callCount, 0);
  });

  testWidgets('con sesión y sin integrantes se muestra el estado vacío',
      (WidgetTester tester) async {
    final TestEnvironment env = await _buildEnvironment(
      httpClient: FakeHttpClient(_dispatch),
      steamToken: _token,
    );

    await pumpWatapApp(tester, env.controller);

    // Navega a la sección Integrantes usando el NavigationBar.
    await tester.tap(find.byIcon(Icons.people_outline));
    await tester.pumpAndSettle();

    expect(env.controller.onboardingComplete, isTrue);
    expect(find.text('Todavía no hay integrantes'), findsOneWidget);
  });

  testWidgets('la navegación inferior cambia de sección',
      (WidgetTester tester) async {
    final TestEnvironment env = await _buildEnvironment(
      httpClient: FakeHttpClient(_dispatch),
      steamToken: _token,
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
      steamToken: _token,
    );

    await env.controller.addProfile(_id);
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