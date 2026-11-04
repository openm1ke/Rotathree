// The video's raw frames, filmed from the app at the App Store preview's
// size: `flutter test tool/promo/reel_test.dart`. See tool/promo/README.md.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'players.dart';
import 'scenes.dart';
import 'studio.dart';

const out = 'build/promo/reel';

/// The scenes filmed, and how many frames of each, at 30 a second.
const reel = {'cube': 180, 'tip': 90, 'volume': 90, 'cross': 210};

void main() {
  setUpAll(loadFonts);

  for (final language in ['ru', 'en']) {
    testWidgets('reel $language', (tester) async {
      useDevice(tester, preview);
      final key = GlobalKey();
      var scene = '';
      var count = 0;
      Future<bool> film(int frame) async {
        await savePng(tester, await capture(tester, key, preview.ratio), '$out/$language/$scene/${count.toString().padLeft(4, '0')}.png');
        count++;
        return false;
      }

      void begin(String name) {
        scene = name;
        count = 0;
      }

      // Cube, some way into a game.
      await openApp(tester, key, language);
      final cube = await startCube(tester);
      final cubePlayer = CubePlayer(cube.game, seed: 7);
      await play(tester, plan: cubePlayer.plan, frames: 1500);
      begin('cube');
      await play(tester, plan: cubePlayer.plan, frames: reel['cube']!, onFrame: film);

      // Held to see how it lands, then tipped over: the depth falls and pops.
      begin('tip');
      cube.view.startTip(true);
      await play(tester, plan: () => null, frames: 24, onFrame: film);
      cube.view.commitTip(true);
      await play(tester, plan: () => null, frames: reel['tip']! - 24, onFrame: film);

      // Looked into.
      begin('volume');
      cube.view.peeking = true;
      await play(tester, plan: () => null, frames: reel['volume']!, onFrame: film);

      // The cross of four glasses, some way into a game.
      await openApp(tester, key, language);
      final cross = await startCross(tester);
      final flat = FlatPlayer(cross.engine, seed: 5);
      await play(tester, plan: flat.plan, frames: 1500);
      begin('cross');
      await play(tester, plan: flat.plan, frames: reel['cross']!, onFrame: film);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
