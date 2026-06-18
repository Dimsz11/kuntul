/// RuntimeBootstrap — the Phase-6f composition root.
///
/// Owns every runtime service and wires them together in the documented order
/// on launch, and re-runs the cheap parts on resume. Keeping the wiring here
/// (rather than in `main.dart`) makes each service DI-friendly and the bootstrap
/// order explicit + testable.
///
/// **Bootstrap order** (matches the phase spec):
///   1. cache + device id + restore session   (storage/identity)
///   2. runtime config (hydrate cache → fetch envelope)  → flags / theme ready
///   3. device register                        (push token attached later)
///   4. push init                              (graceful no-op without Firebase)
///   5. deep links init                        (cold-start link replays here)
///   6. start sync + analytics session         (offline + telemetry)
///
/// Every step is independently `try`-guarded so one failing capability (e.g.
/// no network for the runtime fetch, no Firebase for push) never blocks the
/// others — the app always finishes booting.
library;

import 'package:flutter/widgets.dart';

import '../api_client.dart';
import '../app_config.dart';
import '../runtime/runtime_models.dart';
import '../storage/cache_service.dart';
import 'analytics_service.dart';
import 'auth_service.dart';
import 'deeplink_service.dart';
import 'device_service.dart';
import 'push_service.dart';
import 'runtime_service.dart';
import 'security_service.dart';
import 'sync_service.dart';

class RuntimeBootstrap with WidgetsBindingObserver {
  RuntimeBootstrap({
    required this.api,
    required this.config,
    required this.navigate,
    required this.localeProvider,
    PushProvider? pushProvider,
    CacheService? cache,
  })  : cache = cache ?? CacheService.instance,
        _pushProvider = pushProvider {
    auth = AuthService(api: api, cache: this.cache);
    runtime = RuntimeService(api: api, cache: this.cache);
    security = SecurityService(api: api, runtime: runtime, auth: auth);
    device = DeviceService(api: api);
    deepLinks = DeepLinkService(
      api: api,
      navigate: navigate,
      onAnalytics: (target, {campaign}) =>
          analytics.click(target: target, campaignCode: campaign),
    );
    analytics = AnalyticsService(
      api: api,
      runtime: runtime,
      deviceId: auth.deviceIdOrAnon, // replaced with the real id during init()
      localeProvider: localeProvider,
      uidProvider: () => auth.uid,
    );
    push = PushService(
      device: device,
      deepLinks: deepLinks,
      localeProvider: localeProvider,
      provider: _pushProvider,
    );
    sync = SyncService(
      api: api,
      cache: this.cache,
      localeProvider: localeProvider,
      deviceIdProvider: () => auth.deviceIdOrAnon, // resolved during start()
      uidProvider: () => auth.uid,
    );
  }

  final ApiClient api;
  final AppConfig config;
  final NavigateFn navigate;
  final String Function() localeProvider;
  final CacheService cache;
  final PushProvider? _pushProvider;

  late final AuthService auth;
  late final RuntimeService runtime;
  late final SecurityService security;
  late final DeviceService device;
  late final DeepLinkService deepLinks;
  late final AnalyticsService analytics;
  late final PushService push;
  late final SyncService sync;

  /// One observer instance to attach to MaterialApp.navigatorObservers.
  late final AnalyticsNavigatorObserver navigatorObserver = AnalyticsNavigatorObserver(analytics);

  bool _started = false;

  /// Run the full ordered bootstrap. Idempotent. Never throws.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);

    // 1) Storage + identity.
    await _guard(() async {
      await cache.init();
      final deviceId = await auth.ensureDeviceId();
      api.deviceId = deviceId;
      await auth.restoreSession();
      // The analytics service was constructed with a placeholder device id;
      // give it the real one + token refresh seam now that they're known.
      analytics.deviceIdOverride = deviceId;
      // 401 → refresh-or-anonymous (no-op unless 6g installs a refreshCallback).
      api.onUnauthorized = auth.handleUnauthorized;
      // Phase 6g: load any persisted device signing key + install the signing hook
      // on the shared client. The hook is inert until flags.security.requestSigning
      // is on AND the path is signed, so this is a clean no-op by default.
      await security.loadSigningKey();
      security.installSigning();
    });

    // 2) Runtime config: hydrate from cache (offline-safe) → fetch envelope.
    await _guard(() async {
      runtime.hydrateFromCache();
      runtime.setContext(_buildContext());
      await runtime.refresh();
    });

