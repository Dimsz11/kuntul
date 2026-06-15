import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../core/models.dart';
import '../../screens/webview_screen.dart';
import '../../shared/section_header.dart';

/// `webview` section — an embedded web page inside the home feed.
///
/// Data source: embedded WebView of `config.url`.
/// Config: `url`.
///
/// Embedded in a scrolling list, so it gets a fixed height and a "fullscreen"
/// affordance that pushes the dedicated [WebViewScreen].
class WebViewSection extends StatefulWidget {
  const WebViewSection({super.key, required this.section});

  final HomeSection section;

  @override
  State<WebViewSection> createState() => _WebViewSectionState();
}

class _WebViewSectionState extends State<WebViewSection> {
  WebViewController? _controller;

  @override
  void initState() {
    super.initState();
    final url = widget.section.url;
    if (url != null && url.isNotEmpty) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        _controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadRequest(uri);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final url = widget.section.url;
    final controller = _controller;
    if (url == null || url.isEmpty || controller == null) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: widget.section.title,
          onSeeAll: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WebViewScreen(url: url, title: widget.section.title),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 280,
              child: WebViewWidget(controller: controller),
            ),
          ),
        ),
      ],
    );
  }
}
