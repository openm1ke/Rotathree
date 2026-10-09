import 'dart:math' as math;
import 'package:flutter/widgets.dart';

enum PadSide { left, right }

class PadPlacement {
  const PadPlacement({this.size = 144, this.x = 0, this.y = 1});
  final double size, x, y;
  PadPlacement copyWith({double? size, double? x, double? y}) =>
      PadPlacement(size: size ?? this.size, x: x ?? this.x, y: y ?? this.y);
  Map<String, double> toJson() => {'size': size, 'x': x, 'y': y};
}

class PadPositions {
  const PadPositions({this.left = const PadPlacement(), this.right = const PadPlacement(x: 1)});
  final PadPlacement left, right;
  PadPlacement operator [](PadSide side) => side == PadSide.left ? left : right;
  PadPositions withSide(PadSide side, PadPlacement p) =>
      PadPositions(left: side == PadSide.left ? p : left, right: side == PadSide.right ? p : right);
  Map<String, Object> toJson() => {'left': left.toJson(), 'right': right.toJson()};
  factory PadPositions.fromJson(Object? raw) {
    final map = raw is Map ? raw : const {};
    PadPlacement read(PadSide side) {
      final fallback = const PadPositions()[side];
      final item = map[side.name] is Map ? map[side.name] as Map : const {};
      double value(String key, double min, double max, double base) =>
          item[key] is num && (item[key] as num).isFinite ? (item[key] as num).clamp(min, max).toDouble() : base;
      return PadPlacement(
        size: value('size', 136, 216, fallback.size),
        x: value('x', 0, 1, fallback.x),
        y: value('y', 0, 1, fallback.y),
      );
    }

    return PadPositions(left: read(PadSide.left), right: read(PadSide.right));
  }
}

double padAreaHeight(double viewportHeight, PadPositions p, double width) =>
    math.max(math.min(math.max(p.left.size, p.right.size), (width - 8) / 2), math.min(260, viewportHeight * .32));
Map<PadSide, Rect> padGeometry(Size area, PadPositions positions) {
  Rect rect(PadPlacement p) {
    final size = math.min(p.size, math.min(math.max(136.0, (area.width - 8) / 2), area.height));
    return Rect.fromLTWH(p.x * math.max(0, area.width - size), p.y * math.max(0, area.height - size), size, size);
  }

  var left = rect(positions.left), right = rect(positions.right);
  bool overlaps(Rect r) =>
      r.left < left.right + 8 && r.right + 8 > left.left && r.top < left.bottom + 8 && r.bottom + 8 > left.top;
  if (overlaps(right)) {
    final candidates =
        [
              Rect.fromLTWH(left.right + 8, right.top, right.width, right.height),
              Rect.fromLTWH(left.left - right.width - 8, right.top, right.width, right.height),
              Rect.fromLTWH(right.left, left.bottom + 8, right.width, right.height),
              Rect.fromLTWH(right.left, left.top - right.height - 8, right.width, right.height),
            ]
            .where((r) => r.left >= 0 && r.top >= 0 && r.right <= area.width && r.bottom <= area.height && !overlaps(r))
            .toList()
          ..sort((a, b) => (a.topLeft - right.topLeft).distance.compareTo((b.topLeft - right.topLeft).distance));
    if (candidates.isNotEmpty) {
      right = candidates.first;
    } else {
      left = Rect.fromLTWH(0, left.top, left.width, left.height);
      right = Rect.fromLTWH(math.max(0, area.width - right.width), right.top, right.width, right.height);
    }
  }
  return {PadSide.left: left, PadSide.right: right};
}

PadPositions movePad(PadPositions positions, PadSide side, Offset offset, Size area) {
  final size = padGeometry(area, positions)[side]!.width;
  var next = positions.withSide(
    side,
    positions[side].copyWith(
      x: (offset.dx / math.max(1, area.width - size)).clamp(0, 1),
      y: (offset.dy / math.max(1, area.height - size)).clamp(0, 1),
    ),
  );
  final geometry = padGeometry(area, next);
  for (final key in PadSide.values) {
    final r = geometry[key]!;
    next = next.withSide(
      key,
      next[key].copyWith(
        x: area.width > r.width ? r.left / (area.width - r.width) : next[key].x,
        y: area.height > r.height ? r.top / (area.height - r.height) : next[key].y,
      ),
    );
  }
  return next;
}
