import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/cube/rules.dart';
import 'package:rotathree/cube/save.dart';
import 'package:rotathree/game/config/modes.dart';
import 'package:rotathree/ui/cube/cube_screen.dart';
import 'package:rotathree/ui/data/progress.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/data/stats.dart';

class _Calls {
  final records = <RunRecord>[];
  final saves = <CubeSave?>[];
  Progress? progress;
  int exits = 0, setups = 0, retries = 0;
}

Future<_Calls> _pumpCube(WidgetTester tester, {CubeSave? restore, int? level}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final calls = _Calls();
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: CubeScreen(
        settings: Settings.defaults(),
        blocked: false,
        onSettings: () {},
        onExit: () => calls.exits++,
        onSetup: () => calls.setups++,
        onRetry: () => calls.retries++,
        onRecord: calls.records.add,
        onCheckpoint: calls.saves.add,
        onProgress: (p) => calls.progress = p,
        restore: restore,
        level: level,
      ),
    ),
  ));
  await tester.pump(const Duration(milliseconds: 16));
  return calls;
}

CubeScreenState screen(WidgetTester tester) => tester.state<CubeScreenState>(find.byType(CubeScreen));

Future<void> frames(WidgetTester tester, int count) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  testWidgets('the keys play the cube and the pause keeps it, to come back paused', (tester) async {
    final calls = await _pumpCube(tester);
    final game = screen(tester).game;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(tester, 40);
    expect(game.placed, 1);
    // ← turns the cross clockwise: the glass on the left comes to the top.
    final left = sides.indexWhere((s) => s.axis == 0 && s.sign == -1);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await frames(tester, 40);
    expect(game.down, left);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await frames(tester, 2);
    expect(find.text('Пауза'), findsOneWidget);
    final kept = calls.saves.whereType<CubeSave>().last;
    expect(kept.level, isNull);
    await tester.tap(find.text('В меню'));
    await frames(tester, 2);
    expect(calls.exits, 1);

    final again = await _pumpCube(tester, restore: kept);
    final back = screen(tester).game;
    expect([back.placed, back.down], [1, left]);
    expect(find.text('Пауза'), findsOneWidget);
    expect(again.records, isEmpty);
  });

  testWidgets('a lost game shows what filled up, records the run and forgets the kept one', (tester) async {
    final calls = await _pumpCube(tester);
    final game = screen(tester).game;
    for (var i = 0; i < 400 && !game.isGameOver; i++) {
      game.dropActive();
      await frames(tester, 3);
    }
    await frames(tester, 10);
    expect(find.text('Игра окончена'), findsOneWidget);
    expect(find.textContaining('стакан заполнился до конца рукава'), findsOneWidget);
    expect(calls.records.single.mode, ModeId.cube);
    expect(calls.records.single.interrupted, isFalse);
    expect(calls.saves.last, isNull);
  });

  testWidgets('a level is passed once its points are in, and opens the next', (tester) async {
    final calls = await _pumpCube(tester, level: 0);
    screen(tester).game.score = 1500;
    await frames(tester, 10);
    expect(find.text('Уровень 1 пройден'), findsOneWidget);
    expect(calls.progress?.unlocked, 1);
    expect(calls.records.single.mode, ModeId.cubeCampaign);
    expect(calls.records.single.level, 2);
  });
}
