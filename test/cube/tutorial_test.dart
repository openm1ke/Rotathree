import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/cube/rules.dart';
import 'package:rotathree/cube/tutorial.dart';
import 'package:rotathree/ui/cube/cube_screen.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/input/game_action.dart';

void run(CubeGame game, double seconds) {
  for (var t = 0.0; t < seconds; t += 0.02) {
    game.update(0.02);
  }
}

final back = sides.indexWhere((s) => s.axis == 2 && s.sign == -1);

void main() {
  group('the lessons\' boards, as on the web', () {
    test('hold the sticks still in the lessons, and let them fall in free play', () {
      final held = lessonGame(1);
      final start = held.activePiece!.pivot;
      run(held, 3);
      expect(held.activePiece!.pivot, start);
      final free = lessonGame(cubeLessonLast);
      final top = free.activePiece!.pivot.y;
      run(free, 3);
      expect(free.activePiece!.pivot.y, lessThan(top));
    });

    test('pop a line with the stick on top dropped where it is', () {
      final game = lessonGame(1);
      expect(game.findMatches().runs, isEmpty);
      game.dropActive();
      run(game, 0.3);
      expect(game.matches, 1);
    });

    test('pop the tops of the columns when tipped back over the top', () {
      final game = lessonGame(3);
      const frame = ViewFrame(Vec(1, 0, 0), Vec(0, 0, -1));
      expect(game.findMatches().runs, isEmpty);
      expect(game.previewTurn(const Vec(0, 1, 0), frame).popped, 3);
      game.turn(back, const Vec(0, 1, 0), frame, true);
      run(game, 2);
      expect(game.matches, 1);
    });

    test('start every lesson with nothing to pop', () {
      for (var lesson = 0; lesson <= cubeLessonLast; lesson++) {
        final game = lessonGame(lesson);
        expect(game.findMatches().runs, isEmpty, reason: 'lesson $lesson');
        expect(game.settle(), isEmpty, reason: 'lesson $lesson');
      }
    });

    test('offer to press what the pads have no button for', () {
      expect(missingOnPads(4, defaultCubeLeftPad, defaultCubeRightPad), isNull);
      expect(missingOnPads(4, defaultCubeLeftPad, {...defaultCubeRightPad, PadSlot.center: GameAction.none}), GameAction.peek);
      expect(missingOnPads(0, defaultCubeLeftPad, defaultCubeRightPad), isNull);
    });
  });

  testWidgets('every lesson is done with the keys it teaches, and a miss lays it out again', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    bool? done;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CubeScreen(
          settings: Settings.defaults(),
          blocked: false,
          tutorial: true,
          onTutorialDone: (played) => done = played,
          onSettings: () {},
          onExit: () {},
          onSetup: () {},
          onRetry: () {},
          onRecord: (_) => fail('the lessons record no run'),
        ),
      ),
    ));
    Future<void> frames(int count) async {
      for (var i = 0; i < count; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    Finder lesson(String title) => find.textContaining(title.toUpperCase(), findRichText: true);
    await frames(2);
    expect(lesson('Это куб'), findsOneWidget);
    await tester.tap(find.text('Начать'));
    await frames(30);
    expect(lesson('Линия — из того, что видно'), findsOneWidget);
    // Moved off the gap, the stick misses: the board is laid out again.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(40);
    expect(find.text('Мимо — попробуй ещё раз'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(120);
    expect(lesson('Поверни куб'), findsOneWidget);
    // A key the lesson does not teach is answered with what to press.
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await frames(2);
    expect(find.text('Нажми подсвеченную кнопку'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await frames(120);
    expect(lesson('Поверни скрытые стаканы'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await frames(60);
    expect(find.textContaining('лопнет 3'), findsOneWidget);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await frames(200);
    expect(lesson('Загляни в объём'), findsOneWidget);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyV);
    await frames(150);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyV);
    await frames(60);
    expect(lesson('Теперь сам'), findsOneWidget);
    await tester.tap(find.text('Играть'));
    await frames(2);
    expect(done, isTrue);
  });
}
