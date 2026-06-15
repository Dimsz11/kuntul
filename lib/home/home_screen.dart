import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import 'sections/about_section.dart';
import 'sections/announcements_section.dart';
import 'sections/banner_section.dart';
import 'sections/categories_section.dart';
import 'sections/contact_section.dart';
import 'sections/faq_section.dart';
import 'sections/gallery_section.dart';
import 'sections/generic_list_section.dart';
import 'sections/hero_section.dart';
import 'sections/html_section.dart';
import 'sections/news_section.dart';
import 'sections/search_section.dart';
import 'sections/shortcuts_section.dart';
import 'sections/slider_section.dart';
import 'sections/social_links_section.dart';
import 'sections/spacer_section.dart';
import 'sections/videos_section.dart';
import 'sections/webview_section.dart';

/// CMS-driven home feed. **Presentational only** — it receives the already
/// loaded menu + sections (and load state) from the owning [MainScaffold] and
/// renders each section top-to-bottom. Keeping the feed stateless of fetching
/// lets the shell own the single source of truth (baked-first, then OTA), and
/// lets the bottom-nav and drawer share the same menu.
class HomeFeed extends StatelessWidget {
  const HomeFeed({
    super.key,
    required this.api,
    required this.menu,
    required this.sections,
    required this.loading,
    required this.error,
    required this.onRefresh,
  });

  final ApiClient api;
  final List<MenuItem> menu;
  final List<HomeSection> sections;
  final bool loading;
  final String? error;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (error != null && sections.isEmpty) {
      return _ErrorState(message: error!, onRetry: onRefresh);
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: sections.isEmpty
          ? _EmptyState(onRetry: onRefresh)
          : ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: sections.length,
              itemBuilder: (context, i) => sectionFor(
                sections[i],
                api: api,
                menu: menu,
              ),
            ),
    );
  }
}

/// Factory: map a [HomeSection] to its widget by `type` (README §7.2).
///
/// Handles all 20 contract types. Type names MUST match the backend exactly:
///   slider | news | shortcuts | banner | publications | services | webview |
///   spacer | announcements | gallery | videos | events | faq | contact |
///   sociallinks | search | html | hero | categories | about
/// Any unrecognized type renders nothing (graceful skip) so the CMS can add new
/// section types without breaking older app builds.
Widget sectionFor(
  HomeSection section, {
  required ApiClient api,
  required List<MenuItem> menu,
}) {
  switch (section.type) {
    // --- original 8 ---
    case 'slider':
      return SliderSection(section: section, api: api);
    case 'news':
      return NewsSection(section: section, api: api);
    case 'shortcuts':
      return ShortcutsSection(section: section, menu: menu);
    case 'banner':
      return BannerSection(section: section);
    case 'publications':
      return GenericListSection.publications(section: section, api: api);
    case 'services':
      return GenericListSection.services(section: section, api: api);
    case 'webview':
      return WebViewSection(section: section);
    case 'spacer':
      return SpacerSection(section: section);

    // --- added 12 ---
    case 'announcements':
      return AnnouncementsSection(section: section, api: api);
    case 'gallery':
      return GallerySection(section: section, api: api);
    case 'videos':
      return VideosSection(section: section, api: api);
    case 'events':
      // Events are news filtered to an event category — same renderer as news.
      return NewsSection(section: section, api: api);
    case 'faq':
      return FaqSection(section: section, api: api);
    case 'contact':
      return ContactSection(section: section, api: api);
    case 'sociallinks':
      return SocialLinksSection(section: section, api: api);
    case 'search':
      return SearchSection(section: section);
    case 'html':
      return HtmlSection(section: section);
    case 'hero':
      return HeroSection(section: section, api: api);
    case 'categories':
      return CategoriesSection(section: section, api: api);
    case 'about':
      return AboutSection(section: section, api: api);

    default:
      // Unknown type → skip gracefully (keep the loop tolerant).
      return const SizedBox.shrink();
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    // Must be scrollable so RefreshIndicator works even when empty.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.layers_clear, size: 48, color: Colors.grey),
                const SizedBox(height: 12),
                Text(isRtl
                    ? 'لا توجد أقسام في الصفحة الرئيسية'
                    : 'No home sections configured'),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: onRetry,
                  child: Text(isRtl ? 'تحديث' : 'Refresh'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onRetry,
              child: Text(isRtl ? 'إعادة المحاولة' : 'Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
