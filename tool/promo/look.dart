// The promo's look, after the key art: glowing words in Exo 2 over the
// night of glowing lines, the game in a frame of neon.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'captions.dart';

const cyan = Color(0xFF78CDFF);
const pink = Color(0xFFFF3D8B);
const violet = Color(0xFFAB50FA);
const navy = Color(0xFF070A1A);

/// The wordmark's letters: ROTA in white, THREE in the brand's colours.
const _wordmark = [
  ('ROTA', Colors.white),
  ('T', Color(0xFFFF145E)),
  ('H', Color(0xFF1689FF)),
  ('R', Color(0xFFFFC400)),
  ('E', Color(0xFF00D982)),
  ('E', Color(0xFFAB50FA)),
];

TextStyle exo(double size, FontWeight weight, {bool italic = false, Color color = Colors.white, List<Shadow>? glow, double? spacing}) =>
    TextStyle(
      fontFamily: 'Exo2',
      fontFamilyFallback: const ['Exo2Cyrillic'],
      fontSize: size,
      fontWeight: weight,
      fontStyle: italic ? FontStyle.italic : FontStyle.normal,
      color: color,
      shadows: glow,
      letterSpacing: spacing,
      height: 1.05,
    );

/// The key art behind, dimmed, darker at the top for the words.
class KeyartBackground extends StatelessWidget {
  const KeyartBackground({super.key, required this.image, this.zoom = 1, this.dim = true});

  final ui.Image image;
  final double zoom;
  final bool dim;

  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      const ColoredBox(color: navy),
      Transform.scale(scale: zoom, child: RawImage(image: image, fit: BoxFit.cover)),
      if (dim)
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [navy.withValues(alpha: 0.82), navy.withValues(alpha: 0.45), navy.withValues(alpha: 0.62)],
              stops: const [0, 0.45, 1],
            ),
          ),
        ),
    ],
  );
}

/// The kicker, the title on one line and the line under it, centred.
class CaptionBlock extends StatelessWidget {
  const CaptionBlock({super.key, required this.caption, required this.base, this.titleScale = 1});

  final Caption caption;

  /// The size the words are measured against.
  final double base;
  final double titleScale;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Text(
        caption.kicker.toUpperCase(),
        textAlign: TextAlign.center,
        style: exo(base * 0.036, FontWeight.w800, color: cyan, spacing: base * 0.006, glow: [
          Shadow(color: cyan.withValues(alpha: 0.7), blurRadius: base * 0.02),
        ]),
      ),
      SizedBox(height: base * 0.018),
      // One line, shrunk to fit a long title.
      FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          caption.title.toUpperCase(),
          maxLines: 1,
          style: exo(base * 0.098 * titleScale, FontWeight.w900, italic: true, glow: [
            Shadow(color: pink.withValues(alpha: 0.55), blurRadius: base * 0.035),
            Shadow(color: cyan.withValues(alpha: 0.35), blurRadius: base * 0.07),
          ]),
        ),
      ),
      if (caption.line.isNotEmpty) ...[
        SizedBox(height: base * 0.022),
        Text(
          caption.line,
          textAlign: TextAlign.center,
          maxLines: 2,
          style: exo(base * 0.042, FontWeight.w600, color: Colors.white.withValues(alpha: 0.88)),
        ),
      ],
    ],
  );
}

/// ROTATHREE as the menu sets it.
class Wordmark extends StatelessWidget {
  const Wordmark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        for (final (letters, colour) in _wordmark)
          TextSpan(text: letters, style: exo(size, FontWeight.w900, italic: true, color: colour)),
      ],
    ),
  );
}

/// A rounded frame of neon light round [child].
class NeonFrame extends StatelessWidget {
  const NeonFrame({super.key, required this.base, required this.radius, required this.child});

