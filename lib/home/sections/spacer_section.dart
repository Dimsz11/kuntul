import 'package:flutter/material.dart';

import '../../core/models.dart';

/// `spacer` section — a simple vertical gap between sections.
///
/// Config: `height` (logical pixels).
class SpacerSection extends StatelessWidget {
  const SpacerSection({super.key, required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) {
    return SizedBox(height: section.height.clamp(0, 400).toDouble());
  }
}
