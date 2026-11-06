import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../style.dart';

/// Half the side of a block in a cell one unit wide: a little room is left
/// round it for the gap between blocks and its shadow.
const blockHalf = 0.455;

/// What a mark on a block's face is drawn in.
enum MarkInk {
  /// Dark, pressed into a light face: the pips of ivory dice.
  carved,

  /// White, standing on a coloured face.
  raised,

  /// The block's own colour, from its dark tone (shade 0) to its light one
  /// (shade 1): a gem's facets, a neon tube.
  tone,
}

/// One mark on a block's face — a pip, a sign, a gem's facet — as a polygon
/// round its centre that every point of it can be seen from (a star, a plus,
/// a circle, a facet), so that it is drawn as a fan from the centre, flat or
/// in 3D. Face coordinates go from -0.5 to 0.5, y down.
class FaceMark {
  const FaceMark(this.centre, this.points, {this.ink, this.shade = 0.5});

  final Offset centre;

  /// The outline, relative to [centre].
  final List<Offset> points;

  /// Its own ink; the skin's when null.
  final MarkInk? ink;

  /// For [MarkInk.tone]: from the dark tone, 0, to the light one, 1.
  final double shade;
}

/// The ink of [skin]'s marks that do not name their own.
MarkInk markInk(BlockSkin skin) => skin == BlockSkin.dice ? MarkInk.carved : MarkInk.raised;

/// The colour of [mark] of a block of [tones] in [skin]. A white mark on a
/// light block is drawn dark instead, so that it still shows; a tone runs
/// from the dark one through the full colour, at a half, to the light one.
Color markColour(FaceMark mark, BlockSkin skin, BlockTones tones) => switch (mark.ink ?? markInk(skin)) {
  MarkInk.carved => const Color(0xFF221F2A),
  MarkInk.raised when skin.body != BlockBody.gem && tones.base.computeLuminance() > 0.72 => const Color(0xFF2A2633),
  MarkInk.raised => const Color(0xF7FFFFFF),
  MarkInk.tone => mark.shade < 0.5
      ? Color.lerp(tones.dark, tones.base, mark.shade * 2)!
      : Color.lerp(tones.base, tones.light, (mark.shade - 0.5) * 2)!,
};

