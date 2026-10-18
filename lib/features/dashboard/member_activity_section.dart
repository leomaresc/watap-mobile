/// Cabecera y contenido de la actividad de un integrante.
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../theme/app_theme.dart';
import '../../widgets/avatar_widget.dart';
import '../../widgets/status_chip.dart';
import 'game_card.dart';

/// Bloque de actividad de un integrante: cabecera con métricas y sus juegos.
class MemberActivitySection extends StatelessWidget {
  const MemberActivitySection({
    super.key,
    required this.activity,
    required this.displayName,
    required this.preferences,
    required this.onRefresh,
    required this.onOpenStore,
    this.onTapHeader,
    this.isRefreshing = false,
  });

  final ProfileActivity activity;
  final String displayName;
  final Preferences preferences;
  final VoidCallback onRefresh;
  final void Function(Game game) onOpenStore;
  final VoidCallback? onTapHeader;
  final bool isRefreshing;

  @override
  Widget build(BuildContext context) {
    final ActivityLevel? level = activityLevelFor(activity, preferences);
    final String cacheLabel = describeCacheOrigin(
      fromCache: activity.fromCache,
      isStale: activity.isStale,
      lastSuccessAtUnix: activity.lastSuccessAtUnix,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Card(
          child: InkWell(
            onTap: onTapHeader,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      AvatarWidget(
                        displayName: displayName,
                        avatarUrl: activity.avatarUrl,
                        isDemo: activity.isDemo,
                        size: 44,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              children: <Widget>[
                                Expanded(
                                  child: Text(
                                    displayName,
                                    style: const TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                      color: WatapColors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (activity.isDemo)
                                  Container(
                                    margin: const EdgeInsets.only(left: 6),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: WatapColors.warning.withValues(alpha: 0.16),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'DEMO',
                                      style: TextStyle(
                                        color: WatapColors.warning,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            ActivityBadge(level: level),
                            const SizedBox(height: 3),
                            Text(
                              'Última consulta: '
                              '${formatRelativeTime(activity.fetchedAtUnix)}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: WatapColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: isRefreshing
                            ? 'Actualizando $displayName'
                            : 'Actualizar $displayName',
                        onPressed: isRefreshing ? null : onRefresh,
                        icon: isRefreshing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: <Widget>[
                      _HeaderMetric(
                        label: 'Minutos recientes',
                        value: formatMinutes(activity.totalRecentMinutes),
                        emphasized: true,
                      ),
                      _HeaderMetric(
                        label: 'Tiempo acumulado',
                        value: formatMinutes(activity.totalForeverMinutes),
                      ),
                      _HeaderMetric(
                        label: 'Juegos',
                        value: '${activity.gamesCount}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      StatusChip(status: activity.status, dense: true),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          cacheLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            color: activity.fromCache || activity.isStale
                                ? WatapColors.warning
                                : WatapColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!activity.status.isAnswered &&
                      (activity.statusMessage ?? '').isNotEmpty) ...<Widget>[
                    const SizedBox(height: 8),
                    Text(
                      activity.statusMessage!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WatapColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (explainFetchStatus(activity.status).isNotEmpty) ...<Widget>[
                    const SizedBox(height: 4),
                    Text(
                      explainFetchStatus(activity.status),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: WatapColors.textSecondary,
                        fontStyle: FontStyle.italic,
                        height: 1.35,
                      ),
                    ),
                  ],
                  if (activity.fromCache && activity.games.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    const Text(
                      'Se muestran los datos guardados de la última consulta '
                      'correcta.',
                      style: TextStyle(
                        fontSize: 11,
                        color: WatapColors.warning,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        if (activity.games.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
            child: Text(
              activity.status.isAnswered
                  ? 'No hay juegos que mostrar con los filtros actuales.'
                  : 'No hay información de juegos guardada para este integrante.',
              style: const TextStyle(
                fontSize: 12.5,
                color: WatapColors.textSecondary,
              ),
            ),
          )
        else
          for (final Game game in activity.games)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: GameCard(
                game: game,
                showCover: preferences.showCovers,
                isDemo: activity.isDemo || game.isDemo,
                onOpenStore: () => onOpenStore(game),
              ),
            ),
      ],
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({
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
            fontSize: emphasized ? 17 : 15,
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
