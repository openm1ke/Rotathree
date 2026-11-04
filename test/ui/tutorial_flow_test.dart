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
  await tester.tap(find.byKey(const ValueKey('menu-tutorial')));
  await settle(tester);
  expect(tester.widget<GameScreen>(find.byType(GameScreen)).tutorial, isTrue);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Play at the end of a tutorial opened from the menu starts the campaign', (tester) async {
    await openTutorialFromMenu(tester);
    final state = tester.state<GameScreenState>(find.byType(GameScreen));
    await tester.tap(find.text('Начать'));
    await tester.pump();
    // Each lesson goes on by itself once its action is done.
    state.move(1, toWall: false);
    await pumpFrames(tester, 20);
    state.press(GameAction.rotateCW);
    await pumpFrames(tester, 20);
    state.press(GameAction.hardDrop);
    // The match plays out, then the second glass grows out of the cross.
    await pumpFrames(tester, 80);
    state.press(GameAction.glassRight);
    // The last lesson comes after a moment, and its frame grows to fit Play.
    await pumpFrames(tester, 30);
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
    expect(find.byKey(const ValueKey('menu-campaign')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
