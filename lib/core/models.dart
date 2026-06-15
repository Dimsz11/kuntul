/// Data models for the CMS2026 mobile contract.
///
/// Field names mirror the backend DTOs (serialized camelCase by ASP.NET Core):
///   * MobileMenuItemDto      → [MenuItem]
///   * HomeLayoutSectionDto   → [HomeSection]
///   * NewsListDto            → [NewsItem]
///   * NewsDetailDto          → [NewsDetail]
///   * GroupLinkItemDto       → [LinkItem]
///   * PublicationListDto     → [Publication]
///   * ServicePublicDto       → [ServiceItem]
///   * PagePublicDto          → [PageContent]
///   * AnnouncementListDto    → [AnnouncementItem]
///   * PhotoAlbumListDto      → [AlbumItem]
///   * SpeechListDto          → [SpeechItem]  (videos)
///   * FaqListDto             → [FaqItem]
///   * news categories        → [CategoryItem]
///   * SemanticSearchResultDto→ [SearchResultItem]
///
/// Every `fromJson` is defensive: missing keys fall back to safe values so a
/// slightly different payload (or a future field) never crashes rendering.
library;

// ---------------------------------------------------------------------------
// Menu — GET /api/mobile/menu?lang= (+ the baked `modules[]` in app_config)
// ---------------------------------------------------------------------------

/// One drawer / bottom-nav entry. `title` is already resolved for the
/// requested language by the backend (network path); for the baked path it is
/// resolved from `titleAr` / `titleEn` per the active language.
class MenuItem {
  const MenuItem({
    required this.moduleName,
    required this.title,
    required this.icon,
    required this.route,
    required this.displayOrder,
    this.titleAr,
    this.titleEn,
  });

  final String moduleName;
  final String title;

  /// Material/Bootstrap icon NAME (string) — mapped to an `IconData` in the UI.
  final String? icon;

  /// In-app route to open, e.g. "/news".
  final String? route;
  final int displayOrder;

  /// Present only on baked items (from `app_config.modules[]`); used to
  /// re-resolve [title] when the language changes before the network menu
  /// arrives.
  final String? titleAr;
  final String? titleEn;

  /// Network shape — `GET /api/mobile/menu` (`MobileMenuItemDto`): `title` is
  /// already language-resolved server-side.
  factory MenuItem.fromJson(Map<String, dynamic> j) => MenuItem(
        moduleName: _s(j['moduleName']),
        title: _s(j['title'], fallback: _s(j['moduleName'])),
        icon: j['icon'] as String?,
        route: j['route'] as String?,
        displayOrder: _i(j['displayOrder']),
        titleAr: j['titleAr'] as String?,
        titleEn: j['titleEn'] as String?,
      );

  /// Baked shape — one entry of `app_config.modules[]`
  /// (`{ name, enabled, icon, route, displayOrder, titleAr, titleEn }`).
  factory MenuItem.fromModuleJson(Map<String, dynamic> j) {
    final titleAr = j['titleAr'] as String?;
    final titleEn = j['titleEn'] as String?;
    final name = _s(j['name'], fallback: _s(j['moduleName']));
    return MenuItem(
      moduleName: name,
      // Default to the Arabic title (the app's default language); the UI calls
      // [localizedTitle] to switch when the locale is English.
      title: (titleAr != null && titleAr.isNotEmpty)
          ? titleAr
          : (titleEn != null && titleEn.isNotEmpty ? titleEn : name),
      icon: j['icon'] as String?,
      route: j['route'] as String?,
      displayOrder: _i(j['displayOrder']),
      titleAr: titleAr,
      titleEn: titleEn,
    );
  }

  /// Title for [lang], preferring the per-language fields when present (baked
  /// items), else the already-resolved [title].
  String localizedTitle(String lang) {
    final preferred = lang == 'en' ? titleEn : titleAr;
    final fallback = lang == 'en' ? titleAr : titleEn;
    if (preferred != null && preferred.isNotEmpty) return preferred;
    if (fallback != null && fallback.isNotEmpty) return fallback;
    return title.isNotEmpty ? title : moduleName;
  }
}

// ---------------------------------------------------------------------------
// Home layout — GET /api/mobile/home-layout?lang=
// ---------------------------------------------------------------------------

/// One home section. `config` is a real JSON object (already parsed server-side
/// from ConfigJson), keyed per section type — see README §7.2.
class HomeSection {
  const HomeSection({
    required this.type,
    required this.title,
    required this.order,
    required this.config,
  });

