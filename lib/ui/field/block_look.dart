import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../style.dart';

/// Half the side of a block in a cell one unit wide: a little room is left
/// round it for the gap between blocks and its shadow.
const blockHalf = 0.455;

/// One mark on a block's face — a pip, a sign — as a polygon round its
/// centre that every point of it can be seen from (a star, a plus, a
/// circle), so that it is drawn as a fan from the centre, flat or in 3D.
/// Face coordinates go from -0.5 to 0.5, y down.
class FaceMark {
  const FaceMark(this.centre, this.points);

  final Offset centre;

  /// The outline, relative to [centre].
  final List<Offset> points;
}

/// What the marks of a skin are drawn in.
enum MarkInk {
  /// Dark, pressed into a light face: the pips of ivory dice.
  carved,

  /// White, standing on a coloured face.
  raised,
}

/// The ink of [skin]'s marks; none for plain stones.
MarkInk? markInk(BlockSkin skin) => switch (skin) {
  BlockSkin.classic => null,
  BlockSkin.dice => MarkInk.carved,
  BlockSkin.colourDice || BlockSkin.symbols => MarkInk.raised,
};

/// The marks on a block of colour [slot] in [skin]: as many pips as the
/// slot's number on dice, the slot's sign on symbols.
List<FaceMark> faceMarks(BlockSkin skin, int slot) => switch (skin) {
  BlockSkin.classic => const [],
  BlockSkin.dice || BlockSkin.colourDice => _pips[(slot % _pips.length)],
  BlockSkin.symbols => _signs[slot % _signs.length],
};

List<Offset> _polygon(int sides, double radius, {double turn = -math.pi / 2, Offset shift = Offset.zero}) => [
  for (var i = 0; i < sides; i++)
    Offset(math.cos(turn + i * 2 * math.pi / sides), math.sin(turn + i * 2 * math.pi / sides)) * radius + shift,
];

List<Offset> _star(int points, double outer, double inner) => [
  for (var i = 0; i < 2 * points; i++)
    Offset(math.cos(-math.pi / 2 + i * math.pi / points), math.sin(-math.pi / 2 + i * math.pi / points)) *
        (i.isEven ? outer : inner),
];

/// Where the pips of one to nine are, as on dice, then as a three-by-three.
final List<List<FaceMark>> _pips = () {
  const d = 0.2;
  const layouts = <List<(int, int)>>[
    [(0, 0)],
    [(-1, -1), (1, 1)],
    [(-1, -1), (0, 0), (1, 1)],
    [(-1, -1), (1, -1), (-1, 1), (1, 1)],
    [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)],
    [(-1, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (1, 1)],
    [(-1, -1), (1, -1), (-1, 0), (0, 0), (1, 0), (-1, 1), (1, 1)],
    [(-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1)],
    [(-1, -1), (0, -1), (1, -1), (-1, 0), (0, 0), (1, 0), (-1, 1), (0, 1), (1, 1)],
  ];
  return [
    for (final layout in layouts)
      [
        for (final (x, y) in layout)
          FaceMark(Offset(x * d, y * d), _polygon(14, layout.length > 6 ? 0.062 : layout.length == 1 ? 0.1 : 0.072)),
      ],
  ];
}();

/// A sign for each slot: circle, triangle, square, diamond, star, hexagon,
/// plus, a triangle pointing down and a pentagon.
final List<List<FaceMark>> _signs = [
  [FaceMark(Offset.zero, _polygon(20, 0.165))],
  [FaceMark(const Offset(0, 0.035), _polygon(3, 0.215))],
  [FaceMark(Offset.zero, _polygon(4, 0.2, turn: -math.pi / 4))],
  [FaceMark(Offset.zero, _polygon(4, 0.215))],
  [FaceMark(const Offset(0, 0.015), _star(5, 0.23, 0.1))],
  [FaceMark(Offset.zero, _polygon(6, 0.19))],
  [
    const FaceMark(Offset.zero, [
      Offset(-0.06, -0.2), Offset(0.06, -0.2), Offset(0.06, -0.06), Offset(0.2, -0.06),
      Offset(0.2, 0.06), Offset(0.06, 0.06), Offset(0.06, 0.2), Offset(-0.06, 0.2),
      Offset(-0.06, 0.06), Offset(-0.2, 0.06), Offset(-0.2, -0.06), Offset(-0.06, -0.06),
    ]),
  ],
  [FaceMark(const Offset(0, -0.035), _polygon(3, 0.215, turn: math.pi / 2))],
  [FaceMark(const Offset(0, 0.01), _polygon(5, 0.195))],
];

