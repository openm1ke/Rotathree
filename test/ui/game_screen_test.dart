import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/modes.dart';
import 'package:rotathree/game/config/campaign.dart';
import 'package:rotathree/game/session.dart';
import 'package:rotathree/game/state/game_state.dart';
import 'package:rotathree/ui/data/progress.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/game/game_screen.dart';
import 'package:rotathree/ui/game/campaign_progress.dart';
import 'package:rotathree/ui/input/dpad.dart';
import 'package:rotathree/ui/input/pad_placement.dart';
import 'package:rotathree/ui/data/run_save.dart';
import 'package:rotathree/ui/data/stats.dart';
import 'package:rotathree/ui/input/game_action.dart';
import 'package:rotathree/ui/game/tutorial.dart';
import 'package:rotathree/ui/field/field_painter.dart';

Future<GameScreenState> pumpGame(
  WidgetTester tester, {
  Session session = const CustomSession(defaultCustom),
  RunSave? restore,
  bool tutorial = false,
  bool blocked = false,
  Settings? settings,
  VoidCallback? onExit,
  ValueChanged<RunSave?>? onCheckpoint,
  ValueChanged<RunRecord>? onRecord,
  Size size = const Size(390, 844),
  VoidCallback? onTutorialDone,
  ValueChanged<bool>? onPauseChanged,
  VoidCallback? onToggleMusic,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(
    MaterialApp(
      home: GameScreen(
        session: session,
        settings: settings ?? Settings.defaults(),
        progress: Progress.initial(),
        blocked: blocked,
        restore: restore,
        tutorial: tutorial,
        onTutorialDone: onTutorialDone,
        onPauseChanged: onPauseChanged,
        onToggleMusic: onToggleMusic,
        onCheckpoint: onCheckpoint,
        onSettings: () {},
        onExit: onExit ?? () {},
        onLevels: () {},
        onRetry: (_) {},
        onInsane: () {},
        onCustomise: () {},
        onRecord: onRecord ?? (_) {},
        onProgress: (_) {},
      ),
    ),
  );
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
  testWidgets('campaign goal uses level points in a thin header above the field on a small phone', (tester) async {
    final state = await pumpGame(tester, session: const CampaignSession(0), size: const Size(320, 568),
      settings: Settings.defaults().copyWith(hud: const HudOptions(score: false, stats: false)));
    state.engine.state.score = 600;
    await pumpFrames(tester, 2);
    final progress = tester.widget<CampaignProgress>(find.byType(CampaignProgress));
    expect(progress.into, 600);
    expect(progress.target, campaignLevels.first.target);
    expect(find.text('600 / 1 200'), findsOneWidget);
    expect(find.text('Ещё 600'), findsNothing);
    expect(find.text('Цель'), findsNothing);
    final bar = tester.getRect(find.byType(CampaignProgress));
    final field = tester.getRect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FieldPainter));
    expect(bar.bottom, lessThanOrEqualTo(field.top));
    expect(bar.height, lessThanOrEqualTo(14));
    expect(field.width, 320);
    expect(bar.left, greaterThanOrEqualTo(0));
    expect(bar.right, lessThanOrEqualTo(320));
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('Пауза'));
    await tester.pump();
    expect(tester.widget<CampaignProgress>(find.byType(CampaignProgress)).animated, isFalse);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('small phone reclaims free pad space without overlapping controls or moving the header', (tester) async {
    tester.view.padding = const FakeViewPadding(top: 24, bottom: 34);
    addTearDown(tester.view.resetPadding);
    final defaults = Settings.defaults();
    await pumpGame(tester, session: const CampaignSession(0), size: const Size(320, 568));
    final fieldFinder = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is FieldPainter);
    final field = tester.getRect(fieldFinder);
    final pause = tester.getRect(find.byTooltip('Пауза'));
    final settingsButton = tester.getRect(find.byTooltip('Настройки'));
    final score = tester.getRect(find.text('0').first);
    expect(pause.center.dy, settingsButton.center.dy);
    expect((pause.center.dy - score.center.dy).abs(), lessThan(2));
    expect(pause.width, greaterThanOrEqualTo(44));
    expect(field.width, greaterThan(290));
    for (var i = 0; i < 2; i++) {
      expect(field.bottom, lessThanOrEqualTo(tester.getRect(find.byType(DPad).at(i)).top));
    }
    final bottomPad = tester.getRect(find.byType(DPad).first);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpGame(tester, session: const CampaignSession(0), size: const Size(320, 568),
      settings: defaults.copyWith(padPositions: PadPositions(
        left: defaults.padPositions.left.copyWith(y: 0), right: defaults.padPositions.right)));
    final smallerField = tester.getRect(fieldFinder);
    expect(smallerField.width, lessThan(field.width - 20));
    expect(tester.getRect(find.byType(DPad).first).top, lessThan(bottomPad.top));
    expect(tester.getRect(find.byTooltip('Пауза')), pause);
    for (var i = 0; i < 2; i++) {
      expect(smallerField.bottom, lessThanOrEqualTo(tester.getRect(find.byType(DPad).at(i)).top));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('custom games and training have no campaign goal', (tester) async {
    await pumpGame(tester);
    expect(find.byType(CampaignProgress), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await pumpGame(tester, tutorial: true, session: const CampaignSession(0));
    expect(find.byType(CampaignProgress), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('training leaves through Back without completing the tutorial or showing a pause', (tester) async {
    var exits = 0, completions = 0;
    final state = await pumpGame(
      tester,
      tutorial: true,
      session: CustomSession(defaultCustom.copyWith(extraGlasses: 0)),
      onExit: () => exits++,
      onTutorialDone: () => completions++,
    );
    expect(find.text('Пауза'), findsNothing);
    expect(find.byTooltip('Настройки'), findsOneWidget);
    expect(tester.getSize(find.byType(TutorialPanel)).height, lessThan(190));
    final field = find.byWidgetPredicate((widget) => widget is CustomPaint && widget.painter is FieldPainter);
    expect(tester.getSize(field).height, greaterThan(280));
    state.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tester.pump();
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.text('Пауза'), findsNothing);
    await tester.tap(find.byTooltip('Назад'));
    expect(exits, 1);
    expect(completions, 0);
  });

  testWidgets('the right arrow of the left pad moves the piece one lane', (tester) async {
    final state = await pumpGame(tester);
    final before = state.engine.activePiece!.column;
    // The right-hand button of the left pad sits at the middle of its right third.
    await tester.tapAt(padButton(tester, 0, 5 / 6, 1 / 2));
    await tester.pump(const Duration(milliseconds: 50));
    expect(state.engine.activePiece!.column, before + 1);
  });

  testWidgets('left pad rotates at the top, drops at the bottom and leaves its center unassigned', (tester) async {
    final state = await pumpGame(tester);
    expect(state.engine.state.piecesPlaced, 0);
    final before = state.engine.activePiece!.piece.orientation;
    await tester.tapAt(padButton(tester, 0, 1 / 2, 1 / 6));
    await tester.pump();
    expect(state.engine.activePiece!.piece.orientation, before.clockwise);
    await tester.tapAt(padButton(tester, 0, 1 / 2, 1 / 2));
    await tester.pump();
    expect(state.engine.state.piecesPlaced, 0);
    expect(state.engine.activePiece!.piece.orientation, before.clockwise);
    await tester.tapAt(padButton(tester, 0, 1 / 2, 5 / 6));
    for (var i = 0; i < 20 && state.engine.state.piecesPlaced == 0; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state.engine.state.piecesPlaced, 1);
  });

  testWidgets('finishing a level announces it, then the next glass comes in', (tester) async {
    final state = await pumpGame(tester, session: const CampaignSession(0));
    expect(find.byTooltip('Уровень 1 / 16'), findsOneWidget);

    state.engine.state.score = campaignLevels[0].target;
    await pumpFrames(tester, 2);
    expect(find.text('УРОВЕНЬ 1 ПРОЙДЕН'), findsOneWidget);
    // The game stands still while the banner shows.
    expect(state.engine.sides.length, 1);

    await pumpFrames(tester, 60);
    expect(find.byTooltip('Уровень 2 / 16'), findsOneWidget);
    expect(find.text('НОВЫЙ СТАКАН'), findsOneWidget);
    // The second glass grows first and gets its first piece when it is built.
    expect(state.engine.sides.length, 2);
    await pumpFrames(tester, 25);
    expect(state.engine.state.phase, GamePhase.playing);
    expect(state.engine.state.incoming.length, 2);
  });

  testWidgets('a new stage starts again with one glass and more colours', (tester) async {
    final state = await pumpGame(tester, session: const CampaignSession(3));
    state.engine.state.score = campaignLevels[3].target;
    await pumpFrames(tester, 2);
    expect(find.text('УРОВЕНЬ 4 ПРОЙДЕН'), findsOneWidget);

    await pumpFrames(tester, 60);
    expect(find.text('НОВЫЙ ЭТАП'), findsOneWidget);
    expect(state.engine.config.numberOfColors, campaignLevels[4].colours);
    expect(state.engine.sides.length, 1);
  });

  testWidgets('the music switch stands beside the gear in a game and in training', (tester) async {
    for (final tutorial in [false, true]) {
      var toggles = 0;
      await pumpGame(tester, tutorial: tutorial, onToggleMusic: () => toggles++);
      final sound = find.byTooltip('Выключить музыку');
      expect(sound, findsOneWidget);
      final gear = tester.getRect(find.byTooltip('Настройки'));
      expect(tester.getRect(sound).right, lessThan(gear.left));
      expect(gear.left - tester.getRect(sound).right, lessThan(12));
      await tester.tap(sound);
      expect(toggles, 1);
    }
  });

  testWidgets('the pause button opens the pause dialog and the game stops', (tester) async {
    final pauses = <bool>[];
    final state = await pumpGame(tester, onPauseChanged: pauses.add);
    await tester.tap(find.byTooltip('Пауза'));
    await pumpFrames(tester, 2);
    expect(find.text('Продолжить'), findsOneWidget);
    expect(pauses.last, isTrue);

    final before = state.engine.state.elapsedSeconds;
    await pumpFrames(tester, 20);
    expect(state.engine.state.elapsedSeconds, before);

    await tester.tap(find.text('Продолжить'));
    await pumpFrames(tester, 2);
    expect(find.text('Продолжить'), findsNothing);
    expect(pauses.last, isFalse);
    state.didChangeAppLifecycleState(AppLifecycleState.inactive);
    await tester.pump();
    expect(pauses.last, isTrue);
    state.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(pauses.last, isTrue);
  });

  testWidgets('a level banner stays frozen in pause and survives saving', (tester) async {
    RunSave? save;
    final state = await pumpGame(tester, session: const CampaignSession(0), onCheckpoint: (value) => save = value);
    state.engine.state.score = campaignLevels[0].target;
    await pumpFrames(tester, 2);
    await tester.tap(find.byTooltip('Пауза'));
    await pumpFrames(tester, 80);
    expect(state.engine.sides.length, 1);
    expect(save!.banner!.pendingLevel, 1);
    final checked = RunSave.read(save!.toJson())!;
    await tester.pumpWidget(const SizedBox());
    final resumed = await pumpGame(tester, session: checked.session, restore: checked);
    await pumpFrames(tester, 80);
    expect(resumed.engine.sides.length, 1);
    await tester.tap(find.text('Продолжить'));
    await pumpFrames(tester, 60);
    expect(find.byTooltip('Уровень 2 / 16'), findsOneWidget);
    expect(resumed.engine.sides.length, 2);
  });

  testWidgets('settings freeze the level banner as well as falling', (tester) async {
    final state = await pumpGame(tester, session: const CampaignSession(0));
    state.engine.state.score = campaignLevels[0].target;
    await pumpFrames(tester, 2);
    // Keep the same screen state while opening settings above it.
    final original = tester.widget<GameScreen>(find.byType(GameScreen));
    await tester.pumpWidget(
      MaterialApp(
        home: GameScreen(
          session: original.session,
          settings: original.settings,
          progress: original.progress,
          blocked: true,
          onSettings: () {},
          onExit: () {},
          onLevels: () {},
          onRetry: (_) {},
          onInsane: () {},
          onCustomise: () {},
          onRecord: (_) {},
          onProgress: (_) {},
        ),
      ),
    );
    await pumpFrames(tester, 80);
    expect(state.engine.sides.length, 1);
    expect(find.text('УРОВЕНЬ 1 ПРОЙДЕН'), findsOneWidget);
  });

  testWidgets('finishing from pause records a run once and clears its save', (tester) async {
    final records = <RunRecord>[];
    RunSave? save;
    final state = await pumpGame(tester, onCheckpoint: (value) => save = value, onRecord: records.add);
    await tester.tap(find.byTooltip('Пауза'));
    await tester.pump();
    expect(save, isNotNull);
    await tester.tap(find.text('Завершить партию'));
    await tester.pump();
    expect(records.single.interrupted, isTrue);
    expect(save, isNull);
    state.handleBack();
    await tester.pump();
    expect(records.length, 1);
  });

  testWidgets('system Back saves the current field and exits without ending the run', (tester) async {
    RunSave? saved;
    var exited = false;
    final records = <RunRecord>[];
    final state = await pumpGame(
      tester,
      onExit: () => exited = true,
      onCheckpoint: (value) => saved = value,
      onRecord: records.add,
    );
    state.move(1, toWall: false);
    state.handleBack();
    expect(exited, isTrue);
    expect(saved!.engine, state.engine.snapshot());
    expect(records, isEmpty);
  });
  testWidgets('training uses customized pad bindings and positions', (tester) async {
    final settings = Settings.defaults().copyWith(
      leftPad: {...defaultLeftPad, PadSlot.up: GameAction.none, PadSlot.down: GameAction.rotateCW},
      rightPad: {...defaultRightPad, PadSlot.up: GameAction.hardDrop},
    );
    final state = await pumpGame(tester, tutorial: true, settings: settings);
    final left = tester.widget<DPad>(find.byType(DPad).first);
    expect(left.layout[PadSlot.down], GameAction.rotateCW);
    await tester.tap(find.text('Дальше'));
    await tester.pump();
    state.move(1, toWall: false);
    await tester.pump();
    await tester.tap(find.text('✓ Дальше'));
    await tester.pump();
    await tester.tapAt(padButton(tester, 0, .5, 5 / 6));
    await tester.pump();
    expect(find.text('✓ Дальше'), findsOneWidget);
    expect(find.descendant(of: find.byType(TutorialPanel), matching: find.text('Левая')), findsOneWidget);
    expect(tester.widget<TutorialPanel>(find.byType(TutorialPanel)).controls.first.keys, ['↓']);
  });

  testWidgets('phone tutorial requires each action and resolves a real match', (tester) async {
    var done = false;
    final state = await pumpGame(
      tester,
      tutorial: true,
      size: const Size(320, 568),
      session: CustomSession(defaultCustom.copyWith(extraGlasses: 0)),
      onTutorialDone: () => done = true,
    );
    final row = state.engine.activePiece!.row;
    await pumpFrames(tester, 80);
    expect(state.engine.activePiece!.row, row);
    await tester.tap(find.text('Дальше'));
    await tester.pump();
    state.press(GameAction.hardDrop);
    expect(state.engine.phase, GamePhase.playing);
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
    expect(state.engine.state.matches, greaterThan(0));
    await tester.tap(find.text('✓ Дальше'));
    await tester.pump();
    await pumpFrames(tester, 25);
    state.press(GameAction.glassRight);
    await tester.pump();
    await tester.tap(find.text('✓ Дальше'));
    await tester.pump();
    await tester.tap(find.text('Играть'));
    await tester.pump();
    expect(done, isTrue);
    expect(tester.takeException(), isNull);
  });
}
