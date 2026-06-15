import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../shared/section_header.dart';

/// `announcements` section — a vertical list of the latest announcements.
///
/// Data source: `GET /api/announcements?pageSize=count`.
/// Config: `count`. Tapping an announcement with a `linkUrl` opens it.
class AnnouncementsSection extends StatefulWidget {
  const AnnouncementsSection({
    super.key,
    required this.section,
    required this.api,
  });

  final HomeSection section;
  final ApiClient api;

  @override
  State<AnnouncementsSection> createState() => _AnnouncementsSectionState();
}

class _AnnouncementsSectionState extends State<AnnouncementsSection> {
  late final Future<List<AnnouncementItem>> _future =
      widget.api.announcements(pageSize: widget.section.count);

  Future<void> _open(String? link) async {
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: widget.section.title),
        FutureBuilder<List<AnnouncementItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SectionStatus.loading(height: 120);
            }
            if (snap.hasError) {
              return SectionStatus.error(
                snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Failed to load announcements',
              );
            }
            final items = snap.data ?? const <AnnouncementItem>[];
            if (items.isEmpty) return const SizedBox.shrink();

            return Column(
              children: [
                for (final a in items)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Card(
                      child: ListTile(
                        leading: (a.imageUrl != null && a.imageUrl!.isNotEmpty)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: CachedNetworkImage(
                                  imageUrl: a.imageUrl!,
                                  width: 48,
                                  height: 48,
                                  fit: BoxFit.cover,
                                  errorWidget: (_, __, ___) =>
                                      const Icon(Icons.campaign),
                                ),
                              )
                            : const Icon(Icons.campaign),
                        title: Text(a.title,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle:
                            (a.description != null && a.description!.isNotEmpty)
                                ? Text(a.description!,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis)
                                : null,
                        trailing: (a.linkUrl != null && a.linkUrl!.isNotEmpty)
                            ? const Icon(Icons.open_in_new, size: 18)
                            : null,
                        onTap: (a.linkUrl != null && a.linkUrl!.isNotEmpty)
                            ? () => _open(a.linkUrl)
                            : null,
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}
