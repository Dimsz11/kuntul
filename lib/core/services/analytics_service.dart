/// AnalyticsService — the on-device emitter for the Phase-6e Analytics plane.
///
/// A local **event queue** with periodic **batch flush** to
/// `POST /api/analytics/events`, honouring an on-device **consent** flag plus
/// the runtime envelope's `flags.analytics.enabled` and
/// `config.analytics.sampleRate`. It auto-tracks the **session**
/// (`session_start` / `session_end` with a `sessionId`) and **screen views**
/// (via [AnalyticsNavigatorObserver]), and offers typed helpers
/// (click / search / download / form_submit) that all carry the device's
/// current **experiment assignments** for A/B attribution.
///
/// ## Exact wire shape (matches `AnalyticsController.IngestBatchRequest`)
/// The controller wraps the batch:
/// ```jsonc
/// { "events": [ AnalyticsEventDto, … ],
///   "appId": 5, "platform": "android", "appVersion": "1.0.0", "country": null }
/// ```
/// and each `AnalyticsEventDto` is (camelCase, all optional but `eventType`):
/// ```jsonc
/// { "eventType":"screen_view", "occurredAt":"…Z", "deviceId":"dev-…",
///   "uid":null, "appBuildConfigId":5, "sessionId":"sess-…",
///   "platform":"android", "appVersion":"1.0.0", "locale":"ar", "country":null,
///   "screenName":"/news", "widgetKey":null, "target":null,
///   "campaignCode":null, "properties":{…}, "value":null,
///   "experiments":{"home_redesign":"B"}, "consent":true }
/// ```
/// The endpoint is anonymous, never 500s, and returns `{accepted,dropped,reasons}`
/// — so the app fire-and-forgets and partial drops (sampling/consent) are normal.
///
/// ## Gating & sampling (client-side, mirrors the server)
///   • `flags.analytics.enabled == false` → the queue is dropped, nothing sent.
///   • `consent != true` (default) AND `config.analytics.consentRequired` →
///     events are not collected. (The reference defaults consent to FALSE and
///     exposes [setConsent]; flip it from a real consent screen.)
///   • `config.analytics.sampleRate` (0..1) → a deterministic per-session
///     decision (so a whole session is in or out, never half) avoids sending
///     events the server would only drop.
///
/// **Graceful degradation:** with no base URL / no network the flush is a
/// no-op and the queue is bounded (oldest dropped past a cap) so memory is
/// safe; nothing here can break the host.
library;

import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../api_client.dart';
import 'runtime_service.dart';

class AnalyticsService with WidgetsBindingObserver {
  AnalyticsService({
    required this.api,
    required this.runtime,
    required String deviceId,
    required this.localeProvider,
    this.uidProvider,
  }) : _deviceId = deviceId;

  final ApiClient api;
  final RuntimeService runtime;

  /// The device id used to attribute events. Constructed with a best-effort
  /// value and overwritten by the bootstrap once the stable id is resolved.
  String _deviceId;

  /// Update the attribution device id after the stable id is known.
  set deviceIdOverride(String value) => _deviceId = value;
  String get deviceId => _deviceId;

  final String Function() localeProvider;

  /// Optional logged-in uid getter (null when anonymous).
  final String? Function()? uidProvider;

  final List<Map<String, dynamic>> _queue = [];
  static const int _maxQueue = 500; // bound memory; drop oldest past this.
  static const int _flushBatch = 50;

  Timer? _flushTimer;
  String? _sessionId;
  bool _consent = false;
  bool _flushing = false;

  /// Sticky per-session sampling decision (computed once per session).
  bool _sessionSampledIn = true;

  /// Set consent (e.g. from a privacy prompt). When false and the server
  /// requires consent, events are dropped server-side anyway; we also avoid
  /// collecting them locally to respect the user.
  void setConsent(bool granted) => _consent = granted;
  bool get consentGranted => _consent;

  String? get sessionId => _sessionId;

  // ── lifecycle ─────────────────────────────────────────────────────────────

  /// Start a session + the periodic flush, and observe app lifecycle so a
  /// background transition flushes + closes the session. [flushInterval] can
  /// come from config; defaults to 30s.
  void start({Duration flushInterval = const Duration(seconds: 30)}) {
    WidgetsBinding.instance.addObserver(this);
    _startSession();
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(flushInterval, (_) => flush());
  }

  void _startSession() {
    _sessionId = 'sess-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    _sessionSampledIn = _computeSampledIn(_sessionId!);
    track('session_start');
  }