/// The marks on a block of colour [slot] in [skin]: as many pips as the
/// slot's number on dice, the slot's sign on symbols, its cut on gems, the
/// tube on neon.
List<FaceMark> faceMarks(BlockSkin skin, int slot) => switch (skin) {
  BlockSkin.classic || BlockSkin.retro => const [],
  BlockSkin.dice || BlockSkin.colourDice => _pips[slot % _pips.length],
  BlockSkin.symbols => _signs[slot % _signs.length],
  BlockSkin.gems => _gems[slot % _gems.length],
  BlockSkin.neon => _tube,
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

/// The outline of each slot's gem: a ruby rhombus, a round sapphire, a
/// hexagonal topaz, an emerald-cut emerald, a trillion amethyst, an
/// octagonal diamond, a pentagonal fire opal, a princess aquamarine and an
/// oval pink sapphire.
final List<List<Offset>> _gemOutlines = [
  const [Offset(0, -0.44), Offset(0.31, 0), Offset(0, 0.44), Offset(-0.31, 0)],
  _polygon(14, 0.39),
  _polygon(6, 0.41, turn: 0),
  const [
    Offset(-0.2, -0.42), Offset(0.2, -0.42), Offset(0.32, -0.3), Offset(0.32, 0.3),
    Offset(0.2, 0.42), Offset(-0.2, 0.42), Offset(-0.32, 0.3), Offset(-0.32, -0.3),
  ],
  _polygon(3, 0.45, shift: const Offset(0, 0.08)),
  _polygon(8, 0.4, turn: -math.pi / 8),
  _polygon(5, 0.42, shift: const Offset(0, 0.03)),
  _polygon(4, 0.43, turn: -math.pi / 4),
  [for (var i = 0; i < 14; i++) Offset(math.cos(i * 2 * math.pi / 14) * 0.3, math.sin(i * 2 * math.pi / 14) * 0.42)],
];

/// A gem cut from [outline]: a facet between each edge and the table, each
/// as bright as it faces the light at the top left, the table on top, and a
/// glint on it.
List<FaceMark> _cut(List<Offset> outline) {
  final centre = outline.reduce((a, b) => a + b) / outline.length.toDouble();
  final table = [for (final p in outline) centre + (p - centre) * 0.52 + const Offset(-0.012, -0.018)];
  const light = Offset(-0.6, -0.8);
  final marks = <FaceMark>[];
  for (var i = 0; i < outline.length; i++) {
    final j = (i + 1) % outline.length;
    final quad = [outline[i], outline[j], table[j], table[i]];
    final middle = quad.reduce((a, b) => a + b) / 4;
    final out = (outline[i] + outline[j]) / 2 - centre;
    final facing = (out.dx * light.dx + out.dy * light.dy) / math.max(out.distance, 1e-6);
    // Neighbouring facets alternate a little, as a cut stone catches light.
    final shade = (0.5 + 0.42 * facing + (i.isEven ? 0.06 : -0.06)).clamp(0.0, 1.0);
    marks.add(FaceMark(middle, [for (final p in quad) p - middle], ink: MarkInk.tone, shade: shade));
  }
  final tableCentre = table.reduce((a, b) => a + b) / table.length.toDouble();
  marks.add(FaceMark(tableCentre, [for (final p in table) p - tableCentre], ink: MarkInk.tone, shade: 0.78));
  marks.add(FaceMark(tableCentre + const Offset(-0.07, -0.08), _star(4, 0.075, 0.018), ink: MarkInk.raised));
  return marks;
}

final List<List<FaceMark>> _gems = [for (final outline in _gemOutlines) _cut(outline)];

/// A neon tube round the face: four bars, lit.
final List<FaceMark> _tube = () {
  const r = 0.31, w = 0.035;
  FaceMark bar(Rect rect) => FaceMark(rect.center, [
        rect.topLeft - rect.center,
        rect.topRight - rect.center,
        rect.bottomRight - rect.center,
        rect.bottomLeft - rect.center,
      ], ink: MarkInk.tone, shade: 1);
  return [
    bar(const Rect.fromLTRB(-r - w, -r - w, r + w, -r + w)),
    bar(const Rect.fromLTRB(-r - w, r - w, r + w, r + w)),
    bar(const Rect.fromLTRB(-r - w, -r + w, -r + w, r - w)),
    bar(const Rect.fromLTRB(r - w, -r + w, r + w, r - w)),
  ];
}();

/// The block of colour [slot] in [skin], in a cell one unit wide centred on
/// the origin: its body (see [BlockBody]) and on it the skin's marks.
void paintBlock(Canvas canvas, BlockTones tones, {BlockSkin skin = BlockSkin.classic, int slot = 0}) {
  canvas.save();
  // Nothing leaves the cell: neighbours in an atlas stay clean.
  canvas.clipRect(const Rect.fromLTRB(-0.5, -0.5, 0.5, 0.5));
  switch (skin.body) {
    case BlockBody.stone:
      _paintStone(canvas, tones, bevel: 0.1, radius: 0.16, gloss: 1);
    case BlockBody.die:
      _paintStone(canvas, tones, bevel: 0.075, radius: 0.2, gloss: 0.6);
    case BlockBody.retro:
      _paintRetro(canvas, tones);
    case BlockBody.neon:
      _paintNeon(canvas, tones);
    case BlockBody.gem:
      // A soft shadow the gem casts, then the gem.
      final outline = _gemOutlines[slot % _gemOutlines.length];
      canvas.drawPath(
        Path()..addPolygon([for (final p in outline) p + const Offset(0.012, 0.03)], true),
        Paint()..color = const Color(0x66000000),
      );
  }
  _paintMarks(canvas, tones, skin, faceMarks(skin, slot));
  if (skin.body == BlockBody.gem) {
    // A dark line round the stone keeps it crisp on any field.
    canvas.drawPath(
      Path()..addPolygon(_gemOutlines[slot % _gemOutlines.length], true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.014
        ..strokeJoin = StrokeJoin.round
        ..color = Color.lerp(tones.dark, const Color(0xFF000000), 0.4)!.withValues(alpha: 0.8),
    );
  }
  canvas.restore();
}

void _paintMarks(Canvas canvas, BlockTones tones, BlockSkin skin, List<FaceMark> marks) {
  for (final mark in marks) {
    final path = Path()..addPolygon([for (final p in mark.points) mark.centre + p], true);
    final ink = mark.ink ?? markInk(skin);
    switch (ink) {
      case MarkInk.carved:
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
      case MarkInk.raised when skin.body != BlockBody.gem:
        // Standing out: a shadow under it, the white on top.
        canvas.drawPath(path.shift(const Offset(0, 0.016)), Paint()..color = const Color(0x59000000));
        canvas.drawPath(path, Paint()..color = markColour(mark, skin, tones));
      case MarkInk.raised || MarkInk.tone:
        // Facets meet without a seam: each is drawn a hair larger.
        canvas.drawPath(
          path,
          Paint()
            ..color = markColour(mark, skin, tones)
            ..style = PaintingStyle.fill,
        );
        if (ink == MarkInk.tone) {
          canvas.drawPath(
            path,
            Paint()
              ..color = markColour(mark, skin, tones)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 0.006,
          );
        }
    }
  }
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

Path _facet(Offset a, Offset b, Offset c, Offset d) => Path()
  ..moveTo(a.dx, a.dy)
  ..lineTo(b.dx, b.dy)
  ..lineTo(c.dx, c.dy)
  ..lineTo(d.dx, d.dy)
  ..close();

void _paintStone(Canvas canvas, BlockTones tones, {required double bevel, required double radius, required double gloss}) {
  const h = blockHalf;
  final body = RRect.fromLTRBR(-h, -h, h, h, Radius.circular(radius));
  final outer = body.outerRect;
  final inner = outer.deflate(bevel);
  final base = tones.base;

  // The shadow it casts on what is under it.
  canvas.drawRRect(body.shift(const Offset(0, 0.03)), Paint()..color = const Color(0x5C000000));

  // Four bevels, each its own tone, meeting at the corners like a cut stone.
  canvas.save();
  canvas.clipRRect(body);
  final paint = Paint();
  canvas.drawPath(
    _facet(outer.topLeft, outer.topRight, inner.topRight, inner.topLeft),
    paint..color = _mix(tones.light, const Color(0xFFFFFFFF), 0.2),
  );
  canvas.drawPath(
    _facet(outer.topLeft, inner.topLeft, inner.bottomLeft, outer.bottomLeft),
    paint..color = _mix(base, tones.light, 0.6),
  );
  canvas.drawPath(
    _facet(outer.topRight, outer.bottomRight, inner.bottomRight, inner.topRight),
    paint..color = _mix(base, tones.dark, 0.55),
  );
  canvas.drawPath(
    _facet(outer.bottomLeft, inner.bottomLeft, inner.bottomRight, outer.bottomRight),
    paint..color = _mix(tones.dark, const Color(0xFF000000), 0.12),
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
        [_mix(base, tones.light, 0.42), base, _mix(base, tones.dark, 0.3)],
        const [0, 0.55, 1],
      ),
  );

  // A gloss over the upper half of the face, and a glint in its corner.
  final shine = RRect.fromLTRBR(inner.left + 0.03, inner.top + 0.025, inner.right - 0.03, inner.top + 0.3,
      const Radius.circular(0.06));
  canvas.drawRRect(
    shine,
    Paint()
      ..shader = ui.Gradient.linear(shine.outerRect.topCenter, shine.outerRect.bottomCenter, [
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
      ..color = _mix(tones.dark, const Color(0xFF000000), 0.35).withValues(alpha: 0.7),
  );
}

/// The old games' block: square, four hard bevels of four tones round a flat
/// face, and a glint of white in its corner.
void _paintRetro(Canvas canvas, BlockTones tones) {
  const h = 0.47;
  const outer = Rect.fromLTRB(-h, -h, h, h);
  final inner = outer.deflate(0.13);
  final base = tones.base;
  final paint = Paint()..isAntiAlias = false;
  canvas.drawRect(outer, paint..color = _mix(tones.dark, const Color(0xFF000000), 0.45));
  final body = outer.deflate(0.02);
  final face = body.deflate(0.11);
  canvas.drawPath(_facet(body.topLeft, body.topRight, face.topRight, face.topLeft), paint..color = _mix(tones.light, const Color(0xFFFFFFFF), 0.3));
  canvas.drawPath(_facet(body.topLeft, face.topLeft, face.bottomLeft, body.bottomLeft), paint..color = _mix(base, tones.light, 0.45));
  canvas.drawPath(_facet(body.topRight, body.bottomRight, face.bottomRight, face.topRight), paint..color = _mix(base, tones.dark, 0.5));
  canvas.drawPath(_facet(body.bottomLeft, face.bottomLeft, face.bottomRight, body.bottomRight), paint..color = tones.dark);
  canvas.drawRect(face, paint..color = base);
  // The glint: a square and a short stroke, as the pixels of old.
  final glint = Rect.fromLTWH(inner.left + 0.02, inner.top + 0.02, 0.075, 0.075);
  canvas.drawRect(glint, paint..color = const Color(0xE6FFFFFF));
  canvas.drawRect(Rect.fromLTWH(glint.right, glint.top, 0.12, 0.035), paint..color = const Color(0x8CFFFFFF));
}

/// Dark glass with a glow of its colour round a tube of light (the marks).
void _paintNeon(Canvas canvas, BlockTones tones) {
  const h = 0.44;
  final body = RRect.fromLTRBR(-h, -h, h, h, const Radius.circular(0.12));
  final colour = tones.base;
  // The glass: nearly black, tinted, darkest in its middle.
  canvas.drawRRect(
    body,
    Paint()
      ..shader = ui.Gradient.radial(Offset.zero, 0.6, [
        _mix(const Color(0xFF07060C), colour, 0.06),
        _mix(const Color(0xFF07060C), colour, 0.24),
      ]),
  );
  // The glow round the tube: wide and faint to narrow and bright.
  final tube = RRect.fromLTRBR(-0.31, -0.31, 0.31, 0.31, const Radius.circular(0.04));
  for (final (width, alpha) in [(0.2, 0.08), (0.13, 0.16), (0.085, 0.3)]) {
    canvas.drawRRect(
      tube,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = width
        ..color = colour.withValues(alpha: alpha),
    );
  }
  // The glass's rim, catching the light.
  canvas.drawRRect(
    body.deflate(0.006),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.012
      ..color = colour.withValues(alpha: 0.35),
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
