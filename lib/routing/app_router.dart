import 'package:flutter/material.dart';

import '../screens/faq_screen.dart';
import '../screens/gallery_screen.dart';
import '../screens/news_detail_screen.dart';
import '../screens/news_screen.dart';
import '../screens/page_screen.dart';
import '../screens/placeholder_screen.dart';
import '../screens/publications_screen.dart';
import '../screens/search_screen.dart';
import '../screens/services_screen.dart';
import '../screens/speeches_screen.dart';
import '../screens/webview_screen.dart';

/// Central route table for the CMS-driven menu.
///
/// The menu's `route` values (e.g. "/news", "/publications", "/page/about")
/// flow straight into [Navigator.pushNamed]; this resolves them to screens.
/// Anything unrecognized degrades to a [PageScreen] (CMS page lookup by key)
/// or a friendly [PlaceholderScreen], so a webmaster adding a new module never
/// produces a dead end.
class AppRouter {
  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    final uri = Uri.parse(settings.name ?? '/');
    final segments = uri.pathSegments;
    final first = segments.isNotEmpty ? segments.first : '';

    Widget page;
    switch (first) {
      case '':
      case 'home':
        // Home is provided directly by MaterialApp.home (MainScaffold); pop
        // back to it rather than pushing a second copy.
        page = const PlaceholderScreen(title: 'Home');
        break;

      case 'news':
      case 'events':
        // /news  or  /news?categoryId=33  or  /news/{id}  (events == news)
        if (segments.length >= 2) {
          final id = int.tryParse(segments[1]);
          page = id != null
              ? NewsDetailScreen(newsId: id)
              : const PlaceholderScreen(title: 'News');
        } else {
          final categoryId = int.tryParse(uri.queryParameters['categoryId'] ?? '');
          page = NewsScreen(categoryId: categoryId);
        }
        break;

      case 'publications':
        page = const PublicationsScreen();
        break;

      case 'services':
        page = const ServicesScreen();
        break;

      case 'gallery':
        page = const GalleryScreen();
        break;

      case 'speeches':
      case 'videos':
        page = const SpeechesScreen();
        break;

      case 'faq':
        page = const FaqScreen();
        break;

      case 'search':
        page = const SearchScreen();
        break;

      case 'contact':
        // Contact is a CMS-managed page; render it by a conventional key.
        page = const PageScreen(pageKey: 'contact', title: 'Contact');
        break;

      case 'page':
      case 'about':
        // /page/{key}  or  /about/{key}
        final key = segments.length >= 2 ? segments[1] : '';
        page = key.isEmpty
            ? const PlaceholderScreen(title: 'Page')
            : PageScreen(pageKey: key);
        break;

      case 'webview':
        // /webview?url=...
        final url = uri.queryParameters['url'] ?? '';
        page = url.isEmpty
            ? const PlaceholderScreen(title: 'Web')
            : WebViewScreen(url: url);
        break;

      default:
        // Unknown module route → try it as a CMS page key, then placeholder.
        page = PageScreen(pageKey: first, title: _titleCase(first));
        break;
    }

    return MaterialPageRoute(builder: (_) => page, settings: settings);
  }

  static String _titleCase(String s) =>
      s.isEmpty ? '' : s[0].toUpperCase() + s.substring(1);
}
