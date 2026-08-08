import 'package:flutter/material.dart';

/// App-wide theming (Material 3, light + dark, strictly black & white).
abstract final class AppTheme {
  static ThemeData light() =>
      _base(Brightness.light, _scheme(Brightness.light));

  static ThemeData dark() => _base(Brightness.dark, _scheme(Brightness.dark));

  static ColorScheme _scheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final Color bg = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    final Color surface = isDark
        ? const Color(0xFF111111)
        : const Color(0xFFFFFFFF);
    final Color surfaceHigh = isDark
        ? const Color(0xFF1E1E1E)
        : const Color(0xFFF1F1F1);
    final Color ink = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    final Color paper = isDark
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    final Color accent = isDark
        ? const Color(0xFFE0E0E0)
        : const Color(0xFF262626);
    final Color accentPaper = isDark
        ? const Color(0xFF111111)
        : const Color(0xFFFFFFFF);
    final Color muted = isDark
        ? const Color(0xFF9E9E9E)
        : const Color(0xFF616161);
    final Color container = isDark
        ? const Color(0xFF262626)
        : const Color(0xFFE8E8E8);
    final Color outline = isDark
        ? const Color(0xFF3D3D3D)
        : const Color(0xFFCFCFCF);
    final Color outlineVariant = isDark
        ? const Color(0xFF2C2C2C)
        : const Color(0xFFE2E2E2);

    return ColorScheme.fromSeed(
      seedColor: const Color(0xFF616161),
      brightness: brightness,
    ).copyWith(
      primary: ink,
      onPrimary: paper,
      primaryContainer: container,
      onPrimaryContainer: ink,
      secondary: accent,
      onSecondary: accentPaper,
      secondaryContainer: container,
      onSecondaryContainer: ink,
      tertiary: accent,
      onTertiary: accentPaper,
      tertiaryContainer: container,
      onTertiaryContainer: ink,
      error: muted,
      onError: paper,
      errorContainer: container,
      onErrorContainer: ink,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      surfaceDim: isDark ? const Color(0xFF000000) : const Color(0xFFF7F7F7),
      surfaceBright: surface,
      surfaceContainerLowest: bg,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: surfaceHigh,
      outline: outline,
      outlineVariant: outlineVariant,
      inverseSurface: isDark
          ? const Color(0xFFFFFFFF)
          : const Color(0xFF000000),
      onInverseSurface: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF),
      inversePrimary: isDark
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF),
      shadow: Colors.transparent,
      scrim: Colors.transparent,
    );
  }

  static ThemeData _base(Brightness brightness, ColorScheme scheme) {
    final isDark = brightness == Brightness.dark;
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surfaceContainerLowest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        margin: EdgeInsets.zero,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primary,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
          );
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark
            ? const Color(0xFFFFFFFF)
            : const Color(0xFF000000),
        contentTextStyle: TextStyle(
          color: isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
