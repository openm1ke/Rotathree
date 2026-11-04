import 'dart:math' as math;
import 'dart:ui';

import '../../game/model/side.dart';

/// Centered above a glass's entry with an air gap, in its own cell axes.
Rect nextPiecePreviewRect(int boardSize, int armLength) => Rect.fromLTWH(
  -math.min(3.6, boardSize.toDouble()) / 2,
  -boardSize / 2 - armLength - 2.2,
  math.min(3.6, boardSize.toDouble()),
  1.6,
);

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
    bool focusSingleGlass = false,
    bool showNextPiece = false,
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
        if (showNextPiece) {
          final preview = nextPiecePreviewRect(boardSize, armLength);
          rect(preview.left, preview.top, preview.right, preview.bottom, angle + side.index * math.pi / 2);
        }
      }
      // Single-glass phone views can fill the canvas. As the
      // second arm grows, interpolate back to the fixed board center.
      if (focusSingleGlass && visible.length == 1) return result;
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

/// Spans of the field, in cells, that its textures are drawn for.
class TextureSpans {
  const TextureSpans(this.rest, this.glow, this.motion);

  factory TextureSpans.of({
    required int boardSize,
    required int armLength,
    required List<Side> sides,
    Side? growing,
    bool focusSingleGlass = false,
    bool showNextPiece = false,
  }) {
    double span(List<Side> visible, double angle) => FieldViewport.fit(
      boardSize: boardSize,
      armLength: armLength,
      sides: visible,
      angle: angle,
      focusSingleGlass: focusSingleGlass,
      showNextPiece: showNextPiece,
    ).span;
    final layouts = [
      sides,
      if (growing != null) [for (final side in sides) if (side != growing) side],
    ];
    final rest = span(sides, 0);
    final glow = layouts.map((visible) => span(visible, 0)).reduce(math.min);
    var motion = glow;
    for (final visible in layouts) {
      for (var step = 1; step < _turnSteps; step++) {
        motion = math.min(motion, span(visible, step * math.pi / 2 / _turnSteps));
      }
    }
    return TextureSpans(rest, glow, motion);
  }

  /// Steps a quarter turn is sampled in: every quarter turn looks the same
  /// to the camera.
  static const _turnSteps = 64;

  /// The cross at rest: blocks are copied to the screen pixel for pixel.
  final double rest;

  /// Glows: the cross at rest or, while a glass grows in, the closer view
  /// without it that the camera starts from.
  final double glow;

  /// The closest the camera comes while it turns or a glass grows in, so
  /// that moving blocks are only ever scaled down.
  final double motion;
}
