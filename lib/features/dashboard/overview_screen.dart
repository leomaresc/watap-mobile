/// Pantalla "General": actividad agregada por AppID.
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../data/steam/steam_api_urls.dart';
import '../../services/activity_aggregator.dart';
import '../../state/app_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/loading_state.dart';
import '../../widgets/ui_helpers.dart';
import 'game_card.dart';
import 'recent_games_screen.dart';

/// Pantalla de actividad agregada de todos los integrantes.
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final AppController controller = AppScope.of(context);

    if (!controller.initialized) {
      return const LoadingState(message: 'Preparando los datos locales…');
    }
    if (controller.initializationError != null) {
      return ErrorStateView(controller: controller);
    }
    if (controller.profiles.isEmpty) {
      return EmptyState(
        title: 'Sin integrantes que agregar',
        message: 'La vista general suma la actividad de todos los integrantes '
            'de tu grupo familiar de Steam. Sincroniza la sección Familia para '
            'cargarlos automáticamente.',
        icon: Icons.bar_chart_outlined,
        actionLabel: 'Ir a Familia',
        onAction: () => controller.setSection(AppSection.members),
      );
    }

    final List<AggregatedGame> games = controller.aggregatedGames;
    final Preferences prefs = controller.preferences;

    if (games.isEmpty) {
      return EmptyState(
        title: 'Todavía no hay actividad que agregar',
        message: controller.hasSteamAuth
            ? 'Actualiza los integrantes para obtener sus juegos recientes. '
                'Si sus perfiles son privados, Steam no entregará los datos.'
            : 'Conecta tu cuenta de Steam y actualiza los integrantes para '
                'ver aquí la actividad combinada.',
        icon: Icons.insights_outlined,
        actionLabel:
            controller.hasSteamAuth ? 'Actualizar integrantes' : 'Ir a Ajustes',
        onAction: () {
          if (controller.hasSteamAuth) {
            controller.refreshAll();
          } else {
            controller.setSection(AppSection.settings);
          }
        },
      );
    }

    return RefreshIndicator(
      onRefresh: controller.refreshAll,
      color: WatapColors.accent,
      backgroundColor: WatapColors.panel,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
        itemCount: games.length + 1,
        itemBuilder: (BuildContext context, int index) {
          if (index == 0) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: _OverviewSummary(controller: controller),
            );
          }
          final AggregatedGame game = games[index - 1];
          return Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: AggregatedGameCard(
              game: game,
              showCover: prefs.showCovers,
              onOpenStore: () => openExternalUrl(
                context,
                SteamApiUrls.storePage(game.appId),
                action: 'abrir la página de Steam',
              ),
              onTapMember: (MemberContribution contribution) {
                controller.setFilterProfile(contribution.steamId64);
                controller.setSection(AppSection.recent);
              },
            ),
          );
        },
      ),
    );
  }
}

class _OverviewSummary extends StatelessWidget {
  const _OverviewSummary({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final int memberCount = controller.profiles.length;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Icon(Icons.groups_outlined, size: 18, color: WatapColors.accent),
                const SizedBox(width: 8),
                Text(
                  'Resumen de $memberCount '
                  'integrante${memberCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: WatapColors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 22,
              runSpacing: 12,
              children: <Widget>[
                _SummaryMetric(
                  label: 'Minutos recientes (suma)',
                  value: formatMinutes(controller.totalRecentMinutes),
                  emphasized: true,
                ),
                _SummaryMetric(
                  label: 'Tiempo acumulado (suma)',
                  value: formatMinutes(controller.totalForeverMinutes),
                ),
                _SummaryMetric(
                  label: 'Juegos distintos',
                  value: '${controller.distinctGames}',
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Agrupado por AppID de Steam. Las sumas son de tiempo registrado '
              'por Steam y no representan juego simultáneo ni el estado actual '
              'de ningún integrante.',
              style: TextStyle(
                fontSize: 11,
                color: WatapColors.textSecondary,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryMetric extends StatelessWidget {
  const _SummaryMetric({
    required this.label,
    required this.value,
    this.emphasized = false,
  });

  final String label;
  final String value;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          value,
          style: TextStyle(
            fontSize: emphasized ? 19 : 17,
            fontWeight: FontWeight.w800,
            color: emphasized ? WatapColors.accent : WatapColors.textPrimary,
          ),
        ),
        Text(
          label,
          style: const TextStyle(fontSize: 10.5, color: WatapColors.textSecondary),
        ),
      ],
    );
  }
}
