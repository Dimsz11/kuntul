import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../main.dart' show AppScope;
import '../shared/format.dart';

/// Speeches / videos list. Source: `GET /api/speeches?pageSize=`. Each row shows
/// a thumbnail with a play overlay (speeches double as the video library).
class SpeechesScreen extends StatefulWidget {
  const SpeechesScreen({super.key});

  @override
  State<SpeechesScreen> createState() => _SpeechesScreenState();
}

class _SpeechesScreenState extends State<SpeechesScreen> {
  ApiClient? _api;
  Future<List<SpeechItem>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= AppScope.of(context).api;
    _future ??= _api!.videos(pageSize: 50);
  }

  Future<void> _refresh() async {
    final f = _api!.videos(pageSize: 50);
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    return Scaffold(
      appBar: AppBar(title: Text(lang == 'en' ? 'Videos' : 'كلمات ومرئيات')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<SpeechItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Centered(
                child: Text(snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Failed to load'),
              );
            }
            final items = snap.data ?? const <SpeechItem>[];
            if (items.isEmpty) {
              return _Centered(
                child: Text(lang == 'en' ? 'No videos' : 'لا توجد مرئيات'),
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              itemBuilder: (context, i) =>
                  _SpeechTile(item: items[i], lang: lang),
            );
          },
        ),
      ),
    );
  }
}

class _SpeechTile extends StatelessWidget {
  const _SpeechTile({required this.item, required this.lang});

  final SpeechItem item;
  final String lang;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 120,
                height: 72,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.black12),
                      )
                    else
                      Container(color: scheme.primaryContainer),
                    const Center(
                      child: Icon(Icons.play_circle_fill,
                          color: Colors.white70, size: 30),
                    ),
                  ],
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (item.eventDate != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      formatDate(item.eventDate!, lang),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(child: child),
        ),
      ],
    );
  }
}
