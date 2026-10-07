import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/sim/bot_player.dart';
import 'package:rotathree/main.dart';
import 'package:rotathree/ui/game_screen.dart';
import 'package:rotathree/ui/lab_panel.dart';

Future<void> _pumpFrames(WidgetTester tester, int frames) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// The status line under the field names the glass that is on top.
Finder _activeGlass(String side) =>
    find.text('ACTIVE GLASS  $side', findRichText: true);

void main() {
  // A phone-sized portrait surface.
  void usePhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('the app starts on the intro and PLAY starts the game', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(const RotathreeApp());
    expect(find.text('ROTATHREE'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('play')));
    await _pumpFrames(tester, 30);
    expect(find.text('ROTATHREE'), findsNothing);
    expect(find.text('SCORE'), findsOneWidget);
    expect(find.text('DROP'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buttons and gestures drive a game without errors', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(showIntro: false)),
    );
    await _pumpFrames(tester, 10);
    expect(_activeGlass('TOP'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('pad-move-left')));
    await tester.tap(find.byKey(const ValueKey('pad-rotate')));
    await tester.tap(find.byKey(const ValueKey('pad-drop')));
    await _pumpFrames(tester, 40);

    // The right-hand button brings the right glass to the top.
    await tester.tap(find.byKey(const ValueKey('pad-turn-right')));
    await _pumpFrames(tester, 30);
    expect(_activeGlass('RIGHT'), findsOneWidget);

    // Swipe on the board: left = next glass, down = drop.
    final field = find.byKey(const ValueKey('field'));
    await tester.drag(field, const Offset(-80, 0));
    await _pumpFrames(tester, 30);
    expect(_activeGlass('BOTTOM'), findsOneWidget);
    await tester.drag(field, const Offset(0, 80));
    await _pumpFrames(tester, 40);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a bot can play in the real screen until game over', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      const MaterialApp(
        home: GameScreen(
          showIntro: false,
          settings: LabSettings(
            config: GameConfig(
              seed: 3,
              activeStepSeconds: 0.25,
              inactiveStepSeconds: 0.5,
            ),
            bot: BotProfile.casual,
          ),
        ),
      ),
    );
    for (var i = 0; i < 4000 && find.text('GAME OVER').evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(find.text('GAME OVER'), findsOneWidget);
    expect(find.text('RESTART'), findsOneWidget);
    expect(find.text('BEST COMBO'), findsWidgets);
    expect(find.text('MATCHES'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('restart')));
    await _pumpFrames(tester, 10);
    expect(find.text('GAME OVER'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the lab panel applies a new configuration', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(
      const MaterialApp(home: GameScreen(showIntro: false)),
    );
    await _pumpFrames(tester, 5);
    await tester.tap(find.byKey(const ValueKey('lab-button')));
    await tester.pump();
    expect(find.text('LAB'), findsOneWidget);

    await tester.tap(find.text('6 s'));
    await tester.tap(find.text('4'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const ValueKey('lab-apply')));
    await tester.tap(find.byKey(const ValueKey('lab-apply')));
    await _pumpFrames(tester, 5);
    expect(find.text('LAB'), findsNothing);
    expect(find.textContaining('1S/6S · 4 COLOURS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
