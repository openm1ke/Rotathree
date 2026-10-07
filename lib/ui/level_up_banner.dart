import 'package:flutter/material.dart';

import '../game/config/zen_levels.dart';
import 'hud.dart';
import 'style.dart';

/// Zen: the announcement of a new level, played over the field while the
/// game stands still. Dims the field, sweeps a band of light across it and
/// slams the level number down; fades out by itself after [seconds].
class LevelUpBanner extends StatelessWidget {
  const LevelUpBanner({
    super.key,
    required this.level,
    required this.seconds,
    required this.em,
  });

  /// The level that has just begun.
  final int level;
  final double seconds;

  /// Unit all sizes are derived from: a 34th of the field.
  final double em;

  static double _window(double t, double fadeIn, double fadeOutFrom) {
    if (t < fadeIn) return t / fadeIn;
    if (t > fadeOutFrom) return (1 - t) / (1 - fadeOutFrom);
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: (seconds * 1000).round()),
      builder: (context, t, _) {
        final shown = _window(t, 0.1, 0.8).clamp(0.0, 1.0);
        final sweep = Motion.snap.transform(((t - 0.03) / 0.46).clamp(0.0, 1.0));
        final slam = Motion.back.transform((t / 0.26).clamp(0.0, 1.0));
        return ClipRect(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // The field dims; the dimming fades out towards its edges so
              // that the square of the field does not show against the rest
              // of the screen.
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    radius: 0.72,
                    colors: [
                      Palette.bg.withValues(alpha: 0.5 * shown),
                      Palette.bg.withValues(alpha: 0.34 * shown),
                      Palette.bg.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.7, 1],
                  ),
                ),
              ),
              // A slanted band of light crossing the field once.
              FractionalTranslation(
                translation: Offset(-1.2 + 2.4 * sweep, 0),
                child: Transform(
                  transform: Matrix4.skewX(-0.28),
                  alignment: Alignment.center,
                  child: const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x00FFFFFF),
                          Color(0x297DF0C5),
                          Color(0x80FFFFFF),
                          Color(0x2978CDFF),
                          Color(0x00FFFFFF),
                        ],
                        stops: [0.36, 0.45, 0.5, 0.55, 0.64],
                      ),
                    ),
                  ),
                ),
              ),
              Center(
                child: Opacity(
                  opacity: shown,
                  child: Transform.scale(
                    scaleY: 0.2 + 0.8 * shown,
                    child: Container(
                      width: double.infinity,
                      padding: EdgeInsets.symmetric(vertical: em * 1.3),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Palette.bg.withValues(alpha: 0),
                            Palette.bg.withValues(alpha: 0.84),
                            Palette.bg.withValues(alpha: 0.84),
                            Palette.bg.withValues(alpha: 0),
                          ],
                          stops: const [0, 0.2, 0.8, 1],
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'УРОВЕНЬ ${level - 1} ПРОЙДЕН',
                            style: Type.label(em * 1.05, color: Palette.zen),
                          ),
                          SizedBox(height: em * 0.5),
                          Transform.scale(
                            scale: 1.9 - 0.9 * slam,
                            child: Text.rich(
                              TextSpan(
                                text: 'УРОВЕНЬ ',
                                children: [
                                  TextSpan(
                                    text: '$level',
                                    style: const TextStyle(color: Palette.zen),
                                  ),
                                ],
                              ),
                              style: Type.display(
                                em * 4.4,
                                shadows: Type.glow(
                                  Palette.zen.withValues(alpha: 0.55),
                                  em * 2,
                                ),
                              ),
                            ),
                          ),
                          SizedBox(height: em * 0.6),
                          Text(
                            'Цель · ${formatScore(ZenLevels.target(level))} очков',
                            style: Type.body(em * 1.05, color: Palette.textDim),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
