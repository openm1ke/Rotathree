// The desktop app's screens at the sizes of a computer's window, to look at
// while the desktop layout is worked on:
// `flutter test tool/promo/desktop_test.dart` → build/promo/desktop.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/state/game_state.dart';
import 'package:rotathree/ui/game/game_screen.dart';

import 'players.dart';
import 'scenes.dart';
import 'studio.dart';

const out = 'build/promo/desktop';

/// Windows at 100 %: a small window and a full-screen one; a MacBook; and a
/// phone, to see that it stays as it was.
const windows = [
  Device('win-720', 1280, 690, 1),
  Device('win-1080', 1920, 1040, 1),
  Device('mac', 2880, 1760, 2),
  Device('phone', 1179, 2556, 3),
];

void main() {
  setUpAll(loadFonts);

  for (final device in windows) {
    testWidgets('desktop: ${device.name}', (tester) async {
      if (device.name != 'phone') debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        useDevice(tester, device);
        final key = GlobalKey();
        Future<void> shoot(String name) async =>
            savePng(tester, await capture(tester, key, device.ratio), '$out/${device.name}/$name.png');

        await openApp(tester, key, 'ru');
        await shoot('menu');

        await tapKey(tester, 'menu-tutorial');
        await shoot('tutorial-1');
        final lesson = tester.state<GameScreenState>(find.byType(GameScreen));
        lesson.debugEnterLesson(5);
        await play(tester, plan: () => null, frames: 40);
        await shoot('tutorial-6');

        await openApp(tester, key, 'ru');
        await tapKey(tester, 'menu-campaign');
        final level = find.byKey(const ValueKey('campaign-level-7'));
        await tester.scrollUntilVisible(level, 300, scrollable: find.byType(Scrollable).first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(level);
        await settleApp(tester, frames: 6);
        final game = tester.state<GameScreenState>(find.byType(GameScreen));
        final player = FlatPlayer(game.engine, seed: 5);
        var popped = false;
        await play(tester, plan: player.plan, frames: 900, onFrame: (i) async {
          if (i > 500 && !popped && game.engine.phase == GamePhase.matching) {
            popped = true;
            await shoot('campaign');
          }
          return false;
        });
        if (!popped) await shoot('campaign');
        if (device.name == 'phone') {
          await tester.tap(find.byTooltip('Пауза'));
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await settleApp(tester, frames: 6);
        await shoot('pause');

        await openApp(tester, key, 'ru');
        final cube = await startCube(tester);
        await play(tester, plan: CubePlayer(cube.game, seed: 3).plan, frames: 400);
        await shoot('cube');
        if (device.name == 'phone') {
          await tester.tap(find.byTooltip('Пауза'));
        } else {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        }
        await settleApp(tester, frames: 6);
        await shoot('cube-pause');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
