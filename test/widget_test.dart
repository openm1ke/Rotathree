import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/model/color.dart';
import 'package:rotathree/game/model/piece.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/state/game_state.dart';
import 'package:rotathree/ui/app.dart';
import 'package:rotathree/ui/game_screen.dart';
import 'package:rotathree/ui/input/dpad.dart';
import 'package:rotathree/ui/settings/pad_action.dart';
import 'package:rotathree/ui/settings/settings.dart';
import 'package:rotathree/ui/settings/settings_store.dart';
import 'package:rotathree/ui/widgets/controls.dart';

/// Runs the app for [seconds], a frame at a time — the game never simulates
/// more than a twentieth of a second per frame.
Future<void> run(WidgetTester tester, double seconds) async {
  for (var t = 0.0; t < seconds - 1e-9; t += 1 / 60) {
    await tester.pump(const Duration(microseconds: 16667));
  }
}

/// Starts the app on a phone-sized portrait screen and waits for the menu.
Future<MemorySettingsStore> startApp(
  WidgetTester tester, {
  Settings settings = const Settings(),
}) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final store = MemorySettingsStore(settings);
  await tester.pumpWidget(RotathreeApp(store: store, seed: 7));
  await run(tester, 1.2);
  return store;
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await run(tester, 0.6);
}

GameScreenState game(WidgetTester tester) =>
    tester.state<GameScreenState>(find.byType(GameScreen));

GameEngine engineOf(WidgetTester tester) => game(tester).engine;

/// The middle of one button of a pad.
Offset slot(WidgetTester tester, String pad, PadSlot slot) {
  final rect = tester.getRect(find.byKey(ValueKey(pad)));
  final third = rect.width / 3;
  return rect.center +
      switch (slot) {
        PadSlot.up => Offset(0, -third),
        PadSlot.down => Offset(0, third),
        PadSlot.left => Offset(-third, 0),
        PadSlot.right => Offset(third, 0),
        PadSlot.center => Offset.zero,
      };
}

Future<void> press(WidgetTester tester, String pad, PadSlot at) async {
  await tester.tapAt(slot(tester, pad, at));
  await tester.pump(const Duration(milliseconds: 16));
}

