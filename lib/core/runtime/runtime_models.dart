/// Typed views over the Phase-6a Runtime Config plane.
///
/// These mirror the backend envelope returned by `GET /api/runtime/config`
/// (see `CMS2026.Application/Features/RuntimeConfig/RuntimeConfigContracts.cs`
/// + `docs/runtime-config-plane.md`):
///
/// ```jsonc
/// { "flags":       { "ui.new_home": true, "search.semantic": true },
///   "config":      { "welcome.message": "…" },
///   "experiments": { "home_redesign": { "variant": "B",
///                                        "config": { "themeId": 2 } } },
///   "theme":       { "brandId": null, "themeId": 2, "mode": "light",
///                    "source": "experiment:home_redesign" },
///   "version":     { "etag": "\"…\"", "polledAtUtc": "2026-06-18T05:26:31Z" } }
/// ```
///
/// Everything is null/absent-safe: a missing block degrades to a sensible empty
/// default so the app still boots when the runtime plane is unavailable (older
/// backend, offline, 304-without-cache). Coercion is deliberately tolerant —
/// flags/config values arrive as untyped JSON scalars.
library;

import 'dart:convert';

/// The request context the app sends to `GET /api/runtime/config` as query
/// params (the long-deferred runtime-context wiring): a stable device id, the
/// platform/version/locale, plus the logged-in uid / role / install campaign
/// when known. `BucketSeed` (server-side) = uid ?? deviceId, so a sticky
/// experiment assignment follows the user across devices once signed in.
class RuntimeContext {
  const RuntimeContext({
    required this.deviceId,
    required this.platform,
    required this.appVersion,
    required this.locale,
    this.appId,
    this.uid,
    this.role,
    this.campaign,
    this.country,
    this.segments = const [],
  });

  /// Stable per-install id (generated once, persisted in secure storage / Hive).
  final String deviceId;

  /// "android" | "ios" | … (lower-cased by the server).
  final String platform;

  /// Marketing version, e.g. "1.0.0" — compared to a rule's appVersionMin/Max.
  final String appVersion;

  /// Active UI locale ("ar" | "en" | …).
  final String locale;

  /// Optional numeric `MobileBuildConfig.Id` (per-app scope). Null → global.
  final int? appId;

  /// Logged-in user id when authenticated (preferred bucket seed).
  final String? uid;

  /// Role from the auth claims (targeting). Null when anonymous.
  final String? role;

  /// Install referrer / first deep-link campaign (targeting + attribution).
  final String? campaign;

  /// ISO country (when known).
  final String? country;

  /// Arbitrary audience segments the app computed (e.g. "beta").
  final List<String> segments;

  /// The query map for `GET /api/runtime/config`. Empty/absent fields are
  /// dropped by ApiClient (which removes blank query values).
  Map<String, String> toQuery() => {
        'deviceId': deviceId,
        'platform': platform,
        'appVersion': appVersion,
        'lang': locale,
        if (appId != null) 'appId': '$appId',
        if (uid != null && uid!.isNotEmpty) 'uid': uid!,
        if (role != null && role!.isNotEmpty) 'role': role!,
        if (campaign != null && campaign!.isNotEmpty) 'campaign': campaign!,
        if (country != null && country!.isNotEmpty) 'country': country!,
        if (segments.isNotEmpty) 'segments': segments.join(','),
      };

  RuntimeContext copyWith({
    String? deviceId,
    String? platform,
    String? appVersion,
    String? locale,
    int? appId,
    String? uid,
    String? role,
    String? campaign,
    String? country,
    List<String>? segments,
  }) =>
      RuntimeContext(
        deviceId: deviceId ?? this.deviceId,
        platform: platform ?? this.platform,
        appVersion: appVersion ?? this.appVersion,
        locale: locale ?? this.locale,
        appId: appId ?? this.appId,
        uid: uid ?? this.uid,
        role: role ?? this.role,
        campaign: campaign ?? this.campaign,
        country: country ?? this.country,
        segments: segments ?? this.segments,
      );
}

/// One experiment assignment from the envelope: the sticky variant key + that
/// variant's config object (`{ expKey: { variant, config } }`).
class ExperimentAssignment {
  const ExperimentAssignment(this.variant, this.config);

  final String variant;
  final Map<String, dynamic> config;

  factory ExperimentAssignment.fromJson(Map<String, dynamic> j) =>
      ExperimentAssignment(
        (j['variant'] ?? '').toString(),
        j['config'] is Map<String, dynamic>
            ? j['config'] as Map<String, dynamic>
            : const <String, dynamic>{},
      );
}

