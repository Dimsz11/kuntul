import 'package:flutter/material.dart';

/// Title row shown above a home section. Hidden when [title] is null/empty so
/// sections without a webmaster-set title render cleanly.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, this.title, this.onSeeAll});

  final String? title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (title == null || title!.trim().isEmpty) {
      return const SizedBox(height: 8);
    }
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title!,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(
                Directionality.of(context) == TextDirection.rtl
                    ? 'المزيد'
                    : 'See all',
              ),
            ),
        ],
      ),
    );
  }
}

/// Compact inline loading / error placeholder for a single section, so one
/// failing section never blanks the whole home screen.
class SectionStatus extends StatelessWidget {
  const SectionStatus.loading({super.key, this.height = 120})
      : message = null,
        isError = false;

  const SectionStatus.error(this.message, {super.key, this.height = 80})
      : isError = true;

  final String? message;
  final bool isError;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: isError
            ? Text(
                message ?? 'Failed to load',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}
