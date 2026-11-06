// Every way to draw the blocks, in a campaign level and in Cube, and the
// settings page that picks one: `flutter test tool/promo/skins_test.dart` →
// build/promo/skins.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/field/block_look.dart';
import 'package:rotathree/ui/game/game_screen.dart';
import 'package:rotathree/ui/style.dart';

import 'players.dart';
import 'scenes.dart';
import 'studio.dart';

const out = 'build/promo/skins';
const window = Device('win-1080', 1920, 1040, 1);

void main() {
  setUpAll(loadFonts);

  testWidgets('skins: close up', (tester) async {
    useDevice(tester, const Device('close-up', 1500, 1320, 2));
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: RepaintBoundary(
          key: key,
          child: ColoredBox(
            color: const Color(0xFF0B0B14),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final skin in BlockSkin.values)
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: BlockRow(skin: skin, colours: classicColours, height: 72),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await savePng(tester, await capture(tester, key, 2), '$out/close-up.png');
  });

  for (final skin in BlockSkin.values) {
    testWidgets('skin: ${skin.name}', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        useDevice(tester, window);
        final key = GlobalKey();
        Future<void> shoot(String name) async =>
            savePng(tester, await capture(tester, key, window.ratio), '$out/${skin.name}-$name.png');
        final settings = {'rotathree.settings.v2': jsonEncode(Settings.defaults().copyWith(skin: skin).toJson())};

        await openApp(tester, key, 'ru', also: settings);
        await tapKey(tester, 'menu-campaign');
        final level = find.byKey(const ValueKey('campaign-level-7'));
        await tester.scrollUntilVisible(level, 300, scrollable: find.byType(Scrollable).first);
        await tester.pump(const Duration(milliseconds: 300));
        await tester.tap(level);
        await settleApp(tester, frames: 6);
        final game = tester.state<GameScreenState>(find.byType(GameScreen));
        await play(tester, plan: FlatPlayer(game.engine, seed: 5).plan, frames: 700);
        await shoot('game');

        await openApp(tester, key, 'ru', also: settings);
        final cube = await startCube(tester);
        await play(tester, plan: CubePlayer(cube.game, seed: 3).plan, frames: 500);
        await shoot('cube');

        if (skin == BlockSkin.dice) {
          await openApp(tester, key, 'ru', also: settings);
          await tapKey(tester, 'menu-settings');
          await tester.tap(find.byType(Tab).at(1));
          await settleApp(tester, frames: 6);
          await shoot('settings');
        }
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }
}
