/// Indicadores de carga y avisos en línea.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Indicador de carga con texto opcional.
///
/// Se usa mientras llegan datos, sin bloquear el resto de la pantalla.
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.message, this.compact = false});

  final String? message;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: compact ? 16 : 40, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: compact ? 18 : 26,
              height: compact ? 18 : 26,
              child: const CircularProgressIndicator(strokeWidth: 2.4),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WatapColors.textSecondary,
                  fontSize: 13.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Aviso en línea, informativo y no bloqueante.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.color = WatapColors.accent,
    this.actionLabel,
    this.onAction,
  });

  final String message;
  final IconData icon;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: WatapColors.textPrimary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!, style: const TextStyle(fontSize: 13)),
            ),
        ],
      ),
    );
  }
}
