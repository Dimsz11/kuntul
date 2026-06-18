import 'dart:convert';

import 'package:http/http.dart' as http;

import 'app_config.dart';
import 'models.dart';

/// Thrown when an HTTP call fails or the API reports `success: false`.
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// A raw, un-unwrapped HTTP outcome (status + decoded body + ETag) for callers
/// that need conditional-GET semantics (e.g. the runtime config 304 path).
class RawResponse {
  const RawResponse(this.statusCode, this.body, {this.etag});
  final int statusCode;
  final dynamic body; // decoded JSON (Map/List) or null
  final String? etag;

  bool get isNotModified => statusCode == 304;
  bool get isOk => statusCode >= 200 && statusCode < 300;
}

/// Phase 6f — security hooks the host can install on the shared client. Both
/// default to no-ops so the app is unchanged until 6g wires real keys.
///
///   • [signRequest] — a request-signing seam (HMAC/JWS of method+path+body).
///     6g supplies the signer; here it just returns no extra headers.
///   • [certPinningClientFactory] — returns the `http.Client` to use. The
///     default returns a plain client; 6g can return a pinned `IOClient`
///     (SecurityContext with the leaf/intermediate SPKI) WITHOUT touching any
///     call site. Kept as a hook so cert-pinning lands behind config later.
class ApiSecurityHooks {
  const ApiSecurityHooks({this.signRequest, this.certPinningClientFactory});

  /// Returns extra headers to attach (e.g. `X-Signature`). Null/empty → none.
  final Map<String, String> Function(String method, Uri uri, String? body)? signRequest;

  /// Returns the http.Client to use for all calls. Null → a default client.
  final http.Client Function()? certPinningClientFactory;
}

/// Thin client over the CMS2026 public API.
///
/// Every endpoint returns the unified envelope
/// `{ success, statusCode, message, data, errors, pagination }`
/// (see `ApiResponse<T>` in the backend). [_getData] performs the request and
/// unwraps `data`; list endpoints that return a `PagedResult` expose their rows
/// under `data.items`, which the typed methods below handle explicitly.
class ApiClient {
  ApiClient({
    required this.config,
    http.Client? httpClient,
    this.lang = 'ar',
    this.security = const ApiSecurityHooks(),
  }) : _http = httpClient ?? security.certPinningClientFactory?.call() ?? http.Client();

  final AppConfig config;
  final http.Client _http;

  /// Phase 6f/6g — installed security hooks (signing + cert-pinning). Defaults to
  /// no-ops, so behaviour is unchanged until 6g supplies real implementations.
  ///
  /// MUTABLE (6g): the request-signing seam is installed AFTER bootstrap (once the
  /// runtime envelope's `flags.security.requestSigning` + the device signing key
  /// are known) via [SecurityService.installSigning] → so it stays a no-op while
  /// the flag is off (default). The cert-pinning client factory, by contrast, is
  /// consulted once at construction (it builds [_http]); pass it at construction
  /// (main.dart) when pins are baked/known — see [ApiSecurityHooks].
  ApiSecurityHooks security;

  /// Language sent as the `lang` query param (and Accept-Language header) so
  /// the backend resolves titles/content for the active locale. Defaults to
  /// Arabic and is overridden by [ApiClient.fromConfig] / the [language] setter.
  String lang;

  /// Phase 6f — the current bearer token (set by AuthService after login /
  /// refresh; null when anonymous). Attached as `Authorization: Bearer …` on
  /// every call. Kept here so the single shared client carries it everywhere.
  String? authToken;

  /// Phase 6f — the stable device id, attached as `X-Device-Id` (lets the
  /// anonymous analytics/runtime/sync endpoints attribute thin requests).
  String? deviceId;

  /// Phase 6f — a 401 handler (set by AuthService). Returns true when a token
  /// refresh succeeded so the call can be retried once. Null → no retry (the
  /// app is anonymous; a 401 just surfaces). Guarded against re-entrancy.
  Future<bool> Function()? onUnauthorized;
  bool _refreshing = false;

  /// Construct with the config's default language.
  factory ApiClient.fromConfig(
    AppConfig config, {
    http.Client? httpClient,
    ApiSecurityHooks security = const ApiSecurityHooks(),
  }) {
    return ApiClient(
      config: config,
      httpClient: httpClient,
      lang: config.languages.defaultLang,
      security: security,
    );
  }

  set language(String value) => lang = value;