  /// One of the 20 contract types (README §7.2):
  ///   slider | news | shortcuts | banner | publications | services |
  ///   webview | spacer | announcements | gallery | videos | events | faq |
  ///   contact | sociallinks | search | html | hero | categories | about.
  /// Unknown types are skipped by the renderer.
  final String type;
  final String? title;
  final int order;
  final Map<String, dynamic> config;

  factory HomeSection.fromJson(Map<String, dynamic> j) => HomeSection(
        type: _s(j['type']),
        title: j['title'] as String?,
        order: _i(j['order']),
        config: j['config'] is Map<String, dynamic>
            ? j['config'] as Map<String, dynamic>
            : <String, dynamic>{},
      );

  // Typed config accessors with defaults (tolerant of int-vs-string).
  String? get linkGroupKey => _ns(config['linkGroupKey']);
  bool get autoplay => _b(config['autoplay'], fallback: false);
  int get interval => _i(config['interval'], fallback: 5);
  int? get categoryId => config['categoryId'] == null ? null : _i(config['categoryId']);
  int get count => _i(config['count'], fallback: 5);
  List<String> get moduleNames => (config['moduleNames'] is List)
      ? (config['moduleNames'] as List).map((e) => e.toString()).toList()
      : const <String>[];
  String? get imageUrl => _ns(config['imageUrl']);
  String? get link => _ns(config['link']);
  String? get url => _ns(config['url']);
  double get height => _d(config['height'], fallback: 24);

  // --- accessors for the 12 added section types ---

  /// `html` — raw HTML block to render (cleaned to text by the renderer).
  String? get html => _ns(config['html']);

  /// `hero` — optional news id to resolve a featured article; when null the
  /// hero uses the static `imageUrl` / `title` / `link` from config.
  int? get newsId => config['newsId'] == null ? null : _i(config['newsId']);

  /// `about` — CMS page key for `GET /api/pages/by-key/{pageKey}`.
  String? get pageKey => _ns(config['pageKey']);
}

// ---------------------------------------------------------------------------
// News — GET /api/news (list) / GET /api/news/{id} (detail)
// ---------------------------------------------------------------------------

/// List item (NewsListDto). The list endpoint wraps these in a PagedResult:
/// `data.items[]`.
class NewsItem {
  const NewsItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.imageUrl,
    required this.publishDate,
    required this.viewCount,
    required this.categoryName,
  });

  final int id;
  final String title;
  final String? summary;
  final String? imageUrl;
  final DateTime? publishDate;
  final int viewCount;
  final String? categoryName;

  factory NewsItem.fromJson(Map<String, dynamic> j) => NewsItem(
        id: _i(j['id']),
        title: _s(j['title']),
        summary: j['summary'] as String?,
        imageUrl: j['imageUrl'] as String?,
        publishDate: _date(j['publishDate']),
        viewCount: _i(j['viewCount']),
        categoryName: j['categoryName'] as String?,
      );
}

/// Detail (NewsDetailDto) — translations carry the language-specific body.
class NewsDetail {
  const NewsDetail({
    required this.id,
    required this.categoryId,
    required this.imageUrl,
    required this.publishDate,
    required this.viewCount,
    required this.translations,
    required this.images,
  });

  final int id;
  final int categoryId;
  final String? imageUrl;
  final DateTime? publishDate;
  final int viewCount;
  final List<NewsTranslation> translations;
  final List<String> images;

  factory NewsDetail.fromJson(Map<String, dynamic> j) => NewsDetail(
        id: _i(j['id']),
        categoryId: _i(j['categoryId']),
        imageUrl: j['imageUrl'] as String?,
        publishDate: _date(j['publishDate']),
        viewCount: _i(j['viewCount']),
        translations: (j['translations'] is List)
            ? (j['translations'] as List)
                .whereType<Map<String, dynamic>>()
                .map(NewsTranslation.fromJson)
                .toList()
            : const <NewsTranslation>[],
        images: (j['images'] is List)
            ? (j['images'] as List)
                .whereType<Map<String, dynamic>>()
                .map((e) => _s(e['imageUrl']))
                .where((u) => u.isNotEmpty)
                .toList()
            : const <String>[],
      );

  /// Pick the translation for [lang], falling back to the first available.
  NewsTranslation? translationFor(String lang) {
    for (final t in translations) {
      if (t.languageCode == lang) return t;
    }
    return translations.isNotEmpty ? translations.first : null;
  }
}

class NewsTranslation {
  const NewsTranslation({
    required this.languageCode,
    required this.title,
    required this.summary,
    required this.content,
  });

  final String languageCode;
  final String title;
  final String? summary;
  final String? content;

