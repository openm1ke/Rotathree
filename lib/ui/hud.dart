import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'settings/settings.dart';
import 'style.dart';
import 'widgets/controls.dart';

/// How the game is played: a single run for survival, or Zen — the same game
/// through levels, each finished by reaching its score.
enum GameMode { classic, zen }

/// The numbers shown in the corners of the field.
@immutable
class HudData {
  const HudData({
    this.score = 0,
    this.bestCombo = 0,
    this.matches = 0,
    this.pieces = 0,
    this.seconds = 0,
    this.level = 0,
    this.levelInto = 0,
    this.levelTarget = 0,
  });

  final int score;
  final int bestCombo;
  final int matches;
  final int pieces;
  final int seconds;

  /// Zen only (0 otherwise): the level being played, the points made in it
  /// and the points it takes.
  final int level;
  final int levelInto;
  final int levelTarget;

  @override
  bool operator ==(Object other) =>
      other is HudData &&
      other.score == score &&
      other.bestCombo == bestCombo &&
      other.matches == matches &&
      other.pieces == pieces &&
      other.seconds == seconds &&
      other.level == level &&
      other.levelInto == levelInto &&
      other.levelTarget == levelTarget;

  @override
  int get hashCode => Object.hash(
      score, bestCombo, matches, pieces, seconds, level, levelInto, levelTarget);
}

/// A short-lived callout: a score gain and, in a cascade, its combo.
@immutable
class Callout {
  const Callout(this.id, {required this.score, required this.combo});

  final int id;
  final int score;
  final int combo;
}

String formatClock(int seconds) =>
    '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

/// 12345 → "12 345".
String formatScore(int score) {
  final digits = score.toString();
  final out = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) out.write(' ');
    out.write(digits[i]);
  }
  return out.toString();
}

/// Four panels in the corners the cross leaves free.
class Hud extends StatelessWidget {
  const Hud({
    super.key,
    required this.data,
    required this.callout,
    required this.options,
    required this.corner,
    required this.onPause,
    required this.onOpenSettings,
  });

  final ValueListenable<HudData> data;
  final ValueListenable<Callout?> callout;
  final HudOptions options;

  /// Side of a corner square, in logical pixels.
  final double corner;
  final VoidCallback onPause;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    // Everything is sized from the corner so that it fits on any phone.
    final em = corner / 11;
    final pad = EdgeInsets.all(em * 0.9);

    Widget panel(Alignment alignment, Widget child) => Align(
          alignment: alignment,
          child: SizedBox.square(
            dimension: corner,
            child: Padding(padding: pad, child: child),
          ),
        );
    // The writing never takes a touch away from the field under it.
    Widget writing(Alignment alignment, Widget child) => IgnorePointer(
          child: panel(
            alignment,
            Opacity(opacity: options.opacity, child: child),
          ),
        );

