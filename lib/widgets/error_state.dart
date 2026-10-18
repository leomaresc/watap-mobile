/// Estado de error recuperable.
library;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Muestra un error sin cerrar la aplicación y ofrece reintentar.
class ErrorState extends StatelessWidget {
  const ErrorState({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
    this.retryLabel = 'Reintentar',
    this.detail,
  });

  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  /// Detalle técnico sin secretos (por ejemplo, el código HTTP).
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.error_outline,
              size: 34,
              color: WatapColors.activityHigh,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: WatapColors.textSecondary,
                fontSize: 14,
                height: 1.45,
              ),
            ),
            if (detail != null) ...<Widget>[
              const SizedBox(height: 10),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: WatapColors.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
            if (onRetry != null) ...<Widget>[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
