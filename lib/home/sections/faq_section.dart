import 'package:flutter/material.dart';

import '../../core/api_client.dart';
import '../../core/models.dart';
import '../../shared/html_text.dart';
import '../../shared/section_header.dart';

/// `faq` section — an expandable accordion of the latest FAQ entries.
///
/// Data source: `GET /api/faq?pageSize=count`. Config: `count`.
/// Only top-level entries (no parent) are shown inline; "See all" opens the
/// full FAQ screen.
class FaqSection extends StatefulWidget {
  const FaqSection({super.key, required this.section, required this.api});

  final HomeSection section;
  final ApiClient api;

  @override
  State<FaqSection> createState() => _FaqSectionState();
}

class _FaqSectionState extends State<FaqSection> {
  late final Future<List<FaqItem>> _future =
      widget.api.faq(pageSize: widget.section.count);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: widget.section.title,
          onSeeAll: () => Navigator.pushNamed(context, '/faq'),
        ),
        FutureBuilder<List<FaqItem>>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SectionStatus.loading(height: 120);
            }
            if (snap.hasError) {
              return SectionStatus.error(
                snap.error is ApiException
                    ? (snap.error as ApiException).message
                    : 'Failed to load FAQ',
              );
            }
            // Top-level questions only for the inline preview.
            final items = (snap.data ?? const <FaqItem>[])
                .where((f) => f.parentId == null)
                .toList();
            if (items.isEmpty) return const SizedBox.shrink();

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                children: [
                  for (final f in items)
                    Card(
                      child: ExpansionTile(
                        leading: const Icon(Icons.help_outline),
                        title: Text(
                          f.question,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        childrenPadding:
                            const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [HtmlText(f.answer)],
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
