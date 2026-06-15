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

/// Thin client over the CMS2026 public API.
///
/// Every endpoint returns the unified envelope
/// `{ success, statusCode, message, data, errors, pagination }`
/// (see `ApiResponse<T>` in the backend). [_getData] performs the request and
/// unwraps `data`; list endpoints that return a `PagedResult` expose their rows
/// under `data.items`, which the typed methods below handle explicitly.
class ApiClient {
  ApiClient({required this.config, http.Client? httpClient})
      : _http = httpClient ?? http.Client();

  final AppConfig config;
  final http.Client _http;

  /// Language sent as the `lang` query param (and Accept-Language header) so
  /// the backend resolves titles/content for the active locale.
  String lang;

  /// Construct with the config's default language.
  factory ApiClient.fromConfig(AppConfig config, {http.Client? httpClient}) {
    return ApiClient(config: config, httpClient: httpClient)
      ..lang = config.languages.defaultLang;
  }

  set language(String value) => lang = value;

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

    final http.Response res;
    try {
      res = await _http.get(
        _uri(path, query),
        headers: {
          'Accept': 'application/json',
          'Accept-Language': lang,
        },
      ).timeout(const Duration(seconds: 20));
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
