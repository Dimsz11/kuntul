import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../../shared/html_text.dart';
import '../../shared/section_header.dart';

/// `html` section — a raw HTML block authored in the CMS.
///
/// Data source: static (the `html` value from config).
/// Config: `html`. Rendered as cleaned, readable text via [HtmlText] (swap for
/// a full HTML renderer in a production design — see `html_text.dart`).
class HtmlSection extends StatelessWidget {
  const HtmlSection({super.key, required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    final html = section.html;
    if (html == null || html.trim().isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: HtmlText(html),
        ),
      ],
    );
  }
}
