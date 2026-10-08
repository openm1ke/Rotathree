import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The backdrop animates for ever, so the screens are pumped for a while
/// instead of until nothing is left to animate. Real time is let through so
/// that the stored settings can be read.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'rotathree.tutorial.v1': 'true'});
  });

  testWidgets('the menu opens and leads to the campaign', (tester) async {
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);

    expect(find.text('Campaign'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Campaign'));
    await settle(tester);
    expect(find.text('Кампания'), findsWidgets);
    expect(find.text('3 ЦВЕТА'), findsOneWidget);
  });

  testWidgets('a custom game can be set up and started', (tester) async {
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);

    await tester.tap(find.text('Custom'));
    await settle(tester);
    expect(find.text('Кастом'), findsWidgets);

    // The screens are lists: the button at the bottom is built once it is scrolled to.
    await tester.scrollUntilVisible(find.text('Начать'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Начать'));
    await settle(tester);
    expect(find.text('Пауза'), findsOneWidget);
  });

  testWidgets('new players see training and can skip into the chosen game', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);
    await tester.tap(find.text('Custom'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Начать'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Начать'));
    await settle(tester);
    expect(find.text('Одна фигура — три клетки'), findsOneWidget);
    await tester.tap(find.text('Пропустить'));
    await settle(tester);
    expect(find.text('Одна фигура — три клетки'), findsNothing);
    expect(find.text('Пауза'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rotathree.tutorial.v1'), 'true');
  });

  testWidgets('mobile settings show pads without keyboard customization', (tester) async {
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('ЭКРАННЫЕ КНОПКИ'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('ЭКРАННЫЕ КНОПКИ'), findsOneWidget);
    expect(find.textContaining('новую клавишу'), findsNothing);
    expect(find.textContaining('Клавиши'), findsNothing);
  });
}
