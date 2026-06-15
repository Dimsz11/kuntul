import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../screens/page_screen.dart';
import '../../shared/html_text.dart';
import '../../shared/section_header.dart';

/// `about` section — a preview of a CMS-managed page (e.g. "About us").
///
/// Data source: `GET /api/pages/by-key/{pageKey}`. Config: `pageKey`.
/// Shows the first lines of the page with a "Read more" affordance that opens
/// the full [PageScreen].
class AboutSection extends StatefulWidget {
  const AboutSection({super.key, required this.section, required this.api});

  final HomeSection section;
  final ApiClient api;

  @override
  State<AboutSection> createState() => _AboutSectionState();
}

class _AboutSectionState extends State<AboutSection> {
  Future<PageContent>? _future;

  @override
  void initState() {
    super.initState();
    final key = widget.section.pageKey;
    if (key != null && key.isNotEmpty) _future = widget.api.pageByKey(key);
  }

  void _openPage(String key, String? title) => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => PageScreen(pageKey: key, title: title),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final key = widget.section.pageKey;
    if (_future == null || key == null) return const SizedBox.shrink();
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: widget.section.title),
        FutureBuilder<PageContent>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SectionStatus.loading(height: 100);
            }
            if (!snap.hasData) return const SizedBox.shrink();
            final page = snap.data!;
            final preview = HtmlText.stripHtml(page.content ?? '');
            if (preview.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    preview,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(height: 1.5),
                  ),
                  Align(
                    alignment:
                        isRtl ? Alignment.centerLeft : Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => _openPage(
                        key,
                        widget.section.title ?? page.title,
                      ),
                      child: Text(isRtl ? 'اقرأ المزيد' : 'Read more'),
                    ),
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
