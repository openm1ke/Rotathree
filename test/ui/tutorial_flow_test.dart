import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/session.dart';
import 'package:rotathree/ui/app.dart';
import 'package:rotathree/ui/game/game_screen.dart';
import 'package:rotathree/ui/input/game_action.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The backdrop animates for ever, so the screens are pumped for a while.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Opens the tutorial from the menu of a fresh install on a phone.
Future<void> openTutorialFromMenu(WidgetTester tester) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
  addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
  await tester.pumpWidget(const RotathreeApp());
  await settle(tester);
  await tester.tap(find.text('Обучение'));
  await settle(tester);
  expect(tester.widget<GameScreen>(find.byType(GameScreen)).tutorial, isTrue);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Play at the end of a tutorial opened from the menu starts the campaign', (tester) async {
    await openTutorialFromMenu(tester);
    final state = tester.state<GameScreenState>(find.byType(GameScreen));
    await tester.tap(find.text('Дальше'));
    await tester.pump();
    state.move(1, toWall: false);
    await tester.pump();
    await tester.tap(find.text('✓ Дальше'));
    await tester.pump();
    state.press(GameAction.rotateCW);
    await tester.pump();
    await tester.tap(find.text('✓ Дальше'));
    await tester.pump();
    state.press(GameAction.hardDrop);
    await pumpFrames(tester, 50);
    await tester.tap(find.text('✓ Дальше'));
    await tester.pump();
    await pumpFrames(tester, 25);
    state.press(GameAction.glassRight);
    await tester.pump();
    await tester.tap(find.text('✓ Дальше'));
    await tester.pump();
    await tester.tap(find.text('Играть'));
    await settle(tester);

    final game = tester.widget<GameScreen>(find.byType(GameScreen));
    expect(game.tutorial, isFalse);
    expect(game.session, isA<CampaignSession>().having((s) => s.level, 'level', 0));
    expect(tester.takeException(), isNull);
  });

  testWidgets('Skip in a tutorial opened from the menu returns to the menu', (tester) async {
    await openTutorialFromMenu(tester);
    await tester.tap(find.text('Пропустить'));
    await settle(tester);
    expect(find.byType(GameScreen), findsNothing);
    expect(find.text('Кампания'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
