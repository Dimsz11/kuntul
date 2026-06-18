/// DeepLinkService — the on-device side of the Phase-6c Deep Linking plane.
///
/// Catches **Universal Links / App Links** and **custom-scheme** links via the
/// `app_links` plugin (its `uriLinkStream` delivers the cold-start initial link
/// too, because it is instantiated at bootstrap), turns each link into an
/// in-app route, and navigates through the existing `Navigator` (the same named
/// routes `lib/routing/app_router.dart` already resolves). Push taps funnel
/// through the SAME [handleLink] path (see PushService), so there is one code
/// path for "open this content".
///
/// Two resolution strategies, in order:
///   1. **Path mapping (offline, instant):** a universal-link path like
///      `/news/15`, `/publications`, `/page/about`, `/l/WELCOME1?...` maps
///      straight to an app route — these already match the server's
///      `DeepLinkRoute.AppRoutePattern` (verified against `DeepLinkingSeeder`)
///      and the app router. `/l/{slug}` short links hit the server redirector
///      first (which records the click), so when the OS hands us the resolved
///      universal link we just navigate.
///   2. **Server resolve (entity links):** for `app://entity/{type}/{id|slug}`
///      style links we call `GET /api/deeplink/resolve` and navigate to the
///      returned `appRoute` (authoritative; validates existence).
///
/// **Click attribution:** a push tap carries a `campaignId` → we report it via
/// `POST /api/push/track/click { campaignId, deviceId }`. Web short links carry
/// their own attribution server-side (the `/l/{slug}` 302 records the click),
/// so we don't double-report those.
///
/// **Graceful degradation:** if `app_links` throws (unsupported platform, no
/// native config) the stream subscription is wrapped so the app still boots;
/// an unresolvable link falls back to opening the web URL in the browser, then
/// to a no-op — navigation never dead-ends.
library;

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api_client.dart';

/// Navigate to an in-app named route (e.g. "/news/15"). Wired to the root
/// Navigator in main.dart. Returns nothing; absent navigator → no-op.
typedef NavigateFn = void Function(String route);

/// Optional analytics emit for a deep-link open (source/target). Null-safe.
typedef DeepLinkAnalyticsFn = void Function(String target, {String? campaign});

class DeepLinkService {
  DeepLinkService({
    required this.api,
    required this.navigate,
    this.onAnalytics,
    AppLinks? appLinks,
  }) : _appLinks = appLinks ?? AppLinks();

  final ApiClient api;
  final NavigateFn navigate;
  final DeepLinkAnalyticsFn? onAnalytics;
  final AppLinks _appLinks;

  StreamSubscription<Uri>? _sub;

  /// Start listening for incoming links. The `uriLinkStream` also replays the
  /// cold-start link, so this is the single entry point. Never throws.
  Future<void> init() async {
    try {
      _sub = _appLinks.uriLinkStream.listen(
        (uri) => _onUri(uri),
        onError: (_) {/* swallow — keep the app running */},
      );
    } catch (_) {
      // Plugin unavailable / not configured → deep links are simply inert.
    }
  }

  void _onUri(Uri uri) {
    final route = routeForUri(uri);
    if (route != null) {
      onAnalytics?.call(uri.toString());
      navigate(route);
      return;
    }
    // Could not map to a route → try server resolve for entity-style links.
    unawaited(_resolveAndNavigate(uri));
  }

  /// Public so PushService can reuse the exact same handling for a tapped
  /// notification's deep link. [campaignId] (when present) is reported as a
  /// push click.
  Future<void> handleLink(String link, {int? campaignId}) async {
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (campaignId != null) {
      // Report the tap (idempotent server-side; bumps the campaign's clicked stat).
      await api.postJsonRaw('/api/push/track/click', {
        'campaignId': campaignId,
        'deviceId': api.deviceId ?? 'anon',
      });
    }
    final route = routeForUri(uri);
    if (route != null) {
      onAnalytics?.call(uri.toString());
      navigate(route);
    } else {
      await _resolveAndNavigate(uri);
    }
  }

