/// Utilidades de interfaz compartidas.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';

/// Diálogo de confirmación para acciones destructivas.
///
/// Devuelve `true` solo si el usuario confirma explícitamente.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Eliminar',
  String cancelLabel = 'Cancelar',
  bool destructive = true,
}) async {
  final bool? result = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: destructive
              ? FilledButton.styleFrom(backgroundColor: Theme.of(ctx).colorScheme.error)
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Abre una URL con la aplicación del sistema.
///
/// Devuelve `true` si el sistema pudo abrirla. Nunca lanza.
Future<bool> openExternalUrl(
  BuildContext context,
  Uri uri, {
  String action = 'abrir el enlace',
}) async {
  final ScaffoldMessengerState messenger = ScaffoldMessenger.of(context);
  try {
    final bool launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(
        SnackBar(content: Text('No se pudo $action.')),
      );
      return false;
    }
    return true;
  } catch (_) {
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          'No se pudo $action: no hay ninguna aplicación compatible disponible.',
        ),
      ),
    );
    return false;
  }
}

/// Muestra un aviso breve.
void showMessage(BuildContext context, String message, {bool isError = false}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      backgroundColor: isError ? const Color(0xFF3A1E22) : null,
    ),
  );
}

/// Sección con título, usada en Ajustes y en pantallas de detalle.
class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.children,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: WatapColors.textSecondary,
                  letterSpacing: 0.6,
                ),
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: WatapColors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
        Card(
          child: Column(children: children),
        ),
      ],
    );
  }
}
