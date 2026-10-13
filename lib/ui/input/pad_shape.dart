import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import 'game_action.dart';

/// The outline of every button on both pads.
enum PadShape {
  /// The arms of one cross of rounded keys, as the game has always drawn it.
  square('Квадратные'),

  /// A round key for every button.
  round('Круглые'),

  /// A triangle for every button, pointing away from the centre of its pad.
  triangle('Треугольные');

  const PadShape(this.label);

  final String label;

  static PadShape fromName(Object? name) =>
      PadShape.values.firstWhere((shape) => shape.name == name, orElse: () => PadShape.square);
}

/// How one button differs from where its cross puts it: its size as a factor
/// of the default size, and its shift as fractions of the pad's size.
class PadTweak {
  const PadTweak({this.scale = 1, this.dx = 0, this.dy = 0});

  static const double minScale = 0.5, maxScale = 1.5, maxShift = 0.25;

  final double scale, dx, dy;

  bool get isDefault => scale == 1 && dx == 0 && dy == 0;

  PadTweak copyWith({double? scale, double? dx, double? dy}) => PadTweak(
    scale: (scale ?? this.scale).clamp(minScale, maxScale).toDouble(),
    dx: (dx ?? this.dx).clamp(-maxShift, maxShift).toDouble(),
    dy: (dy ?? this.dy).clamp(-maxShift, maxShift).toDouble(),
  );

  Map<String, double> toJson() => {'scale': scale, 'dx': dx, 'dy': dy};

  /// Reads a stored tweak; anything missing or out of range falls back.
  factory PadTweak.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    double read(String key, double min, double max, double fallback) {
      final value = map[key];
      return value is num && value.isFinite ? value.clamp(min, max).toDouble() : fallback;
    }

    return PadTweak(
      scale: read('scale', minScale, maxScale, 1),
      dx: read('dx', -maxShift, maxShift, 0),
      dy: read('dy', -maxShift, maxShift, 0),
    );
  }
}

/// The tweaks of one pad, by button. A button without an entry is untouched.
typedef PadTweaks = Map<PadSlot, PadTweak>;

/// The cross of a pad is a 3 by 3 grid: up, left, centre, right and down.
Offset _cellOf(PadSlot slot) => switch (slot) {
  PadSlot.up => const Offset(1, 0),
  PadSlot.left => const Offset(0, 1),
  PadSlot.center => const Offset(1, 1),
  PadSlot.right => const Offset(2, 1),
  PadSlot.down => const Offset(1, 2),
};

/// Where every button of a pad [size] wide sits, in the pad's own coordinates.
/// Without tweaks this is the cross the game has always drawn; a tweak scales a
/// button about its own centre and shifts it, and it always stays on the pad.
Map<PadSlot, Rect> padButtonRects(double size, PadTweaks tweaks) {
  final cell = size / 3;
  Rect rectOf(PadSlot slot) {
    final at = _cellOf(slot);
    // The arms keep a thin gap between them; the centre keeps a wider one.
    final inset = cell * (slot == PadSlot.center ? 0.1 : 0.035);
    final base = Rect.fromLTWH(at.dx * cell, at.dy * cell, cell, cell).deflate(inset);
    final tweak = tweaks[slot] ?? const PadTweak();
    final side = base.width * tweak.scale;
    final centre = base.center + Offset(tweak.dx * size, tweak.dy * size);
    final rect = Rect.fromCenter(center: centre, width: side, height: side);
    return rect.shift(Offset(_inside(rect.left, rect.width, size), _inside(rect.top, rect.height, size)));
  }

  return {for (final slot in PadSlot.values) slot: rectOf(slot)};
}

/// How far a span starting at [start] must move to lie within [0, bound].
double _inside(double start, double length, double bound) {
  if (start < 0) return -start;
  if (start + length > bound) return bound - (start + length);
  return 0;
}

/// The shape a button is drawn and touched with.
enum _Outline { circle, box, triangle }

_Outline _outlineOf(PadShape shape, PadSlot slot) => switch (shape) {
  PadShape.round => _Outline.circle,
  PadShape.triangle => _Outline.triangle,
  PadShape.square => slot == PadSlot.center ? _Outline.circle : _Outline.box,
};

/// The three corners of a triangular button, pointing away from the centre.
List<Offset> _triangle(PadSlot slot, Rect r) => switch (slot) {
  PadSlot.up || PadSlot.center => [Offset(r.center.dx, r.top), r.bottomRight, r.bottomLeft],
  PadSlot.down => [Offset(r.center.dx, r.bottom), r.topRight, r.topLeft],
  PadSlot.left => [Offset(r.left, r.center.dy), r.bottomRight, r.topRight],
  PadSlot.right => [Offset(r.right, r.center.dy), r.bottomLeft, r.topLeft],
};