    // 3) Device registration (token attached later by push, on refresh).
    await _guard(() async {
      final topics = _topicsFromConfig();
      final regData = await device.register(
        deviceId: auth.deviceIdOrAnon,
        locale: localeProvider(),
        appBuildConfigId: config.buildConfigId,
        topics: topics,
        userId: auth.uid,
      );
      // Phase 6g: a freshly-minted signing key (shown once) → persist it so request
      // signing can sign once the flag is turned on. Re-registers omit the secret.
      final newKeyId = regData?['signingKeyId']?.toString();
      final newSecret = regData?['signingSecret']?.toString();
      if (!security.hasSigningKey && (newKeyId?.isNotEmpty ?? false) && (newSecret?.isNotEmpty ?? false)) {
        await security.setSigningKey(keyId: newKeyId!, secret: newSecret!);
      }
      final hbSec = runtime.configInt('push.heartbeatSeconds') ?? 1800;
      device.startHeartbeat(locale: localeProvider(), interval: Duration(seconds: hbSec.clamp(60, 86400)));
    });

    // 4) Push (graceful no-op without a real provider / Firebase config).
    await _guard(() async {
      if (runtime.flagBool('push.enabled', fallback: true) &&
          config.featureEnabled('pushNotifications')) {
        await push.init(topics: _topicsFromConfig());
      }
    });

    // 5) Deep links (the cold-start link replays through the stream here).
    await _guard(() async {
      if (runtime.flagBool('deeplink.enabled', fallback: true)) {
        await deepLinks.init();
      }
    });

    // 6) Sync + analytics. Analytics consent defaults to the build's `analytics`
    //    feature unless a consent screen flips it. Sync loads the manifest,
    //    precaches, starts the delta loop + connectivity listener, then pulls
    //    the server's favorite set into the local mirror.
    await _guard(() async {
      analytics.setConsent(config.featureEnabled('analytics'));
      final flushSec = runtime.configInt('analytics.flushSeconds') ?? 30;
      analytics.start(flushInterval: Duration(seconds: flushSec.clamp(5, 600)));
    });
    await _guard(() async {
      if (runtime.flagBool('offline.enabled', fallback: true) &&
          config.featureEnabled('offlineMode')) {
        await sync.start();
        await sync.pullFavorites();
      }
    });

    // 7) Device integrity / trust (Phase 6g). Report the (stub) signals + read the
    //    trust verdict so the app can gate per flags.security.blockUntrusted. Pure
    //    no-op effect by default (blockUntrusted off → blocked stays false); honest
    //    (the server records "unverified" with no attestation key).
    await _guard(() async {
      await security.reportIntegrity();
      if (security.blocked) onUntrusted?.call();
    });
  }

  /// Re-run the cheap, resume-time work: refresh the runtime envelope (304-cheap),
  /// heartbeat, pull a delta + flush the form queue, flush analytics.
  Future<void> onResume() async {
    await _guard(() async {
      runtime.setContext(_buildContext());
      final changed = await runtime.refresh();
      if (changed) onConfigChanged?.call();
    });
    await _guard(() => device.heartbeatNow(localeProvider()));
    await _guard(() => sync.onResume());
    await _guard(() => analytics.flush());
    // Phase 6g: a cheap trust re-read on resume (gate may have changed server-side).
    await _guard(() async {
      await security.refreshTrust();
      if (security.blocked) onUntrusted?.call();
    });
  }

  /// Called when the runtime locale changes (so the next poll + registrations
  /// use the new language).
  Future<void> onLocaleChanged() async {
    await _guard(() async {
      runtime.setContext(_buildContext());
      await runtime.refresh();
      await device.heartbeatNow(localeProvider());
    });
  }

  /// Optional callback invoked when a refresh changed the envelope (so the host
  /// can re-apply the theme). Wired in main.dart.
  VoidCallback? onConfigChanged;

  /// Phase 6g — optional callback invoked when the device trust gate fires (i.e.
  /// flags.security.blockUntrusted is on AND the device's trust score is below the
  /// threshold). The host can show a block/upgrade screen. Null = no gating UI
  /// (the default, since blockUntrusted defaults off → this never fires).
  VoidCallback? onUntrusted;

  // ── helpers ───────────────────────────────────────────────────────────────

  RuntimeContext _buildContext() => RuntimeContext(
        deviceId: auth.deviceIdOrAnon,
        platform: DeviceService.platform,
        appVersion: config.versionName,
        locale: localeProvider(),
        appId: config.buildConfigId,
        uid: auth.uid,
        role: auth.role,
        // campaign: filled from the install referrer / first deep link by 6g/host.
      );

  /// Topics from runtime `config.push.topics` (string-list or CSV), else none.
  List<String> _topicsFromConfig() {
    final raw = runtime.configValue('push.topics');
    if (raw is List) return raw.map((e) => e.toString()).where((s) => s.isNotEmpty).toList();
    if (raw is String && raw.isNotEmpty) {
      return raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
    }
    return const [];
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume();
  }

  Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } catch (_) {/* never block bootstrap on one capability */}
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    device.dispose();
    push.dispose();
    deepLinks.dispose();
    analytics.dispose();
    sync.dispose();
    runtime.dispose();
  }
}
