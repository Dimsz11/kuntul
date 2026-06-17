import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import 'models.dart' show MenuItem, HomeSection;

/// Typed view over `assets/config/app_config.json`.
///
/// The CI workflow (`.github/workflows/build.yml` → "Inject app_config.json")
/// writes the CMS-generated config (the byte-for-byte output of the backend
/// `AppConfigBuilder`) to that asset before building, so whatever the webmaster
/// configured in the admin is what the app boots with — including the **per-app
/// menu, home layout and navigation style** baked right in.
///
/// The baked shape (see `AppConfigBuilder.BuildAppConfigAsync`):
/// ```jsonc
/// {
///   "app":   { "appId": "com.jsc.app", "appName": "…", "bundleId": "…",
///              "versionName": "1.0.0", "versionCode": 1 },
///   "api":   { "baseUrl": "https://host", "mobileEndpoint": "/mobile", "timeout": 30000 },
///   "branding":   { "primaryColor": "#…", …, "fontFamily": "Cairo" },
///   "navigation": { "style": "drawer" | "bottomnav" | "both" },
///   "modules":    [ { "name": "news", "enabled": true, "icon": "newspaper",
///                     "route": "/news", "displayOrder": 2, "titleAr": "…", "titleEn": "…" } ],
///   "home":       [ { "type": "slider", "title": "…", "config": { … }, "order": 1 } ],
///   "languages":  { "default": "ar", "supported": ["ar","en"], "rtlLanguages": ["ar"] },
///   "features":   { "pushNotifications": true, "darkMode": false, … }
/// }
/// ```
///
/// A legacy/flat config (top-level `appName`, `appId`, `modules:["news"]`,
/// `features:{search:true}`, `languages.rtl`) is still accepted — every reader
/// below checks both the nested and the flat location. Everything is null-safe
/// with sensible defaults so a missing/partial config never crashes startup.
class AppConfig {
  AppConfig({
    required this.appName,
    required this.appNameEn,
    required this.appId,
    required this.versionName,
    required this.versionCode,
    required this.api,
    required this.branding,
    required this.languages,
    required this.navigation,
    required this.modules,
    required this.bakedMenu,
    required this.bakedHome,
    required this.features,
    required this.firebase,
    this.designTokens,
    this.designTokensDark,
  });

  final String appName;
  final String appNameEn;
  final String appId;
  final String versionName;
  final int versionCode;
  final ApiConfig api;
  final BrandingConfig branding;
  final LanguageConfig languages;
  final NavigationConfig navigation;

  /// Enabled module names (the simple list, derived from the baked `modules`).
  final List<String> modules;

  /// Baked menu items (from the `modules` array) — rendered instantly on first
  /// launch, before the OTA `GET /api/mobile/menu?app=` refresh returns.
  final List<MenuItem> bakedMenu;

  /// Baked home sections (from the `home` array) — rendered instantly on first
  /// launch, before the OTA `GET /api/mobile/home-layout?app=` refresh returns.
  final List<HomeSection> bakedHome;

  final Map<String, bool> features;
  final FirebaseConfig firebase;

  /// Design System tokens (Phase 4c) baked into `app_config.json` under `designTokens`
  /// (schema `cms2026.flutter-tokens/1`). The RICHER styling source — when present, [AppTheme]
  /// builds [ThemeData] from it; otherwise it falls back to [branding]. Null when the config predates
  /// the Design System (older backend) so old apps keep their branding-driven look. See [AppTheme].
  final DesignTokensConfig? designTokens;

  /// Optional second token set for the OPPOSITE brightness, when the backend bakes both light + dark
  /// (e.g. under `designTokensDark`). When present, [AppTheme] uses each for its matching brightness;
  /// when absent, the single [designTokens] set drives both (its own brightness exact, the other derived).
  final DesignTokensConfig? designTokensDark;