/// The block of colour [slot] in [skin], in a cell one unit wide centred on
/// the origin: a cut stone with four bevels lit from the top left, a domed
/// face with a gloss and a glint, a dark rim and a soft shadow — rounder and
/// softer for dice — and on its face the skin's marks.
void paintBlock(Canvas canvas, BlockTones tones, {BlockSkin skin = BlockSkin.classic, int slot = 0}) {
  final dice = skin.isDice;
  _paintBody(canvas, tones, bevel: dice ? 0.075 : 0.1, radius: dice ? 0.2 : 0.16, gloss: dice ? 0.6 : 1);
  final marks = faceMarks(skin, slot);
  if (marks.isEmpty) return;
  final carved = markInk(skin) == MarkInk.carved;
  for (final mark in marks) {
    final path = Path()..addPolygon([for (final p in mark.points) mark.centre + p], true);
    if (carved) {
      // Pressed in: a lit lower lip, then the pit, darkest in its middle.
      canvas.drawPath(path.shift(const Offset(0.008, 0.012)), Paint()..color = const Color(0xB3FFFFFF));
      final radius = mark.points.first.distance;
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.radial(mark.centre - Offset(radius * 0.3, radius * 0.3), radius * 1.3, const [
            Color(0xFF15131C),
            Color(0xFF3B3644),
          ]),
      );
    } else {
      // Standing out: a shadow under it, the white on top.
      canvas.drawPath(path.shift(const Offset(0, 0.016)), Paint()..color = const Color(0x59000000));
      canvas.drawPath(path, Paint()..color = const Color(0xF7FFFFFF));
    }
  }
}

void _paintBody(Canvas canvas, BlockTones tones, {required double bevel, required double radius, required double gloss}) {
  const h = blockHalf;
  final body = RRect.fromLTRBR(-h, -h, h, h, Radius.circular(radius));
  final outer = body.outerRect;
  final inner = outer.deflate(bevel);
  final base = tones.base;
  Color mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  // The shadow it casts on what is under it.
  canvas.drawRRect(body.shift(const Offset(0, 0.03)), Paint()..color = const Color(0x5C000000));

  // Four bevels, each its own tone, meeting at the corners like a cut stone.
  canvas.save();
  canvas.clipRRect(body);
  Path facet(Offset a, Offset b, Offset c, Offset d) => Path()
    ..moveTo(a.dx, a.dy)
    ..lineTo(b.dx, b.dy)
    ..lineTo(c.dx, c.dy)
    ..lineTo(d.dx, d.dy)
    ..close();
  final paint = Paint();
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
    facet(outer.bottomLeft, inner.bottomLeft, inner.bottomRight, outer.bottomRight),
    paint..color = mix(tones.dark, const Color(0xFF000000), 0.12),
  );
  canvas.restore();

  // The face, domed: lightest towards the light, darker at its far edge.
  final face = RRect.fromRectAndRadius(inner, Radius.circular(math.max(0.04, radius - bevel)));
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
  final gloss_ = RRect.fromLTRBR(inner.left + 0.03, inner.top + 0.025, inner.right - 0.03, inner.top + 0.3,
      const Radius.circular(0.06));
  canvas.drawRRect(
    gloss_,
    Paint()
      ..shader = ui.Gradient.linear(gloss_.outerRect.topCenter, gloss_.outerRect.bottomCenter, [
        const Color(0xFFFFFFFF).withValues(alpha: 0.42 * gloss),
        const Color(0x08FFFFFF),
      ]),
  );
  canvas.drawCircle(
    const Offset(-0.2, -0.205),
    0.08,
    Paint()
      ..shader = ui.Gradient.radial(const Offset(-0.2, -0.205), 0.08, [
        const Color(0xFFFFFFFF).withValues(alpha: 0.85 * gloss),
        const Color(0x00FFFFFF),
      ]),
  );

  // A dark rim round it all.
  canvas.drawRRect(
    body.deflate(0.006),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.014
      ..color = mix(tones.dark, const Color(0xFF000000), 0.35).withValues(alpha: 0.7),
  );
}

/// A row of blocks of [colours] in [skin], drawn as the field draws them:
/// for the settings to show a look before it is chosen.
class BlockRow extends StatelessWidget {
  const BlockRow({super.key, required this.skin, required this.colours, this.count, this.height = 30});

  final BlockSkin skin;
  final List<Color> colours;

  /// How many of the slots are shown, from the first; all by default.
  final int? count;
  final double height;

  @override
  Widget build(BuildContext context) {
    final shown = count ?? colours.length;
    return ExcludeSemantics(
      child: SizedBox(
        height: height,
        width: height * shown,
        child: CustomPaint(painter: _BlockRowPainter(skin, colours, shown)),
      ),
    );
  }
}

class _BlockRowPainter extends CustomPainter {
  _BlockRowPainter(this.skin, this.colours, this.count);

  final BlockSkin skin;
  final List<Color> colours;
  final int count;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.height;
    for (var slot = 0; slot < count; slot++) {
      final tones = skin.coloured ? BlockTones.fromBase(colours[slot % colours.length]) : BlockTones.ivory;
      canvas.save();
      canvas.translate(unit * (slot + 0.5), unit / 2);
      canvas.scale(unit);
      paintBlock(canvas, tones, skin: skin, slot: slot);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BlockRowPainter old) => old.skin != skin || old.colours != colours || old.count != count;
}
