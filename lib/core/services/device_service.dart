/// DeviceService — the on-device side of the Phase-6b Device Registry.
///
/// Registers the device with the CMS so push campaigns + segments can target
/// it, then keeps it warm with a periodic heartbeat and syncs topic
/// subscriptions. All three endpoints are anonymous (the app calls them
/// pre-auth) and keyed by the stable device id (an UPSERT server-side).
///
/// Contract (matches `RegisterDeviceCommand` / `DevicesController`):
///   • `POST /api/devices/register`            { deviceId, platform, pushToken,
///       pushProvider, appBuildConfigId, model, osVersion, appVersion, locale,
///       capabilitiesJson, topicsCsv, userId }
///   • `POST /api/devices/{deviceId}/heartbeat` { healthJson, appVersion, locale }
///   • `POST /api/devices/{deviceId}/topics`    { subscribe:[], unsubscribe:[] }
///
/// **Graceful degradation:** every call is fire-and-forget via the raw client
/// (never throws); with no base URL or no network it simply no-ops. The push
/// token is OPTIONAL — the device registers (for heartbeat/locale/segmenting)
/// even when push is unavailable, and re-registers when a token later arrives
/// (FCM token refresh).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import '../api_client.dart';

class DeviceService {
  DeviceService({required this.api});

  final ApiClient api;

  Timer? _heartbeatTimer;
  String? _deviceId;
  String? _lastPushToken;
  String? _lastPushProvider;

  /// The runtime platform string the registry expects.
  static String get platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) return 'web';
    return 'android';
  }

  /// Default push provider for the platform (the server normalises this too).
  static String get _defaultProvider => Platform.isIOS ? 'apns' : 'fcm';

  /// Register (or refresh) the device. Call on launch and again whenever the
  /// push token changes. [locale] is the active UI language.
  ///
  /// Phase 6g: returns the unwrapped `data` map so the caller can pick up a
  /// freshly-minted signing key (`signingKeyId` + `signingSecret`, shown ONCE) for
  /// request signing. Null on a network/parse miss (fire-and-forget safe).
  Future<Map<String, dynamic>?> register({
    required String deviceId,
    required String locale,
    String? pushToken,
    String? pushProvider,
    int? appBuildConfigId,
    List<String> topics = const [],
    String? userId,
  }) async {
    _deviceId = deviceId;
    if (pushToken != null && pushToken.isNotEmpty) {
      _lastPushToken = pushToken;
      _lastPushProvider = pushProvider ?? _defaultProvider;
    }

    final body = <String, dynamic>{
      'deviceId': deviceId,
      'platform': platform,
      'pushToken': _lastPushToken,
      'pushProvider': _lastPushProvider,
      'appBuildConfigId': appBuildConfigId,
      'model': null, // device_info_plus not used here (keeps deps minimal); optional server-side.
      'osVersion': _safeOsVersion(),
      'appVersion': api.config.versionName,
      'locale': locale,
      'capabilitiesJson': jsonEncode({
        'push': _lastPushToken != null,
        'platform': platform,
      }),
      'topicsCsv': topics.isEmpty ? null : topics.join(','),
      'userId': userId,
    };

    final res = await api.postJsonRaw('/api/devices/register', body);
    final data = res.body is Map && (res.body as Map)['data'] is Map
        ? ((res.body as Map)['data'] as Map).map((k, v) => MapEntry(k.toString(), v))
        : null;
    return data;
  }

  /// FCM/APNs token refresh → re-register so the new token is stored.
  Future<void> updatePushToken(String token, {String? provider, required String locale}) async {
    if (_deviceId == null) return;
    await register(
      deviceId: _deviceId!,
      locale: locale,
      pushToken: token,
      pushProvider: provider,
    );
  }

  /// Begin periodic heartbeats (refresh LastSeen + version/locale). Safe to
  /// call repeatedly — it resets the timer. [interval] usually comes from the
  /// runtime `config` (falls back to 30 min).
  void startHeartbeat({required String locale, Duration interval = const Duration(minutes: 30)}) {
    _heartbeatTimer?.cancel();
    if (_deviceId == null) return;
    // Fire once promptly, then on the interval.
    _sendHeartbeat(locale);
    _heartbeatTimer = Timer.periodic(interval, (_) => _sendHeartbeat(locale));
  }

  /// One heartbeat now (also called on app resume).
  Future<void> heartbeatNow(String locale) => _sendHeartbeat(locale);

  Future<void> _sendHeartbeat(String locale) async {
    final id = _deviceId;
    if (id == null) return;
    await api.postJsonRaw('/api/devices/$id/heartbeat', {
      'healthJson': jsonEncode({'ts': DateTime.now().toUtc().toIso8601String()}),
      'appVersion': api.config.versionName,
      'locale': locale,
    });
  }

  /// Subscribe / unsubscribe topics for this device.
  Future<void> updateTopics({List<String> subscribe = const [], List<String> unsubscribe = const []}) async {
    final id = _deviceId;
    if (id == null || (subscribe.isEmpty && unsubscribe.isEmpty)) return;
    await api.postJsonRaw('/api/devices/$id/topics', {
      'subscribe': subscribe,
      'unsubscribe': unsubscribe,
    });
  }

  String _safeOsVersion() {
    try {
      return Platform.operatingSystemVersion;
    } catch (_) {
      return '';
    }
  }

  void dispose() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = null;
  }
}