  /// Map a link [uri] to an in-app route, or null when it isn't an in-app
  /// destination. Handles universal links (path-based), the `/l/{slug}`
  /// redirector form (when the OS hands us the slug), and custom schemes whose
  /// host is the section (e.g. `myapp://news/15`).
  ///
  /// The returned routes are EXACTLY what `app_router.dart` already resolves,
  /// so navigation is a single `Navigator.pushNamed`.
  String? routeForUri(Uri uri) {
    // Custom scheme (app://, myapp://): the host is often the first segment.
    // Normalise to a path-segment list that starts with the section.
    final segments = <String>[
      if (uri.scheme.isNotEmpty && uri.host.isNotEmpty && !uri.host.contains('.')) uri.host,
      ...uri.pathSegments.where((s) => s.isNotEmpty),
    ];
    if (segments.isEmpty) return null;

    final first = segments.first.toLowerCase();
    final second = segments.length > 1 ? segments[1] : null;
    final qp = uri.queryParameters;

    switch (first) {
      case 'news':
      case 'events':
        // /news, /news/15, /news?categoryId=33
        if (second != null && int.tryParse(second) != null) return '/news/$second';
        if (qp['categoryId'] != null) return '/news?categoryId=${qp['categoryId']}';
        return '/news';
      case 'publications':
        return '/publications';
      case 'services':
        return '/services';
      case 'gallery':
        return '/gallery';
      case 'speeches':
      case 'videos':
        return '/speeches';
      case 'faq':
        return '/faq';
      case 'search':
        final q = qp['q'] ?? (second ?? '');
        return q.isEmpty ? '/search' : '/search?q=$q';
      case 'contact':
        return '/contact';
      case 'forms':
        // /forms or /forms/{key} → the app routes forms to a page lookup today.
        return second != null ? '/page/$second' : '/page/forms';
      case 'category':
        // /category/{id} → news filtered by category
        if (second != null) return '/news?categoryId=$second';
        return '/news';
      case 'page':
      case 'about':
        return second != null ? '/page/$second' : null;
      case 'l':
        // Short link form `/l/{slug}` reached the app directly (rare — usually
        // the server 302s to a universal link first). Resolve via the server.
        return null;
      default:
        // Unknown first segment → let the server resolve, or page-by-key.
        return null;
    }
  }

  /// Ask the server to resolve an entity link, then navigate to its appRoute.
  /// Falls back to opening the web URL, then to a no-op.
  Future<void> _resolveAndNavigate(Uri uri) async {
    // Derive an entityType + id/slug from the link shape, when present.
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? entityType;
    int? id;
    String? slug;

    // `…/entity/{type}/{idOrSlug}` or `…/{type}/{idOrSlug}` for known types.
    const known = {'news', 'event', 'publication', 'service', 'form', 'category', 'search', 'page', 'profile'};
    final idx = segments.indexWhere((s) => known.contains(s.toLowerCase()));
    if (idx >= 0) {
      entityType = segments[idx].toLowerCase();
      final next = idx + 1 < segments.length ? segments[idx + 1] : null;
      if (next != null) {
        final asInt = int.tryParse(next);
        if (asInt != null) {
          id = asInt;
        } else {
          slug = next;
        }
      }
    }

    if (entityType != null && api.hasBaseUrl) {
      final res = await api.getRaw('/api/deeplink/resolve', query: {
        'entityType': entityType,
        if (id != null) 'id': '$id',
        if (slug != null) 'slug': slug,
      });
      if (res.isOk && res.body is Map) {
        final data = (res.body as Map)['data'];
        if (data is Map) {
          final appRoute = data['appRoute'] as String?;
          final webUrl = data['webUrl'] as String?;
          if (appRoute != null && appRoute.isNotEmpty) {
            onAnalytics?.call(uri.toString());
            navigate(appRoute);
            return;
          }
          if (webUrl != null && webUrl.isNotEmpty) {
            await _openExternal(webUrl);
            return;
          }
        }
      }
    }

    // Last resort: if the link is an http(s) URL, open it externally.
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      await _openExternal(uri.toString());
    }
  }

  Future<void> _openExternal(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    } catch (_) {/* ignore */}
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