  /// Resolve the app title for [langCode] (falls back to the Arabic name).
  String titleFor(String langCode) =>
      langCode == 'en' && appNameEn.isNotEmpty ? appNameEn : appName;

  bool featureEnabled(String key) => features[key] ?? false;

  /// Loads and parses the bundled config asset. Never throws: on any failure
  /// it returns [AppConfig.fallback] so the app can still start.
  static Future<AppConfig> load({
    String assetPath = 'assets/config/app_config.json',
  }) async {
    try {
      final raw = await rootBundle.loadString(assetPath);
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return AppConfig.fromJson(json);
    } catch (_) {
      return AppConfig.fallback();
    }
  }

  factory AppConfig.fromJson(Map<String, dynamic> json) {
    // `app` is the nested block in the baked config; fall back to the root for
    // a legacy flat config.
    final app = _map(json['app']);

    final appName = _firstStr(
      [app['appName'], json['appName'], json['displayName']],
      'CMS2026',
    );
    final appNameEn =
        _firstStr([app['appNameEn'], json['appNameEn']], appName);

    // Baked menu (modules[]) and home (home[]) — parsed once, used as the
    // instant first paint before the network refresh.
    final bakedMenu = _list(json['modules'])
        .where((m) => _bool(m['enabled'], true)) // hide disabled modules
        .map(MenuItem.fromModuleJson)
        .toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));

    final bakedHome = _list(json['home'])
        .map(HomeSection.fromJson)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    // Simple enabled-module-name list (kept for feature checks / config shape).
    final moduleNames = bakedMenu.map((m) => m.moduleName).toList();

    return AppConfig(
      appName: appName,
      appNameEn: appNameEn,
      appId: _firstStr([app['appId'], json['appId']], 'com.cms2026.app'),
      versionName:
          _firstStr([app['versionName'], json['versionName']], '1.0.0'),
      versionCode: _int(app['versionCode'] ?? json['versionCode'], 1),
      api: ApiConfig.fromJson(_map(json['api'])),
      branding: BrandingConfig.fromJson(_map(json['branding'])),
      languages: LanguageConfig.fromJson(_map(json['languages'])),
      navigation: NavigationConfig.fromJson(_map(json['navigation'])),
      modules: moduleNames.isNotEmpty
          ? moduleNames
          : _stringList(json['modules'], const ['home', 'news']),
      bakedMenu: bakedMenu,
      bakedHome: bakedHome,
      features: _boolMap(json['features']),
      firebase: FirebaseConfig.fromJson(_map(json['firebase'])),
      // Design System tokens (Phase 4c). Present only when the backend baked them; null-safe otherwise so
      // an older config still parses and the app falls back to branding.
      designTokens: DesignTokensConfig.tryParse(json['designTokens']),
      designTokensDark: DesignTokensConfig.tryParse(json['designTokensDark']),
    );
  }

  factory AppConfig.fallback() => AppConfig(
        appName: 'CMS2026',
        appNameEn: 'CMS2026',
        appId: 'com.cms2026.app',
        versionName: '1.0.0',
        versionCode: 1,
        api: const ApiConfig(baseUrl: ''),
        branding: BrandingConfig.fallback(),
        languages: const LanguageConfig(
          defaultLang: 'ar',
          supported: ['ar', 'en'],
          rtl: ['ar'],
        ),
        navigation: const NavigationConfig(style: 'drawer'),
        modules: const ['home', 'news'],
        bakedMenu: const [],
        bakedHome: const [],
        features: const {},
        firebase: const FirebaseConfig(enabled: false),
      );
}

class ApiConfig {
  const ApiConfig({required this.baseUrl});

  /// Same host as the CMS; all `/api/...` calls hang off this.
  final String baseUrl;

  factory ApiConfig.fromJson(Map<String, dynamic> json) =>
      ApiConfig(baseUrl: _str(json['baseUrl'], '').trimRight());
}

