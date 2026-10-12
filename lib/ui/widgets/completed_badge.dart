import 'package:flutter/material.dart';

import '../i18n/strings.dart';
import '../style.dart';

/// Pixel check and square frame echo the pieces and menu typography.
class CompletedBadge extends StatelessWidget {
  const CompletedBadge({super.key});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Palette.accent.withValues(alpha: 0.45)),
      gradient: LinearGradient(colors: [Palette.accent.withValues(alpha: 0.12), Palette.brandGreen.withValues(alpha: 0.06)]),
      boxShadow: [BoxShadow(color: Palette.brandGreen.withValues(alpha: 0.1), blurRadius: 16)],
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(width: 16, height: 12, child: Stack(children: [
        for (final point in const [(0.0, 4.0), (4.0, 8.0), (8.0, 4.0), (12.0, 0.0)])
          Positioned(left: point.$1, top: point.$2, child: Container(width: 4, height: 4, color: point.$1 == 0 ? Palette.brandBlue : Palette.brandGreen)),
      ])),
      const SizedBox(width: 6),
      LText('пройдена', style: Type.display(11, spacing: 0.4)),
    ]),
  );
}
