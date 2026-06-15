import 'package:flutter/material.dart';

import '../core/app_config.dart';

/// Builds [ThemeData] from the CMS branding so the webmaster's colour / font /
/// theme-mode choices drive the app's look. Pure mapping — no I/O.
class AppTheme {
  const AppTheme(this.branding);

  final BrandingConfig branding;

  Color get primary => parseHex(branding.primaryColor, fallback: const Color(0xFF2F7995));
  Color get secondary => parseHex(branding.secondaryColor, fallback: const Color(0xFF1D586F));
  Color get accent => parseHex(branding.accentColor, fallback: const Color(0xFFE8A33D));

  /// "light" | "dark" | "system" → Flutter [ThemeMode].
  ThemeMode get themeMode {
    switch (branding.themeMode.toLowerCase()) {
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'light':
      default:
        return ThemeMode.light;
    }
  }

  ThemeData get light => _build(Brightness.light);
  ThemeData get dark => _build(Brightness.dark);

  ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      secondary: secondary,
      tertiary: accent,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      // Empty/null fontFamily → platform default (Material handles null).
      fontFamily: branding.fontFamily,
      scaffoldBackgroundColor: scheme.surface,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      // NOTE: `CardTheme` is the correct type for `cardTheme` on Flutter 3.24
      // (the `CardThemeData` rename landed in a later stable). Keep this as
      // `CardTheme` to match `env.FLUTTER_VERSION` in build.yml.
      cardTheme: CardTheme(
        elevation: 1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: primary),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: accent.withOpacity(0.15),
        labelStyle: TextStyle(color: brightness == Brightness.dark ? scheme.onSurface : secondary),
      ),
    );
  }

  /// Parse "#RRGGBB" / "RRGGBB" / "#AARRGGBB" into a [Color]. Bad input →
  /// [fallback] so a typo in the CMS never crashes theme construction.
  static Color parseHex(String hex, {required Color fallback}) {
    var value = hex.trim();
    if (value.isEmpty) return fallback;
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) value = 'FF$value'; // assume opaque
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }
}