class BrandingConfig {
  const BrandingConfig({
    required this.primaryColor,
    required this.secondaryColor,
    required this.accentColor,
    required this.logoUrl,
    required this.splashUrl,
    required this.themeMode,
    required this.fontFamily,
  });

  /// Hex strings exactly as authored in the CMS ("#RRGGBB"); the theme layer
  /// converts them to [Color]. Kept as strings here so the model stays a pure
  /// data holder with no Flutter `dart:ui` dependency.
  final String primaryColor;
  final String secondaryColor;
  final String accentColor;
  final String logoUrl;
  final String splashUrl;

  /// "light" | "dark" | "system".
  final String themeMode;

  /// Optional font family bundled in the template (e.g. "Cairo"); null/empty
  /// means use the platform default.
  final String? fontFamily;

  factory BrandingConfig.fromJson(Map<String, dynamic> json) => BrandingConfig(
        primaryColor: _str(json['primaryColor'], '#2F7995'),
        secondaryColor: _str(json['secondaryColor'], '#1D586F'),
        accentColor: _str(json['accentColor'], '#E8A33D'),
        logoUrl: _str(json['logoUrl'], ''),
        splashUrl: _str(json['splashUrl'], ''),
        themeMode: _str(json['themeMode'], 'light'),
        fontFamily: (json['fontFamily'] as String?)?.trim().isEmpty ?? true
            ? null
            : (json['fontFamily'] as String).trim(),
      );

  factory BrandingConfig.fallback() => const BrandingConfig(
        primaryColor: '#2F7995',
        secondaryColor: '#1D586F',
        accentColor: '#E8A33D',
        logoUrl: '',
        splashUrl: '',
        themeMode: 'light',
        fontFamily: null,
      );
}

/// `navigation.style` from the baked config drives whether the app uses a
/// drawer, a bottom navigation bar, or both. The shell ([MainScaffold]) reads
/// [NavStyle] and builds the matching chrome.
enum NavStyle { drawer, bottomNav, both }

class NavigationConfig {
  const NavigationConfig({required this.style});

  /// Raw value as authored ("drawer" | "bottomnav" | "both").
  final String style;

  /// Parsed style; anything unrecognized falls back to a drawer.
  NavStyle get navStyle {
    switch (style.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '')) {
      case 'bottomnav':
      case 'bottom':
      case 'bottombar':
      case 'tabs':
        return NavStyle.bottomNav;
      case 'both':
      case 'drawerbottomnav':
        return NavStyle.both;
      case 'drawer':
      default:
        return NavStyle.drawer;
    }
  }

  bool get hasDrawer =>
      navStyle == NavStyle.drawer || navStyle == NavStyle.both;
  bool get hasBottomNav =>
      navStyle == NavStyle.bottomNav || navStyle == NavStyle.both;

  factory NavigationConfig.fromJson(Map<String, dynamic> json) =>
      NavigationConfig(style: _str(json['style'], 'drawer'));
}

class LanguageConfig {
  const LanguageConfig({
    required this.defaultLang,
    required this.supported,
    required this.rtl,
  });

  final String defaultLang;
  final List<String> supported;
  final List<String> rtl;

  bool isRtl(String langCode) => rtl.contains(langCode);

  factory LanguageConfig.fromJson(Map<String, dynamic> json) => LanguageConfig(
        defaultLang: _str(json['default'], 'ar'),
        supported: _stringList(json['supported'], const ['ar', 'en']),
        // Baked config uses `rtlLanguages`; a flat config may use `rtl`.
        rtl: _stringList(json['rtlLanguages'] ?? json['rtl'], const ['ar']),
      );
}

class FirebaseConfig {
  const FirebaseConfig({
    required this.enabled,
    this.projectId = '',
    this.messagingSenderId = '',
  });

  final bool enabled;
  final String projectId;
  final String messagingSenderId;

