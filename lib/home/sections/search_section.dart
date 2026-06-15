import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../shared/section_header.dart';

/// `search` section — a tappable search bar that opens the search screen.
///
/// Data source: none here; the search screen queries
/// `GET /api/search/semantic?q=` (with a keyword news-search fallback).
/// Config: `{}`.
class SearchSection extends StatelessWidget {
  const SearchSection({super.key, required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: InkWell(
            borderRadius: BorderRadius.circular(28),
            onTap: () => Navigator.pushNamed(context, '/search'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                children: [
                  Icon(Icons.search, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text(
                    isRtl ? 'ابحث...' : 'Search...',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
