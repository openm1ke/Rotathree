import 'package:flutter/material.dart';

import 'neon_widgets.dart';
import 'theme.dart';

class StartOverlay extends StatelessWidget {
  const StartOverlay({super.key, required this.onPlay, required this.onOpenLab});

  final VoidCallback onPlay;
  final VoidCallback onOpenLab;

  static const _rules = [
    ('Four sticks fall at once, a cell at a time: once a second in the glass on top, once every three seconds in the others.', null),
    ('Swipe the field left / right (or tap a glass) to bring another glass to the top.', Icons.swipe_rounded),
    ('Drag the stick in the top glass or use the MOVE buttons to aim, tap to rotate.', Icons.open_with_rounded),
    ('Swipe down or DROP to send it in. Line up 3+ of a colour.', Icons.keyboard_double_arrow_down_rounded),
    ('Sticks you leave alone land by themselves. A glass that fills up to the far end of its arm ends the game.', Icons.warning_amber_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      children: [
        const PanelTitle('ROTATHREE', color: NeonPalette.outline),
        const SizedBox(height: 6),
        const Text(
          'gameplay prototype',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: NeonPalette.textDim,
            fontSize: 12,
            letterSpacing: 3,
          ),
        ),
        const SizedBox(height: 20),
        for (final (text, icon) in _rules)
          Padding(
            padding: const EdgeInsets.only(bottom: 11),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  icon ?? Icons.grid_view_rounded,
                  size: 18,
                  color: NeonPalette.outline,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    text,
                    style: const TextStyle(
                      color: NeonPalette.text,
                      fontSize: 13.5,
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 10),
        NeonButton(key: const ValueKey('play'), label: 'PLAY', onPressed: onPlay),
        const SizedBox(height: 10),
        NeonButton(label: 'LAB SETTINGS', primary: false, onPressed: onOpenLab),
      ],
    );
  }
}
