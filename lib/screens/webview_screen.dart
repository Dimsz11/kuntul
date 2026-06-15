import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// External-link screen for the `/webview?url=` route and the home `webview`
/// section's "open" affordance.
///
/// `webview_flutter` was removed for CI build portability (its native Android
/// plugin needs a newer Kotlin than `flutter create` scaffolds in CI), so this
/// no longer embeds a WebView. It auto-launches the URL in the external browser
/// on open and offers a button to re-open it.
class WebViewScreen extends StatefulWidget {
  const WebViewScreen({super.key, required this.url, this.title});

  final String url;
  final String? title;

  @override
  State<WebViewScreen> createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  bool _launched = false;

  @override
  void initState() {
    super.initState();
    // Try to open the link in the browser as soon as the screen appears.
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }

  Future<void> _open() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) setState(() => _launched = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final uri = Uri.tryParse(widget.url);
    final invalid = uri == null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: invalid
              ? Text(isRtl ? 'رابط غير صالح' : 'Invalid URL')
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.open_in_browser,
                        size: 48, color: Colors.grey),
                    const SizedBox(height: 16),
                    Text(
                      _launched
                          ? (isRtl
                              ? 'تم فتح الرابط في المتصفح'
                              : 'Opened in your browser')
                          : (isRtl
                              ? 'سيتم فتح هذا الرابط في المتصفح'
                              : 'This link opens in your browser'),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      widget.url,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.icon(
                      onPressed: _open,
                      icon: const Icon(Icons.open_in_new),
                      label: Text(isRtl ? 'افتح الرابط' : 'Open link'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
