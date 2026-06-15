import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/app_config.dart';
import '../core/models.dart';
import '../home/home_screen.dart';
import '../main.dart' show AppScope;
import '../shared/icon_map.dart';
import 'app_drawer.dart';

/// The app shell. Owns the chrome (AppBar + drawer and/or bottom-nav) and the
/// home feed, switching layout based on the baked `navigation.style`:
///
///   * `drawer`    → a navigation [Drawer] only (hamburger menu).
///   * `bottomnav` → a [BottomNavigationBar] built from the first menu items;
///                   no drawer.
///   * `both`      → drawer **and** bottom-nav.
///
/// It loads the menu + home layout **baked-first** (instant first paint from
/// `app_config.json`) then OTA-refreshes from the API, degrading back to the
/// baked data on any error. This is the single owner of that data; the home
/// feed and the bottom-nav both read it from here.
class MainScaffold extends StatefulWidget {
  const MainScaffold({super.key});

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  late ApiClient _api;
  late AppConfig _config;
  String _lang = '';

  /// Current menu + home, seeded from the baked config and replaced by the OTA
  /// refresh when it succeeds.
  List<MenuItem> _menu = const [];
  List<HomeSection> _sections = const [];

  /// Home-feed load state (drives the feed's loading/empty/error UI). The shell
  /// itself always renders so navigation is available even while loading.
  bool _loading = true;
  String? _error;

  /// Selected bottom-nav index (0 == Home). Other indices navigate to the
  /// corresponding menu item and snap back to Home — a classic hub pattern that
  /// reuses the existing full-screen routes without nesting Scaffolds.
  int _navIndex = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = AppScope.of(context);
    if (_lang.isEmpty || scope.lang != _lang) {
      _api = scope.api;
      _config = scope.config;
      _lang = scope.lang;
      _seedFromBaked();
      _refresh();
    }
  }

  /// Instant first paint: render whatever the build baked into app_config.json.
  void _seedFromBaked() {
    _menu = _localizedMenu(_config.bakedMenu);
    _sections = _config.bakedHome;
    // If the baked config carried sections we can show them immediately while
    // the network refresh runs; otherwise keep the spinner until it returns.
    _loading = _sections.isEmpty;
    _error = null;
  }

  /// Re-resolve baked menu titles for the active language.
  List<MenuItem> _localizedMenu(List<MenuItem> items) => [
        for (final m in items)
          MenuItem(
            moduleName: m.moduleName,
            title: m.localizedTitle(_lang),
            icon: m.icon,
            route: m.route,
            displayOrder: m.displayOrder,
            titleAr: m.titleAr,
            titleEn: m.titleEn,
          ),
      ];

  /// OTA refresh: pull the live menu + home for THIS app. A menu failure keeps
  /// the baked menu; a layout failure keeps the baked sections (or surfaces an
  /// error only when there were none to show).
  Future<void> _refresh() async {
    setState(() {
      _error = null;
      if (_sections.isEmpty) _loading = true;
    });

    final menuFuture = _api.menu().catchError((_) => _menu);
    List<HomeSection>? sections;
    Object? layoutError;
    try {
      sections = await _api.homeLayout();
    } catch (e) {
      layoutError = e;
    }
    final menu = await menuFuture;

    if (!mounted) return;

    // Resolve the next state outside setState so a local null-check isn't lost
    // across the closure boundary (Dart promotion rules).
    final nextMenu = menu.isNotEmpty ? menu : _menu;
    final List<HomeSection> nextSections;
    final bool failedWithNoData;
    if (sections != null) {
      nextSections = sections;
      failedWithNoData = false;
    } else {
      nextSections = _sections; // keep baked/previous sections on failure
      failedWithNoData = _sections.isEmpty;
    }
    final nextError = failedWithNoData
        ? (layoutError is ApiException
            ? layoutError.message
            : 'Something went wrong')
        : null;

    setState(() {
      _menu = nextMenu;
      _sections = nextSections;
      _loading = false;
      _error = nextError;
    });
  }

  /// Bottom-nav destinations: Home + the first menu items (capped so the bar
  /// stays usable). Home is always index 0.
  List<MenuItem> get _bottomItems {
    const maxTabs = 5; // Material guidance: 3–5 destinations.
    final extra = _menu.take(maxTabs - 1).toList();
    return [
      MenuItem(
        moduleName: 'home',
        title: _lang == 'en' ? 'Home' : 'الرئيسية',
        icon: 'home',
        route: '/',
        displayOrder: 0,
      ),
      ...extra,
    ];
  }

  String _langLabel(String lang) {
    switch (lang) {
      case 'ar':
        return 'العربية';
      case 'en':
        return 'English';
      default:
        return lang.toUpperCase();
    }
  }

  void _onNavTap(int index) {
    if (index == 0) {
      setState(() => _navIndex = 0);
      return;
    }
    final item = _bottomItems[index];
    final route = item.route;
    if (route != null && route.isNotEmpty && route != '/') {
      // Push the destination, then snap selection back to Home on return so the
      // bar reflects the currently-visible screen.
      Navigator.pushNamed(context, route).then((_) {
        if (mounted) setState(() => _navIndex = 0);
      });
      setState(() => _navIndex = index);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final nav = _config.navigation;
    final supported = _config.languages.supported;
    // When there's no drawer, the drawer's language switcher is unavailable, so
    // surface a compact language menu in the AppBar instead.
    final showLangAction = !nav.hasDrawer && supported.length > 1;

    return Scaffold(
      appBar: AppBar(
        title: _AppBarTitle(
          title: _config.titleFor(_lang),
          logoUrl: _config.branding.logoUrl,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: _lang == 'en' ? 'Search' : 'بحث',
            onPressed: () => Navigator.pushNamed(context, '/search'),
          ),
          if (showLangAction)
            PopupMenuButton<String>(
              icon: const Icon(Icons.language),
              tooltip: _lang == 'en' ? 'Language' : 'اللغة',
              onSelected: scope.setLanguage,
              itemBuilder: (context) => [
                for (final l in supported)
                  PopupMenuItem<String>(
                    value: l,
                    child: Text(_langLabel(l)),
                  ),
              ],
            ),
        ],
      ),
      drawer: nav.hasDrawer ? AppDrawer(items: _menu) : null,
      body: HomeFeed(
        api: _api,
        menu: _menu,
        sections: _sections,
        loading: _loading,
        error: _error,
        onRefresh: _refresh,
      ),
      bottomNavigationBar: nav.hasBottomNav && _bottomItems.length >= 2
          ? BottomNavigationBar(
              currentIndex: _navIndex.clamp(0, _bottomItems.length - 1),
              onTap: _onNavTap,
              type: BottomNavigationBarType.fixed,
              items: [
                for (final item in _bottomItems)
                  BottomNavigationBarItem(
                    icon: Icon(iconFromName(item.icon)),
                    label: item.title,
                  ),
              ],
            )
          : null,
    );
  }
}

class _AppBarTitle extends StatelessWidget {
  const _AppBarTitle({required this.title, required this.logoUrl});

  final String title;
  final String logoUrl;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (logoUrl.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedNetworkImage(
              imageUrl: logoUrl,
              width: 28,
              height: 28,
              fit: BoxFit.cover,
              errorWidget: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 8),
        ],
        Flexible(
          child: Text(title, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}
