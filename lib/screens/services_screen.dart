import 'package:flutter/material.dart';

import '../core/api_client.dart';
import '../core/models.dart';
import '../main.dart' show AppScope;
import '../shared/html_text.dart';

/// Services directory. Source: `GET /api/companies/services` (a parent →
/// children tree). Top-level services render as expandable tiles; leaf services
/// show their description.
class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});

  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen> {
  ApiClient? _api;
  Future<List<ServiceItem>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _api ??= AppScope.of(context).api;
    _future ??= _api!.services();
  }

  Future<void> _refresh() async {
    final f = _api!.services();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    final lang = AppScope.of(context).lang;
    return Scaffold(
      appBar: AppBar(title: Text(lang == 'en' ? 'Services' : 'الخدمات')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<ServiceItem>>(
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
            final items = snap.data ?? const <ServiceItem>[];
            if (items.isEmpty) {
              return _Centered(
                child: Text(lang == 'en' ? 'No services' : 'لا توجد خدمات'),
              );
            }
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(8),
              children: [for (final s in items) _ServiceNode(service: s)],
            );
          },
        ),
      ),
    );
  }
}

class _ServiceNode extends StatelessWidget {
  const _ServiceNode({required this.service});
  final ServiceItem service;

  @override
  Widget build(BuildContext context) {
    if (service.children.isEmpty) {
      return Card(
        child: ListTile(
          leading: const Icon(Icons.chevron_right),
          title: Text(service.name),
          subtitle: (service.description != null && service.description!.isNotEmpty)
              ? HtmlText(
                  service.description,
                  style: Theme.of(context).textTheme.bodySmall,
                )
              : null,
        ),
      );
    }
    return Card(
      child: ExpansionTile(
        leading: const Icon(Icons.folder_open),
        title: Text(service.name,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        childrenPadding: const EdgeInsets.only(left: 8, right: 8, bottom: 8),
        children: [for (final c in service.children) _ServiceNode(service: c)],
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
