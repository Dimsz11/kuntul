import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../main.dart' show AppScope;
import 'news_detail_screen.dart';

/// Search screen. Queries `GET /api/search/semantic?q=` (vector search); if that
/// fails (e.g. embeddings not configured) it falls back to a keyword news
/// search (`GET /api/news?search=`). Results route to a news detail when the
/// hit is a news item; otherwise they're shown inline.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _controller = TextEditingController();
  ApiClient? _api;

  Future<List<SearchResultItem>>? _future;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= AppScope.of(context).api;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final q = value.trim();
    if (q.isEmpty) return;
    setState(() {
      _query = q;
      _future = _runSearch(q);
    });
  }

  /// Semantic search first; on error, keyword news search mapped into the same
  /// result shape so the UI stays uniform.
  Future<List<SearchResultItem>> _runSearch(String q) async {
    try {
      return await _api!.search(q);
    } catch (_) {
      final news = await _api!.newsSearch(q);
      return [
        for (final n in news)
          SearchResultItem(
            entityType: 'news',
            entityId: n.id,
            title: n.title,
            snippet: n.summary,
            score: 0,
          ),
      ];
    }
  }

  void _openResult(SearchResultItem r) {
    if (r.entityType.toLowerCase() == 'news') {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => NewsDetailScreen(newsId: r.entityId)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    final isRtl = lang != 'en';
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onSubmitted: _submit,
          decoration: InputDecoration(
            border: InputBorder.none,
            hintText: isRtl ? 'ابحث...' : 'Search...',
            hintStyle: TextStyle(
              color: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
            ),
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
          cursorColor: Theme.of(context).colorScheme.onPrimary,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () => _submit(_controller.text),
          ),
        ],
      ),
      body: _future == null
          ? _Hint(text: isRtl ? 'ابدأ بالبحث' : 'Start typing to search')
          : FutureBuilder<List<SearchResultItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return _Hint(
                    text: snap.error is ApiException
                        ? (snap.error as ApiException).message
                        : (isRtl ? 'فشل البحث' : 'Search failed'),
                  );
                }
                final results = snap.data ?? const <SearchResultItem>[];
                if (results.isEmpty) {
                  return _Hint(
                    text: isRtl
                        ? 'لا توجد نتائج لـ "$_query"'
                        : 'No results for "$_query"',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(8),
                  itemCount: results.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final r = results[i];
                    final tappable = r.entityType.toLowerCase() == 'news';
                    return ListTile(
                      leading: const Icon(Icons.article_outlined),
                      title: Text(r.title,
                          maxLines: 2, overflow: TextOverflow.ellipsis),
                      subtitle: (r.snippet != null && r.snippet!.isNotEmpty)
                          ? Text(r.snippet!,
                              maxLines: 2, overflow: TextOverflow.ellipsis)
                          : null,
                      trailing: tappable
                          ? const Icon(Icons.chevron_right)
                          : Text(r.entityType,
                              style: Theme.of(context).textTheme.labelSmall),
                      onTap: tappable ? () => _openResult(r) : null,
                    );
                  },
                );
              },
            ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium),
      ),
    );
  }
}
