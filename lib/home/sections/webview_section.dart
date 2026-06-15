import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../shared/section_header.dart';

/// `webview` section — a link to an external web page.
///
/// Data source: `config.url`. Config: `url`.
///
/// `webview_flutter` was removed for CI build portability, so instead of an
/// inline WebView this renders a card whose button opens the URL in the
/// external browser via `url_launcher`.
class WebViewSection extends StatelessWidget {
  const WebViewSection({super.key, required this.section});

  final HomeSection section;

  Future<void> _open() async {
    final url = section.url;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = section.url;
    if (url == null || url.isEmpty) return const SizedBox.shrink();

    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: section.title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Card(
            child: InkWell(
              onTap: _open,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.public, color: scheme.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        url,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      onPressed: _open,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: Text(isRtl ? 'افتح الرابط' : 'Open link'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
