import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../shared/icon_map.dart';
import '../../shared/section_header.dart';

/// A lightweight, uniform card model so `publications` and `services` (and any
/// future list section) can share one horizontal-card renderer.
class _ListCard {
  const _ListCard({
    required this.title,
    this.subtitle,
    this.imageUrl,
    this.icon,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final IconData? icon;
  final VoidCallback? onTap;
}

/// `publications` and `services` home sections.
///
/// - publications → `GET /api/publications?pageSize=count` (config: `count`)
/// - services     → `GET /api/companies/services`          (no count filter)
///
/// Both render as a horizontal strip of cards; a "See all" header link opens
/// the corresponding full screen.
class GenericListSection extends StatefulWidget {
  const GenericListSection._({
    required this.section,
    required this.loader,
    required this.seeAllRoute,
    this.height = 200,
  });

  /// Publications variant.
  factory GenericListSection.publications({
    required HomeSection section,
    required ApiClient api,
  }) {
    return GenericListSection._(
      section: section,
      seeAllRoute: '/publications',
      loader: () async {
        final items = await api.publications(pageSize: section.count);
        return [
          for (final p in items)
            _ListCard(
              title: p.title,
              subtitle: p.summary,
              imageUrl: p.imageUrl,
              icon: Icons.menu_book,
            ),
        ];
      },
    );
  }

  /// Services variant (flattens the parent→children tree to top-level roots).
  factory GenericListSection.services({
    required HomeSection section,
    required ApiClient api,
  }) {
    return GenericListSection._(
      section: section,
      seeAllRoute: '/services',
      loader: () async {
        final items = await api.services();
        return [
          for (final s in items)
            _ListCard(
              title: s.name,
              subtitle: s.description,
              imageUrl: s.imageUrl ?? s.iconUrl,
              icon: iconFromName(null, fallback: Icons.design_services),
            ),
        ];
      },
    );
  }

  final HomeSection section;
  final Future<List<_ListCard>> Function() loader;
  final String seeAllRoute;
  final double height;

  @override
  State<GenericListSection> createState() => _GenericListSectionState();
}

class _GenericListSectionState extends State<GenericListSection> {
  late final Future<List<_ListCard>> _future = widget.loader();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: widget.section.title,
          onSeeAll: () => Navigator.pushNamed(context, widget.seeAllRoute),
        ),
        FutureBuilder<List<_ListCard>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return SectionStatus.loading(height: widget.height);
            }
            if (snap.hasError) {
              return SectionStatus.error(
                snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Failed to load',
              );
            }
            final cards = snap.data ?? const <_ListCard>[];
            if (cards.isEmpty) return const SizedBox.shrink();

            return SizedBox(
              height: widget.height,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: cards.length,
                itemBuilder: (context, i) => _Card(card: cards[i]),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.card});
  final _ListCard card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 160,
      child: Card(
        child: InkWell(
          onTap: card.onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: (card.imageUrl != null && card.imageUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: card.imageUrl!,
                        width: double.infinity,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.black12),
                        errorWidget: (_, __, ___) => Container(
                          color: scheme.primaryContainer,
                          child: Icon(card.icon ?? Icons.image),
                        ),
                      )
                    : Container(
                        width: double.infinity,
                        color: scheme.primaryContainer,
                        child: Icon(card.icon ?? Icons.article, size: 32),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  card.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
