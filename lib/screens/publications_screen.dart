import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../main.dart' show AppScope;

/// Publications list. Source: `GET /api/publications?pageSize=`.
/// Tapping a publication with a `fileUrl` opens it externally (PDF, etc.).
class PublicationsScreen extends StatefulWidget {
  const PublicationsScreen({super.key});

  @override
  State<PublicationsScreen> createState() => _PublicationsScreenState();
}

class _PublicationsScreenState extends State<PublicationsScreen> {
  ApiClient? _api;
  Future<List<Publication>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= AppScope.of(context).api;
    _future ??= _api!.publications(pageSize: 30);
  }

  Future<void> _refresh() async {
    final f = _api!.publications(pageSize: 30);
    setState(() => _future = f);
    await f;
  }

  Future<void> _open(String? fileUrl) async {
    if (fileUrl == null || fileUrl.isEmpty) return;
    final uri = Uri.tryParse(fileUrl);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    return Scaffold(
      appBar: AppBar(title: Text(lang == 'en' ? 'Publications' : 'الإصدارات')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<Publication>>(
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
            final items = snap.data ?? const <Publication>[];
            if (items.isEmpty) {
              return _Centered(
                child: Text(lang == 'en' ? 'No publications' : 'لا توجد إصدارات'),
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final p = items[i];
                return Card(
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: SizedBox(
                        width: 48,
                        height: 60,
                        child: (p.imageUrl != null && p.imageUrl!.isNotEmpty)
                            ? CachedNetworkImage(
                                imageUrl: p.imageUrl!,
                                fit: BoxFit.cover,
                                errorWidget: (_, __, ___) => const Icon(Icons.menu_book),
                              )
                            : Container(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                child: const Icon(Icons.menu_book),
                              ),
                      ),
                    ),
                    title: Text(p.title, maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: (p.summary != null && p.summary!.isNotEmpty)
                        ? Text(p.summary!, maxLines: 2, overflow: TextOverflow.ellipsis)
                        : null,
                    trailing: (p.fileUrl != null && p.fileUrl!.isNotEmpty)
                        ? const Icon(Icons.download)
                        : null,
                    onTap: () => _open(p.fileUrl),
                  ),
                );
              },
            );
          },
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
