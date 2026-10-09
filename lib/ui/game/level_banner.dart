import '../i18n/strings.dart';
import 'package:flutter/widgets.dart';

import '../style.dart';

/// A message over the field: a level finished, a new stage, a new glass.
class BannerData {
  const BannerData({
    required this.id,
    required this.kicker,
    required this.title,
    this.sub,
    this.colours = const [],
  });

  final int id;
  final String kicker;
  final String title;
  final String? sub;

  /// Colours of the stage, shown as dots.
  final List<Color> colours;
}

class LevelBanner extends StatelessWidget {
  const LevelBanner({super.key, required this.banner});

  final BannerData banner;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      key: ValueKey(banner.id),
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 320),
      curve: Motion.back,
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(offset: Offset(0, (1 - t) * -12), child: child),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Palette.panelStrong,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.accent.withValues(alpha: 0.6)),
          boxShadow: [BoxShadow(color: Palette.accent.withValues(alpha: 0.25), blurRadius: 24)],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LText(banner.kicker.toUpperCase(), style: Type.label(11, color: Palette.accent)),
              const SizedBox(height: 2),
              LText(banner.title, style: Type.display(24), textAlign: TextAlign.center),
              if (banner.sub != null) ...[
                const SizedBox(height: 2),
                LText(banner.sub!, style: Type.body(13, color: Palette.textDim), textAlign: TextAlign.center),
              ],
              if (banner.colours.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final colour in banner.colours)
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
