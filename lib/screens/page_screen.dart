import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../main.dart' show AppScope;
import '../shared/html_text.dart';

/// Renders a CMS-managed page. Source: `GET /api/pages/by-key/{key}`.
///
/// Used for static/info modules (about, contact, ...) and as the fallback for
/// any menu route the app doesn't have a bespoke screen for.
class PageScreen extends StatefulWidget {
  const PageScreen({super.key, required this.pageKey, this.title});

  final String pageKey;
  final String? title;

  @override
  State<PageScreen> createState() => _PageScreenState();
}

class _PageScreenState extends State<PageScreen> {
  ApiClient? _api;
  Future<PageContent>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= AppScope.of(context).api;
    _future ??= _api!.pageByKey(widget.pageKey);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title ?? '')),
      body: FutureBuilder<PageContent>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError || !snap.hasData) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  snap.error is ApiException
                      ? (snap.error as ApiException).message
                      : 'Page not available',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          final page = snap.data!;
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (page.title.isNotEmpty &&
                    page.title != (widget.title ?? '')) ...[
                  Text(
                    page.title,
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                ],
                HtmlText(page.content),
              ],
            ),
          );
        },
      ),
    );
  }
}