/// The resolved remote theme pointer (remote theme switching). The app uses
/// these ids to fetch real tokens from the existing brand/theme endpoints (or,
/// in this reference, to pick the matching baked token set) — no rebuild.
class RuntimeTheme {
  const RuntimeTheme({this.brandId, this.themeId, this.mode, this.source = 'default'});

  final int? brandId;
  final int? themeId;

  /// "light" | "dark" | "highContrast" | null.
  final String? mode;

  /// "default" | "flag:ui.theme" | "config:theme.id" | "experiment:…".
  final String source;

  factory RuntimeTheme.fromJson(Map<String, dynamic> j) => RuntimeTheme(
        brandId: _asInt(j['brandId']),
        themeId: _asInt(j['themeId']),
        mode: (j['mode'] as String?)?.trim().isEmpty ?? true ? null : j['mode'] as String?,
        source: (j['source'] ?? 'default').toString(),
      );

  bool get isDark => (mode ?? '').toLowerCase() == 'dark';
}

/// The full resolved envelope the app consumes + gates on.
class RuntimeConfig {
  const RuntimeConfig({
    required this.flags,
    required this.config,
    required this.experiments,
    required this.theme,
    required this.etag,
    required this.polledAtUtc,
  });

  /// `{ flagKey → typed value }`.
  final Map<String, dynamic> flags;

  /// `{ configKey → typed value }` (global ∪ app, app overriding).
  final Map<String, dynamic> config;

  /// `{ expKey → assignment }`.
  final Map<String, ExperimentAssignment> experiments;

  final RuntimeTheme theme;

  /// `version.etag` — persisted + sent as `If-None-Match` on the next poll.
  final String etag;
  final DateTime? polledAtUtc;

  /// The empty default used before the first successful fetch (and when the
  /// runtime plane is unavailable). Every accessor falls back to safe values,
  /// so the app degrades to "no flags overridden, default theme".
  factory RuntimeConfig.empty() => const RuntimeConfig(
        flags: {},
        config: {},
        experiments: {},
        theme: RuntimeTheme(),
        etag: '',
        polledAtUtc: null,
      );

  /// Parse the unwrapped `data` node of `ApiResponse<RuntimeConfig>`.
  factory RuntimeConfig.fromJson(Map<String, dynamic> j) {
    final exps = <String, ExperimentAssignment>{};
    final rawExps = j['experiments'];
    if (rawExps is Map) {
      rawExps.forEach((k, v) {
        if (v is Map<String, dynamic>) {
          exps[k.toString()] = ExperimentAssignment.fromJson(v);
        } else if (v is Map) {
          exps[k.toString()] =
              ExperimentAssignment.fromJson(v.map((kk, vv) => MapEntry(kk.toString(), vv)));
        }
      });
    }
    final version = j['version'] is Map ? (j['version'] as Map) : const {};
    return RuntimeConfig(
      flags: _asMap(j['flags']),
      config: _asMap(j['config']),
      experiments: exps,
      theme: j['theme'] is Map
          ? RuntimeTheme.fromJson((j['theme'] as Map).map((k, v) => MapEntry(k.toString(), v)))
          : const RuntimeTheme(),
      etag: (version['etag'] ?? '').toString(),
      polledAtUtc: version['polledAtUtc'] is String
          ? DateTime.tryParse(version['polledAtUtc'] as String)
          : null,
    );
  }

  /// Round-trip to a plain JSON map (for the on-disk cache, so a 304 keeps the
  /// last full envelope). Mirrors [fromJson] exactly.
  Map<String, dynamic> toCacheJson() => {
        'flags': flags,
        'config': config,
        'experiments': {
          for (final e in experiments.entries)
            e.key: {'variant': e.value.variant, 'config': e.value.config},
        },
        'theme': {
          'brandId': theme.brandId,
          'themeId': theme.themeId,
          'mode': theme.mode,
          'source': theme.source,
        },
        'version': {
          'etag': etag,
          'polledAtUtc': polledAtUtc?.toIso8601String(),
        },
      };

  String encodeCache() => jsonEncode(toCacheJson());

  static RuntimeConfig? decodeCache(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final j = jsonDecode(raw);
      if (j is Map<String, dynamic>) return RuntimeConfig.fromJson(j);
    } catch (_) {/* fall through */}
    return null;
  }
}

// ── tolerant coercion (flags/config arrive as untyped JSON scalars) ──

Map<String, dynamic> _asMap(dynamic v) {
  if (v is Map<String, dynamic>) return v;
  if (v is Map) return v.map((k, vv) => MapEntry(k.toString(), vv));
  return <String, dynamic>{};
}

int? _asInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v);
  return null;
}
