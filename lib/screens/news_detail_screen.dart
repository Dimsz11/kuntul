import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../main.dart' show AppScope;
import '../shared/format.dart';
import '../shared/html_text.dart';

/// Single news article. Source: `GET /api/news/{id}`.
/// Picks the translation for the active language (falls back to first).
class NewsDetailScreen extends StatefulWidget {
  const NewsDetailScreen({super.key, required this.newsId});

  final int newsId;

  @override
  State<NewsDetailScreen> createState() => _NewsDetailScreenState();
}

class _NewsDetailScreenState extends State<NewsDetailScreen> {
  ApiClient? _api;
  Future<NewsDetail>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= AppScope.of(context).api;
    _future ??= _api!.newsById(widget.newsId);
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    return Scaffold(
      body: FutureBuilder<NewsDetail>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const _LoadingScaffoldBody();
          }
          if (snap.hasError || !snap.hasData) {
            return _ErrorBody(
              message: snap.error is ApiException
                  ? (snap.error as ApiException).message
                  : 'Failed to load article',
              onBack: () => Navigator.maybePop(context),
            );
          }

          final detail = snap.data!;
          final tr = detail.translationFor(lang);
          final title = tr?.title ?? '';
          final hero = detail.imageUrl;

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: (hero != null && hero.isNotEmpty) ? 220 : kToolbarHeight,
                pinned: true,
                flexibleSpace: (hero != null && hero.isNotEmpty)
                    ? FlexibleSpaceBar(
                        background: CachedNetworkImage(
                          imageUrl: hero,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => const ColoredBox(color: Colors.black12),
                        ),
                      )
                    : null,
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .headlineSmall
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (detail.publishDate != null) ...[
                            const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                            const SizedBox(width: 4),
                            Text(
                              formatDate(detail.publishDate!, lang),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(width: 16),
                          ],
                          const Icon(Icons.remove_red_eye, size: 14, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('${detail.viewCount}',
                              style: Theme.of(context).textTheme.bodySmall),
                        ],
                      ),
                      const Divider(height: 24),
                      if (tr?.summary != null && tr!.summary!.isNotEmpty) ...[
                        Text(
                          tr.summary!,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 12),
                      ],
                      HtmlText(tr?.content),
                      const SizedBox(height: 16),
                      ...detail.images.map(
                        (url) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: CachedNetworkImage(imageUrl: url, fit: BoxFit.cover),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoadingScaffoldBody extends StatelessWidget {
  const _LoadingScaffoldBody();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(),
        const Expanded(child: Center(child: CircularProgressIndicator())),
      ],
    );
  }
}

class _ErrorBody extends StatelessWidget {
  const _ErrorBody({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AppBar(),
        Expanded(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 40, color: Colors.grey),
                const SizedBox(height: 12),
                Text(message),
                const SizedBox(height: 12),
                OutlinedButton(onPressed: onBack, child: const Text('Back')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
