import '../i18n/strings.dart';
import 'package:flutter/material.dart';

import '../../game/config/campaign.dart';
import '../data/settings.dart';
import '../format.dart';
import '../style.dart';

/// The numbers used by the game readout and campaign progress.
class HudState {
  const HudState({
    required this.score,
    required this.combo,
    required this.bestCombo,
    required this.matches,
    required this.pieces,
    required this.seconds,
    required this.level,
    required this.into,
    required this.target,
    required this.colours,
    required this.glasses,
    required this.speed,
  });

  static const empty = HudState(
    score: 0,
    combo: 0,
    bestCombo: 0,
    matches: 0,
    pieces: 0,
    seconds: 0,
    level: 0,
    into: 0,
    target: 0,
    colours: 0,
    glasses: 0,
    speed: 0,
  );

  /// Points of the whole game so far.
  final int score;
  final int combo;
  final int bestCombo;
  final int matches;
  final int pieces;
  final int seconds;

  /// Campaign only (0 otherwise): the level being played, from 1, the points
  /// made in it, the points it takes, and its colours and glasses.
  final int level;
  final int into;
  final int target;
  final int colours;
  final int glasses;

  /// Modes whose falling speeds up: the speed level, from 1 (0 otherwise).
  final int speed;

  @override
  bool operator ==(Object other) =>
      other is HudState &&
      other.score == score &&
      other.combo == combo &&
      other.bestCombo == bestCombo &&
      other.matches == matches &&
      other.pieces == pieces &&
      other.seconds == seconds &&
      other.level == level &&
      other.into == into &&
      other.target == target &&
      other.colours == colours &&
      other.glasses == glasses &&
      other.speed == speed;

  @override
  int get hashCode =>
      Object.hash(score, combo, bestCombo, matches, pieces, seconds, level, into, target, colours, glasses, speed);
}

/// A short-lived callout: a score gain with its combo, or a new speed.
class Callout {
  const Callout.score({required this.id, required this.points, required this.combo}) : speed = 0, isSpeed = false;
  const Callout.speed({required this.id, required this.speed}) : points = 0, combo = 0, isSpeed = true;

  final int id;
  final bool isSpeed;
  final int points;
  final int combo;
  final int speed;
}

class _CalloutView extends StatelessWidget {
  const _CalloutView({required this.callout, required this.base});

  final Callout callout;
  final double base;

  @override
  Widget build(BuildContext context) {
    final text = callout.isSpeed
        ? LText('Скорость ${callout.speed}', style: Type.display(base * 1.3, color: Palette.warning))
        : LText(
            '+${callout.points}',
            style: Type.display(base * 1.5, color: Palette.accent),
          );
    // A new key per callout makes it pop again each time.
    return TweenAnimationBuilder<double>(
      key: ValueKey(callout.id),
      tween: Tween(begin: 0.6, end: 1),
      duration: const Duration(milliseconds: 260),
      curve: Motion.back,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: t, alignment: Alignment.topLeft, child: child),
      ),
      child: text,
    );
  }
}

/// A single row between the two header buttons. Labels remain available to
/// screen readers and long values shrink within their own space.
class GameReadout extends StatelessWidget {
  const GameReadout({super.key, required this.hud, required this.options, this.callout});
  final HudState hud;
  final HudOptions options;
  final Callout? callout;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: options.opacity,
    child: SizedBox(
      height: 44,
      child: Row(
        children: [
          if (options.score)
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Semantics(
                        label: context.tr(formatPoints(hud.score)),
                        excludeSemantics: true,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: LText(formatNumber(hud.score), style: Type.display(20)),
                        ),
                      ),
                    ),
                  ),
                  if (callout != null)
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: ClipRect(child: IgnorePointer(child: _CalloutView(callout: callout!, base: 6))),
                    ),
                ],
              ),
            )
          else
            const Spacer(),
          if (options.score && hud.level > 0)
            _ReadoutStat(icon: Icons.layers_outlined, value: '${hud.level}/${campaignLevels.length}',
              label: 'Уровень ${hud.level} / ${campaignLevels.length}', accent: true),
          if (options.score && hud.speed > 0)
            _ReadoutStat(icon: Icons.speed_rounded, value: '${hud.speed}', label: 'Скорость ${hud.speed}', accent: true),
          if (options.stats) ...[
            _ReadoutStat(icon: Icons.schedule_rounded, value: formatClock(hud.seconds), label: 'Время'),
            _ReadoutStat(icon: Icons.view_module_outlined, value: formatNumber(hud.pieces), label: 'Фигуры'),
          ],
        ],
      ),
    ),
  );
}

class _ReadoutStat extends StatelessWidget {
  const _ReadoutStat({required this.icon, required this.value, required this.label, this.accent = false});
  final IconData icon;
  final String value, label;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final caption = context.tr(label);
    final color = accent ? Palette.accent : Palette.textDim;
    return Flexible(
      child: Padding(
        padding: const EdgeInsets.only(left: 6),
        child: Tooltip(
          message: caption,
          child: Semantics(
            label: accent ? caption : '$caption: $value',
            excludeSemantics: true,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(icon, size: 12, color: color),
                const SizedBox(width: 3),
                LText(value, style: Type.body(11, color: color)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