  void _endSession() {
    track('session_end');
    // Flush synchronously-ish (fire-and-forget) so the close event is sent.
    flush();
    _sessionId = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.detached) {
      flush();
    } else if (state == AppLifecycleState.resumed) {
      // New session if we had closed one. Keeps sessions bounded by foreground.
      _sessionId ??= 'sess-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 20)}';
    }
  }

  // ── enqueue helpers ─────────────────────────────────────────────────────────

  /// Enqueue a screen view (used by [AnalyticsNavigatorObserver]).
  void screenView(String screenName) => track('screen_view', screenName: screenName);

  void click({String? widgetKey, String? target, String? screenName, String? campaignCode}) =>
      track('click', widgetKey: widgetKey, target: target, screenName: screenName, campaignCode: campaignCode);

  void search(String query, {int? resultCount, String? screenName}) => track(
        'search',
        screenName: screenName,
        properties: {'query': query, if (resultCount != null) 'resultCount': resultCount},
      );

  void download(String itemId, {int? bytes, String? screenName}) => track(
        'download',
        target: itemId,
        screenName: screenName,
        properties: {'itemId': itemId, if (bytes != null) 'bytes': bytes},
      );

  void formSubmit(int formId, {String? screenName, bool offline = false}) => track(
        'form_submit',
        screenName: screenName,
        properties: {'formId': formId, 'offline': offline},
      );

  /// The core enqueue. Respects the flag/consent gates; stamps the common
  /// fields + the current experiment assignments. Bounded queue.
  void track(
    String eventType, {
    String? screenName,
    String? widgetKey,
    String? target,
    String? campaignCode,
    Map<String, dynamic>? properties,
    double? value,
  }) {
    // Local gates (the server re-checks; this avoids collecting what would be
    // dropped + respects consent on-device).
    if (!runtime.flagBool('analytics.enabled', fallback: true)) return;
    final consentRequired = runtime.configBool('analytics.consentRequired') ?? false;
    if (consentRequired && !_consent) return;
    if (!_sessionSampledIn) return;

    final exps = runtime.experimentsForAnalytics();
    final event = <String, dynamic>{
      'eventType': eventType,
      'occurredAt': DateTime.now().toUtc().toIso8601String(),
      'deviceId': deviceId,
      if (uidProvider?.call() != null) 'uid': uidProvider!.call(),
      if (api.config.buildConfigId != null) 'appBuildConfigId': api.config.buildConfigId,
      if (_sessionId != null) 'sessionId': _sessionId,
      'platform': _platform(),
      'appVersion': api.config.versionName,
      'locale': localeProvider(),
      if (screenName != null) 'screenName': screenName,
      if (widgetKey != null) 'widgetKey': widgetKey,
      if (target != null) 'target': target,
      if (campaignCode != null) 'campaignCode': campaignCode,
      if (properties != null && properties.isNotEmpty) 'properties': properties,
      if (value != null) 'value': value,
      if (exps.isNotEmpty) 'experiments': exps,
      'consent': _consent,
    };

    _queue.add(event);
    if (_queue.length > _maxQueue) {
      _queue.removeRange(0, _queue.length - _maxQueue); // drop oldest
    }
  }

  // ── flush ─────────────────────────────────────────────────────────────────

  /// Flush queued events in batches. Never throws; on success it removes the
  /// sent rows, on failure it keeps them for the next attempt. If the analytics
  /// flag is off, the queue is discarded (the server would drop it anyway).
  Future<void> flush() async {
    if (_flushing || _queue.isEmpty || !api.hasBaseUrl) return;
    if (!runtime.flagBool('analytics.enabled', fallback: true)) {
      _queue.clear();
      return;
    }
    _flushing = true;
    try {
      while (_queue.isNotEmpty) {
        final batch = _queue.take(_flushBatch).toList();
        final body = {
          'events': batch,
          if (api.config.buildConfigId != null) 'appId': api.config.buildConfigId,
          'platform': _platform(),
          'appVersion': api.config.versionName,
        };
        final res = await api.postJsonRaw('/api/analytics/events', body);
        if (res.statusCode == 0) break; // network error → keep + retry later
        // 200 (even with drops) → these rows are handled; remove them.
        _queue.removeRange(0, batch.length);
        if (!res.isOk) break; // unexpected non-2xx → stop, keep the rest
      }
    } finally {
      _flushing = false;
    }
  }

  // ── sampling ──────────────────────────────────────────────────────────────

  /// Deterministic, whole-session sample decision from `config.analytics.sampleRate`.
  /// >=1 keeps all; <=0 drops all; otherwise a stable hash bucket of the
  /// sessionId (so the same session is consistently in or out — no half-sessions,
  /// matching the server's per-`deviceId|sessionId` rule).
  bool _computeSampledIn(String sessionId) {
    final rate = runtime.configDouble('analytics.sampleRate') ?? 1.0;
    if (rate >= 1.0) return true;
    if (rate <= 0.0) return false;
    final bucket = _stableBucket('$deviceId|$sessionId'); // 0..99
    return bucket < (rate * 100);
  }

  /// 0..99 bucket — a small FNV-1a hash of the key (deterministic across runs).
  int _stableBucket(String key) {
    var hash = 0x811c9dc5;
    for (final c in key.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash % 100;
  }

  String _platform() {
    try {
      if (Platform.isIOS) return 'ios';
      if (Platform.isAndroid) return 'android';
    } catch (_) {/* non-io platform */}
    return 'android';
  }

  Future<void> stopAndFlush() async {
    _flushTimer?.cancel();
    _endSession();
  }

  void dispose() {
    _flushTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// A [NavigatorObserver] that emits a `screen_view` for each pushed/popped
/// route, derived from its `RouteSettings.name` (the app's named routes, e.g.
/// "/news/15"). Attach to `MaterialApp.navigatorObservers`.
class AnalyticsNavigatorObserver extends NavigatorObserver {
  AnalyticsNavigatorObserver(this.analytics);

  final AnalyticsService analytics;

  void _emit(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name != null && name.isNotEmpty) analytics.screenView(name);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    _emit(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);
    _emit(previousRoute); // back to the previous screen
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);
    _emit(newRoute);
  }
}
