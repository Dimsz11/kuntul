import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../main.dart' show AppScope;
import '../../screens/news_detail_screen.dart';
import '../../shared/section_header.dart';

/// `hero` section — a single large featured banner.
///
/// Two modes (config-driven):
///   * `newsId` set → resolve `GET /api/news/{id}` and feature that article
///     (tap opens its detail screen).
///   * otherwise → a static hero from `imageUrl` / `title` / `link`.
class HeroSection extends StatefulWidget {
  const HeroSection({super.key, required this.section, required this.api});

  final HomeSection section;
  final ApiClient api;

  @override
  State<HeroSection> createState() => _HeroSectionState();
}

class _HeroSectionState extends State<HeroSection> {
  Future<NewsDetail>? _newsFuture;

  @override
  void initState() {
    super.initState();
    final id = widget.section.newsId;
    if (id != null) _newsFuture = widget.api.newsById(id);
  }

  Future<void> _openLink(String? link) async {
    if (link == null || link.isEmpty) return;
    final uri = Uri.tryParse(link);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.section;

    // Static hero (no newsId).
    if (_newsFuture == null) {
      final img = s.imageUrl;
      if ((img == null || img.isEmpty) &&
          (s.title == null || s.title!.isEmpty)) {
        return const SizedBox.shrink();
      }
      return _HeroCard(
        imageUrl: img,
        title: s.title,
        onTap: () => _openLink(s.link),
      );
    }

    // News-backed hero.
    final lang = AppScope.of(context).lang;
    return FutureBuilder<NewsDetail>(
      future: _newsFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SectionStatus.loading(height: 200);
        }
        if (!snap.hasData) return const SizedBox.shrink();
        final detail = snap.data!;
        final title = detail.translationFor(lang)?.title ?? s.title;
        return _HeroCard(
          imageUrl: detail.imageUrl ?? s.imageUrl,
          title: title,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => NewsDetailScreen(newsId: detail.id),
            ),
          ),
        );
      },
    );
  }
}

class _HeroCard extends StatelessWidget {
  const _HeroCard({this.imageUrl, this.title, this.onTap});

  final String? imageUrl;
  final String? title;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 200,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (imageUrl != null && imageUrl!.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: imageUrl!,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: Colors.black12),
                    errorWidget: (_, __, ___) =>
                        Container(color: scheme.primaryContainer),
                  )
                else
                  Container(color: scheme.primaryContainer),
                if (title != null && title!.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Colors.black87, Colors.transparent],
                        ),
                      ),
                      child: Text(
                        title!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