    return ValueListenableBuilder<HudData>(
      valueListenable: data,
      builder: (context, hud, _) => Stack(
        children: [
          if (options.score)
            writing(
              Alignment.topLeft,
              _ScorePanel(hud: hud, callout: callout, em: em),
            ),
          if (options.stats) ...[
            writing(
              Alignment.topRight,
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _Label('Время', em),
                  _Value(formatClock(hud.seconds), em * 2.1),
                  SizedBox(height: em * 0.6),
                  _Label('Фигуры', em),
                  _Value('${hud.pieces}', em * 1.6),
                ],
              ),
            ),
            writing(
              Alignment.bottomLeft,
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _Label('Матчи', em),
                  _Value('${hud.matches}', em * 2.1),
                  SizedBox(height: em * 0.6),
                  _Label('Лучшее комбо', em),
                  _Value('×${hud.bestCombo}', em * 1.6),
                ],
              ),
            ),
          ],
          panel(
            Alignment.bottomRight,
            Align(
              alignment: Alignment.bottomRight,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RoundButton(
                    icon: Icons.pause_rounded,
                    onPressed: onPause,
                    semanticLabel: 'Пауза',
                    size: em * 3.3,
                  ),
                  SizedBox(width: em * 0.7),
                  RoundButton(
                    icon: Icons.tune_rounded,
                    onPressed: onOpenSettings,
                    semanticLabel: 'Настройки',
                    size: em * 3.3,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text, this.em);

  final String text;
  final double em;

  @override
  Widget build(BuildContext context) =>
      Text(text.toUpperCase(), maxLines: 1, style: Type.label(em * 0.82));
}

class _Value extends StatelessWidget {
  const _Value(this.text, this.size);

  final String text;
  final double size;

  @override
  Widget build(BuildContext context) => Text(
        text,
        maxLines: 1,
        style: Type.display(size).copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      );
}

/// The score, the Zen level under it, and the callouts of the last match.
class _ScorePanel extends StatelessWidget {
  const _ScorePanel({required this.hud, required this.callout, required this.em});

  final HudData hud;
  final ValueListenable<Callout?> callout;
  final double em;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Label('Счёт', em),
        // Re-keyed on change so the number pops every time it grows.
        TweenAnimationBuilder<double>(
          key: ValueKey(hud.score),
          tween: Tween(begin: hud.score == 0 ? 1 : 1.22, end: 1),
          duration: const Duration(milliseconds: 260),
          curve: Motion.back,
          builder: (context, scale, child) => Transform.scale(
            scale: scale,
            alignment: Alignment.centerLeft,
            child: child,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              formatScore(hud.score),
              maxLines: 1,
              style: Type.display(
                em * 3.3,
                shadows: Type.glow(Palette.accent.withValues(alpha: 0.35), em * 1.4),
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
          ),
        ),
        if (hud.level > 0) ...[
          SizedBox(height: em * 0.45),
          _LevelBar(hud: hud, em: em),
        ],
        ValueListenableBuilder<Callout?>(
          valueListenable: callout,
          builder: (context, value, _) =>
              value == null ? const SizedBox.shrink() : _Callouts(value, em),
        ),
      ],
    );
  }
}

/// Zen: the level being played and how far along it is.
class _LevelBar extends StatelessWidget {
  const _LevelBar({required this.hud, required this.em});

  final HudData hud;
  final double em;

  @override
  Widget build(BuildContext context) {
    final progress =
        hud.levelTarget == 0 ? 0.0 : hud.levelInto / hud.levelTarget;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Text(
                'УРОВЕНЬ ${hud.level}',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.fade,
                style: Type.display(em * 0.95, color: Palette.zen, spacing: em * 0.06),
              ),
            ),
            Text(
              '${hud.levelInto}/${hud.levelTarget}',
              style: Type.body(em * 0.72, color: Palette.textDim, height: 1),
            ),
          ],
        ),
        SizedBox(height: em * 0.3),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: SizedBox(
            height: em * 0.36,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: Colors.white.withValues(alpha: 0.1)),
                TweenAnimationBuilder<double>(
                  tween: Tween(end: progress.clamp(0.0, 1.0)),
                  duration: const Duration(milliseconds: 320),
                  curve: Motion.snap,
                  builder: (context, value, _) => FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: value,
                    child: const DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Palette.zenDeep, Palette.accent],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// "+300" floating up, and under it "3× КОМБО" slammed down at a slant.
class _Callouts extends StatelessWidget {
  const _Callouts(this.callout, this.em);

  final Callout callout;
  final double em;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(callout.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 1300),
      builder: (context, t, _) {
        // In fast, hold, drift away.
        final appear = Motion.back.transform((t / 0.16).clamp(0.0, 1.0));
        final leave = ((t - 0.76) / 0.24).clamp(0.0, 1.0);
        final opacity = ((t / 0.12).clamp(0.0, 1.0) * (1 - leave)).clamp(0.0, 1.0);
        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: Offset(0, -em * 0.5 * leave),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(height: em * 0.3),
                Text(
                  '+${callout.score}',
                  style: Type.display(em * 1.7, color: Palette.accent),
                ),
                if (callout.combo > 1)
                  Transform.rotate(
                    angle: -0.1,
                    alignment: Alignment.centerLeft,
                    child: Transform.scale(
                      scale: 2.2 - 1.2 * appear,
                      alignment: Alignment.centerLeft,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '${callout.combo}×',
                              style: Type.display(em * 2.4, color: Colors.white),
                            ),
                            const TextSpan(text: ' КОМБО'),
                          ],
                        ),
                        maxLines: 1,
                        style: Type.display(
                          em * 1.35,
                          color: Palette.warning,
                          shadows: Type.glow(Palette.warning.withValues(alpha: 0.7), em),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