  /// Common headers for every request: JSON + the active language + (when set)
  /// the bearer token, the device id, and the platform/version (the
  /// analytics/runtime ingestors read `X-Platform` / `X-App-Version`).
  Map<String, String> _headers({Map<String, String>? extra}) => {
        'Accept': 'application/json',
        'Accept-Language': lang,
        'X-Lang': lang,
        if (authToken != null && authToken!.isNotEmpty) 'Authorization': 'Bearer $authToken',
        if (deviceId != null && deviceId!.isNotEmpty) 'X-Device-Id': deviceId!,
        'X-App-Version': config.versionName,
        if (extra != null) ...extra,
      };

  String get _base => config.api.baseUrl;

  Uri _uri(String path, [Map<String, String>? query]) {
    // baseUrl has no trailing slash (normalized in AppConfig); path starts "/".
    final base = Uri.parse('$_base$path');
    if (query == null) return base;
    final params = {...query}..removeWhere((_, v) => v.isEmpty);
    return params.isEmpty ? base : base.replace(queryParameters: params);
  }

  /// GET [path] and return the unwrapped `data` node (raw, untyped).
  ///
  /// - Non-2xx → [ApiException] with the server message when present.
  /// - `success == false` → [ApiException] with the envelope message.
  Future<dynamic> _getData(String path, {Map<String, String>? query}) async {
    if (_base.isEmpty) {
      throw ApiException('API base URL is not configured');
    }

    final uri = _uri(path, query);
    final http.Response res;
    try {
      res = await _http
          .get(uri, headers: _headers(extra: _sign('GET', uri, null)))
          .timeout(const Duration(seconds: 20));
    } catch (e) {
      throw ApiException('Network error: $e');
    }

    Map<String, dynamic> body;
    try {
      body = jsonDecode(res.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('Invalid response', statusCode: res.statusCode);
    }

    final success = body['success'] == true;
    if (res.statusCode < 200 || res.statusCode >= 300 || !success) {
      final msg = (body['message'] as String?) ??
          'Request failed (${res.statusCode})';
      throw ApiException(msg, statusCode: res.statusCode);
    }

    return body['data'];
  }

  /// Request-signing hook headers (no-op unless [ApiSecurityHooks.signRequest]
  /// is installed). 6g supplies the signer; here it returns no extra headers.
  Map<String, String> _sign(String method, Uri uri, String? body) =>
      security.signRequest?.call(method, uri, body) ?? const {};

  // -------------------------------------------------------------------------
  // Phase 6f — RAW transport (no envelope unwrap). Used by the runtime/device/
  // sync/analytics services that need status codes (304), or that POST.
  // None of these throw on a non-2xx: they return the [RawResponse] so the
  // caller decides (the runtime poll keeps its cache on 304; ingestion
  // fire-and-forgets). A network error surfaces as statusCode 0.
  // -------------------------------------------------------------------------

  bool get hasBaseUrl => _base.isNotEmpty;

  /// GET returning the raw status + decoded body + ETag, with optional
  /// `If-None-Match`. The runtime config plane relies on the 304 path.
  Future<RawResponse> getRaw(
    String path, {
    Map<String, String>? query,
    String? ifNoneMatch,
    bool retried = false,
  }) async {
    if (_base.isEmpty) return const RawResponse(0, null);
    final uri = _uri(path, query);
    try {
      final res = await _http.get(
        uri,
        headers: _headers(extra: {
          if (ifNoneMatch != null && ifNoneMatch.isNotEmpty) 'If-None-Match': ifNoneMatch,
          ..._sign('GET', uri, null),
        }),
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode == 401 && !retried && await _tryRefresh()) {
        return getRaw(path, query: query, ifNoneMatch: ifNoneMatch, retried: true);
      }
      final etag = res.headers['etag'];
      if (res.statusCode == 304) return RawResponse(304, null, etag: etag ?? ifNoneMatch);
      dynamic decoded;
      if (res.body.isNotEmpty) {
        try {
          decoded = jsonDecode(res.body);
        } catch (_) {/* leave null */}
      }
      return RawResponse(res.statusCode, decoded, etag: etag);
    } catch (_) {
      return const RawResponse(0, null);
    }
  }

  /// Run the 401 handler at most once-per-call (re-entrancy guarded). Returns
  /// true when a refresh succeeded and the caller should retry.
  Future<bool> _tryRefresh() async {
    final cb = onUnauthorized;
    if (cb == null || _refreshing) return false;
    _refreshing = true;
    try {
      return await cb();
    } catch (_) {
      return false;
    } finally {
      _refreshing = false;
    }
  }

  /// POST a JSON body, returning the raw outcome (never throws).
  Future<RawResponse> postJsonRaw(
    String path,
    Object? jsonBody, {
    Map<String, String>? query,
    bool retried = false,
  }) async {
    if (_base.isEmpty) return const RawResponse(0, null);
    final uri = _uri(path, query);
    final encoded = jsonBody == null ? null : jsonEncode(jsonBody);
    try {
      final res = await _http.post(
        uri,
        headers: _headers(extra: {
          'Content-Type': 'application/json',
          ..._sign('POST', uri, encoded),
        }),
        body: encoded,
      ).timeout(const Duration(seconds: 20));
      if (res.statusCode == 401 && !retried && await _tryRefresh()) {
        return postJsonRaw(path, jsonBody, query: query, retried: true);
      }
      dynamic decoded;
      if (res.body.isNotEmpty) {
        try {
          decoded = jsonDecode(res.body);
        } catch (_) {/* leave null */}
      }
      return RawResponse(res.statusCode, decoded, etag: res.headers['etag']);
    } catch (_) {
      return const RawResponse(0, null);
    }
  }

  /// POST a JSON body and unwrap the envelope `data` (throws like [_getData]).
  Future<dynamic> postData(String path, Object? jsonBody, {Map<String, String>? query}) async {
    final raw = await postJsonRaw(path, jsonBody, query: query);
    if (raw.statusCode == 0) throw ApiException('Network error');
    final body = raw.body;
    final success = body is Map && body['success'] == true;
    if (!raw.isOk || !success) {
      final msg = (body is Map ? body['message'] as String? : null) ??
          'Request failed (${raw.statusCode})';
      throw ApiException(msg, statusCode: raw.statusCode);
    }
    return (body as Map)['data'];
  }

  /// Helper: unwrap a `PagedResult` envelope to its `items` list of maps.
  List<Map<String, dynamic>> _pagedItems(dynamic data) {
    if (data is Map<String, dynamic> && data['items'] is List) {
      return (data['items'] as List).whereType<Map<String, dynamic>>().toList();
    }
    // Tolerate a bare array too (in case an endpoint returns data:[...]).
    if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    return const <Map<String, dynamic>>[];
  }

  List<Map<String, dynamic>> _list(dynamic data) {
    if (data is List) return data.whereType<Map<String, dynamic>>().toList();
    return const <Map<String, dynamic>>[];
  }

  /// The per-app identifier baked into `app_config.json` (`app.appId`). Sent as
  /// `?app=` so the menu/home endpoints resolve THIS app's rows (falling back to
  /// the global default when the app owns none) — see `MobileLayoutResolver`.
  String get _appId => config.appId;

  // -------------------------------------------------------------------------
  // Typed endpoints (mirror README §7 + content detail endpoints).
  // -------------------------------------------------------------------------

  /// GET /api/mobile/menu?app=&lang= — ordered, enabled drawer/bottom-nav items
  /// for this app (OTA refresh of the baked `modules[]`).
  Future<List<MenuItem>> menu() async {
    final data = await _getData('/api/mobile/menu',
        query: {'app': _appId, 'lang': lang});
    return _list(data).map(MenuItem.fromJson).toList()
      ..sort((a, b) => a.displayOrder.compareTo(b.displayOrder));
  }

  /// GET /api/mobile/home-layout?app=&lang= — ordered, enabled home sections for
  /// this app (OTA refresh of the baked `home[]`).
  Future<List<HomeSection>> homeLayout() async {
    final data = await _getData('/api/mobile/home-layout',
        query: {'app': _appId, 'lang': lang});
    final sections = _list(data).map(HomeSection.fromJson).toList()
      ..sort((a, b) => a.order.compareTo(b.order));
    return sections;
  }

  /// GET /api/news?categoryId=&pageSize= — news list (PagedResult → items).
  Future<List<NewsItem>> news({int? categoryId, int pageSize = 10}) async {
    final data = await _getData('/api/news', query: {
      'pageSize': '$pageSize',
      'lang': lang,
      if (categoryId != null) 'categoryId': '$categoryId',
    });
    return _pagedItems(data).map(NewsItem.fromJson).toList();
  }

  /// GET /api/news/{id} — single news item with translations.
  Future<NewsDetail> newsById(int id) async {
    final data = await _getData('/api/news/$id');
    if (data is Map<String, dynamic>) return NewsDetail.fromJson(data);
    throw ApiException('News not found', statusCode: 404);
  }

  /// GET /api/links/by-group-key/{key} — slider items (image + title + url).
  Future<List<LinkItem>> linksByGroup(String key) async {
    final data = await _getData('/api/links/by-group-key/$key');
    return LinkItem.listFromGroup(data);
  }

  /// GET /api/publications?pageSize= — publications list (PagedResult → items).
  Future<List<Publication>> publications({int pageSize = 10}) async {
    final data = await _getData('/api/publications', query: {
      'pageSize': '$pageSize',
    });
    return _pagedItems(data).map(Publication.fromJson).toList();
  }

  /// GET /api/companies/services — services directory (parent → children tree).
  Future<List<ServiceItem>> services() async {
    final data = await _getData('/api/companies/services');
    return _list(data).map(ServiceItem.fromJson).toList();
  }

  /// GET /api/pages/by-key/{key} — CMS-managed page (title + HTML content).
  Future<PageContent> pageByKey(String key) async {
    final data = await _getData('/api/pages/by-key/$key', query: {'lang': lang});
    if (data is Map<String, dynamic>) return PageContent.fromJson(data);
    throw ApiException('Page not found', statusCode: 404);
  }

  // -------------------------------------------------------------------------
  // Added endpoints for the 12 new home section types.
  // -------------------------------------------------------------------------

  /// GET /api/announcements?pageSize= — announcements list (PagedResult → items).
  Future<List<AnnouncementItem>> announcements({int pageSize = 10}) async {
    final data = await _getData('/api/announcements', query: {
      'pageSize': '$pageSize',
      'lang': lang,
    });
    return _pagedItems(data).map(AnnouncementItem.fromJson).toList();
  }

  /// GET /api/gallery?pageSize= — photo albums (PagedResult → items).
  Future<List<AlbumItem>> galleryAlbums({int pageSize = 10}) async {
    final data = await _getData('/api/gallery', query: {
      'pageSize': '$pageSize',
      'lang': lang,
    });
    return _pagedItems(data).map(AlbumItem.fromJson).toList();
  }

  /// GET /api/speeches?pageSize= — speeches/videos (PagedResult → items).
  Future<List<SpeechItem>> videos({int pageSize = 10}) async {
    final data = await _getData('/api/speeches', query: {
      'pageSize': '$pageSize',
      'lang': lang,
    });
    return _pagedItems(data).map(SpeechItem.fromJson).toList();
  }

  /// GET /api/faq?pageSize= — FAQ entries (PagedResult → items).
  Future<List<FaqItem>> faq({int pageSize = 20}) async {
    final data = await _getData('/api/faq', query: {
      'pageSize': '$pageSize',
      'lang': lang,
    });
    return _pagedItems(data).map(FaqItem.fromJson).toList();
  }

  /// GET /api/news/categories — news categories (bare list, not paged).
  Future<List<CategoryItem>> newsCategories() async {
    final data = await _getData('/api/news/categories', query: {'lang': lang});
    return _list(data).map(CategoryItem.fromJson).toList();
  }

  /// GET /api/settings/public — public settings as a flat Key→Value map
  /// (anonymous). Used by the `contact` section (phone/email/address).
  Future<Map<String, String>> settingsPublic() async {
    final data = await _getData('/api/settings/public');
    if (data is Map<String, dynamic>) {
      return data.map((k, v) => MapEntry(k, v?.toString() ?? ''));
    }
    return const <String, String>{};
  }

  /// GET /api/search/semantic?q=&topK= — semantic content search.
  ///
  /// The CMS exposes search under `/api/search/semantic` (vector search). If
  /// that errors (e.g. embeddings not configured), the caller falls back to a
  /// keyword news search via [news] + the `search` query param.
  Future<List<SearchResultItem>> search(String q, {int topK = 20}) async {
    final data = await _getData('/api/search/semantic', query: {
      'q': q,
      'topK': '$topK',
    });
    return _list(data).map(SearchResultItem.fromJson).toList();
  }

  /// GET /api/news?search=&pageSize= — keyword news search (fallback used by the
  /// search screen when semantic search is unavailable).
  Future<List<NewsItem>> newsSearch(String q, {int pageSize = 30}) async {
    final data = await _getData('/api/news', query: {
      'search': q,
      'pageSize': '$pageSize',
      'lang': lang,
    });
    return _pagedItems(data).map(NewsItem.fromJson).toList();
  }

  void dispose() => _http.close();
}
