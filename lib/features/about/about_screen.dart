/// Pantalla "Acerca de WATAP".
library;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/ui_helpers.dart';

/// Información de la aplicación y de su estado.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Acerca de WATAP')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 54,
                height: 54,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: WatapColors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: WatapColors.accent.withValues(alpha: 0.4),
                  ),
                ),
                child: const Text(
                  'W',
                  style: TextStyle(
                    color: WatapColors.accent,
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '${AppConstants.appName} Mobile',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: WatapColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      AppConstants.appExpandedName,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: WatapColors.textSecondary,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Versión ${AppConstants.appVersion} '
                      '(build ${AppConstants.appBuild})',
                      style: TextStyle(
                        fontSize: 11.5,
                        color: WatapColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          const InlineNotice(
            message: 'Proyecto en desarrollo. Las funciones descritas en el '
                'README son las realmente implementadas; cualquier limitación '
                'conocida está documentada allí.',
          ),
          const SizedBox(height: 18),
          const _Block(
            title: 'Qué es WATAP',
            body: 'Una herramienta pequeña y privada para consultar y comparar la '
                'actividad reciente de un grupo de perfiles de Steam: minutos de '
                'las últimas dos semanas, tiempo acumulado cuando Steam lo '
                'comunica y qué juegos concentran más tiempo entre todos los '
                'integrantes.',
          ),
          const _Block(
            title: 'Qué no es',
            body: 'No es un cliente de Steam, ni un launcher, ni un chat, ni un '
                'sistema de seguimiento en tiempo real, ni una herramienta de '
                'compras. No muestra estados como "jugando ahora" ni afirmaciones '
                'sobre la disponibilidad actual de nadie.',
          ),
          const _Block(
            title: 'Atribución',
            body: 'WATAP Mobile es un proyecto independiente y no está afiliado ni '
                'respaldado por Valve Corporation. Steam es una marca registrada '
                'de Valve. Los datos se obtienen exclusivamente de la Steam Web '
                'API pública y del CDN público de imágenes de Steam.',
          ),
          _Block(
            title: 'Estado de los datos en esta sesión',
            body: 'Perfiles reales guardados: ${controller.realProfiles.length}. '
                'Juegos almacenados: ${controller.gamesStoredCount}. '
                'Clave de API: ${controller.hasApiKey ? "configurada" : "no configurada"}. '
                'Modo demostración: ${controller.showingDemoData ? "activado" : "desactivado"}.',
          ),
          SectionCard(
            title: 'ENLACES',
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.public),
                title: const Text('Steam Web API'),
                subtitle: const Text(AppConstants.steamWebApiDocsUrl),
                onTap: () => openExternalUrl(
                  context,
                  Uri.parse(AppConstants.steamWebApiDocsUrl),
                  action: 'abrir la documentación',
                ),
              ),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: const Text('Tienda de Steam'),
                subtitle: const Text(AppConstants.steamStoreBaseUrl),
                onTap: () => openExternalUrl(
                  context,
                  Uri.parse(AppConstants.steamStoreBaseUrl),
                  action: 'abrir la tienda de Steam',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Licencia MIT. Consulta el archivo LICENSE del repositorio para el '
            'texto completo y las atribuciones.',
            style: TextStyle(
              fontSize: 11.5,
              color: WatapColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Endpoints utilizados: ${SteamApiEndpoints.recentlyPlayed.trim()}, '
            '${SteamApiEndpoints.playerSummaries.trim()}, '
            '${SteamApiEndpoints.resolveVanityUrl.trim()} y '
            '${SteamApiEndpoints.friendList.trim()} (opcional).',
            style: const TextStyle(
              fontSize: 11,
              color: WatapColors.textSecondary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              color: WatapColors.textPrimary,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            body,
            style: const TextStyle(
              fontSize: 13,
              color: WatapColors.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
