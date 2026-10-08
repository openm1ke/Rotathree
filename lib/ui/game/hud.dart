import 'package:flutter/widgets.dart';

import '../../game/config/campaign.dart';
import '../data/bindings.dart';
import '../data/settings.dart';
import '../format.dart';
import '../input/game_action.dart';
import '../style.dart';

/// The numbers shown in the corners of the field.
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
  int get hashCode => Object.hash(score, combo, bestCombo, matches, pieces, seconds, level, into, target, colours, glasses, speed);
}

/// A short-lived callout: a score gain with its combo, or a new speed.
class Callout {
  const Callout.score({required this.id, required this.points, required this.combo}) : speed = 0, isSpeed = false;
  const Callout.speed({required this.id, required this.speed})
      : points = 0,
        combo = 0,
        isSpeed = true;

  final int id;
  final bool isSpeed;
  final int points;
  final int combo;
  final int speed;
}

/// Four panels in the corners the cross leaves free.
class Hud extends StatelessWidget {
  const Hud({
    super.key,
    required this.hud,
    required this.callout,
    required this.bindings,
    required this.options,
    required this.corner,
    required this.base,
    required this.onPause,
    required this.onOpenSettings,
  });

  final HudState hud;
  final Callout? callout;
  final Bindings bindings;
  final HudOptions options;

  /// Side of a corner square, in logical pixels.
  final double corner;

  /// The base text size; everything on the field is a multiple of it.
  final double base;
  final VoidCallback onPause;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final pad = base * 0.5;
    final label = Type.label(base * 0.9);
    final value = Type.display(base * 1.8, height: 1.05);
    final small = Type.display(base * 1.25, height: 1.05);
    return Opacity(
      opacity: options.opacity,
      child: Stack(
        children: [
          if (options.score)
            Positioned(
              left: pad,
              top: pad,
              width: corner * 1.1,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Счёт', style: label),
                  Text(formatNumber(hud.score), style: value.copyWith(fontSize: base * 2.4)),
                  if (hud.level > 0) ...[
                    SizedBox(height: base * 0.6),
                    _LevelBlock(hud: hud, base: base),
                  ],
                  if (hud.speed > 0)
                    Text('Скорость ${hud.speed}', style: Type.body(base * 0.95, color: Palette.accent)),
                  if (callout != null) _CalloutView(callout: callout!, base: base),
                ],
              ),
            ),
          if (options.stats) ...[
            Positioned(
              right: pad,
              top: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Время', style: label),
                  Text(formatClock(hud.seconds), style: small),
                  Text('Фигуры', style: label),
                  Text('${hud.pieces}', style: small),
                ],
              ),
            ),
            Positioned(
              left: pad,
              bottom: pad,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Матчи', style: label),
                  Text('${hud.matches}', style: small),
                  Text('Лучшее комбо', style: label),
                  Text('×${hud.bestCombo}', style: small),
                ],
              ),
            ),
          ],
          Positioned(
            right: pad,
            bottom: pad,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (options.keyHints) ...[
                  _Hints(bindings: bindings, base: base),
                  SizedBox(height: base * 0.5),
                ],
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _HudButton(label: 'Пауза', onPressed: onPause, base: base),
                    SizedBox(width: base * 0.5),
                    _HudButton(label: 'Настройки', onPressed: onOpenSettings, base: base),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelBlock extends StatelessWidget {
  const _LevelBlock({required this.hud, required this.base});

  final HudState hud;
  final double base;

  @override
  Widget build(BuildContext context) {
    final fraction = hud.target <= 0 ? 0.0 : (hud.into / hud.target).clamp(0.0, 1.0).toDouble();
    return SizedBox(
      width: base * 11,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Уровень ${hud.level} / ${campaignLevels.length}',
            style: Type.body(base * 1.0, weight: FontWeight.w800),
          ),
          Text('${hud.colours} цв · ${hud.glasses} ст', style: Type.body(base * 0.85, color: Palette.textDim)),
          SizedBox(height: base * 0.35),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(height: base * 0.4, color: Palette.line),
                FractionallySizedBox(
                  widthFactor: fraction,
                  child: Container(height: base * 0.4, color: Palette.accent),
                ),
              ],
            ),
          ),
          SizedBox(height: base * 0.3),
          Text(
            '${formatNumber(hud.into)} / ${formatNumber(hud.target)}',
            style: Type.body(base * 0.9, color: Palette.textDim, weight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _CalloutView extends StatelessWidget {
  const _CalloutView({required this.callout, required this.base});

  final Callout callout;
  final double base;

  @override
  Widget build(BuildContext context) {
    final text = callout.isSpeed
        ? Text('Скорость ${callout.speed}', style: Type.display(base * 1.3, color: Palette.warning))
        : Text(
            callout.combo > 1
                ? '+${callout.points}  ${callout.combo}× комбо'
                : '+${callout.points}',
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

class _Hints extends StatelessWidget {
  const _Hints({required this.bindings, required this.base});

  final Bindings bindings;
  final double base;

  @override
  Widget build(BuildContext context) {
    Widget row(String text, List<GameAction> actions) {
      final keys = [
        for (final action in actions)
          ...bindings[action]!.take(1).map(keyLabel),
      ];
      return Padding(
        padding: EdgeInsets.only(bottom: base * 0.25),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final key in keys) ...[
              Text(key, style: Type.body(base * 0.95, weight: FontWeight.w800)),
              SizedBox(width: base * 0.25),
            ],
            Text(text, style: Type.body(base * 0.9, color: Palette.textDim)),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        row('движение', [GameAction.moveLeft, GameAction.moveRight]),
        row('поворот', [GameAction.rotateCW, GameAction.rotateCCW]),
        row('сброс', [GameAction.hardDrop]),
        row('стаканы', [GameAction.glassLeft, GameAction.glassRight]),
      ],
    );
  }
}

class _HudButton extends StatelessWidget {
  const _HudButton({required this.label, required this.onPressed, required this.base});

  final String label;
  final VoidCallback onPressed;
  final double base;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: base * 0.7, vertical: base * 0.4),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Palette.lineStrong),
        ),
        child: Text(label, style: Type.body(base * 0.95, weight: FontWeight.w800)),
      ),
    );
  }
}
