import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/input/dpad.dart';
import 'package:rotathree/ui/input/game_action.dart';
import 'package:rotathree/ui/input/pad_placement.dart';
import 'package:rotathree/ui/input/pad_shape.dart';
import 'package:rotathree/ui/menu/settings_screen.dart';

Settings _roundTrip(Settings settings) => Settings.fromJson(jsonDecode(jsonEncode(settings.toJson())));

void main() {
  group('the geometry of a pad', () {
    test('without tweaks the buttons sit where the cross has always put them', () {
      final rects = padButtonRects(300, const {});
      expect(rects[PadSlot.center]!.center, const Offset(150, 150));
      expect(rects[PadSlot.center]!.width, closeTo(80, 1e-9));
      expect(rects[PadSlot.up]!.center, const Offset(150, 50));
      expect(rects[PadSlot.left]!.center, const Offset(50, 150));
      expect(rects[PadSlot.right]!.center, const Offset(250, 150));
      expect(rects[PadSlot.down]!.center, const Offset(150, 250));
      expect(rects[PadSlot.up]!.width, closeTo(93, 1e-9));
    });

    test('a tweak scales a button about its own centre', () {
      final rects = padButtonRects(300, {PadSlot.center: const PadTweak(scale: 1.5)});
      expect(rects[PadSlot.center]!.width, closeTo(120, 1e-9));
      expect(rects[PadSlot.center]!.center, const Offset(150, 150));
      expect(rects[PadSlot.up]!.width, closeTo(93, 1e-9));
    });

    test('a button that would leave the pad is moved back onto it', () {
      final rects = padButtonRects(300, {PadSlot.up: const PadTweak(scale: 1.5)});
      final up = rects[PadSlot.up]!;
      expect(up.width, closeTo(139.5, 1e-9));
      expect(up.top, closeTo(0, 1e-9));
      expect(up.bottom, lessThanOrEqualTo(300));
    });

    test('a shift moves a button by a fraction of the pad, and it stays on the pad', () {
      final moved = padButtonRects(300, {PadSlot.left: const PadTweak(dx: 0.1, dy: -0.05)});
      expect(moved[PadSlot.left]!.center, const Offset(80, 135));

      final pushed = padButtonRects(300, {PadSlot.up: const PadTweak(scale: 1.5, dy: -0.25)});
      final up = pushed[PadSlot.up]!;
      expect(up.top, greaterThanOrEqualTo(0));
      expect(up.bottom, lessThanOrEqualTo(300));
    });

    test('a touch on the centre is the centre, and no other point of the cross is dead', () {
      final rects = padButtonRects(300, const {});
      const slop = 300 / 3 * 0.12;
      expect(padSlotAt(const Offset(150, 150), rects, PadShape.square, slop: slop), PadSlot.center);
      expect(padSlotAt(const Offset(150, 30), rects, PadShape.square, slop: slop), PadSlot.up);
      expect(padSlotAt(const Offset(30, 150), rects, PadShape.square, slop: slop), PadSlot.left);
      expect(padSlotAt(const Offset(270, 150), rects, PadShape.square, slop: slop), PadSlot.right);
      expect(padSlotAt(const Offset(150, 270), rects, PadShape.square, slop: slop), PadSlot.down);
      expect(padSlotAt(const Offset(60, 60), rects, PadShape.square, slop: slop), isNot(PadSlot.center));
    });

    test('a round button takes the touches inside its circle, and nearby ones', () {
      final rects = padButtonRects(300, const {});
      const slop = 300 / 3 * 0.12;
      expect(padSlotAt(const Offset(150, 150), rects, PadShape.round, slop: slop), PadSlot.center);
      expect(padSlotAt(const Offset(110, 40), rects, PadShape.round, slop: slop), PadSlot.up);
      expect(padSlotAt(const Offset(100, 100), rects, PadShape.round, slop: slop), isNot(PadSlot.center));
    });

    test('a triangle takes the touches inside its outline', () {
      final rects = padButtonRects(300, const {});
      const slop = 300 / 3 * 0.12;
      expect(padSlotAt(const Offset(150, 60), rects, PadShape.triangle, slop: slop), PadSlot.up);
      expect(padSlotAt(const Offset(30, 150), rects, PadShape.triangle, slop: slop), PadSlot.left);
      expect(padSlotAt(const Offset(150, 150), rects, PadShape.triangle, slop: slop), PadSlot.center);
    });

    test('a button outline has the shape it is drawn with', () {
      final r = Rect.fromLTWH(0, 0, 100, 100);
      expect(padButtonPath(PadShape.round, PadSlot.up, r).getBounds(), r);
      expect(padButtonPath(PadShape.triangle, PadSlot.up, r).getBounds(), r);
      expect(padButtonPath(PadShape.square, PadSlot.up, r).getBounds(), r);
    });
  });

  group('tweaks and settings', () {
    test('a tweak keeps its values in range, and bad values fall back', () {
      final loud = PadTweak.fromJson({'scale': 9, 'dx': -1, 'dy': 'high'});
      expect(loud.scale, PadTweak.maxScale);
      expect(loud.dx, -PadTweak.maxShift);
      expect(loud.dy, 0);
      expect(const PadTweak().isDefault, isTrue);
      expect(PadTweak.fromJson(null).isDefault, isTrue);
    });

    test('the shape and the tweaks survive a round trip, and defaults are not stored', () {
      final settings = Settings.defaults()
          .copyWith(padShape: PadShape.triangle)
          .withButton(PadSide.right, PadSlot.down, const PadTweak(scale: 1.2, dx: -0.05))
          .withButton(PadSide.left, PadSlot.up, const PadTweak());
      final again = _roundTrip(settings);
      expect(again.padShape, PadShape.triangle);
      expect(again.padButtons[PadSide.right]![PadSlot.down]!.scale, closeTo(1.2, 1e-9));
      expect(again.padButtons[PadSide.right]![PadSlot.down]!.dx, closeTo(-0.05, 1e-9));
      expect(again.padButtons[PadSide.left], isEmpty);

      final stored = (settings.toJson()['pads']! as Map)['buttons']! as Map;
      expect((stored['left'] as Map).containsKey('up'), isFalse);
    });

    test('a default tweak removes the button from the saved settings', () {
      final changed = Settings.defaults().withButton(PadSide.left, PadSlot.center, const PadTweak(scale: 0.8));
      expect(changed.padButtons[PadSide.left]!.containsKey(PadSlot.center), isTrue);
      final reset = changed.withButton(PadSide.left, PadSlot.center, const PadTweak());
      expect(reset.padButtons[PadSide.left]!.containsKey(PadSlot.center), isFalse);
    });

    test('older saves without a shape or tweaks get the square cross', () {
      final settings = Settings.fromJson({
        'pads': {'left': {'up': 'rotateCW'}},
      });
      expect(settings.padShape, PadShape.square);
      expect(settings.padButtons, isEmpty);
      expect(settings.hud.keyHints, isTrue);
    });
  });

  group('the pad on screen', () {
    testWidgets('without labels no caption is drawn, and a tweaked button answers where it is drawn', (tester) async {
      final presses = <GameAction>[];
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: DPad(
            layout: defaultLeftPad,
            size: 300,
            showLabels: false,
            tweaks: const {PadSlot.up: PadTweak(dy: 0.1)},
            onDown: presses.add,
            onUp: (_) {},
          ),
        ),
      ));
      expect(find.text('ВЛЕВО'), findsNothing);

      final origin = tester.getTopLeft(find.byType(DPad));
      await tester.tapAt(origin + const Offset(150, 80));
      await tester.pump();
      expect(presses, [GameAction.rotateCW]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the outline of the chosen button is drawn in the preview', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: DPad(
            layout: defaultLeftPad,
            size: 300,
            highlight: PadSlot.left,
            onDown: (_) {},
            onUp: (_) {},
          ),
        ),
      ));
      expect(tester.takeException(), isNull);
      expect(find.byType(DPad), findsOneWidget);
    });

    testWidgets('the settings offer the three shapes and the reset, and the shape is kept', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var current = Settings.defaults();
      await tester.pumpWidget(
        MaterialApp(
          home: Material(
            child: StatefulBuilder(
              builder: (context, setState) => SettingsScreen(
                settings: current,
                stored: true,
                onBack: () {},
                onChange: (next) => setState(() => current = next),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.ensureVisible(find.text('Треугольные'));
      await tester.pump();
      await tester.tap(find.text('Треугольные'));
      await tester.pump();
      expect(current.padShape, PadShape.triangle);

      await tester.ensureVisible(find.text('Сбросить кнопки'));
      await tester.pump();
      await tester.tap(find.text('Сбросить кнопки'));
      await tester.pump();
      expect(current.padShape, PadShape.square);
      expect(current.hud.keyHints, isTrue);
      expect(tester.takeException(), isNull);
    });
  });
}
