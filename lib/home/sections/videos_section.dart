import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../shared/section_header.dart';

/// `videos` section — a horizontal strip of video/speech thumbnails with a
/// play affordance.
///
/// Data source: `GET /api/speeches?pageSize=count` (speeches double as the
/// video library in this CMS). Config: `count`. Tapping opens the speeches
/// list screen.
class VideosSection extends StatefulWidget {
  const VideosSection({super.key, required this.section, required this.api});

  final HomeSection section;
  final ApiClient api;

  @override
  State<VideosSection> createState() => _VideosSectionState();
}

class _VideosSectionState extends State<VideosSection> {
  late final Future<List<SpeechItem>> _future =
      widget.api.videos(pageSize: widget.section.count);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: widget.section.title,
          onSeeAll: () => Navigator.pushNamed(context, '/speeches'),
        ),
        FutureBuilder<List<SpeechItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SectionStatus.loading(height: 170);
            }
            if (snap.hasError) {
              return SectionStatus.error(
                snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Failed to load videos',
              );
            }
            final items = snap.data ?? const <SpeechItem>[];
            if (items.isEmpty) return const SizedBox.shrink();

            return SizedBox(
              height: 170,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                itemCount: items.length,
                itemBuilder: (context, i) => _VideoTile(item: items[i]),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.item});
  final SpeechItem item;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 220,
      child: Card(
        child: InkWell(
          onTap: () => Navigator.pushNamed(context, '/speeches'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (item.imageUrl != null && item.imageUrl!.isNotEmpty)
                      CachedNetworkImage(
                        imageUrl: item.imageUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => Container(color: Colors.black12),
                        errorWidget: (_, __, ___) =>
                            Container(color: Colors.black12),
                      )
                    else
                      Container(color: scheme.primaryContainer),
                    const Center(
                      child: Icon(Icons.play_circle_fill,
                          size: 40, color: Colors.white70),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  item.title,
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
