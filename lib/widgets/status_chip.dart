/// Etiquetas de estado de consulta.
library;

import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/models.dart';
import '../theme/app_theme.dart';

/// Color asociado a un estado de consulta.
Color fetchStatusColor(FetchStatus status) => switch (status) {
      FetchStatus.ok => WatapColors.success,
      FetchStatus.noRecentGames => WatapColors.accent,
      FetchStatus.notFetched => WatapColors.textSecondary,
      FetchStatus.privateOrUnavailable => WatapColors.warning,
      FetchStatus.rateLimited => WatapColors.warning,
      FetchStatus.networkError => WatapColors.activityHigh,
      FetchStatus.invalidProfile => WatapColors.activityHigh,
      FetchStatus.malformedResponse => WatapColors.activityHigh,
      FetchStatus.incompleteConfiguration => WatapColors.warning,
    };

/// Icono asociado a un estado de consulta.
IconData fetchStatusIcon(FetchStatus status) => switch (status) {
      FetchStatus.ok => Icons.check_circle_outline,
      FetchStatus.noRecentGames => Icons.remove_circle_outline,
      FetchStatus.notFetched => Icons.hourglass_empty,
      FetchStatus.privateOrUnavailable => Icons.lock_outline,
      FetchStatus.rateLimited => Icons.hourglass_top,
      FetchStatus.networkError => Icons.cloud_off,
      FetchStatus.invalidProfile => Icons.person_off_outlined,
      FetchStatus.malformedResponse => Icons.report_gmailerrorred,
      FetchStatus.incompleteConfiguration => Icons.settings_suggest_outlined,
    };

/// Etiqueta compacta con el estado de la consulta.
class StatusChip extends StatelessWidget {
  const StatusChip({
    super.key,
    required this.status,
    this.label,
    this.dense = false,
  });

  final FetchStatus status;
  final String? label;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final Color color = fetchStatusColor(status);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(fetchStatusIcon(status), size: dense ? 11 : 13, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label ?? describeFetchStatus(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: dense ? 10.5 : 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Etiqueta de nivel de actividad con la escala de color de WATAP.
class ActivityBadge extends StatelessWidget {
  const ActivityBadge({super.key, required this.level});

  final ActivityLevel? level;

  @override
  Widget build(BuildContext context) {
    final Color color = Color(activityLevelColorValue(level));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            describeActivityLevel(level),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: color,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
