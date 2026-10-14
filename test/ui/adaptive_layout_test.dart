import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/app.dart';
import 'package:rotathree/ui/field/field_painter.dart';
import 'package:rotathree/ui/game/game_screen.dart';
import 'package:rotathree/ui/layout.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The backdrop animates for ever, so the screens are pumped for a while.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Phones stay upright, tablets turn: each size in logical points, with the
/// text scale the lesson panel uses there.
const sizes = [
  ('phone upright', Size(390, 844), 1.0),
  ('tablet upright', Size(1032, 1376), 1.5),
  ('tablet turned', Size(1376, 1032), 1.5),
];

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'rotathree.tutorial.v1': 'true'});
  });

  for (final (name, size, textScale) in sizes) {
    testWidgets('the menu, a lesson and a level lay out on a $name', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
      addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);

      await tester.pumpWidget(const RotathreeApp());
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('Настройки'), findsOneWidget);
      if (isTablet(size)) {
        // The menu sits in the middle of the screen, not pinned to its top edge.
        expect(tester.getTopLeft(find.text('Обучение')).dy, greaterThan(size.height * 0.2));
        expect(tester.getBottomLeft(find.textContaining('из 16')).dy, lessThan(size.height));
      }

      await tester.tap(find.text('Обучение'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      expect(_fieldWidth(tester), lessThanOrEqualTo(math.min(size.width, size.height) + 0.5));
      final lesson = find.textContaining('Фигуры падают сверху');
      expect(MediaQuery.textScalerOf(tester.element(lesson)).scale(1), textScale);

      await tester.tap(find.byTooltip('Назад'));
      await settle(tester);

      await tester.tap(find.text('Кампания'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      if (isTablet(size)) {
        // Four tiles across, each taller than it is wide.
        final first = tester.getRect(find.byKey(const ValueKey('campaign-level-0')));
        expect(tester.getRect(find.byKey(const ValueKey('campaign-level-3'))).top, first.top);
        expect(tester.getRect(find.byKey(const ValueKey('campaign-level-4'))).top, greaterThan(first.bottom));
        expect(first.height, greaterThan(first.width));
      }

      await tester.tap(find.text('01'));
      await settle(tester);
      expect(find.byType(GameScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(_fieldWidth(tester), lessThanOrEqualTo(math.min(size.width, size.height) + 0.5));
      if (isTablet(size) && size.height > size.width) {
        // Upright, a tablet's field is wider than a phone's: the screen has room.
        expect(_fieldWidth(tester), greaterThan(800));
      }
    });
  }
}

/// The width of the field as drawn: the square the game lays out.
double _fieldWidth(WidgetTester tester) {
  final field = find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is FieldPainter);
  expect(field, findsOneWidget);
  return tester.getSize(field).width;
}
