import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../main.dart' show AppScope;
import 'news_detail_screen.dart';

/// Full news list, optionally filtered by [categoryId].
/// Source: `GET /api/news?categoryId=&pageSize=`.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key, this.categoryId});

  final int? categoryId;

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  ApiClient? _api;
  Future<List<NewsItem>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= AppScope.of(context).api;
    _future ??= _api!.news(categoryId: widget.categoryId, pageSize: 30);
  }

  Future<void> _refresh() async {
    final f = _api!.news(categoryId: widget.categoryId, pageSize: 30);
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    return Scaffold(
      appBar: AppBar(title: Text(lang == 'en' ? 'News' : 'الأخبار')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<NewsItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Message(
                text: snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Failed to load news',
              );
            }
            final items = snap.data ?? const <NewsItem>[];
            if (items.isEmpty) {
              return _Message(text: lang == 'en' ? 'No news' : 'لا توجد أخبار');
            }
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 4),
              itemBuilder: (context, i) => _NewsTile(
                item: items[i],
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NewsDetailScreen(newsId: items[i].id),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NewsTile extends StatelessWidget {
  const _NewsTile({required this.item, required this.onTap});

  final NewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 96,
                  height: 72,
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
                          child: const Icon(Icons.newspaper),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    if (item.summary != null && item.summary!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.summary!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
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

class _Message extends StatelessWidget {
  const _Message({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    // Scrollable so pull-to-refresh still works on empty/error.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(child: Text(text)),
        ),
      ],
    );
  }
}
