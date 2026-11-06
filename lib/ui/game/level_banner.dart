import '../i18n/strings.dart';
import 'package:flutter/material.dart';

import '../field/block_look.dart';
import '../style.dart';

/// What a banner says, which picks its badge.
enum BannerKind {
  /// A level was finished.
  passed(Icons.emoji_events_rounded),

  /// A new number of colours: a fresh board.
  stage(Icons.auto_awesome_rounded),

  /// A glass more in play.
  glass(Icons.add_box_rounded),

  /// The next level of the same board.
  level(Icons.flag_rounded);

  const BannerKind(this.icon);

  final IconData icon;
}

/// A message over the field: a level finished, a new stage, a new glass.
class BannerData {
  const BannerData({
    required this.id,
    required this.kicker,
    required this.title,
    this.sub,
    this.colours = const [],
    this.kind = BannerKind.level,
  });

  final int id;
  final String kicker;
  final String title;
  final String? sub;

  /// Colours of the stage, shown as blocks.
  final List<Color> colours;
  final BannerKind kind;
}

/// A small card that pops up over the field: a badge for what happened, its
/// kicker and title, what comes next on a pill, and a new stage's colours
/// as blocks drawn as the field draws them.
class LevelBanner extends StatelessWidget {
  const LevelBanner({super.key, required this.banner});

  final BannerData banner;

  @override
  Widget build(BuildContext context) {
    final sub = banner.sub;
    return TweenAnimationBuilder<double>(
      key: ValueKey(banner.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 420),
      curve: Motion.back,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.scale(scale: 0.85 + 0.15 * t, child: child),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 220, maxWidth: 340),
        // A border of light round a dark glass, as on the pause.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Palette.accent.withValues(alpha: 0.75),
                Palette.violet.withValues(alpha: 0.5),
                Palette.pink.withValues(alpha: 0.55),
              ],
            ),
            boxShadow: [
              BoxShadow(color: Palette.accent.withValues(alpha: 0.28), blurRadius: 36, spreadRadius: -4),
              const BoxShadow(color: Color(0x99000000), blurRadius: 24, offset: Offset(0, 10)),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(1.5),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20.5),
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xF51B1A2C), Color(0xF50B0B14)],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _Badge(icon: banner.kind.icon),
                    const SizedBox(height: 10),
                    LText(
                      context.tr(banner.kicker).toUpperCase(),
                      translate: false,
                      textAlign: TextAlign.center,
                      style: Type.label(11, color: Palette.accent),
                    ),
                    const SizedBox(height: 4),
                    LText(
                      banner.title,
                      textAlign: TextAlign.center,
                      style: Type.display(28, height: 1.05, shadows: Type.glow(Palette.accent.withValues(alpha: 0.5), 16)),
                    ),
                    if (banner.colours.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      BlockRow(skin: BlockTones.skin, colours: banner.colours, height: 26),
                    ],
                    if (sub != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0x14FFFFFF),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: Palette.line),
                        ),
                        child: LText(sub, textAlign: TextAlign.center, style: Type.body(13, color: Palette.textDim)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// An icon in a ring of the accent colours.
class _Badge extends StatelessWidget {
  const _Badge({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: Container(
          width: 44,
          height: 44,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Palette.accent, Palette.violet],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [BoxShadow(color: Palette.accent.withValues(alpha: 0.4), blurRadius: 16)],
          ),
          child: DecoratedBox(
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF151423)),
            child: Icon(icon, size: 22, color: Palette.text),
          ),
        ),
      );
}
