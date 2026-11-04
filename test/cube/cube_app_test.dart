import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/app.dart';
import 'package:rotathree/ui/cube/cube_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> openApp(WidgetTester tester, Map<String, Object> stored) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  SharedPreferences.setMockInitialValues(stored);
  await tester.pumpWidget(const RotathreeApp());
  await settle(tester);
}

void main() {
  testWidgets('the campaign holds Cube\'s levels after the flat ones, and plays them', (tester) async {
    await openApp(tester, {'rotathree.tutorial.v1': 'true', 'rotathree.cube-tutorial.v1': 'true'});
    await tester.tap(find.byKey(const ValueKey('menu-campaign')));
    await settle(tester);
    expect(find.text('СТАКАНЫ · 2D'), findsOneWidget);
    final first = find.byKey(const ValueKey('cube-level-0'));
    await tester.ensureVisible(first);
    await settle(tester);
    expect(find.text('КУБ · 3D'), findsOneWidget);
    expect(find.text('пройдено 0 из 8'), findsOneWidget);
    await tester.tap(first);
    await settle(tester);
    final screen = tester.widget<CubeScreen>(find.byType(CubeScreen));
    expect([screen.level, screen.tutorial], [0, false]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the first game of Cube begins with its lessons; skipping them goes into the game', (tester) async {
    await openApp(tester, {'rotathree.tutorial.v1': 'true'});
    await tester.tap(find.byKey(const ValueKey('menu-cube')));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Играть'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Играть'));
    await settle(tester);
    expect(tester.widget<CubeScreen>(find.byType(CubeScreen)).tutorial, isTrue);
    await tester.tap(find.text('Пропустить'));
    await settle(tester);
    final screen = tester.widget<CubeScreen>(find.byType(CubeScreen));
    expect([screen.tutorial, screen.level], [false, null]);
    expect(tester.takeException(), isNull);
  });
}
