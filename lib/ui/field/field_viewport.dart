import 'dart:math' as math;
import 'dart:ui';

import '../../game/model/side.dart';

/// Fit arms around the fixed board center; make room before growing a new arm.
class FieldViewport {
  const FieldViewport(this.bounds, this.grow);
  final Rect bounds;
  final double grow;
  double get span => math.max(bounds.width, bounds.height);
  Offset get center => bounds.center;

  factory FieldViewport.fit({
    required int boardSize,
    required int armLength,
    required List<Side> sides,
    double angle = 0,
    Side? building,
    double progress = 1,
    bool reduceMotion = false,
  }) {
    final half = boardSize / 2;
    Rect bounds(List<Side> visible) {
      var result = Rect.zero;
      var first = true;
      void rect(double x1, double y1, double x2, double y2, double turn) {
        final c = math.cos(turn), s = math.sin(turn);
        for (final x in [x1, x2]) {
          for (final y in [y1, y2]) {
            final point = Offset(c * x - s * y, s * x + c * y);
            final box = Rect.fromPoints(point, point);
            result = first ? box : result.expandToInclude(box);
            first = false;
          }
        }
      }

      rect(-half, -half, half, half, angle);
      for (final side in visible) {
        rect(-half, -half - armLength, half, -half, angle + side.index * math.pi / 2);
      }
      final pad = math.max(0, visible.length - 1) * 0.25;
      final rx = math.max(result.left.abs(), result.right.abs()) + pad;
      final ry = math.max(result.top.abs(), result.bottom.abs()) + pad;
      return Rect.fromLTRB(-rx, -ry, rx, ry);
    }

    double ease(double t) => 1 - math.pow(1 - t.clamp(0, 1), 3).toDouble();
    final after = bounds(sides);
    final before = building == null ? after : bounds(sides.where((side) => side != building).toList());
    final t = building == null || reduceMotion ? 1.0 : ease(progress / 0.4);
    return FieldViewport(
      Rect.lerp(before, after, t)!,
      building == null || reduceMotion ? 1 : ease((progress - 0.25) / 0.75),
    );
  }
}