/// The outline of a button filling [r].
Path padButtonPath(PadShape shape, PadSlot slot, Rect r) {
  return switch (_outlineOf(shape, slot)) {
    _Outline.circle => Path()..addOval(r),
    _Outline.triangle => Path()..addPolygon(_triangle(slot, r), true),
    _Outline.box => _arms(slot, r),
  };
}

/// An arm of the cross: rounded at its outer end, nearly square at the inner.
Path _arms(PadSlot slot, Rect r) {
  final outer = Radius.circular(r.width * 0.32);
  final inner = Radius.circular(r.width * 0.11);
  final rounded = switch (slot) {
    PadSlot.up => RRect.fromRectAndCorners(r, topLeft: outer, topRight: outer, bottomLeft: inner, bottomRight: inner),
    PadSlot.down => RRect.fromRectAndCorners(r, topLeft: inner, topRight: inner, bottomLeft: outer, bottomRight: outer),
    PadSlot.left => RRect.fromRectAndCorners(r, topLeft: outer, bottomLeft: outer, topRight: inner, bottomRight: inner),
    PadSlot.right => RRect.fromRectAndCorners(r, topLeft: inner, bottomLeft: inner, topRight: outer, bottomRight: outer),
    PadSlot.center => RRect.fromRectAndRadius(r, outer),
  };
  return Path()..addRRect(rounded);
}

/// Pushes the picture and caption of a button towards the broad side of a
/// triangle, so that they sit in the middle of its mass. In fractions of the
/// button's size.
Offset padContentShift(PadShape shape, PadSlot slot) {
  if (shape != PadShape.triangle) return Offset.zero;
  return switch (slot) {
    PadSlot.up || PadSlot.center => const Offset(0, 0.07),
    PadSlot.down => const Offset(0, -0.07),
    PadSlot.left => const Offset(0.07, 0),
    PadSlot.right => const Offset(-0.07, 0),
  };
}

/// Signed distance from [p] to the outline of a button drawn in [r]: negative
/// inside, positive outside.
double _distance(Offset p, PadSlot slot, Rect r, PadShape shape) {
  return switch (_outlineOf(shape, slot)) {
    _Outline.circle => (p - r.center).distance - r.width / 2,
    _Outline.box => _boxDistance(p - r.center, Offset(r.width / 2, r.height / 2)),
    _Outline.triangle => _polygonDistance(p, _triangle(slot, r)),
  };
}

double _boxDistance(Offset d, Offset half) {
  final qx = d.dx.abs() - half.dx;
  final qy = d.dy.abs() - half.dy;
  final outside = Offset(math.max(qx, 0), math.max(qy, 0)).distance;
  return outside + math.min(math.max(qx, qy), 0);
}

double _polygonDistance(Offset p, List<Offset> v) {
  var nearest = double.infinity;
  var inside = false;
  for (var i = 0, j = v.length - 1; i < v.length; j = i++) {
    final a = v[j], b = v[i];
    final edge = b - a;
    final w = p - a;
    final t = ((w.dx * edge.dx + w.dy * edge.dy) / (edge.dx * edge.dx + edge.dy * edge.dy)).clamp(0.0, 1.0);
    nearest = math.min(nearest, (w - edge * t).distance);
    if ((a.dy > p.dy) != (b.dy > p.dy) && p.dx < (b.dx - a.dx) * (p.dy - a.dy) / (b.dy - a.dy) + a.dx) {
      inside = !inside;
    }
  }
  return inside ? -nearest : nearest;
}

/// The button a touch at [point] belongs to. A touch inside the centre is the
/// centre. Anywhere else the nearest button takes it, measured from its
/// outline and relative to its size, so that no point of the pad is dead.
/// [slop] widens every outline a little so that touches near a gap still land.
PadSlot padSlotAt(Offset point, Map<PadSlot, Rect> rects, PadShape shape, {required double slop}) {
  final centre = rects[PadSlot.center]!;
  if (_distance(point, PadSlot.center, centre, shape) - slop <= 0) return PadSlot.center;
  var best = PadSlot.up;
  var bestScore = double.infinity;
  for (final slot in PadSlot.values) {
    final rect = rects[slot]!;
    final score = (_distance(point, slot, rect, shape) - slop) / (rect.shortestSide / 2);
    if (score < bestScore) {
      bestScore = score;
      best = slot;
    }
  }
  return best;
}

/// The touch slop for a pad [size] wide: a little more than a tenth of a cell.
double padTouchSlop(double size) => size / 3 * 0.12;
