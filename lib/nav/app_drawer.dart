import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/models.dart';
import '../main.dart' show AppScope;
import '../shared/icon_map.dart';

/// Navigation drawer built from `GET /api/mobile/menu`. The menu items are
/// passed in (the home screen already fetched them), keeping the drawer a pure
/// renderer. Tapping an item closes the drawer and pushes its `route`.
class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.items});

  final List<MenuItem> items;

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final config = scope.config;
    final theme = Theme.of(context);

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            _Header(
              title: config.titleFor(scope.lang),
              logoUrl: config.branding.logoUrl,
              background: theme.colorScheme.primary,
              onBackground: theme.colorScheme.onPrimary,
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Always offer Home first (returns to the CMS-driven home).
                  ListTile(
                    leading: const Icon(Icons.home),
                    title: Text(_homeLabel(scope.lang)),
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.popUntil(context, (r) => r.isFirst);
                    },
                  ),
                  for (final item in items)
                    ListTile(
                      leading: Icon(iconFromName(item.icon)),
                      title: Text(item.title),
                      onTap: () {
                        Navigator.pop(context);
                        final route = item.route;
                        if (route != null && route.isNotEmpty) {
                          Navigator.pushNamed(context, route);
                        }
                      },
                    ),
                ],
              ),
            ),
            const Divider(height: 1),
            _LanguageSwitcher(
              current: scope.lang,
              supported: config.languages.supported,
              onSelected: scope.setLanguage,
            ),
          ],
        ),
      ),
    );
  }

  String _homeLabel(String lang) => lang == 'en' ? 'Home' : 'الرئيسية';
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.logoUrl,
    required this.background,
    required this.onBackground,
  });

  final String title;
  final String logoUrl;
  final Color background;
  final Color onBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: background,
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (logoUrl.isNotEmpty)
            CircleAvatar(
              radius: 28,
              backgroundColor: onBackground.withOpacity(0.15),
              child: ClipOval(
                child: CachedNetworkImage(
                  imageUrl: logoUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Icon(Icons.apps, color: onBackground),
                ),
              ),
            )
          else
            Icon(Icons.apps, size: 40, color: onBackground),
          const SizedBox(height: 12),
          Text(
            title,
            style: TextStyle(
              color: onBackground,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _LanguageSwitcher extends StatelessWidget {
  const _LanguageSwitcher({
    required this.current,
    required this.supported,
    required this.onSelected,
  });

  final String current;
  final List<String> supported;
  final void Function(String) onSelected;

  @override
  Widget build(BuildContext context) {
    if (supported.length < 2) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        children: [
          for (final lang in supported)
            ChoiceChip(
              label: Text(_label(lang)),
              selected: lang == current,
              onSelected: (_) => onSelected(lang),
            ),
        ],
      ),
    );
  }

  String _label(String lang) {
    switch (lang) {
      case 'ar':
        return 'العربية';
      case 'en':
        return 'English';
      default:
        return lang.toUpperCase();
    }
  }
}
