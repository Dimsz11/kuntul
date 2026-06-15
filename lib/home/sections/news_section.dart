import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../screens/news_detail_screen.dart';
import '../../shared/section_header.dart';

/// `news` section — a horizontal strip of latest-news cards.
///
/// Data source: `GET /api/news?categoryId=&pageSize=count`.
/// Config: `categoryId?`, `count`.
class NewsSection extends StatefulWidget {
  const NewsSection({super.key, required this.section, required this.api});

  final HomeSection section;
  final ApiClient api;

  @override
  State<NewsSection> createState() => _NewsSectionState();
}

class _NewsSectionState extends State<NewsSection> {
  late final Future<List<NewsItem>> _future = widget.api.news(
    categoryId: widget.section.categoryId,
    pageSize: widget.section.count,
  );

  void _openDetail(int id) => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NewsDetailScreen(newsId: id)),
      );

  void _openCategory() {
    final route = StringBuffer('/news');
    if (widget.section.categoryId != null) {
      route.write('?categoryId=${widget.section.categoryId}');
    }
    Navigator.pushNamed(context, route.toString());
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: widget.section.title, onSeeAll: _openCategory),
        FutureBuilder<List<NewsItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SectionStatus.loading(height: 220);
            }
            if (snap.hasError) {
              return SectionStatus.error(
                snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Failed to load news',
              );
            }
            final items = snap.data ?? const <NewsItem>[];
            if (items.isEmpty) return const SizedBox.shrink();

            return SizedBox(
              height: 220,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: items.length,
                itemBuilder: (context, i) => _NewsCard(
                  item: items[i],
                  onTap: () => _openDetail(items[i].id),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _NewsCard extends StatelessWidget {
  const _NewsCard({required this.item, required this.onTap});

  final NewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 240,
      child: Card(
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                    ? CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.black12),
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.black12, child: const Icon(Icons.image)),
                      )
                    : Container(
                        color: Theme.of(context).colorScheme.primaryContainer,
                        child: const Icon(Icons.newspaper, size: 32),
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (item.categoryName != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        item.categoryName!,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
