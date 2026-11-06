import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../style.dart';

/// Half the side of a block in a cell one unit wide: a little room is left
/// round it for the gap between blocks and its shadow.
const blockHalf = 0.455;

/// The block, in a cell one unit wide centred on the origin: a cut stone
/// with four bevels lit from the top left, a domed face with a gloss on its
/// upper half and a glint, a dark rim that keeps neighbours apart, and a
/// soft shadow under it.
void paintBlock(Canvas canvas, BlockTones tones) {
  const h = blockHalf;
  const bevel = 0.1;
  final body = RRect.fromLTRBR(-h, -h, h, h, const Radius.circular(0.16));
  final outer = body.outerRect;
  final inner = outer.deflate(bevel);
  final base = tones.base;
  Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  // The shadow it casts on what is under it.
  canvas.drawRRect(
    body.shift(const Offset(0, 0.03)),
    Paint()..color = const Color(0x5C000000),
  );

  // Four bevels, each its own tone, meeting at the corners like a cut stone.
  canvas.save();
  canvas.clipRRect(body);
  Path facet(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();
  final paint = Paint()..isAntiAlias = true;
  canvas.drawPath(
    facet(outer.topLeft, outer.topRight, inner.topRight, inner.topLeft),
    paint..color = mix(tones.light, const Color(0xFFFFFFFF), 0.2),
  );
  canvas.drawPath(
    facet(outer.topLeft, inner.topLeft, inner.bottomLeft, outer.bottomLeft),
    paint..color = mix(base, tones.light, 0.6),
  );
  canvas.drawPath(
    facet(outer.topRight, outer.bottomRight, inner.bottomRight, inner.topRight),
    paint..color = mix(base, tones.dark, 0.55),
  );
  canvas.drawPath(
    facet(
      outer.bottomLeft,
      inner.bottomLeft,
      inner.bottomRight,
      outer.bottomRight,
    ),
    paint..color = mix(tones.dark, const Color(0xFF000000), 0.12),
  );
  canvas.restore();

  // The face, domed: lightest towards the light, darker at its far edge.
  final face = RRect.fromRectAndRadius(inner, const Radius.circular(0.075));
  canvas.drawRRect(
    face,
    Paint()
      ..shader = ui.Gradient.radial(
        const Offset(-0.13, -0.15),
        0.56,
        [mix(base, tones.light, 0.42), base, mix(base, tones.dark, 0.3)],
        const [0, 0.55, 1],
      ),
  );

  // A gloss over the upper half of the face, and a glint in its corner.
  final gloss = RRect.fromLTRBR(
    inner.left + 0.03,
    inner.top + 0.025,
    inner.right - 0.03,
    inner.top + 0.3,
    const Radius.circular(0.06),
  );
  canvas.drawRRect(
    gloss,
    Paint()
      ..shader = ui.Gradient.linear(
        gloss.outerRect.topCenter,
        gloss.outerRect.bottomCenter,
        const [Color(0x6BFFFFFF), Color(0x08FFFFFF)],
      ),
  );
  canvas.drawCircle(
    const Offset(-0.2, -0.205),
    0.08,
    Paint()
      ..shader = ui.Gradient.radial(const Offset(-0.2, -0.205), 0.08, const [
        Color(0xD9FFFFFF),
        Color(0x00FFFFFF),
      ]),
  );

  // A dark rim round it all.
  canvas.drawRRect(
    body.deflate(0.006),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.014
      ..color = mix(
        tones.dark,
        const Color(0xFF000000),
        0.35,
      ).withValues(alpha: 0.7),
  );
}
