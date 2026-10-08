import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/modes.dart';
import 'package:rotathree/game/config/campaign.dart';
import 'package:rotathree/game/session.dart';
import 'package:rotathree/game/state/game_state.dart';
import 'package:rotathree/ui/data/progress.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/game/game_screen.dart';
import 'package:rotathree/ui/input/dpad.dart';

Future<GameScreenState> pumpGame(WidgetTester tester, {Session session = const CustomSession(defaultCustom)}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(
    home: GameScreen(
      session: session,
      settings: Settings.defaults(),
      progress: Progress.initial(),
      blocked: false,
      onSettings: () {},
      onExit: () {},
      onLevels: () {},
      onRetry: (_) {},
      onInsane: () {},
      onCustomise: () {},
      onRecord: (_) {},
      onProgress: (_) {},
    ),
  ));
  await tester.pump(const Duration(milliseconds: 100));
  return tester.state<GameScreenState>(find.byType(GameScreen));
}

/// The centre of the button of [slot] on the pad at [index] (0 left, 1 right).
Offset padButton(WidgetTester tester, int index, double fx, double fy) {
  final pad = tester.getRect(find.byType(DPad).at(index));
  return Offset(pad.left + pad.width * fx, pad.top + pad.height * fy);
}

/// Lets [frames] frames of 50 ms go by, as a device does at 20 frames a second.
Future<void> pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  testWidgets('the right arrow of the left pad moves the piece one lane', (tester) async {
    final state = await pumpGame(tester);
    final before = state.engine.activePiece!.column;
    // The right-hand button of the left pad sits at the middle of its right third.
    await tester.tapAt(padButton(tester, 0, 5 / 6, 1 / 2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.engine.activePiece!.column, before + 1);
  });

  testWidgets('the top button of the left pad drops the piece', (tester) async {
    final state = await pumpGame(tester);
    expect(state.engine.state.piecesPlaced, 0);
    await tester.tapAt(padButton(tester, 0, 1 / 2, 1 / 6));
    for (var i = 0; i < 20 && state.engine.state.piecesPlaced == 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state.engine.state.piecesPlaced, 1);
  });

  testWidgets('finishing a level announces it, then the next glass comes in', (tester) async {
    final state = await pumpGame(tester, session: const CampaignSession(0));
    expect(find.text('Уровень 1 / 15'), findsOneWidget);

    state.engine.state.score = campaignLevels[0].target;
    await pumpFrames(tester, 2);
    expect(find.text('УРОВЕНЬ 1 ПРОЙДЕН'), findsOneWidget);
    // The game stands still while the banner shows.
    expect(state.engine.sides.length, 1);

    await pumpFrames(tester, 60);
    expect(find.text('Уровень 2 / 15'), findsOneWidget);
    expect(find.text('НОВЫЙ СТАКАН'), findsOneWidget);
    // The second glass grows first and gets its first piece when it is built.
    expect(state.engine.sides.length, 2);
    await pumpFrames(tester, 25);
    expect(state.engine.state.phase, GamePhase.playing);
    expect(state.engine.state.incoming.length, 2);
  });

  testWidgets('a new stage starts again with one glass and more colours', (tester) async {
    final state = await pumpGame(tester, session: const CampaignSession(2));
    state.engine.state.score = campaignLevels[2].target;
    await pumpFrames(tester, 2);
    expect(find.text('УРОВЕНЬ 3 ПРОЙДЕН'), findsOneWidget);

    await pumpFrames(tester, 60);
    expect(find.text('НОВЫЙ ЭТАП'), findsOneWidget);
    expect(state.engine.config.numberOfColors, campaignLevels[3].colours);
    expect(state.engine.sides.length, 1);
  });

  testWidgets('the pause button opens the pause dialog and the game stops', (tester) async {
    final state = await pumpGame(tester);
    await tester.tap(find.text('Пауза'));
    await pumpFrames(tester, 2);
    expect(find.text('Продолжить'), findsOneWidget);

    final before = state.engine.state.elapsedSeconds;
    await pumpFrames(tester, 20);
    expect(state.engine.state.elapsedSeconds, before);

    await tester.tap(find.text('Продолжить'));
    await pumpFrames(tester, 2);
    expect(find.text('Продолжить'), findsNothing);
  });
}
