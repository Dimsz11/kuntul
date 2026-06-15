import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../main.dart' show AppScope;
import '../shared/html_text.dart';

/// Full FAQ list. Source: `GET /api/faq?pageSize=`. Top-level questions render
/// as expandable accordion tiles.
class FaqScreen extends StatefulWidget {
  const FaqScreen({super.key});

  @override
  State<FaqScreen> createState() => _FaqScreenState();
}

class _FaqScreenState extends State<FaqScreen> {
  ApiClient? _api;
  Future<List<FaqItem>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= AppScope.of(context).api;
    _future ??= _api!.faq(pageSize: 100);
  }

  Future<void> _refresh() async {
    final f = _api!.faq(pageSize: 100);
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    return Scaffold(
      appBar: AppBar(
        title: Text(lang == 'en' ? 'FAQ' : 'الأسئلة الشائعة'),
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<FaqItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return _Centered(
                child: Text(snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Failed to load'),
              );
            }
            final items = (snap.data ?? const <FaqItem>[])
                .where((f) => f.parentId == null)
                .toList();
            if (items.isEmpty) {
              return _Centered(
                child: Text(lang == 'en' ? 'No questions' : 'لا توجد أسئلة'),
              );
            }
            return ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final f = items[i];
                return Card(
                  child: ExpansionTile(
                    leading: const Icon(Icons.help_outline),
                    title: Text(
                      f.question,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    expandedCrossAxisAlignment: CrossAxisAlignment.start,
                    children: [HtmlText(f.answer)],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Center(child: child),
        ),
      ],
    );
  }
}
