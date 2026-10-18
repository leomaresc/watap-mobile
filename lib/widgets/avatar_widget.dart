/// Avatar de un perfil con recurso alternativo por iniciales.
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'network_image_policy.dart';

/// Avatar circular de un integrante.
class AvatarWidget extends StatelessWidget {
  const AvatarWidget({
    super.key,
    required this.displayName,
    this.avatarUrl,
    this.size = 44,
  });

  final String displayName;
  final String? avatarUrl;
  final double size;

  String get _initials {
    final String name = displayName.trim();
    if (name.isEmpty) return '?';
    final List<String> parts =
        name.split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      return _firstChars(parts.first, 2).toUpperCase();
    }
    return (_firstChars(parts[0], 1) + _firstChars(parts[1], 1)).toUpperCase();
  }

  /// Toma los primeros [count] caracteres respetando los pares subrogados.
  static String _firstChars(String value, int count) {
    final List<int> runes = value.runes.toList(growable: false);
    if (runes.isEmpty) return '?';
    final int end = count < runes.length ? count : runes.length;
    return String.fromCharCodes(runes.sublist(0, end));
  }

  @override
  Widget build(BuildContext context) {
    final String? url = avatarUrl;
    final Widget fallback = _InitialsAvatar(
      initials: _initials,
      size: size,
    );

    if (url == null || url.trim().isEmpty || !watapRemoteImagesEnabled) {
      return Semantics(
        label: 'Avatar de $displayName',
        child: fallback,
      );
    }

    return Semantics(
      label: 'Avatar de $displayName',
      image: true,
      child: ClipOval(
        child: CachedNetworkImage(
          imageUrl: url,
          width: size,
          height: size,
          fit: BoxFit.cover,
          memCacheWidth: (size * 3).round(),
          placeholder: (BuildContext context, String _) => fallback,
          errorWidget: (BuildContext context, String _, Object __) => fallback,
        ),
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  const _InitialsAvatar({
    required this.initials,
    required this.size,
  });

  final String initials;
  final double size;

  @override
  Widget build(BuildContext context) {
    const Color base = WatapColors.accent;
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: base.withValues(alpha: 0.18),
        border: Border.all(color: base.withValues(alpha: 0.45)),
      ),
      child: Text(
        initials,
        style: TextStyle(
          color: base,
          fontWeight: FontWeight.w700,
          fontSize: size * 0.36,
        ),
      ),
    );
  }
}
