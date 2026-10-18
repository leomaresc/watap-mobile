/// Tarjetas de juego.
library;

import 'package:flutter/material.dart';

import '../../core/formatters.dart';
import '../../core/models.dart';
import '../../services/activity_aggregator.dart';
import '../../theme/app_theme.dart';
import '../../widgets/cover_widget.dart';

/// Tarjeta de un juego con los minutos que Steam ha comunicado.
class GameCard extends StatelessWidget {
  const GameCard({
    super.key,
    required this.game,
    required this.onOpenStore,
    this.showCover = true,
    this.memberName,
  });

  final Game game;
  final VoidCallback onOpenStore;
  final bool showCover;

  /// Nombre del integrante al que pertenece la tarjeta (opcional).
  final String? memberName;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (showCover) ...<Widget>[
              CoverWidget(
                title: game.label,
                coverUrl: game.coverUrl,
              ),
              const SizedBox(width: 12),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          game.label,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: WatapColors.textPrimary,
                            height: 1.25,
                          ),
                        ),
                      ),

                    ],
                  ),
                  if (memberName != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      memberName!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: WatapColors.textSecondary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 14,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      _Metric(
                        label: 'Últimas 2 semanas',
                        value: formatMinutes(game.playtime2Weeks),
                        emphasized: true,
                      ),
                      _Metric(
                        label: 'Tiempo acumulado',
                        // Un dato no comunicado por Steam se muestra como guion,
                        // nunca como cero.
                        value: formatMinutes(game.playtimeForever),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Abrir la página de Steam de ${game.label}',
              onPressed: onOpenStore,
              icon: const Icon(Icons.open_in_new, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
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
            fontSize: emphasized ? 15 : 13.5,
            fontWeight: emphasized ? FontWeight.w800 : FontWeight.w600,
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

/// Tarjeta de un juego agregado por AppID con el desglose por integrante.
class AggregatedGameCard extends StatelessWidget {
  const AggregatedGameCard({
    super.key,
    required this.game,
    required this.onOpenStore,
    this.showCover = true,
    this.onTapMember,
  });

  final AggregatedGame game;
  final VoidCallback onOpenStore;
  final bool showCover;
  final void Function(MemberContribution contribution)? onTapMember;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                if (showCover) ...<Widget>[
                  CoverWidget(
                    title: game.name,
                    coverUrl: game.coverUrl,
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              game.name,
                              style: const TextStyle(
                                fontSize: 14.5,
                                fontWeight: FontWeight.w700,
                                color: WatapColors.textPrimary,
                                height: 1.25,
                              ),
                            ),
                          ),

                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'AppID ${game.appId} · ${game.memberCount} '
                        'integrante${game.memberCount == 1 ? '' : 's'} con '
                        'actividad reciente',
                        style: const TextStyle(
                          fontSize: 11,
                          color: WatapColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 14,
                        runSpacing: 4,
                        children: <Widget>[
                          _Metric(
                            label: 'Últimas 2 semanas (suma)',
                            value: formatMinutes(game.recentMinutes),
                            emphasized: true,
                          ),
                          _Metric(
                            label: game.hasCompleteForever
                                ? 'Tiempo acumulado (suma)'
                                : 'Tiempo acumulado (incompleto)',
                            value: formatMinutes(game.foreverMinutes),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Abrir la página de Steam de ${game.name}',
                  onPressed: onOpenStore,
                  icon: const Icon(Icons.open_in_new, size: 18),
                ),
              ],
            ),
            if (game.topSteamId64 != null) ...<Widget>[
              const SizedBox(height: 10),
              Row(
                children: <Widget>[
                  const Icon(
                    Icons.trending_up,
                    size: 14,
                    color: WatapColors.activityModerate,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Mayor actividad reciente: ${game.topDisplayName} '
                      '(${formatMinutes(game.topRecentMinutes)})',
                      style: const TextStyle(
                        fontSize: 12,
                        color: WatapColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            const Text(
              'Desglose por integrante (minutos de las últimas 2 semanas)',
              style: TextStyle(fontSize: 11, color: WatapColors.textSecondary),
            ),
            const SizedBox(height: 6),
            for (final MemberContribution contribution in game.contributions)
              InkWell(
                onTap: onTapMember == null ? null : () => onTapMember!(contribution),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          contribution.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            color: WatapColors.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        formatMinutes(contribution.recentMinutes),
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: WatapColors.accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 92,
                        child: Text(
                          formatMinutes(contribution.foreverMinutes),
                          textAlign: TextAlign.right,
                          style: const TextStyle(
                            fontSize: 12,
                            color: WatapColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 4),
            const Text(
              'Los totales son sumas de tiempo registrado por Steam. No '
              'representan juego simultáneo ni el estado actual de nadie.',
              style: TextStyle(
                fontSize: 10.5,
                color: WatapColors.textSecondary,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