  factory FirebaseConfig.fromJson(Map<String, dynamic> json) => FirebaseConfig(
        // Baked config has no `enabled` flag — treat a present projectId as
        // enabled; a flat config may carry an explicit `enabled`.
        enabled: _bool(
          json['enabled'],
          _str(json['projectId'], '').isNotEmpty,
        ),
        projectId: _str(json['projectId'], ''),
        messagingSenderId:
            _str(json['senderId'] ?? json['messagingSenderId'], ''),
      );
}

// ════════════════════════════════════════════════════════════════════════════
// DESIGN SYSTEM TOKENS (Phase 4c) — typed view over app_config.json `designTokens`.
//
// Mirrors the backend Flutter token JSON (schema `cms2026.flutter-tokens/1`, produced by
// DesignTokenResolver.ToFlutter and embedded by AppConfigBuilder): semantic colors as hex, a type scale,
// numeric spacing/radius, motion, and the `useMaterial3` flag. Pure data holder — no `dart:ui` import here;
// hex→Color conversion + ThemeData construction live in `theme/app_theme.dart` (AppTheme.fromTokens).
//
// Everything is null-safe: a missing/partial token block yields nulls and the theme layer falls back per
// field, so a half-authored theme never crashes theme construction.
// ════════════════════════════════════════════════════════════════════════════
class DesignTokensConfig {
  const DesignTokensConfig({
    required this.schema,
    required this.mode,
    required this.platform,
    required this.useMaterial3,
    required this.rtlAware,
    required this.fontFamilyBase,
    required this.fontFamilyHeading,
    required this.colors,
    required this.typeScale,
    required this.spacing,
    required this.radius,
    required this.motionDurationMs,
  });

  /// e.g. "cms2026.flutter-tokens/1".
  final String schema;

  /// The brightness this token set was resolved for: "light" | "dark" | "highContrast".
  final String mode;

  /// "material" | "cupertino".
  final String platform;

  final bool useMaterial3;
  final bool rtlAware;

  /// Base/heading font families (null/empty → platform default).
  final String? fontFamilyBase;
  final String? fontFamilyHeading;

  /// Semantic role → hex string ("primary","onPrimary","secondary","surface","onSurface","background",
  /// "onBackground","error","onError","outline",…). The theme layer parses hex → Color with fallbacks.
  final Map<String, String> colors;

  /// Type-scale role → metrics ("display","h1","h2","title","body","label","caption").
  final Map<String, TypeScaleToken> typeScale;

  /// Spacing scale (px), e.g. {"xs":4,"sm":8,"md":16,…}.
  final Map<String, double> spacing;

  /// Radius scale (px), e.g. {"none":0,"sm":4,"md":8,"lg":12,"pill":999}.
  final Map<String, double> radius;

  /// Motion durations (ms), e.g. {"fast":150,"base":250,"slow":400}.
  final Map<String, double> motionDurationMs;

  /// True for a dark token set (drives the [Brightness] the theme layer builds).
  bool get isDark => mode.toLowerCase() == 'dark';

  /// Convenience: a named color, or null when absent/blank.
  String? color(String role) {
    final v = colors[role];
    return (v != null && v.isNotEmpty) ? v : null;
  }

  /// A radius value (px) by key, or [fallback].
  double radiusOf(String key, double fallback) => radius[key] ?? fallback;

