import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../game/model/side.dart';
import 'theme.dart';

/// The numbers shown above the field. Compared by value so the HUD only
/// rebuilds when something visible changed.
@immutable
class HudData {
  const HudData({
    required this.score,
    required this.combo,
    required this.bestCombo,
    required this.matches,
    required this.seconds,
    required this.activeSide,
  });

  final int score;
  final int combo;
  final int bestCombo;
  final int matches;
  final int seconds;
  final Side activeSide;

  @override
  bool operator ==(Object other) =>
      other is HudData &&
      other.score == score &&
      other.combo == combo &&
      other.bestCombo == bestCombo &&
      other.matches == matches &&
      other.seconds == seconds &&
      other.activeSide == activeSide;

  @override
  int get hashCode =>
      Object.hash(score, combo, bestCombo, matches, seconds, activeSide);
}

String formatClock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

class Hud extends StatelessWidget {
  const Hud({super.key, required this.data, required this.onOpenLab});

  final ValueListenable<HudData> data;
  final VoidCallback onOpenLab;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 6, 4),
      child: ValueListenableBuilder<HudData>(
        valueListenable: data,
        builder: (context, hud, _) {
          final inCombo = hud.combo > 1;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 13,
                child: _Stat(
                  label: 'SCORE',
                  value: hud.score.toString(),
                  large: true,
                ),
              ),
              Expanded(
                flex: 10,
                child: _Stat(
                  label: inCombo ? 'COMBO' : 'BEST COMBO',
                  value: '×${inCombo ? hud.combo : hud.bestCombo}',
                  color: inCombo ? NeonPalette.warning : NeonPalette.text,
                ),
              ),
              Expanded(
                flex: 9,
                child: _Stat(label: 'MATCHES', value: hud.matches.toString()),
              ),
              Expanded(
                flex: 8,
                child: _Stat(label: 'TIME', value: formatClock(hud.seconds)),
              ),
              IconButton(
                key: const ValueKey('lab-button'),
                onPressed: onOpenLab,
                tooltip: 'Lab settings',
                icon: const Icon(Icons.tune_rounded),
                color: NeonPalette.textDim,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.label,
    required this.value,
    this.large = false,
    this.color = NeonPalette.text,
  });

  final String label;
  final String value;
  final bool large;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: NeonPalette.textDim,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: color,
              fontSize: large ? 30 : 20,
              height: 1.05,
              fontWeight: FontWeight.w800,
              fontFeatures: const [FontFeature.tabularFigures()],
              shadows: [
                Shadow(color: color.withValues(alpha: 0.45), blurRadius: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
