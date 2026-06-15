import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../shared/section_header.dart';

/// `gallery` section — a horizontal strip of photo-album cover tiles.
///
/// Data source: `GET /api/gallery?pageSize=count` (photo albums).
/// Config: `count`. Tapping an album opens the full gallery screen.
class GallerySection extends StatefulWidget {
  const GallerySection({super.key, required this.section, required this.api});

  final HomeSection section;
  final ApiClient api;

  @override
  State<GallerySection> createState() => _GallerySectionState();
}

class _GallerySectionState extends State<GallerySection> {
  late final Future<List<AlbumItem>> _future =
      widget.api.galleryAlbums(pageSize: widget.section.count);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: widget.section.title,
          onSeeAll: () => Navigator.pushNamed(context, '/gallery'),
        ),
        FutureBuilder<List<AlbumItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SectionStatus.loading(height: 160);
            }
            if (snap.hasError) {
              return SectionStatus.error(
                snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Failed to load gallery',
              );
            }
            final items = snap.data ?? const <AlbumItem>[];
            if (items.isEmpty) return const SizedBox.shrink();

            return SizedBox(
              height: 160,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: items.length,
                itemBuilder: (context, i) => _AlbumTile(album: items[i]),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _AlbumTile extends StatelessWidget {
  const _AlbumTile({required this.album});
  final AlbumItem album;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 180,
      child: Card(
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, '/gallery'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (album.imageUrl != null && album.imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: album.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.black12),
                        errorWidget: (_, __, ___) => Container(
                          color: scheme.primaryContainer,
                          child: const Icon(Icons.photo_library),
                        ),
                      )
                    else
                      Container(
                        color: scheme.primaryContainer,
                        child: const Icon(Icons.photo_library, size: 32),
                      ),
                    const Positioned(
                      top: 6,
                      right: 6,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.black45,
                        child: Icon(Icons.photo_library,
                            size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  album.title,
                  maxLines: 1,
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
