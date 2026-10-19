/// Cabecera de WATAP.
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

/// Cabecera compacta con nombre, contexto de la cuenta conectada,
/// actualización rápida y aviso de configuración pendiente.
class WatapHeader extends StatelessWidget implements PreferredSizeWidget {
  const WatapHeader({
    super.key,
    required this.controller,
    this.onRefresh,
    this.showRefresh = true,
  });

  final AppController controller;
  final VoidCallback? onRefresh;
  final bool showRefresh;

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final bool busy = controller.isRefreshingAll;
    final String? hint = _contextLine(controller);

    return AppBar(
      toolbarHeight: 60,
      titleSpacing: 16,
      title: Row(
        children: <Widget>[
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: WatapColors.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: WatapColors.accent.withValues(alpha: 0.4)),
            ),
            child: const Text(
              'W',
              style: TextStyle(
                color: WatapColors.accent,
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                const Text(
                  AppConstants.appName,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                    color: WatapColors.textPrimary,
                  ),
                ),
                Text(
                  hint ?? AppConstants.appSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: hint != null
                        ? WatapColors.warning
                        : WatapColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: <Widget>[
        if (!controller.onboardingComplete)
          IconButton(
            tooltip: 'Terminar la configuración',
            onPressed: () => controller.setSection(AppSection.settings),
            icon: const Icon(
              Icons.error_outline,
              color: WatapColors.warning,
              semanticLabel: 'Configuración pendiente',
            ),
          ),
        if (showRefresh)
          IconButton(
            tooltip: busy ? 'Actualizando…' : 'Actualizar todos los integrantes',
            onPressed: busy ? null : onRefresh,
            icon: busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.2),
                  )
                : const Icon(
                    Icons.refresh,
                    semanticLabel: 'Actualizar todos los integrantes',
                  ),
          ),
      ],
    );
  }

  /// Segunda línea de la cabecera.
  ///
  /// Devuelve `null` cuando no hay nada que avisar, en cuyo caso se usa el
  /// subtítulo habitual de la aplicación.
  static String? _contextLine(AppController controller) {
    if (!controller.hasSteamAuth) {
      return 'Conecta tu Steam para importar tu grupo familiar.';
    }
    final String? group = controller.familyGroupName;
    if (group != null && group.trim().isNotEmpty) {
      return 'Familia: ${group.trim()}';
    }
    if (!controller.hasProfiles) {
      return 'Sincroniza para cargar tu grupo familiar.';
    }
    return null;
  }
}
