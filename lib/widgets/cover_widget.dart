/// Portada de un juego con recurso alternativo tolerante a fallos.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'network_image_policy.dart';

/// Miniatura de la portada de un juego.
///
/// Si la imagen no está disponible (CDN caído, URL inexistente, tiempo de
/// espera) se muestra un recurso visual alternativo y **toda la información
/// textual del juego se conserva**.
class CoverWidget extends StatelessWidget {
  const CoverWidget({
    super.key,
    required this.title,
    this.coverUrl,
    this.fallbackUrl,
    this.width = 92,
    this.height = 43,
    this.isDemo = false,
  });

  final String title;
  final String? coverUrl;

  /// URL secundaria (por ejemplo, la cápsula pequeña del CDN).
  final String? fallbackUrl;

  final double width;
  final double height;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final String url = (coverUrl ?? '').trim();
    final Widget placeholder = _CoverPlaceholder(
      title: title,
      width: width,
      height: height,
      isDemo: isDemo,
    );
    final String fallback = (fallbackUrl ?? '').trim();

    if (url.isEmpty || !watapRemoteImagesEnabled) {
      if (fallback.isEmpty || !watapRemoteImagesEnabled) return placeholder;
      return _networkImage(fallback, placeholder, placeholder);
    }

    return _networkImage(url, placeholder, placeholder);
  }

  Widget _networkImage(String url, Widget placeholder, Widget errorWidget) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: CachedNetworkImage(
        imageUrl: url,
        width: width,
        height: height,
        fit: BoxFit.cover,
        memCacheWidth: (width * 2.4).round(),
        fadeInDuration: const Duration(milliseconds: 180),
        placeholder: (BuildContext context, String _) => placeholder,
        errorWidget: (BuildContext context, String _, Object __) {
          final String fallback = (fallbackUrl ?? '').trim();
          if (fallback.isNotEmpty && fallback != url) {
            return CachedNetworkImage(
              imageUrl: fallback,
              width: width,
              height: height,
              fit: BoxFit.cover,
              memCacheWidth: (width * 2.4).round(),
              placeholder: (BuildContext context, String _) => errorWidget,
              errorWidget: (BuildContext context, String _, Object __) => errorWidget,
            );
          }
          return errorWidget;
        },
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({
    required this.title,
    required this.width,
    required this.height,
    required this.isDemo,
  });

  final String title;
  final double width;
  final double height;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    final Color accent = isDemo ? WatapColors.warning : WatapColors.accent;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: WatapColors.border),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            WatapColors.panelAlt,
            Color.alphaBlend(accent.withValues(alpha: 0.14), WatapColors.panelAlt),
          ],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.videogame_asset_outlined,
        size: height * 0.45,
        color: accent.withValues(alpha: 0.75),
        semanticLabel: 'Portada no disponible para $title',
      ),
    );
  }
}