  final double base, radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final border = base * 0.006;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius + border),
        gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [cyan, violet, pink]),
        boxShadow: [
          BoxShadow(color: cyan.withValues(alpha: 0.45), blurRadius: base * 0.07, spreadRadius: base * 0.004),
          BoxShadow(color: pink.withValues(alpha: 0.3), blurRadius: base * 0.12, offset: Offset(0, base * 0.03)),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.all(border),
        child: ClipRRect(borderRadius: BorderRadius.circular(radius), child: child),
      ),
    );
  }
}

/// Part of a picture, [source] in its pixels, drawn to fill the box.
class Cropped extends StatelessWidget {
  const Cropped({super.key, required this.image, required this.source});

  final ui.Image image;
  final Rect source;

  @override
  Widget build(BuildContext context) => CustomPaint(painter: _CropPainter(image, source), size: Size.infinite);
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.image, this.source);

  final ui.Image image;
  final Rect source;

  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawImageRect(image, source, Offset.zero & size, Paint()..filterQuality = FilterQuality.high);

  @override
  bool shouldRepaint(_CropPainter old) => old.image != image || old.source != source;
}

/// Where the game is on a device's screen, in parts of its height: the
/// field with its incoming sticks, and the pads at the bottom. Between and
/// above them the app leaves room that a store screenshot need not show.
class ScreenLayout {
  const ScreenLayout(this.fieldTop, this.fieldBottom, this.padsTop);

  final double fieldTop, fieldBottom, padsTop;
}

const layouts = {
  'iphone-6.9': ScreenLayout(0.205, 0.69, 0.835),
  'ipad-13': ScreenLayout(0.085, 0.825, 0.865),
};

/// The game as large as [window] lets it be: the field enlarged, as near as
/// it can be without losing its top or bottom or more than a tenth at each
/// side, the pads under it and the empty room between cut out. A [list]
/// screen is shown from its top instead, as wide as the window.
class GameWindow extends StatelessWidget {
  const GameWindow({
    super.key,
    required this.shot,
    required this.layout,
    required this.window,
    this.list = false,
    this.centre = 0.5,
  });

  final ui.Image shot;
  final ScreenLayout layout;
  final Size window;
  final bool list;
  final double centre;

  @override
  Widget build(BuildContext context) {
    final rawWidth = shot.width.toDouble(), rawHeight = shot.height.toDouble();
    if (list) {
      // A screen too short to be as wide as the window is shown whole.
      final scale = window.width / rawWidth;
      if (window.height / scale <= rawHeight) {
        return Cropped(image: shot, source: Rect.fromLTWH(0, 0, rawWidth, window.height / scale));
      }
      return ColoredBox(color: navy, child: Center(child: RawImage(image: shot, fit: BoxFit.contain)));
    }
    final padsHeight = (1 - layout.padsTop) * rawHeight;
    final padsShown = padsHeight * window.width / rawWidth;
    final fieldShown = window.height - padsShown;
    final field = (layout.fieldBottom - layout.fieldTop) * rawHeight;
    final span = (window.width * field / fieldShown / rawWidth).clamp(0.8, 1.0) * rawWidth;
    final scale = window.width / span;
    final sourceHeight = (fieldShown / scale).clamp(0.0, rawHeight);
    final left = (centre * rawWidth - span / 2).clamp(0.0, rawWidth - span);
    final middle = (layout.fieldTop + layout.fieldBottom) / 2 * rawHeight;
    final top = (middle - sourceHeight / 2).clamp(0.0, rawHeight - sourceHeight);
    final overlap = padsShown * 0.3;
    return Stack(
      children: [
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: fieldShown + overlap,
          child: Cropped(image: shot, source: Rect.fromLTWH(left, top, span, sourceHeight + overlap / scale)),
        ),
        // The pads fade in over the field's empty bottom.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: padsShown,
          child: ShaderMask(
            blendMode: BlendMode.dstIn,
            shaderCallback: (bounds) => const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.white],
              stops: [0, 0.3],
            ).createShader(bounds),
            child: Cropped(image: shot, source: Rect.fromLTWH(0, layout.padsTop * rawHeight, rawWidth, padsHeight)),
          ),
        ),
      ],
    );
  }
}
