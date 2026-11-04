import 'package:flutter/material.dart';

import '../style.dart';

/// The classic set's colours for the little pictures (MainMenu.tsx).
const _red = 0, _blue = 1, _yellow = 2, _green = 3, _violet = 4, _orange = 6;

/// How a block of a tile's picture is drawn: whole, see-through, or as a thin
/// line across its row, under the blocks.
enum _Look { solid, faint, track }

/// A picture made of the game's own blocks: column, row and colour on a
/// three-by-three grid.
typedef _Block = (double x, double y, int colour, _Look look);

const _pictures = <String, List<_Block>>{
  // A play sign, stacked.
  'resume': [(0, 0, _green, _Look.solid), (0, 1, _green, _Look.solid), (0, 2, _green, _Look.solid),
      (1, 0.5, _green, _Look.solid), (1, 1.5, _green, _Look.solid), (2, 1, _green, _Look.solid)],
  // Three in a row, the game in one picture.
  'campaign': [(0, 2, _red, _Look.solid), (1, 2, _red, _Look.solid), (2, 2, _red, _Look.solid), (1, 1, _blue, _Look.solid)],
  // A cube: its front, and its back showing behind.
  'cube': [(1, 0, _blue, _Look.faint), (2, 0, _blue, _Look.faint), (2, 1, _blue, _Look.faint),
      (0, 1, _blue, _Look.solid), (1, 1, _blue, _Look.solid), (0, 2, _blue, _Look.solid), (1, 2, _blue, _Look.solid)],
  // A stick of three colours, as the player sets them.
  'custom': [(1, 0, _yellow, _Look.solid), (1, 1, _green, _Look.solid), (1, 2, _violet, _Look.solid)],
  // A stick coming down into the gap that makes the line.
  'tutorial': [(1, 0, _green, _Look.solid), (0, 2, _green, _Look.solid), (2, 2, _green, _Look.solid), (1, 2, _green, _Look.faint)],
  // Columns growing: the records.
  'statistics': [(0, 2, _violet, _Look.solid), (1, 2, _violet, _Look.solid), (1, 1, _violet, _Look.solid),
      (2, 2, _violet, _Look.solid), (2, 1, _violet, _Look.solid), (2, 0, _violet, _Look.solid)],
  // Three sliders, each set somewhere else.
  'settings': [(0, 0, _orange, _Look.track), (0, 1, _orange, _Look.track), (0, 2, _orange, _Look.track),
      (2, 0, _orange, _Look.solid), (0, 1, _orange, _Look.solid), (1, 2, _orange, _Look.solid)],
  // A cup on its stand: the achievements.
  'trophy': [(0, 0, _yellow, _Look.solid), (1, 0, _yellow, _Look.solid), (2, 0, _yellow, _Look.solid),
      (1, 1, _yellow, _Look.solid), (0, 2, _yellow, _Look.faint), (1, 2, _yellow, _Look.solid), (2, 2, _yellow, _Look.faint)],
  // A cross of red, the Nightmare.
  'nightmare': [(0, 0, _red, _Look.solid), (2, 0, _red, _Look.solid), (1, 1, _red, _Look.solid),
      (0, 2, _red, _Look.solid), (2, 2, _red, _Look.solid)],
};

/// A picture made of the game's blocks, with the bevel of the game's own,
/// on a three-by-three grid: the menu's tiles, the achievements.
class BlockPicture extends StatelessWidget {
  const BlockPicture(this.name, {super.key, required this.size, this.dimmed = false});

  /// One of [blockPictures].
  final String name;
  final double size;

  /// Drawn see-through, as for an achievement not yet earned.
  final bool dimmed;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: dimmed ? 0.3 : 1,
    child: SizedBox.square(dimension: size, child: CustomPaint(painter: _BlocksPainter(_pictures[name]!))),
  );
}

/// The names of the pictures there are.
Iterable<String> get blockPictures => _pictures.keys;

class _BlocksPainter extends CustomPainter {
  _BlocksPainter(this.blocks);

  final List<_Block> blocks;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width;
    final side = unit * 0.31;
    // Tracks first: the blocks sit on them.
    for (final (x, y, colour, _) in blocks.where((b) => b.$4 == _Look.track)) {
      final rect = Rect.fromLTWH(x * unit * 0.34, y * unit * 0.34 + unit * 0.11, unit, unit * 0.09);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
        Paint()..color = classicColours[colour].withValues(alpha: 0.35),
      );
    }
    for (final (x, y, colour, look) in blocks.where((b) => b.$4 != _Look.track)) {
      final rect = Rect.fromLTWH(x * unit * 0.34, y * unit * 0.34, side, side);
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(side * 0.22));
      final tones = BlockTones.fromBase(classicColours[colour]);
      final alpha = look == _Look.faint ? 0.32 : 1.0;
      final bevel = (side * 0.1).clamp(1.0, 2.0);
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRect(rect, Paint()..color = tones.base.withValues(alpha: alpha));
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, bevel), Paint()..color = tones.light.withValues(alpha: alpha));
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.bottom - bevel, rect.width, bevel), Paint()..color = tones.dark.withValues(alpha: alpha));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BlocksPainter old) => old.blocks != blocks;
}
