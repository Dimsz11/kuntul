import 'package:flutter/material.dart';

import '../core/app_config.dart';

/// Builds [ThemeData] for the app.
///
/// PHASE 4c — single source of truth: when the CMS bakes a Design System token set into
/// `app_config.json` (`designTokens`, schema `cms2026.flutter-tokens/1`), the theme is built FROM THOSE
/// TOKENS — a [ColorScheme] from the semantic colors, a [TextTheme] from the type scale, and card / button
/// shapes from the radius scale, with `useMaterial3` taken from the tokens. When no token set is present
/// (older config / no DS theme), it FALLS BACK to the previous branding-colour theme so existing apps look
/// exactly as before.
///
/// Light + dark:
///   • If the config carries BOTH a light and a dark token set (`designTokens` + `designTokensDark`), each
///     drives its matching brightness.
///   • If it carries ONE set, that set drives its own brightness exactly and the other brightness is derived
///     from the same seed colour (so a single baked mode still yields a sensible dark/light counterpart).
///
/// Kept Cupertino-friendly: no Material-only widgets are referenced; only ThemeData/ColorScheme/TextTheme,
/// which a CupertinoApp can read via `MaterialBasedCupertinoThemeData` or ignore.
class AppTheme {
  /// Branding-only constructor (back-compat). Used when no Design System tokens are available.
  const AppTheme(this.branding)
      : tokens = null,
        tokensDark = null;

  /// Token-aware constructor — prefers [tokens]/[tokensDark]; [branding] remains the fallback per field.
  const AppTheme.fromConfig(AppConfig config)
      : branding = config.branding,
        tokens = config.designTokens,
        tokensDark = config.designTokensDark;

  final BrandingConfig branding;

  /// Primary Design System token set (its own brightness). Null → branding-driven theme.
  final DesignTokensConfig? tokens;

  /// Optional second token set for the opposite brightness (when the backend baked both).
  final DesignTokensConfig? tokensDark;

  // ── branding-derived seed colours (the fallback palette) ──
  Color get _brandPrimary => parseHex(branding.primaryColor, fallback: const Color(0xFF2F7995));
  Color get _brandSecondary => parseHex(branding.secondaryColor, fallback: const Color(0xFF1D586F));
  Color get _brandAccent => parseHex(branding.accentColor, fallback: const Color(0xFFE8A33D));

  /// "light" | "dark" | "system" → Flutter [ThemeMode]. Driven by branding (the webmaster's app-level
  /// choice); the token sets supply the *palette* for each brightness, not which mode is active.
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

  ThemeData get light => _themeFor(Brightness.light);
  ThemeData get dark => _themeFor(Brightness.dark);

  /// Pick the token set that matches [brightness], else build from branding.
  ThemeData _themeFor(Brightness brightness) {
    final wantDark = brightness == Brightness.dark;

    // Choose the best-matching baked token set for this brightness.
    final DesignTokensConfig? primarySet = tokens;
    final DesignTokensConfig? darkSet = tokensDark;
    DesignTokensConfig? chosen;
    if (primarySet != null || darkSet != null) {
      final light = primarySet != null && !primarySet.isDark
          ? primarySet
          : (darkSet != null && !darkSet.isDark ? darkSet : null);
      final darkT = darkSet != null && darkSet.isDark
          ? darkSet
          : (primarySet != null && primarySet.isDark ? primarySet : null);
      // Prefer the exact-brightness set; otherwise use whichever set exists (palette still applies).
      chosen = wantDark ? (darkT ?? light ?? primarySet) : (light ?? darkT ?? primarySet);
    }

    return chosen != null
        ? _buildFromTokens(chosen, brightness)
        : _buildFromBranding(brightness);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TOKEN-DRIVEN THEME (Phase 4c)
  // ══════════════════════════════════════════════════════════════════════════
  ThemeData _buildFromTokens(DesignTokensConfig t, Brightness brightness) {
    Color col(String role, Color fallback) => _hexOr(t.color(role), fallback);

    final primary = col('primary', _brandPrimary);
    final secondary = col('secondary', _brandSecondary);
    final tertiary = col('accent', _brandAccent);
    final surface = col('surface', brightness == Brightness.dark ? const Color(0xFF111827) : Colors.white);
    final error = col('error', const Color(0xFFB00020));

    // Build a complete scheme from the seed, then override the roles the tokens define explicitly.
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    ).copyWith(
      primary: primary,
      onPrimary: col('onPrimary', _onColor(primary)),
      secondary: secondary,
      onSecondary: col('onSecondary', _onColor(secondary)),
      tertiary: tertiary,
      onTertiary: col('onAccent', _onColor(tertiary)),
      surface: surface,
      onSurface: col('onSurface', _onColor(surface)),
      error: error,
      onError: col('onError', _onColor(error)),
      // Only override outline when the tokens define it (null leaves the seed-derived value untouched).
      outline: t.color('outline') != null ? col('outline', const Color(0xFFCBD5E1)) : null,
    );

    final radius = t.radiusOf('lg', 12);
    final fontFamily = (t.fontFamilyHeading?.isNotEmpty == true)
        ? _firstFamily(t.fontFamilyHeading!)
        : (t.fontFamilyBase?.isNotEmpty == true ? _firstFamily(t.fontFamilyBase!) : branding.fontFamily);

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: t.useMaterial3,
      fontFamily: fontFamily,
      scaffoldBackgroundColor: scheme.surface,
    );

