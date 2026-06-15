import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../shared/section_header.dart';

/// `banner` section — a single static promotional image.
///
/// Data source: static (straight from the section config).
/// Config: `imageUrl`, `link?`.
class BannerSection extends StatelessWidget {
  const BannerSection({super.key, required this.section});

  final HomeSection section;

  Future<void> _open(String? link) async {
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final imageUrl = section.imageUrl;
    if (imageUrl == null || imageUrl.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: GestureDetector(
            onTap: () => _open(section.link),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CachedNetworkImage(
                imageUrl: imageUrl,
                width: double.infinity,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 120,
                  color: Colors.black12,
                ),
                errorWidget: (_, __, ___) => Container(
                  height: 120,
                  color: Colors.black12,
                  child: const Icon(Icons.broken_image),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
