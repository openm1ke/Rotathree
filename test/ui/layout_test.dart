import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/layout.dart';
import 'package:rotathree/ui/widgets/controls.dart';

void main() {
  test('phones keep the whole width and tablets do not', () {
    expect(isTablet(const Size(390, 844)), isFalse);
    expect(isTablet(const Size(430, 932)), isFalse);
    expect(isTablet(const Size(744, 1133)), isTrue);
    expect(isTablet(const Size(1032, 1376)), isTrue);
    expect(isTablet(const Size(1376, 1032)), isTrue);
  });

  for (final (name, size, expected) in [
    ('a phone', const Size(390, 844), 390.0),
    ('a tablet', const Size(1032, 1376), tabletMenuWidth),
  ]) {
    testWidgets('a menu column on $name is ${expected.toStringAsFixed(0)} points wide and centred', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      const key = ValueKey('column');
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MenuWidth(child: Container(key: key, color: Colors.red)),
          ),
        ),
      );
      final box = tester.getRect(find.byKey(key));
      expect(box.width, expected);
      expect(box.center.dx, size.width / 2);
    });
  }

  testWidgets('a result card is wider and its text larger on a tablet', (tester) async {
    tester.view.physicalSize = const Size(1032, 1376);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: TabletScale(
              child: const DialogCard(
                kicker: 'Кастом',
                title: 'Игра окончена',
                children: [SizedBox(width: 2000, height: 1)],
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(DialogCard)).width, 420 * 1.5);
    expect(MediaQuery.textScalerOf(tester.element(find.text('Игра окончена'))).scale(1), 1.5);
  });
}
