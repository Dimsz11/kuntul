import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../main.dart' show AppScope;

/// Photo-album gallery. Source: `GET /api/gallery?pageSize=`. Albums render in a
/// two-column grid of cover tiles.
class GalleryScreen extends StatefulWidget {
  const GalleryScreen({super.key});

  @override
  State<GalleryScreen> createState() => _GalleryScreenState();
}

class _GalleryScreenState extends State<GalleryScreen> {
  ApiClient? _api;
  Future<List<AlbumItem>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= AppScope.of(context).api;
    _future ??= _api!.galleryAlbums(pageSize: 50);
  }

  Future<void> _refresh() async {
    final f = _api!.galleryAlbums(pageSize: 50);
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    return Scaffold(
      appBar: AppBar(title: Text(lang == 'en' ? 'Gallery' : 'معرض الصور')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<AlbumItem>>(
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
            final items = snap.data ?? const <AlbumItem>[];
            if (items.isEmpty) {
              return _Centered(
                child: Text(lang == 'en' ? 'No albums' : 'لا توجد ألبومات'),
              );
            }
            return GridView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) => _AlbumCard(album: items[i]),
            );
          },
        ),
      ),
    );
  }
}

class _AlbumCard extends StatelessWidget {
  const _AlbumCard({required this.album});
  final AlbumItem album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: (album.imageUrl != null && album.imageUrl!.isNotEmpty)
                ? CachedNetworkImage(
                    imageUrl: album.imageUrl!,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.black12),
                    errorWidget: (_, __, ___) => Container(
                      color: scheme.primaryContainer,
                      child: const Icon(Icons.photo_library),
                    ),
                  )
                : Container(
                    width: double.infinity,
                    color: scheme.primaryContainer,
                    child: const Icon(Icons.photo_library, size: 32),
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Text(
              album.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
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