  factory NewsTranslation.fromJson(Map<String, dynamic> j) => NewsTranslation(
        languageCode: _s(j['languageCode']),
        title: _s(j['title']),
        summary: j['summary'] as String?,
        content: j['content'] as String?,
      );
}

// ---------------------------------------------------------------------------
// Links — GET /api/links/by-group-key/{key}  (slider data source)
// data = { key, groupName, items:[ GroupLinkItemDto ] }
// ---------------------------------------------------------------------------

class LinkItem {
  const LinkItem({
    required this.id,
    required this.title,
    required this.description,
    required this.url,
    required this.imageUrl,
  });

  final int id;
  final String title;
  final String? description;
  final String url;
  final String? imageUrl;

  factory LinkItem.fromJson(Map<String, dynamic> j) => LinkItem(
        id: _i(j['id']),
        title: _s(j['title']),
        description: j['description'] as String?,
        url: _s(j['url']),
        imageUrl: j['imageUrl'] as String?,
      );

  /// Parses the `data` envelope payload (the group object) into its `items`.
  static List<LinkItem> listFromGroup(dynamic data) {
    if (data is Map<String, dynamic> && data['items'] is List) {
      return (data['items'] as List)
          .whereType<Map<String, dynamic>>()
          .map(LinkItem.fromJson)
          .toList();
    }
    return const <LinkItem>[];
  }
}

// ---------------------------------------------------------------------------
// Publications — GET /api/publications  → PagedResult → data.items[]
// ---------------------------------------------------------------------------

class Publication {
  const Publication({
    required this.id,
    required this.title,
    required this.summary,
    required this.imageUrl,
    required this.fileUrl,
    required this.publishDate,
  });

  final int id;
  final String title;
  final String? summary;
  final String? imageUrl;
  final String? fileUrl;
  final DateTime? publishDate;

  factory Publication.fromJson(Map<String, dynamic> j) => Publication(
        id: _i(j['id']),
        title: _s(j['title']),
        summary: j['summary'] as String?,
        imageUrl: j['imageUrl'] as String?,
        fileUrl: j['fileUrl'] as String?,
        publishDate: _date(j['publishDate']),
      );
}

// ---------------------------------------------------------------------------
// Services — GET /api/companies/services  → data = [ ServicePublicDto tree ]
// ---------------------------------------------------------------------------

class ServiceItem {
  const ServiceItem({
    required this.id,
    required this.name,
    required this.description,
    required this.iconUrl,
    required this.imageUrl,
    required this.children,
  });

  final int id;
  final String name;
  final String? description;
  final String? iconUrl;
  final String? imageUrl;
  final List<ServiceItem> children;

  factory ServiceItem.fromJson(Map<String, dynamic> j) => ServiceItem(
        id: _i(j['id']),
        name: _s(j['name']),
        description: j['description'] as String?,
        iconUrl: j['iconUrl'] as String?,
        imageUrl: j['imageUrl'] as String?,
        children: (j['children'] is List)
            ? (j['children'] as List)
                .whereType<Map<String, dynamic>>()
                .map(ServiceItem.fromJson)
                .toList()
            : const <ServiceItem>[],
      );
}

// ---------------------------------------------------------------------------
// Page — GET /api/pages/by-key/{key}  → data = PagePublicDto
// ---------------------------------------------------------------------------

class PageContent {
  const PageContent({
    required this.id,
    required this.pageKey,
    required this.title,
    required this.content,
    required this.languageCode,
  });

  final int id;
  final String? pageKey;
  final String title;
  final String? content;
  final String languageCode;

  factory PageContent.fromJson(Map<String, dynamic> j) => PageContent(
        id: _i(j['id']),
        pageKey: j['pageKey'] as String?,
        title: _s(j['title']),
        content: j['content'] as String?,
        languageCode: _s(j['languageCode'], fallback: 'ar'),
      );
}

// ---------------------------------------------------------------------------
// Announcements — GET /api/announcements  → PagedResult → data.items[]
// (AnnouncementListDto)
// ---------------------------------------------------------------------------

class AnnouncementItem {
  const AnnouncementItem({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.linkUrl,
    required this.startDate,
  });

  final int id;
  final String title;
  final String? description;
  final String? imageUrl;
  final String? linkUrl;
  final DateTime? startDate;

  factory AnnouncementItem.fromJson(Map<String, dynamic> j) => AnnouncementItem(
        id: _i(j['id']),
        title: _s(j['title']),
        description: j['description'] as String?,
        imageUrl: j['imageUrl'] as String?,
        linkUrl: j['linkUrl'] as String?,
        startDate: _date(j['startDate']),
      );
}