  /// Parse a `designTokens` JSON node, or null when absent / not an object / missing the schema marker.
  static DesignTokensConfig? tryParse(dynamic node) {
    if (node is! Map) return null;
    final json = node.map((k, v) => MapEntry(k.toString(), v));

    final schema = _str(json['schema'], '');
    // Be tolerant: accept any cms2026 flutter-tokens schema; bail only if there's clearly no token data.
    final colorsRaw = _map(json['colors']);
    if (schema.isEmpty && colorsRaw.isEmpty) return null;

    final colors = <String, String>{};
    colorsRaw.forEach((k, v) {
      if (v is String && v.isNotEmpty) colors[k] = v;
    });

    final typeScale = <String, TypeScaleToken>{};
    _map(json['typography']).forEach((k, v) {
      if (v is Map) typeScale[k] = TypeScaleToken.fromJson(v.map((kk, vv) => MapEntry(kk.toString(), vv)));
    });

    return DesignTokensConfig(
      schema: schema.isEmpty ? 'cms2026.flutter-tokens/1' : schema,
      mode: _str(json['mode'], 'light'),
      platform: _str(json['platform'], 'material'),
      useMaterial3: _bool(json['useMaterial3'], true),
      rtlAware: _bool(json['rtlAware'], true),
      fontFamilyBase: _optStr(_map(json['fontFamily'])['base']),
      fontFamilyHeading: _optStr(_map(json['fontFamily'])['heading']),
      colors: colors,
      typeScale: typeScale,
      spacing: _numMap(json['spacing']),
      radius: _numMap(json['radius']),
      motionDurationMs: _numMap(_map(json['motion'])['duration']),
    );
  }
}

/// One type-scale role's metrics (logical px / 100..900 weight / unitless height). All nullable so a
/// partial scale degrades gracefully (the theme layer supplies Material defaults for anything missing).
class TypeScaleToken {
  const TypeScaleToken({this.size, this.weight, this.height, this.letterSpacing});

  final double? size;
  final int? weight;
  final double? height;
  final double? letterSpacing;

  factory TypeScaleToken.fromJson(Map<String, dynamic> json) => TypeScaleToken(
        size: _optNum(json['size']),
        weight: _optInt(json['weight']),
        height: _optNum(json['height']),
        letterSpacing: _optNum(json['letterSpacing']),
      );
}

// --- small null-safe coercion helpers (kept private to this file) ---

String _str(dynamic v, String fallback) =>
    v is String && v.isNotEmpty ? v : fallback;

/// Optional trimmed string (null when absent/blank).
String? _optStr(dynamic v) {
  if (v is String && v.trim().isNotEmpty) return v.trim();
  return null;
}

/// Optional double (null when not numeric).
double? _optNum(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v);
  return null;
}

/// Optional int (null when not numeric).
int? _optInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}

/// A { key → double } map from a JSON object (non-numeric values skipped).
Map<String, double> _numMap(dynamic v) {
  final out = <String, double>{};
  if (v is Map) {
    v.forEach((k, val) {
      final n = _optNum(val);
      if (n != null) out[k.toString()] = n;
    });
  }
  return out;
}

/// First non-empty string among [candidates], else [fallback].
String _firstStr(List<dynamic> candidates, String fallback) {
  for (final c in candidates) {
    if (c is String && c.isNotEmpty) return c;
  }
  return fallback;
}

int _int(dynamic v, int fallback) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

bool _bool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  return fallback;
}

Map<String, dynamic> _map(dynamic v) =>
    v is Map<String, dynamic> ? v : <String, dynamic>{};

/// A list of JSON maps (e.g. `modules[]`, `home[]`). Non-list → empty.
List<Map<String, dynamic>> _list(dynamic v) {
  if (v is List) return v.whereType<Map<String, dynamic>>().toList();
  return const <Map<String, dynamic>>[];
}

List<String> _stringList(dynamic v, [List<String> fallback = const []]) {
  if (v is List) {
    // A baked `modules` array holds objects; pull `name` from each. A flat
    // config holds plain strings.
    final out = <String>[];
    for (final e in v) {
      if (e is String && e.isNotEmpty) {
        out.add(e);
      } else if (e is Map && e['name'] is String) {
        out.add(e['name'] as String);
      }
    }
    return out.isNotEmpty ? out : List<String>.from(fallback);
  }
  return List<String>.from(fallback);
}

Map<String, bool> _boolMap(dynamic v) {
  if (v is Map) {
    return v.map((key, value) => MapEntry(key.toString(), _bool(value, false)));
  }
  return <String, bool>{};
}
