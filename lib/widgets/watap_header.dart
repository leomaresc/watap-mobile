/// Cabecera de WATAP.
library;

import 'package:flutter/material.dart';

import '../core/constants.dart';
import '../state/app_controller.dart';
import '../theme/app_theme.dart';

/// Cabecera compacta con nombre, subtítulo, indicador de demostración,
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
    final bool demo = controller.showingDemoData;
    final bool busy = controller.isRefreshingAll;

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
                Row(
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
                    if (demo) ...<Widget>[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: WatapColors.warning.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: WatapColors.warning.withValues(alpha: 0.5),
                          ),
                        ),
                        child: const Text(
                          AppConstants.demoLabel,
                          style: TextStyle(
                            color: WatapColors.warning,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  controller.setupHint ?? AppConstants.appSubtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: controller.setupHint != null
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
        if (controller.needsSetup)
          IconButton(
            tooltip: controller.setupHint ?? 'Configuración pendiente',
            onPressed: controller.needsSetup
                ? () => controller.setSection(AppSection.settings)
                : null,
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
}