// ---------------------------------------------------------------------------
// Gallery (photo albums) — GET /api/gallery → PagedResult → data.items[]
// (PhotoAlbumListDto)
// ---------------------------------------------------------------------------

class AlbumItem {
  const AlbumItem({
    required this.id,
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.albumDate,
  });

  final int id;
  final String title;
  final String? description;
  final String? imageUrl;
  final DateTime? albumDate;

  factory AlbumItem.fromJson(Map<String, dynamic> j) => AlbumItem(
        id: _i(j['id']),
        title: _s(j['title']),
        description: j['description'] as String?,
        // Prefer the thumbnail for grid tiles, fall back to the full image.
        imageUrl: _ns(j['thumbnailUrl']) ?? j['imageUrl'] as String?,
        albumDate: _date(j['albumDate']),
      );
}

// ---------------------------------------------------------------------------
// Videos / speeches — GET /api/speeches → PagedResult → data.items[]
// (SpeechListDto)
// ---------------------------------------------------------------------------

class SpeechItem {
  const SpeechItem({
    required this.id,
    required this.title,
    required this.summary,
    required this.imageUrl,
    required this.eventDate,
    required this.isEvent,
  });

  final int id;
  final String title;
  final String? summary;
  final String? imageUrl;
  final DateTime? eventDate;
  final bool isEvent;

  factory SpeechItem.fromJson(Map<String, dynamic> j) => SpeechItem(
        id: _i(j['id']),
        title: _s(j['title']),
        summary: j['summary'] as String?,
        imageUrl: j['imageUrl'] as String?,
        eventDate: _date(j['eventDate']),
        isEvent: _b(j['isEvent']),
      );
}

// ---------------------------------------------------------------------------
// FAQ — GET /api/faq → PagedResult → data.items[]  (FaqListDto)
// ---------------------------------------------------------------------------

class FaqItem {
  const FaqItem({
    required this.id,
    required this.question,
    required this.answer,
    required this.parentId,
  });

  final int id;
  final String question;
  final String answer;
  final int? parentId;

  factory FaqItem.fromJson(Map<String, dynamic> j) => FaqItem(
        id: _i(j['id']),
        question: _s(j['question']),
        answer: _s(j['answer']),
        parentId: j['parentId'] == null ? null : _i(j['parentId']),
      );
}

// ---------------------------------------------------------------------------
// News categories — GET /api/news/categories → data = [ { id, name, key,
// isEvent } ]
// ---------------------------------------------------------------------------

class CategoryItem {
  const CategoryItem({
    required this.id,
    required this.name,
    required this.key,
    required this.isEvent,
  });

  final int id;
  final String name;
  final String? key;
  final bool isEvent;

  factory CategoryItem.fromJson(Map<String, dynamic> j) => CategoryItem(
        id: _i(j['id']),
        name: _s(j['name'], fallback: 'Category ${_i(j['id'])}'),
        key: j['key'] as String?,
        isEvent: _b(j['isEvent']),
      );
}

// ---------------------------------------------------------------------------
// Search — GET /api/search/semantic?q= → data = [ SemanticSearchResultDto ]
// ---------------------------------------------------------------------------

class SearchResultItem {
  const SearchResultItem({
    required this.entityType,
    required this.entityId,
    required this.title,
    required this.snippet,
    required this.score,
  });

  final String entityType;
  final int entityId;
  final String title;
  final String? snippet;
  final double score;

  factory SearchResultItem.fromJson(Map<String, dynamic> j) => SearchResultItem(
        entityType: _s(j['entityType']),
        entityId: _i(j['entityId']),
        title: _s(j['title']),
        snippet: j['snippet'] as String?,
        score: _d(j['score']),
      );

  /// In-app route for this result (only `news` has a dedicated detail screen
  /// in this reference; everything else falls back to a CMS page lookup).
  String? get route {
    switch (entityType.toLowerCase()) {
      case 'news':
        return '/news/$entityId';
      default:
        return null;
    }
  }
}

// --- shared null-safe coercion helpers ---

String _s(dynamic v, {String fallback = ''}) =>
    v is String && v.isNotEmpty ? v : fallback;

/// Nullable string: a non-empty string, else null (so empty config values are
/// treated as absent).
String? _ns(dynamic v) => v is String && v.isNotEmpty ? v : null;

int _i(dynamic v, {int fallback = 0}) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

double _d(dynamic v, {double fallback = 0}) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

bool _b(dynamic v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is String) return v.toLowerCase() == 'true';
  if (v is num) return v != 0;
  return fallback;
}

DateTime? _date(dynamic v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}
