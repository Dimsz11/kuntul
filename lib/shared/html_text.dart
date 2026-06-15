import 'package:flutter/material.dart';

/// Renders CMS rich-text (HTML) as readable plain text.
///
/// The CMS stores news/page bodies as HTML. A production design would use a
/// package such as `flutter_html` or `flutter_widget_from_html` for full markup
/// + image rendering; to keep this reference dependency-light we strip tags and
/// decode the common entities so the content is still readable. Swap this
/// widget for an HTML renderer when wiring up a real design.
class HtmlText extends StatelessWidget {
  const HtmlText(this.html, {super.key, this.style});

  final String? html;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final text = stripHtml(html ?? '');
    if (text.isEmpty) return const SizedBox.shrink();
    return SelectableText(
      text,
      style: style ?? Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.6),
    );
  }

  /// Strip tags, collapse whitespace, and decode a handful of named/numeric
  /// HTML entities. Block tags become line breaks so paragraphs survive.
  static String stripHtml(String input) {
    if (input.isEmpty) return '';
    var s = input
        .replaceAll(RegExp(r'<\s*(br|/p|/div|/li|/h[1-6])\s*/?>',
            caseSensitive: false), '\n')
        .replaceAll(RegExp(r'<[^>]+>'), '');

    const entities = {
      '&nbsp;': ' ',
      '&amp;': '&',
      '&lt;': '<',
      '&gt;': '>',
      '&quot;': '"',
      '&#39;': "'",
      '&apos;': "'",
      '&laquo;': '«',
      '&raquo;': '»',
      '&mdash;': '—',
      '&ndash;': '–',
      '&hellip;': '…',
    };
    entities.forEach((k, v) => s = s.replaceAll(k, v));

    // Numeric entities (&#1234;).
    s = s.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1)!);
      return code == null ? m.group(0)! : String.fromCharCode(code);
    });

    // Collapse runs of blank lines / spaces.
    return s
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }
}
