/// PushService — the on-device side of the Phase-6b Push plane.
///
/// Wires a push transport to the rest of the runtime: it pushes the FCM/APNs
/// token into the Device Registry (and re-registers on token refresh),
/// subscribes the configured topics, and routes a **notification tap → its deep
/// link → navigation** through the SAME [DeepLinkService.handleLink] path the
/// OS deep links use, reporting the tap as a push click.
///
/// ## Why a pluggable provider (graceful when Firebase is absent)
/// `firebase_messaging` is intentionally NOT a hard dependency of this
/// reference: Firebase needs native config files (`google-services.json` /
/// `GoogleService-Info.plist`) that the CI does NOT provide, and the
/// google-services Gradle plugin FAILS the build when they're missing. So push
/// talks to a [PushProvider] interface whose default is [NoOpPushProvider] — the
/// app boots and runs with push simply inert. To enable real push, add
/// `firebase_core` + `firebase_messaging`, implement a `FirebasePushProvider`
/// (skeleton in the README), and pass it in. Nothing else changes.
///
/// The provider surfaces the three FCM lifecycles uniformly:
///   • foreground  — `onMessage`
///   • background tap / from-terminated tap — `onMessageOpenedApp`
///   • cold-start (app opened from a notification) — `getInitialMessage`
/// each delivering a [PushMessage] { title, body, deepLink, campaignId, data }.
library;

import 'dart:async';

import 'device_service.dart';
import 'deeplink_service.dart';

/// A normalised inbound push, transport-agnostic. `deepLink` + `campaignId` are
/// read from the message's `data` map (the CMS fan-out sets them).
class PushMessage {
  const PushMessage({this.title, this.body, this.deepLink, this.campaignId, this.data = const {}});

  final String? title;
  final String? body;
  final String? deepLink;
  final int? campaignId;
  final Map<String, dynamic> data;

  /// Build from a flat data map (the common FCM `message.data` shape). Accepts
  /// `deepLink`/`deep_link`/`url` and `campaignId`/`campaign_id`.
  factory PushMessage.fromData(Map<String, dynamic> data, {String? title, String? body}) {
    int? campaignId;
    final rawCampaign = data['campaignId'] ?? data['campaign_id'];
    if (rawCampaign is int) {
      campaignId = rawCampaign;
    } else if (rawCampaign is String) {
      campaignId = int.tryParse(rawCampaign);
    }
    return PushMessage(
      title: title,
      body: body,
      deepLink: (data['deepLink'] ?? data['deep_link'] ?? data['url'])?.toString(),
      campaignId: campaignId,
      data: data,
    );
  }
}

/// The transport abstraction. A real implementation wraps `firebase_messaging`;
/// the default [NoOpPushProvider] makes the whole service safely inert.
abstract class PushProvider {
  /// Request permission + initialise. Returns true when push is actually
  /// available (a real provider with granted permission).
  Future<bool> initialize();

  /// The current device push token (null when unavailable).
  Future<String?> getToken();

  /// Emits a new token whenever it rotates.
  Stream<String> get onTokenRefresh;

  /// Foreground messages.
  Stream<PushMessage> get onMessage;

  /// A tap that opened/foregrounded the app (background or terminated).
  Stream<PushMessage> get onMessageOpenedApp;

  /// The message that cold-started the app from a notification, if any.
  Future<PushMessage?> getInitialMessage();

  /// Subscribe / unsubscribe FCM topics natively (the provider may also do this
  /// server-side via the Device Registry; both are harmless).
  Future<void> subscribeToTopic(String topic);
  Future<void> unsubscribeFromTopic(String topic);
}

/// The default: push does nothing. Lets the app build + run with no Firebase.
class NoOpPushProvider implements PushProvider {
  const NoOpPushProvider();

  @override
  Future<bool> initialize() async => false;
  @override
  Future<String?> getToken() async => null;
  @override
  Stream<String> get onTokenRefresh => const Stream<String>.empty();
  @override
  Stream<PushMessage> get onMessage => const Stream<PushMessage>.empty();
  @override
  Stream<PushMessage> get onMessageOpenedApp => const Stream<PushMessage>.empty();
  @override
  Future<PushMessage?> getInitialMessage() async => null;
  @override
  Future<void> subscribeToTopic(String topic) async {}
  @override
  Future<void> unsubscribeFromTopic(String topic) async {}
}

class PushService {
  PushService({
    required this.device,
    required this.deepLinks,
    required this.localeProvider,
    PushProvider? provider,
  }) : provider = provider ?? const NoOpPushProvider();

  final PushProvider provider;
  final DeviceService device;
  final DeepLinkService deepLinks;

  /// Returns the active UI locale at call time (so a re-register uses the right
  /// language). Kept as a callback so the service has no widget dependency.
  final String Function() localeProvider;

  bool _available = false;
  bool get available => _available;

  StreamSubscription<String>? _tokenSub;
  StreamSubscription<PushMessage>? _msgSub;
  StreamSubscription<PushMessage>? _openSub;

  /// Initialise push. With the default no-op provider this returns quickly and
  /// the app continues unaffected. With a real provider it registers the token,
  /// wires the foreground/tap handlers, and handles a cold-start tap.
  ///
  /// [topics] (from runtime `config.push.topics`) are subscribed best-effort.
  Future<void> init({List<String> topics = const []}) async {
    try {
      _available = await provider.initialize();
    } catch (_) {
      _available = false;
    }
    if (!_available) return;

    // 1) Register the current token with the Device Registry.
    try {
      final token = await provider.getToken();
      if (token != null && token.isNotEmpty) {
        await device.updatePushToken(token, locale: localeProvider());
      }
    } catch (_) {/* token unavailable — device still registered without it */}

    // 2) Token refresh → re-register.
    _tokenSub = provider.onTokenRefresh.listen((token) {
      device.updatePushToken(token, locale: localeProvider());
    });

    // 3) Topics.
    if (topics.isNotEmpty) {
      for (final t in topics) {
        try {
          await provider.subscribeToTopic(t);
        } catch (_) {/* ignore per-topic */}
      }
      await device.updateTopics(subscribe: topics);
    }

    // 4) Foreground messages — the app can show an in-app banner; here we only
    //    keep the hook (no intrusive UI in the reference). Tapping a system
    //    notification goes through onMessageOpenedApp below.
    _msgSub = provider.onMessage.listen((_) {/* hook for an in-app banner */});

    // 5) Tap (background / terminated) → deep link → navigate + report click.
    _openSub = provider.onMessageOpenedApp.listen(_handleTap);

    // 6) Cold-start: opened from a notification while terminated.
    try {
      final initial = await provider.getInitialMessage();
      if (initial != null) _handleTap(initial);
    } catch (_) {/* ignore */}
  }

  void _handleTap(PushMessage msg) {
    final link = msg.deepLink;
    if (link != null && link.isNotEmpty) {
      // Single code path with OS deep links; reports the push click when a
      // campaignId is present.
      deepLinks.handleLink(link, campaignId: msg.campaignId);
    }
  }

  void dispose() {
    _tokenSub?.cancel();
    _msgSub?.cancel();
    _openSub?.cancel();
  }
}
