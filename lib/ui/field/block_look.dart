import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../style.dart';

/// Half the side of a block in a cell one unit wide: a little room is left
/// round it for the gap between blocks and its shadow.
const blockHalf = 0.455;

/// One mark on a block's face — a pip — as a polygon round its centre that
/// every point of it can be seen from, so that it is drawn as a fan from the
/// centre, flat or in 3D. Face coordinates go from -0.5 to 0.5, y down.
class FaceMark {
  const FaceMark(this.centre, this.points);

  final Offset centre;

  /// The outline, relative to [centre].
  final List<Offset> points;
}

/// The colour of a mark on a block of [tones]: white, or dark on a block too
/// light for white to show.
Color markColour(BlockTones tones) =>
    tones.base.computeLuminance() > 0.72 ? const Color(0xFF2A2633) : const Color(0xF7FFFFFF);

/// The marks on a block of colour [slot] in [skin]: as many pips as the
/// slot's number on dice, none on the others.
List<FaceMark> faceMarks(BlockSkin skin, int slot) => switch (skin) {
  BlockSkin.classic || BlockSkin.retro => const [],
  BlockSkin.colourDice => _pips[slot % _pips.length],
};

List<Offset> _polygon(int sides, double radius) => [
  for (var i = 0; i < sides; i++)
    Offset(math.cos(-math.pi / 2 + i * 2 * math.pi / sides), math.sin(-math.pi / 2 + i * 2 * math.pi / sides)) * radius,
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

/// The block of colour [slot] in [skin], in a cell one unit wide centred on
/// the origin: its body (see [BlockBody]) and on it the skin's marks.
void paintBlock(Canvas canvas, BlockTones tones, {BlockSkin skin = BlockSkin.classic, int slot = 0}) {
  canvas.save();
  // Nothing leaves the cell: neighbours in an atlas stay clean.
  canvas.clipRect(const Rect.fromLTRB(-0.5, -0.5, 0.5, 0.5));
  switch (skin.body) {
    case BlockBody.stone:
      _paintCushion(canvas, tones, radius: 0.17, gloss: 1);
    case BlockBody.die:
      _paintCushion(canvas, tones, radius: 0.21, gloss: 0.7);
    case BlockBody.retro:
      _paintRetro(canvas, tones);
  }
  final ink = markColour(tones);
  for (final mark in faceMarks(skin, slot)) {
    // Standing out: a shadow under it, the mark on top.
    final path = Path()..addPolygon([for (final p in mark.points) mark.centre + p], true);
    canvas.drawPath(path.shift(const Offset(0, 0.016)), Paint()..color = const Color(0x59000000));
    canvas.drawPath(path, Paint()..color = ink);
  }
  canvas.restore();
}

Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

const _white = Color(0xFFFFFFFF);
const _black = Color(0xFF000000);

/// A cushion of the block's colour: one piece with no seam, its edges round
/// — the light running down them at the top left, the shade at the bottom
/// right — its middle domed towards the light, a soft gloss and a glint.
void _paintCushion(Canvas canvas, BlockTones tones, {required double radius, required double gloss}) {
  const h = blockHalf;
  final body = RRect.fromLTRBR(-h, -h, h, h, Radius.circular(radius));
  final base = tones.base;

  // The shadow it casts on what is under it.
  canvas.drawRRect(body.shift(const Offset(0, 0.03)), Paint()..color = const Color(0x5C000000));

  // The block's slope, lit at the top left.
  canvas.drawRRect(
    body,
    Paint()
      ..shader = ui.Gradient.linear(
        const Offset(-h, -h),
        const Offset(h, h),
        [_mix(base, tones.light, 0.45), base, _mix(base, tones.dark, 0.5)],
        const [0, 0.5, 1],
      ),
  );

  canvas.save();
  canvas.clipRRect(body);
  // The round edge: rings from the rim inwards, each fainter, lit towards
  // the top left and shaded towards the bottom right.
  const rings = 8;
  for (var i = 0; i < rings; i++) {
    final ring = body.deflate(0.007 + i * 0.015);
    final strength = math.pow(1 - i / rings, 1.6).toDouble();
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.016
        ..shader = ui.Gradient.linear(const Offset(-h, -h), const Offset(0.1, 0.1), [
          _white.withValues(alpha: 0.42 * strength),
          _white.withValues(alpha: 0),
        ]),
    );
    canvas.drawRRect(
      ring,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.016
        ..shader = ui.Gradient.linear(const Offset(h, h), const Offset(-0.1, -0.1), [
          _black.withValues(alpha: 0.42 * strength),
          _black.withValues(alpha: 0),
        ]),
    );
  }

  // The middle, domed towards the light.
  canvas.drawRRect(
    body,
    Paint()
      ..shader = ui.Gradient.radial(const Offset(-0.1, -0.14), 0.5, [
        _mix(base, tones.light, 0.35).withValues(alpha: 0.75),
        base.withValues(alpha: 0),
      ]),
  );

  // A soft gloss across the top, and a glint in its corner.
  canvas.save();
  canvas.translate(-0.03, -0.2);
  canvas.scale(1, 0.42);
  canvas.drawCircle(
    Offset.zero,
    0.34,
    Paint()
      ..shader = ui.Gradient.radial(Offset.zero, 0.34, [
        _white.withValues(alpha: 0.5 * gloss),
        _white.withValues(alpha: 0.12 * gloss),
        _white.withValues(alpha: 0),
      ], const [0, 0.6, 1]),
  );
  canvas.restore();
  canvas.drawCircle(
    const Offset(-0.22, -0.22),
    0.075,
    Paint()
      ..shader = ui.Gradient.radial(const Offset(-0.22, -0.22), 0.075, [
        _white.withValues(alpha: 0.85 * gloss),
        _white.withValues(alpha: 0),
      ]),
  );
  canvas.restore();

  // A dark rim round it all keeps neighbours apart.
  canvas.drawRRect(
    body.deflate(0.006),
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.012
      ..color = _mix(tones.dark, _black, 0.35).withValues(alpha: 0.6),
  );
}

Path _facet(Offset a, Offset b, Offset c, Offset d) => Path()
  ..moveTo(a.dx, a.dy)
  ..lineTo(b.dx, b.dy)
  ..lineTo(c.dx, c.dy)
  ..lineTo(d.dx, d.dy)
  ..close();

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
      final tones = BlockTones.fromBase(colours[slot % colours.length]);
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
