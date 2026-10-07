import 'package:flutter/material.dart';

import '../game/state/game_state.dart';
import 'hud.dart';
import 'neon_widgets.dart';
import 'theme.dart';

class GameOverOverlay extends StatelessWidget {
  const GameOverOverlay({
    super.key,
    required this.state,
    required this.onRestart,
    required this.onOpenLab,
  });

  final GameState state;
  final VoidCallback onRestart;
  final VoidCallback onOpenLab;

  @override
  Widget build(BuildContext context) {
    final cause = state.gameOver;
    return NeonPanel(
      children: [
        const PanelTitle('GAME OVER', color: NeonPalette.danger),
        if (cause != null) ...[
          const SizedBox(height: 8),
          Text(
            'The ${cause.side.name.toUpperCase()} glass filled up to the far '
            'end of its arm.',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: NeonPalette.textDim,
              fontSize: 12.5,
              height: 1.3,
            ),
          ),
        ],
        const SizedBox(height: 18),
        _Line('SCORE', state.score.toString(), highlight: true),
        _Line('BEST COMBO', '×${state.bestCombo}'),
        _Line('MATCHES', state.matches.toString()),
        _Line('STICKS PLACED', state.piecesPlaced.toString()),
        _Line('TIME', formatClock(state.elapsedSeconds.floor())),
        const SizedBox(height: 18),
        NeonButton(
          key: const ValueKey('restart'),
          label: 'RESTART',
          onPressed: onRestart,
        ),
        const SizedBox(height: 10),
        NeonButton(label: 'LAB SETTINGS', primary: false, onPressed: onOpenLab),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line(this.label, this.value, {this.highlight = false});

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: NeonPalette.textDim,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.6,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: highlight ? NeonPalette.outline : NeonPalette.text,
              fontSize: highlight ? 28 : 20,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
