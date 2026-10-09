import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/ui/field/field_painter.dart';
import 'package:rotathree/ui/field/field_viewport.dart';

void main() {
  FieldViewport view(
    List<Side> sides, {
    Side? building,
    double progress = 1,
    double angle = 0,
    int arm = 9,
    bool reduced = false,
  }) => FieldViewport.fit(
    boardSize: 6,
    armLength: arm,
    sides: sides,
    building: building,
    progress: progress,
    angle: angle,
    reduceMotion: reduced,
  );

  test('one glass fills the available field and every added glass steps back', () {
    final views = [for (var count = 1; count <= 4; count++) view(glassOrder.take(count).toList())];
    expect(views.first.span, 15);
    expect(views.first.span, lessThan(views.last.span * 0.65));
    for (var i = 1; i < views.length; i++) {
      expect(views[i].span, greaterThan(views[i - 1].span));
    }
  });

  test('reframe comes before growth and a restored building phase uses the same camera', () {
    for (var count = 2; count <= 4; count++) {
      final sides = glassOrder.take(count).toList();
      final before = view(sides.take(count - 1).toList());
      final start = view(sides, building: sides.last, progress: 0);
      expect(start.bounds, before.bounds);
      expect(start.grow, 0);
      final middle = view(sides, building: sides.last, progress: 0.4);
      expect(middle.bounds, view(sides).bounds);
      expect(middle.grow, inExclusiveRange(0, 1));
      expect(view(sides, building: sides.last, progress: 1).bounds, view(sides).bounds);
      expect(view(sides, building: sides.last, progress: 0.1, reduced: true).grow, 1);
    }
  });

  test('camera contains every rotated arm for all custom lengths', () {
    for (final arm in [4, 9, 12]) {
      for (var count = 1; count <= 4; count++) {
        final sides = glassOrder.take(count).toList();
        for (var step = 0; step <= 16; step++) {
          final angle = step * math.pi / 8;
          final v = view(sides, angle: angle, arm: arm);
          for (final side in sides) {
            final turn = angle + side.index * math.pi / 2;
            for (final x in [-3.0, 3.0]) {
              for (final y in [-3.0, -3.0 - arm]) {
                final point = Offset(math.cos(turn) * x - math.sin(turn) * y, math.sin(turn) * x + math.cos(turn) * y);
                expect(v.bounds.inflate(1e-8).contains(point), isTrue);
              }
            }
          }
        }
      }
    }
  });

  test('touch targets follow the zoom and translated center and ignore absent arms', () {
    const config = GameConfig(glassCount: 2);
    final g = FieldGeometry(320, config, devicePixelRatio: 3);
    expect(g.zoneAt(g.origin), FieldZone.center);
    expect(g.zoneAt(g.origin + Offset(0, -7 * g.drawnCell)), FieldZone.top);
    expect(g.zoneAt(g.origin + Offset(7 * g.drawnCell, 0)), FieldZone.right);
    expect(g.zoneAt(g.origin + Offset(-7 * g.drawnCell, 0)), FieldZone.outside);
    final turned = FieldGeometry(320, config, angle: -math.pi / 2, sides: config.sides);
    expect(turned.zoneAt(turned.origin + Offset(-7 * turned.drawnCell, 0)), FieldZone.left);
  });
}
