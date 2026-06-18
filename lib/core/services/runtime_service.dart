/// RuntimeService — the on-device consumer of the Phase-6a Runtime Config plane.
///
/// This is the long-deferred **runtime-context wiring**: on launch and on
/// resume the app builds a [RuntimeContext] (stable deviceId, platform, app
/// version, locale, and — when known — uid / role / install campaign), calls
/// `GET /api/runtime/config?…` with those query params and an
/// **`If-None-Match`** of the persisted ETag, and consumes the resolved
/// envelope:
///   • [flagBool] / [configValue] / [experimentVariant] gate UI + features,
///   • [theme] drives remote theme switching (brandId/themeId/mode), applied by
///     `AppTheme.fromConfigWithRuntime` against the baked token sets (no rebuild),
///   • the analytics layer tags every event with the current experiment
///     assignments ([experimentsForAnalytics]).
///
/// **Graceful degradation:** the service starts with [RuntimeConfig.empty] and,
/// on launch, hydrates from the on-disk cache BEFORE the network call — so even
/// offline the app gets the last-known flags/theme. A 304 keeps the cache; a
/// network failure keeps whatever is loaded. The app therefore boots and gates
/// correctly whether or not the runtime plane is reachable.
library;

import 'package:flutter/foundation.dart';

import '../api_client.dart';
import '../runtime/runtime_models.dart';
import '../storage/cache_service.dart';

class RuntimeService {
  RuntimeService({required this.api, required this.cache});

  final ApiClient api;
  final CacheService cache;

  static const _etagKey = 'runtime.etag';
  static const _envelopeKey = 'runtime.envelope';

  /// The current resolved config. A [ValueNotifier] so widgets (theme, gated
  /// UI) can rebuild when a refresh changes flags/theme.
  final ValueNotifier<RuntimeConfig> configNotifier =
      ValueNotifier<RuntimeConfig>(RuntimeConfig.empty());

  RuntimeConfig get current => configNotifier.value;

  /// The context the next poll will use — kept fresh as auth/locale change.
  RuntimeContext? _context;
  RuntimeContext? get context => _context;

  /// Hydrate from cache (instant, offline-safe). Call once before the first
  /// network fetch so the app has last-known flags/theme even with no network.
  void hydrateFromCache() {
    final cached = RuntimeConfig.decodeCache(cache.getString(_envelopeKey));
    if (cached != null) configNotifier.value = cached;
  }

  /// Set / update the runtime context (e.g. after sign-in adds uid+role, or the
  /// locale changes). Does not fetch — call [refresh] after.
  void setContext(RuntimeContext ctx) => _context = ctx;

  /// Fetch the envelope with `If-None-Match`. On 200 → store the new envelope +
  /// ETag and notify; on 304 → keep cache; on failure → keep current. Returns
  /// true when the config actually changed (so the caller can re-apply theme).
  Future<bool> refresh({RuntimeContext? context}) async {
    final ctx = context ?? _context;
    if (ctx == null || !api.hasBaseUrl) return false;
    _context = ctx;

    final etag = cache.getString(_etagKey);
    final res = await api.getRaw('/api/runtime/config', query: ctx.toQuery(), ifNoneMatch: etag);

    // 304 → unchanged; keep the cache. Network error (statusCode 0) → keep current.
    if (res.isNotModified || res.statusCode == 0) return false;
    if (!res.isOk) return false;

    final body = res.body;
    final data = body is Map && body['data'] is Map
        ? (body['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : (body is Map ? body.map((k, v) => MapEntry(k.toString(), v)) : null);
    if (data == null) return false;

    final next = RuntimeConfig.fromJson(data);
    final changed = next.etag != current.etag || current.etag.isEmpty;
    configNotifier.value = next;

    // Persist for the next launch / offline boot. Prefer the server ETag header,
    // fall back to the envelope's version.etag.
    final newEtag = res.etag ?? (next.etag.isNotEmpty ? next.etag : null);
    if (newEtag != null && newEtag.isNotEmpty) await cache.setString(_etagKey, newEtag);
    await cache.setString(_envelopeKey, next.encodeCache());
    return changed;
  }

  // ── Typed accessors (gate UI / features on these) ───────────────────────────

  /// A boolean feature flag (defaults to [fallback] when absent / wrong type).
  bool flagBool(String key, {bool fallback = false}) {
    final v = current.flags[key];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    if (v is num) return v != 0;
    return fallback;
  }

  /// A remote-config value (raw). Use [configString] / [configInt] /
  /// [configDouble] for typed reads.
  dynamic configValue(String key) => current.config[key];

  String? configString(String key) {
    final v = current.config[key];
    return v == null ? null : v.toString();
  }

  int? configInt(String key) {
    final v = current.config[key];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  double? configDouble(String key) {
    final v = current.config[key];
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  bool? configBool(String key) {
    final v = current.config[key];
    if (v is bool) return v;
    if (v is String) return v.toLowerCase() == 'true';
    if (v is num) return v != 0;
    return null;
  }

  /// The assigned variant of an experiment, or null when not assigned.
  String? experimentVariant(String key) => current.experiments[key]?.variant;

  /// An experiment variant's config object (e.g. `{ themeId: 2 }`).
  Map<String, dynamic> experimentConfig(String key) =>
      current.experiments[key]?.config ?? const {};

  RuntimeTheme get theme => current.theme;

  /// `{ expKey: variant }` — attached to analytics events for A/B attribution
  /// (matches what the 6e ingestor would otherwise enrich from the resolver).
  Map<String, String> experimentsForAnalytics() => {
        for (final e in current.experiments.entries) e.key: e.value.variant,
      };

  void dispose() => configNotifier.dispose();
}
