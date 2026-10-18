/// Identidad visual de WATAP Mobile.
///
/// Paleta oscura inspirada en Steam, adaptada a pantallas pequeñas y a
/// navegación táctil. No es una copia del diseño de escritorio.
library;

import 'package:flutter/material.dart';

/// Colores corporativos de WATAP Mobile.
class WatapColors {
  const WatapColors._();

  static const Color background = Color(0xFF14151A);
  static const Color panel = Color(0xFF1B1D24);
  static const Color panelAlt = Color(0xFF21232C);
  static const Color card = Color(0xFF23252E);
  static const Color textPrimary = Color(0xFFE7E9EE);
  static const Color textSecondary = Color(0xFF9BA1B0);
  static const Color border = Color(0xFF31343F);
  static const Color accent = Color(0xFF66C0F4);
  static const Color activityHigh = Color(0xFFE06C75);
  static const Color activityModerate = Color(0xFFE0B341);
  static const Color activityLow = Color(0xFF7BC96F);
  static const Color danger = Color(0xFFE06C75);
  static const Color success = Color(0xFF7BC96F);
  static const Color warning = Color(0xFFE0B341);
}

/// Tema Material 3 de la aplicación.
class AppTheme {
  const AppTheme._();

  /// Espaciado base usado en toda la interfaz.
  static const double gap = 12;
  static const double radius = 14;

  static ThemeData dark() {
    const ColorScheme scheme = ColorScheme.dark(
      primary: WatapColors.accent,
      onPrimary: Color(0xFF08202C),
      primaryContainer: Color(0xFF1E3A4C),
      onPrimaryContainer: WatapColors.textPrimary,
      secondary: WatapColors.activityModerate,
      onSecondary: Color(0xFF241A00),
      surface: WatapColors.panel,
      onSurface: WatapColors.textPrimary,
      surfaceContainerHighest: WatapColors.card,
      error: WatapColors.danger,
      onError: Color(0xFF2A0B0E),
      outline: WatapColors.border,
      outlineVariant: WatapColors.border,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: WatapColors.background,
      canvasColor: WatapColors.background,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
    );

    return base.copyWith(
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: WatapColors.background,
        foregroundColor: WatapColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      dividerTheme: const DividerThemeData(
        color: WatapColors.border,
        thickness: 1,
        space: 1,
      ),
      cardTheme: CardThemeData(
        color: WatapColors.card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: const BorderSide(color: WatapColors.border),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: WatapColors.textSecondary,
        textColor: WatapColors.textPrimary,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: WatapColors.panelAlt,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        hintStyle: const TextStyle(color: WatapColors.textSecondary),
        labelStyle: const TextStyle(color: WatapColors.textSecondary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WatapColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WatapColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WatapColors.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: WatapColors.danger),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: WatapColors.border),
          foregroundColor: WatapColors.textPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 44),
          foregroundColor: WatapColors.accent,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: WatapColors.panel,
        indicatorColor: WatapColors.accent.withValues(alpha: 0.16),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>(
          (Set<WidgetState> states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w500,
            color: states.contains(WidgetState.selected)
                ? WatapColors.accent
                : WatapColors.textSecondary,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith<IconThemeData>(
          (Set<WidgetState> states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? WatapColors.accent
                : WatapColors.textSecondary,
          ),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: WatapColors.panelAlt,
        selectedColor: WatapColors.accent.withValues(alpha: 0.18),
        side: const BorderSide(color: WatapColors.border),
        labelStyle: const TextStyle(color: WatapColors.textPrimary, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: WatapColors.panelAlt,
        contentTextStyle: TextStyle(color: WatapColors.textPrimary),
        behavior: SnackBarBehavior.floating,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: WatapColors.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        titleTextStyle: const TextStyle(
          color: WatapColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle:
            const TextStyle(color: WatapColors.textSecondary, fontSize: 14.5, height: 1.4),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: WatapColors.panel,
        surfaceTintColor: Colors.transparent,
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: WatapColors.accent),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> s) => s.contains(WidgetState.selected)
              ? WatapColors.accent
              : WatapColors.textSecondary,
        ),
        trackColor: WidgetStateProperty.resolveWith<Color>(
          (Set<WidgetState> s) => s.contains(WidgetState.selected)
              ? WatapColors.accent.withValues(alpha: 0.3)
              : WatapColors.panelAlt,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: WatapColors.panelAlt,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: const TextStyle(color: WatapColors.textPrimary, fontSize: 12),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          side: WidgetStateProperty.all(
            const BorderSide(color: WatapColors.border),
          ),
          foregroundColor: WidgetStateProperty.resolveWith<Color>(
            (Set<WidgetState> s) => s.contains(WidgetState.selected)
                ? WatapColors.accent
                : WatapColors.textSecondary,
          ),
          backgroundColor: WidgetStateProperty.resolveWith<Color>(
            (Set<WidgetState> s) => s.contains(WidgetState.selected)
                ? WatapColors.accent.withValues(alpha: 0.14)
                : WatapColors.panelAlt,
          ),
        ),
      ),
    );
  }

  static TextTheme _textTheme(TextTheme base) {
    // Se usa la tipografía del sistema (Roboto en Android, SF en iOS) para
    // maximizar legibilidad y respetar el escalado de accesibilidad.
    return base
        .copyWith(
          headlineSmall: base.headlineSmall?.copyWith(
            color: WatapColors.textPrimary,
            fontWeight: FontWeight.w700,
          ),
          titleLarge: base.titleLarge?.copyWith(
            color: WatapColors.textPrimary,
            fontWeight: FontWeight.w700,
            fontSize: 20,
          ),
          titleMedium: base.titleMedium?.copyWith(
            color: WatapColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          titleSmall: base.titleSmall?.copyWith(
            color: WatapColors.textPrimary,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          bodyLarge: base.bodyLarge?.copyWith(color: WatapColors.textPrimary),
          bodyMedium: base.bodyMedium?.copyWith(color: WatapColors.textPrimary),
          bodySmall: base.bodySmall?.copyWith(color: WatapColors.textSecondary),
          labelLarge: base.labelLarge?.copyWith(
            color: WatapColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: base.labelMedium?.copyWith(color: WatapColors.textSecondary),
          labelSmall: base.labelSmall?.copyWith(color: WatapColors.textSecondary),
        )
        .apply(
          bodyColor: WatapColors.textPrimary,
          displayColor: WatapColors.textPrimary,
        );
  }
}
