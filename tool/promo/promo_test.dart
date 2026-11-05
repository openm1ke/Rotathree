// The promo's raw shots: `flutter test tool/promo/promo_test.dart`.
// See tool/promo/README.md.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/cube/rules.dart';
import 'package:rotathree/game/state/game_state.dart';

import 'players.dart';
import 'scenes.dart';
import 'studio.dart';

const out = 'build/promo/raw';

void main() {
  setUpAll(loadFonts);

  for (final device in [iphone, ipad]) {
    for (final language in ['ru', 'en']) {
      testWidgets('shots: ${device.name} $language', (tester) async {
        useDevice(tester, device);
        final key = GlobalKey();
        String path(String name) => '$out/${device.name}/$language/$name.png';
        Future<void> shoot(String name) async => savePng(tester, await capture(tester, key, device.ratio), path(name));

        await openApp(tester, key, language);
        await shoot('menu');

        // Of the moments [moment] picks between frames [from] and [to], the
        // one with the most blocks in play.
        Future<bool> shootFullest(
          String name, {
          required Plan? Function() plan,
          required int from,
          required int to,
          required bool Function() moment,
          required int Function() blocks,
        }) async {
          ui.Image? best;
          var most = -1;
          var was = false;
          await play(tester, plan: plan, frames: to, onFrame: (i) async {
            final now = moment();
            if (i >= from && now && !was && blocks() > most) {
              most = blocks();
              best = await capture(tester, key, device.ratio);
            }
            was = now;
            return false;
          });
          await savePng(tester, best ?? await capture(tester, key, device.ratio), path(name));
          return best != null;
        }

        // Cube: a game played a while, caught as a line pops when the most is
        // in play; then the cube held to tip over, and looked into.
        final cube = await startCube(tester);
        final cubePlayer = CubePlayer(cube.game, seed: 3);
        int cubeBlocks() {
          var count = 0;
          cube.game.hub.forEachBlock((_, _, _) => count++);
          return count;
        }

        await shootFullest(
          'cube',
          plan: cubePlayer.plan,
          from: 1500,
          to: 2700,
          moment: () => cube.game.phase == CubePhase.matching,
          blocks: cubeBlocks,
        );
        await play(tester, plan: cubePlayer.plan, frames: 60, onFrame: (i) async => cube.game.phase == CubePhase.playing);
        // Held to see how it would land if tipped over: it leans in 3D.
        cube.view.startTip(true);
        await play(tester, plan: () => null, frames: 12);
        await shoot('cube-lean');
        cube.view.commitTip(true);
        await play(tester, plan: () => null, frames: 60);
        cube.view.peeking = true;
        await play(tester, plan: () => null, frames: 45);
        await shoot('cube-volume');

        // The cross of four glasses at rest when the most is on it, then a
        // cascade being scored.
        await openApp(tester, key, language);
        final cross = await startCross(tester);
        final flat = FlatPlayer(cross.engine, seed: 5);
        int crossBlocks() => cross.engine.board.blockCount;
        await shootFullest(
          'cross',
          plan: flat.plan,
          from: 1500,
          to: 2600,
          moment: () => cross.engine.phase == GamePhase.matching,
          blocks: crossBlocks,
        );
        final cascaded = await shootFullest(
          'combo',
          plan: flat.plan,
          from: 0,
          to: 1500,
          moment: () => cross.engine.phase == GamePhase.cascading,
          blocks: crossBlocks,
        );
        if (!cascaded) {
          await shootFullest(
            'combo',
            plan: flat.plan,
            from: 0,
            to: 900,
            moment: () => cross.engine.phase == GamePhase.matching,
            blocks: crossBlocks,
          );
        }

        // The Nightmare: six colours, four glasses, the speed rising.
        await openApp(tester, key, language, also: campaignDone());
        final nightmare = await startNightmare(tester);
        await shootFullest(
          'nightmare',
          plan: FlatPlayer(nightmare.engine, seed: 9).plan,
          from: 1200,
          to: 2400,
          moment: () => nightmare.engine.phase == GamePhase.matching,
          blocks: () => nightmare.engine.board.blockCount,
        );

        // The settings: the colours and the pads.
        await openApp(tester, key, language);
        await tapKey(tester, 'menu-settings');
        await tester.tap(find.byType(Tab).at(1));
        await settleApp(tester, frames: 6);
        await shoot('settings-colours');
        await tester.tap(find.byType(Tab).at(0));
        await settleApp(tester, frames: 6);
        await shoot('settings-controls');

        await openApp(tester, key, language);
        await tapKey(tester, 'menu-campaign');
        await shoot('campaign');
        await openApp(tester, key, language);
        await tapKey(tester, 'menu-statistics');
        await tapKey(tester, 'open-achievements');
        await shoot('achievements');
        await tester.pumpWidget(const SizedBox());
      });
    }
  }
}