    final textTheme = _textThemeFromTokens(t, base.textTheme, scheme.onSurface);

    return base.copyWith(
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      // NOTE: `CardTheme` is the correct type for `cardTheme` on Flutter 3.24 (the `CardThemeData` rename
      // landed later). Keep `CardTheme` to match env.FLUTTER_VERSION in build.yml.
      cardTheme: CardTheme(
        elevation: 1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusOf('md', 8))),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusOf('md', 8))),
        ),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tertiary.withOpacity(0.15),
        labelStyle: TextStyle(color: brightness == Brightness.dark ? scheme.onSurface : secondary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(t.radiusOf('pill', 999))),
      ),
    );
  }

  /// Map the token type scale onto a [TextTheme] (size / weight / height / letterSpacing), filling any
  /// missing role from the platform default so a partial scale still produces a complete TextTheme.
  TextTheme _textThemeFromTokens(DesignTokensConfig t, TextTheme base, Color onSurface) {
    TextStyle? styleFor(String role, TextStyle? fallback) {
      final tok = t.typeScale[role];
      if (tok == null) return fallback;
      return (fallback ?? const TextStyle()).copyWith(
        fontSize: tok.size,
        fontWeight: tok.weight != null ? _fontWeight(tok.weight!) : null,
        height: tok.height,
        letterSpacing: tok.letterSpacing,
        color: (fallback?.color) ?? onSurface,
      );
    }

    // Map our roles → Material 3 TextTheme slots (closest-fit).
    return base.copyWith(
      displayLarge: styleFor('display', base.displayLarge),
      headlineLarge: styleFor('h1', base.headlineLarge),
      headlineMedium: styleFor('h2', base.headlineMedium),
      titleLarge: styleFor('title', base.titleLarge),
      bodyLarge: styleFor('body', base.bodyLarge),
      bodyMedium: styleFor('body', base.bodyMedium),
      labelLarge: styleFor('label', base.labelLarge),
      labelSmall: styleFor('caption', base.labelSmall),
      bodySmall: styleFor('caption', base.bodySmall),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BRANDING-DERIVED THEME (fallback — unchanged behaviour from before Phase 4c)
  // ══════════════════════════════════════════════════════════════════════════
  ThemeData _buildFromBranding(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _brandPrimary,
      brightness: brightness,
      primary: _brandPrimary,
      secondary: _brandSecondary,
      tertiary: _brandAccent,
    );

    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: branding.fontFamily,
      scaffoldBackgroundColor: scheme.surface,
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: _brandPrimary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        centerTitle: true,
      ),
      cardTheme: CardTheme(
        elevation: 1,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(backgroundColor: _brandPrimary),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: _brandAccent.withOpacity(0.15),
        labelStyle: TextStyle(color: brightness == Brightness.dark ? scheme.onSurface : _brandSecondary),
      ),
    );
  }

  // ── helpers ──

  /// Parse a token hex into a [Color], or [fallback] when null/invalid.
  static Color _hexOr(String? hex, Color fallback) =>
      hex == null ? fallback : parseHex(hex, fallback: fallback);

  /// A readable on-color (black/white) for [bg] based on luminance — used when a token omits its on-color.
  static Color _onColor(Color bg) =>
      bg.computeLuminance() > 0.5 ? const Color(0xFF1A1A1A) : Colors.white;

  /// Map a numeric token weight (100..900) to the nearest [FontWeight].
  static FontWeight _fontWeight(int w) {
    const map = {
      100: FontWeight.w100, 200: FontWeight.w200, 300: FontWeight.w300,
      400: FontWeight.w400, 500: FontWeight.w500, 600: FontWeight.w600,
      700: FontWeight.w700, 800: FontWeight.w800, 900: FontWeight.w900,
    };
    final int rounded = ((w / 100).round().clamp(1, 9) * 100).toInt();
    return map[rounded] ?? FontWeight.w400;
  }

  /// The first family from a CSS-style font stack ("'Tajawal', 'Segoe UI', sans-serif" → "Tajawal").
  static String _firstFamily(String stack) {
    final first = stack.split(',').first.trim().replaceAll("'", '').replaceAll('"', '');
    return first.isEmpty ? stack.trim() : first;
  }

  /// Parse "#RRGGBB" / "RRGGBB" / "#AARRGGBB" into a [Color]. Bad input → [fallback] so a typo in the CMS
  /// never crashes theme construction.
  static Color parseHex(String hex, {required Color fallback}) {
    var value = hex.trim();
    if (value.isEmpty) return fallback;
    if (value.startsWith('#')) value = value.substring(1);
    if (value.length == 6) value = 'FF$value'; // assume opaque
    final parsed = int.tryParse(value, radix: 16);
    return parsed == null ? fallback : Color(parsed);
  }
}
