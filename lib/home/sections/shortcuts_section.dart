import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../shared/icon_map.dart';
import '../../shared/section_header.dart';

/// `shortcuts` section — an icon grid of quick links.
///
/// Data source: the matching items from `GET /api/mobile/menu` (already loaded
/// by the home screen and passed in here).
/// Config: `moduleNames[]` — which menu modules to surface, in that order.
class ShortcutsSection extends StatelessWidget {
  const ShortcutsSection({
    super.key,
    required this.section,
    required this.menu,
  });

  final HomeSection section;
  final List<MenuItem> menu;

  /// Resolve the requested module names against the menu, preserving the order
  /// given in `moduleNames`. Names with no matching menu item are dropped.
  List<MenuItem> get _shortcuts {
    final wanted = section.moduleNames;
    if (wanted.isEmpty) return const [];
    final byModule = {for (final m in menu) m.moduleName: m};
    return [
      for (final name in wanted)
        if (byModule[name] != null) byModule[name]!,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = _shortcuts;
    if (shortcuts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.title),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 0.85,
          children: [
            for (final item in shortcuts)
              _Shortcut(
                item: item,
                onTap: () {
                  final route = item.route;
                  if (route != null && route.isNotEmpty) {
                    Navigator.pushNamed(context, route);
                  }
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({required this.item, required this.onTap});

  final MenuItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(iconFromName(item.icon), color: scheme.onPrimaryContainer),
          ),
          const SizedBox(height: 6),
          Text(
            item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
