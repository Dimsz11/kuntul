import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../shared/section_header.dart';

/// `sociallinks` section — a centered row of tappable social-media icons.
///
/// Data source: `GET /api/links/by-group-key/{linkGroupKey}`.
/// Config: `linkGroupKey` (required). Each link's title is matched to a brand
/// icon; tapping opens the URL in the browser / native app.
class SocialLinksSection extends StatefulWidget {
  const SocialLinksSection({
    super.key,
    required this.section,
    required this.api,
  });

  final HomeSection section;
  final ApiClient api;

  @override
  State<SocialLinksSection> createState() => _SocialLinksSectionState();
}

class _SocialLinksSectionState extends State<SocialLinksSection> {
  late final Future<List<LinkItem>> _future = _load();

  Future<List<LinkItem>> _load() {
    final key = widget.section.linkGroupKey;
    if (key == null || key.isEmpty) return Future.value(const <LinkItem>[]);
    return widget.api.linksByGroup(key);
  }

  Future<void> _open(String url) async {
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// Best-effort brand icon from the link title/url (Material has no brand
  /// glyphs, so these are sensible stand-ins).
  IconData _iconFor(LinkItem link) {
    final hay = '${link.title} ${link.url}'.toLowerCase();
    if (hay.contains('facebook') || hay.contains('fb.')) return Icons.facebook;
    if (hay.contains('youtube') || hay.contains('youtu.be')) {
      return Icons.play_circle_fill;
    }
    if (hay.contains('instagram')) return Icons.camera_alt;
    if (hay.contains('linkedin')) return Icons.business_center;
    if (hay.contains('whatsapp') || hay.contains('wa.me')) return Icons.chat;
    if (hay.contains('telegram') || hay.contains('t.me')) return Icons.send;
    if (hay.contains('mail') || hay.startsWith('mailto')) return Icons.email;
    if (hay.contains('twitter') ||
        hay.contains('x.com') ||
        hay.contains('/x ')) {
      return Icons.alternate_email;
    }
    return Icons.public;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: widget.section.title),
        FutureBuilder<List<LinkItem>>(
          future: _future,
          builder: (context, snap) {
            final items = snap.data ?? const <LinkItem>[];
            if (items.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final link in items)
                    IconButton.filledTonal(
                      tooltip: link.title,
                      icon: Icon(_iconFor(link)),
                      color: scheme.primary,
                      onPressed: () => _open(link.url),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
