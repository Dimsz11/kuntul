import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../shared/section_header.dart';

/// `contact` section — a card with phone / email / address.
///
/// Data source: `GET /api/settings/public` (a flat Key→Value map of public
/// settings). The section `config` may also carry explicit `phone` / `email` /
/// `address` values that take precedence. There is no list endpoint — contact
/// info is static settings.
class ContactSection extends StatefulWidget {
  const ContactSection({super.key, required this.section, required this.api});

  final HomeSection section;
  final ApiClient api;

  @override
  State<ContactSection> createState() => _ContactSectionState();
}

class _ContactSectionState extends State<ContactSection> {
  late final Future<Map<String, String>> _future =
      widget.api.settingsPublic().catchError((_) => <String, String>{});

  /// Look up [keys] (in order) from [config] first, then [settings].
  String? _pick(
    Map<String, dynamic> config,
    Map<String, String> settings,
    List<String> keys,
  ) {
    for (final k in keys) {
      final c = config[k];
      if (c is String && c.isNotEmpty) return c;
    }
    for (final k in keys) {
      final s = settings[k];
      if (s != null && s.isNotEmpty) return s;
    }
    return null;
  }

  Future<void> _launch(String scheme, String value) async {
    final uri = Uri(scheme: scheme, path: value);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.section.config;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: widget.section.title),
        FutureBuilder<Map<String, String>>(
          future: _future,
          builder: (context, snap) {
            final settings = snap.data ?? const <String, String>{};

            final phone = _pick(cfg, settings,
                ['phone', 'contactPhone', 'Contact.Phone', 'phoneNumber']);
            final email = _pick(cfg, settings,
                ['email', 'contactEmail', 'Contact.Email']);
            final address = _pick(cfg, settings,
                ['address', 'contactAddress', 'Contact.Address']);

            if (phone == null && email == null && address == null) {
              // Still loading or nothing configured → render nothing.
              return snap.connectionState == ConnectionState.waiting
                  ? const SectionStatus.loading(height: 80)
                  : const SizedBox.shrink();
            }

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Card(
                child: Column(
                  children: [
                    if (phone != null)
                      ListTile(
                        leading: const Icon(Icons.phone),
                        title: Text(phone),
                        onTap: () => _launch('tel', phone),
                      ),
                    if (email != null)
                      ListTile(
                        leading: const Icon(Icons.email),
                        title: Text(email),
                        onTap: () => _launch('mailto', email),
                      ),
                    if (address != null)
                      ListTile(
                        leading: const Icon(Icons.location_on),
                        title: Text(address),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}
