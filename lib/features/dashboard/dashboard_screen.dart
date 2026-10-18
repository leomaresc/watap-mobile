/// Contenedor principal con cabecera, secciones y navegación inferior.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/app_controller.dart';
import '../../widgets/app_bottom_navigation.dart';
import '../../widgets/watap_header.dart';
import '../members/members_screen.dart';
import '../settings/settings_screen.dart';
import 'overview_screen.dart';
import 'recent_games_screen.dart';

/// Pantalla raíz de WATAP Mobile.
///
/// Mantiene las cuatro secciones en un `IndexedStack` para conservar el estado
/// (posición de desplazamiento, filtros) al cambiar de pestaña, sin volver a
/// consultar la red.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Al volver al primer plano se intenta actualizar, siempre que el usuario
    // lo haya habilitado. El coordinador evita duplicados y respeta los
    // límites de solicitudes de Steam. No hay ningún temporizador periódico.
    final AppController controller = AppScope.of(context);
    if (controller.initialized &&
        controller.preferences.refreshOnOpen &&
        controller.hasApiKey &&
        controller.hasRealProfiles) {
      unawaited(controller.refreshAll(silent: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);
    final AppSection section = controller.section;

    return Scaffold(
      appBar: WatapHeader(
        controller: controller,
        onRefresh: () => _refreshAll(context, controller),
      ),
      body: SafeArea(
        top: false,
        child: IndexedStack(
          index: section.index,
          children: const <Widget>[
            RecentGamesScreen(),
            OverviewScreen(),
            MembersScreen(),
            SettingsScreen(),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNavigation(
        current: section,
        onSelected: controller.setSection,
      ),
    );
  }

  Future<void> _refreshAll(BuildContext context, AppController controller) async {
    if (controller.profiles.isEmpty) {
      final String message = controller.showingDemoData
          ? 'El modo demostración usa datos locales: no se consulta Steam.'
          : 'Añade al menos un integrante antes de actualizar.';
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
      return;
    }
    if (controller.showingDemoData) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'El modo demostración usa datos ficticios locales: no se envía '
            'ninguna solicitud a Steam.',
          ),
        ),
      );
      return;
    }
    await controller.refreshAll();
  }
}
