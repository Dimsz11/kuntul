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

// --- small null-safe coercion helpers (kept private to this file) ---

String _str(dynamic v, String fallback) =>
    v is String && v.isNotEmpty ? v : fallback;

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
