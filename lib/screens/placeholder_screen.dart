import 'package:flutter/material.dart';

/// Friendly fallback when a menu route has no bespoke screen and isn't a CMS
/// page either. Keeps navigation from dead-ending if a webmaster adds a module
/// the app doesn't specifically handle yet.
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.widgets_outlined, size: 48, color: Colors.grey),
              const SizedBox(height: 12),
              Text(
                'This section is not available yet.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