void main() {
  testWidgets('the app opens on the menu and Играть starts a game', (tester) async {
    await startApp(tester);
    expect(find.text('ИГРАТЬ'), findsOneWidget);
    expect(find.text('ДЗЕН'), findsOneWidget);
    expect(find.text('НАСТРОЙКИ'), findsOneWidget);

    await tapKey(tester, 'menu-play');
    expect(find.text('ИГРАТЬ'), findsNothing);
    expect(find.text('СЧЁТ'), findsOneWidget);
    expect(find.byType(DPad), findsNWidgets(2));
    expect(game(tester).status, GameStatus.playing);
    expect(engineOf(tester).state.incoming, hasLength(4));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the left pad steers the piece', (tester) async {
    await startApp(tester);
    await tapKey(tester, 'menu-play');
    final engine = engineOf(tester);
    final piece = engine.activePiece!;
    final start = piece.column;

    await press(tester, 'pad-left', PadSlot.left);
    expect(piece.column, start - 1);

    // Held, a direction repeats until the wall stops it.
    final hold = await tester.startGesture(slot(tester, 'pad-left', PadSlot.right));
    await run(tester, 0.7);
    await hold.up();
    expect(piece.column, 10 - piece.piece.width);

    // Soft drop works while the button is held and no longer.
    final row = piece.row;
    final soft = await tester.startGesture(slot(tester, 'pad-left', PadSlot.down));
    await run(tester, 0.3);
    await soft.up();
    expect(piece.row, greaterThan(row + 3));
    final after = piece.row;
    await run(tester, 0.3);
    expect(piece.row, lessThanOrEqualTo(after + 1));

    await press(tester, 'pad-left', PadSlot.up);
    await run(tester, 0.6);
    expect(engine.state.piecesPlaced, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the right pad turns the piece and the cross', (tester) async {
    await startApp(tester);
    await tapKey(tester, 'menu-play');
    final engine = engineOf(tester);
    final piece = engine.activePiece!;

    await press(tester, 'pad-right', PadSlot.up);
    expect(piece.piece.orientation, PieceOrientation.vertical);
    await press(tester, 'pad-right', PadSlot.down);
    await press(tester, 'pad-right', PadSlot.down);
    expect(piece.piece.orientation, PieceOrientation.verticalFlipped);

    await press(tester, 'pad-right', PadSlot.right);
    expect(engine.activeSide, Side.right);
    await press(tester, 'pad-right', PadSlot.center);
    expect(engine.activeSide, Side.left);
    await press(tester, 'pad-right', PadSlot.left);
    expect(engine.activeSide, Side.bottom);
    await run(tester, 0.5);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tapping a glass on the field brings it to the top', (tester) async {
    await startApp(tester);
    await tapKey(tester, 'menu-play');
    final field = tester.getRect(find.byKey(const ValueKey('field')));
    await tester.tapAt(field.centerRight - const Offset(40, 0));
    await run(tester, 0.4);
    expect(engineOf(tester).activeSide, Side.right);
    // The centre does nothing unless field gestures are switched on.
    final piece = engineOf(tester).activePiece!;
    await tester.tapAt(field.center);
    await run(tester, 0.4);
    expect(piece.piece.orientation, PieceOrientation.horizontal);
  });

  testWidgets('pause stops the clock and continue starts it again', (tester) async {
    await startApp(tester);
    await tapKey(tester, 'menu-play');
    final engine = engineOf(tester);

    await tester.tap(find.byIcon(Icons.pause_rounded));
    await run(tester, 0.5);
    expect(find.text('ПАУЗА'), findsOneWidget);
    final frozenAt = engine.state.elapsedSeconds;
    await run(tester, 1);
    expect(engine.state.elapsedSeconds, frozenAt);

    await tester.tap(find.text('ПРОДОЛЖИТЬ'));
    await run(tester, 0.5);
    expect(find.text('ПАУЗА'), findsNothing);
    expect(engine.state.elapsedSeconds, greaterThan(frozenAt));

    // From the pause menu back to the main one.
    await tester.tap(find.byIcon(Icons.pause_rounded));
    await run(tester, 0.5);
    await tester.tap(find.text('В МЕНЮ'));
    await run(tester, 0.8);
    expect(find.text('ИГРАТЬ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings freeze the game, are saved, and new rules start a new game',
      (tester) async {
    final store = await startApp(tester);
    await tapKey(tester, 'menu-play');
    await press(tester, 'pad-left', PadSlot.up);
    await run(tester, 0.6);
    expect(engineOf(tester).state.piecesPlaced, 1);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await run(tester, 0.5);
    expect(find.text('НАСТРОЙКИ'), findsOneWidget);
    final frozenAt = engineOf(tester).state.elapsedSeconds;
    await run(tester, 0.5);
    expect(engineOf(tester).state.elapsedSeconds, frozenAt);

    // How the screen looks does not touch the running game.
    await tester.tap(find.text('ИНТЕРФЕЙС'));
    await run(tester, 0.3);
    await tester.tap(find.text('скрыть').first);
    await run(tester, 0.3);
    expect(store.settings.hud.padLabels, isFalse);
    expect(engineOf(tester).state.piecesPlaced, 1);

    // The rules do: five colours and one extra glass start a new game.
    await tester.tap(find.text('ИГРА'));
    await run(tester, 0.3);
    final fiveColours = find.widgetWithText(ChipButton, '5');
    await tester.ensureVisible(fiveColours);
    await tester.tap(fiveColours);
    await run(tester, 0.3);
    final oneMoreGlass = find.widgetWithText(ChipButton, '1');
    await tester.ensureVisible(oneMoreGlass);
    await tester.tap(oneMoreGlass);
    await run(tester, 0.3);
    expect(store.settings.game.numberOfColors, 5);
    expect(store.settings.game.glassCount, 2);

    await tapKey(tester, 'settings-close');
    final engine = engineOf(tester);
    expect(engine.config.numberOfColors, 5);
    expect(engine.sides, [Side.top, Side.right]);
    expect(engine.state.piecesPlaced, 0);
    expect(find.text('СБРОС'), findsNothing); // the labels are hidden
    expect(tester.takeException(), isNull);
  });

  testWidgets('a pad button can be given another action', (tester) async {
    final store = await startApp(tester);
    await tapKey(tester, 'menu-settings');
    // The first "Центр" row belongs to the left pad.
    await tester.tap(find.byKey(const ValueKey('slot-center')).first);
    await run(tester, 0.5);
    await tester.tap(find.text('Пауза').last);
    await run(tester, 0.5);
    expect(store.settings.pads.left[PadSlot.center], PadAction.pause);
    expect(store.settings.pads.right, defaultRightPad);
    await tapKey(tester, 'settings-close');

    await tapKey(tester, 'menu-play');
    await press(tester, 'pad-left', PadSlot.center);
    await run(tester, 0.4);
    expect(game(tester).status, GameStatus.paused);
    expect(tester.takeException(), isNull);
  });

  testWidgets('saved settings are in force from the start', (tester) async {
    await startApp(
      tester,
      settings: const Settings(
        game: GameOptions(glassCount: 3, numberOfColors: 6, armLength: 6),
      ),
    );
    await tapKey(tester, 'menu-play');
    final engine = engineOf(tester);
    expect(engine.sides, [Side.top, Side.right, Side.left]);
    expect(engine.config.numberOfColors, 6);
    expect(engine.config.armLength, 6);
    await run(tester, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('zen: reaching the score of a level is celebrated, then play goes on',
      (tester) async {
    await startApp(tester);
    await tapKey(tester, 'menu-zen');
    final engine = engineOf(tester);
    expect(find.text('УРОВЕНЬ 1'), findsOneWidget);

    engine.state.score = 1100;
    await run(tester, 0.2);
    expect(game(tester).status, GameStatus.levelUp);
    expect(find.text('УРОВЕНЬ 1 ПРОЙДЕН'), findsOneWidget);
    expect(find.text('УРОВЕНЬ 2', findRichText: true), findsWidgets);

    // The game stands still while the level is announced…
    final frozenAt = engine.state.elapsedSeconds;
    final piece = engine.activePiece!;
    await press(tester, 'pad-left', PadSlot.left);
    await run(tester, 1);
    expect(engine.state.elapsedSeconds, frozenAt);
    expect(piece.column, engine.incoming.spawnColumn);

    // …and carries on from where it was.
    await run(tester, GameScreenState.levelUpSeconds);
    expect(game(tester).status, GameStatus.playing);
    expect(find.text('УРОВЕНЬ 1 ПРОЙДЕН'), findsNothing);
    expect(find.text('УРОВЕНЬ 2'), findsOneWidget);
    expect(engine.state.elapsedSeconds, greaterThan(frozenAt));
    expect(engine.state.score, 1100);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a lost zen game offers to start over from level one', (tester) async {
    await startApp(tester);
    await tapKey(tester, 'menu-zen');
    final engine = engineOf(tester);
    engine.state.score = 1300;
    await run(tester, GameScreenState.levelUpSeconds + 0.5);
    expect(find.text('УРОВЕНЬ 2'), findsOneWidget);

    // Fill the lanes where the top glass gets its pieces, right up to the end.
    final arm = engine.config.armLength;
    for (var row = 0; row < arm + 10; row++) {
      for (var lane = 3; lane <= 5; lane++) {
        engine.board.set(
          row,
          arm + lane,
          (row + lane).isEven ? BlockColor.red : BlockColor.blue,
        );
      }
    }
    await run(tester, 3);
    expect(engine.phase, GamePhase.gameOver);
    expect(find.text('ИГРА ОКОНЧЕНА'), findsOneWidget);
    expect(find.textContaining('Начнёте заново с первого уровня?'), findsOneWidget);

    await tester.tap(find.text('НАЧАТЬ ЗАНОВО'));
    await run(tester, 0.6);
    expect(game(tester).status, GameStatus.playing);
    expect(engine.board.isEmpty, isTrue);
    expect(engine.state.score, 0);
    expect(find.text('УРОВЕНЬ 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
