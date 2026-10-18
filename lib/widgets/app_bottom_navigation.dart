/// Navegación inferior de WATAP.
library;

import 'package:flutter/material.dart';

import '../state/app_controller.dart';

/// Barra de navegación inferior con las cuatro secciones.
class AppBottomNavigation extends StatelessWidget {
  const AppBottomNavigation({
    super.key,
    required this.current,
    required this.onSelected,
  });

  final AppSection current;
  final ValueChanged<AppSection> onSelected;

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: current.index,
      onDestinationSelected: (int index) {
        onSelected(AppSection.values[index]);
      },
      destinations: const <Widget>[
        NavigationDestination(
          icon: Icon(Icons.schedule_outlined),
          selectedIcon: Icon(Icons.schedule),
          label: 'Recientes',
          tooltip: 'Juegos recientes por integrante',
        ),
        NavigationDestination(
          icon: Icon(Icons.bar_chart_outlined),
          selectedIcon: Icon(Icons.bar_chart),
          label: 'General',
          tooltip: 'Actividad agregada de todos los integrantes',
        ),
        NavigationDestination(
          icon: Icon(Icons.people_outline),
          selectedIcon: Icon(Icons.people),
          label: 'Familia',
          tooltip: 'Integrantes del grupo familiar de Steam',
        ),
        NavigationDestination(
          icon: Icon(Icons.settings_outlined),
          selectedIcon: Icon(Icons.settings),
          label: 'Ajustes',
          tooltip: 'Clave de API, preferencias y caché',
        ),
      ],
    );
  }
}
