// Scenes for the promo: the app opened with a player's results already in
// it, walked to a screen, and its games played by the players.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/cube/campaign.dart';
import 'package:rotathree/game/config/campaign.dart';
import 'package:rotathree/game/config/modes.dart';
import 'package:rotathree/ui/app.dart';
import 'package:rotathree/ui/cube/cube_screen.dart';
import 'package:rotathree/ui/data/progress.dart';
import 'package:rotathree/ui/data/stats.dart';
import 'package:rotathree/ui/game/game_screen.dart';
import 'package:rotathree/ui/widgets/controls.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'players.dart';

const frame = Duration(microseconds: 33333);

/// A player some way into the game: seven levels and two of Cube's passed,
/// a few dozen games, the lessons played.
Map<String, Object> playedPrefs() {
  var progress = Progress.initial();
  for (var level = 0; level < 7; level++) {
    progress = progress.levelFinished(level, campaignLevels[level].target + 300 * level);
  }
  var cube = defaultCubeProgress();
  for (var level = 0; level < 2; level++) {
    cube = cube.levelFinished(level, cubeCampaign[level].target + 200);
  }
  Stats stats = Stats.empty();
  final modes = {
    ModeId.campaign: const ModeStats(games: 11, totalScore: 31800, bestScore: 6200, totalPieces: 820, totalMatches: 240, bestCombo: 4, totalSeconds: 2900, bestLevel: 8),
    ModeId.custom: const ModeStats(games: 4, totalScore: 9200, bestScore: 4100, totalPieces: 260, totalMatches: 70, bestCombo: 3, totalSeconds: 800, bestLevel: 2),
    ModeId.cube: const ModeStats(games: 3, totalScore: 7400, bestScore: 3600, totalPieces: 190, totalMatches: 55, bestCombo: 3, totalSeconds: 700, bestLevel: 2),
  };
  stats = Stats(modes: {...stats.modes, ...modes}, recent: const []);
  final at = DateTime(2026, 11, 3).millisecondsSinceEpoch;
  return {
    'rotathree.tutorial.v1': 'true',
    'rotathree.cube-tutorial.v1': 'true',
    'rotathree.progress.v1': jsonEncode(progress.toJson()),
    'rotathree.cube-progress.v1': jsonEncode(cube.toJson()),
    'rotathree.stats.v1': jsonEncode(stats.toJson()),
    'rotathree.achievements.v1': jsonEncode({'LESSONS': at, 'CUBE_LESSONS': at}),
    'rotathree.custom.v1': jsonEncode(defaultCustom.copyWith(extraGlasses: 3, colours: 4).toJson()),
  };
}

/// The campaign played through, which opens the Nightmare.
Map<String, Object> campaignDone() {
  var progress = Progress.initial();
  for (var level = 0; level < campaignLevels.length; level++) {
    progress = progress.levelFinished(level, campaignLevels[level].target + 400);
  }
  return {'rotathree.progress.v1': jsonEncode(progress.toJson())};
}

/// Opens the app afresh in [language] under [key], on its menu, with
/// [also] in its store over [playedPrefs].
Future<void> openApp(WidgetTester tester, GlobalKey key, String language, {Map<String, Object> also = const {}}) async {
  tester.binding.platformDispatcher.localesTestValue = [Locale(language)];
  SharedPreferences.setMockInitialValues({...playedPrefs(), ...also});
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(RepaintBoundary(key: key, child: const RotathreeApp()));
  await settleApp(tester);
}

/// Lets real time pass for what the app reads from its store, then frames.
Future<void> settleApp(WidgetTester tester, {int frames = 12}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(ValueKey(key)));
  await settleApp(tester, frames: 6);
}

/// The last GoButton on the screen: Play, Start.
Future<void> tapGo(WidgetTester tester) async {
  final go = find.byType(GoButton);
  await tester.scrollUntilVisible(go, 400, scrollable: find.byType(Scrollable).first);
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(go.last);
  await settleApp(tester, frames: 6);
}

/// Plays a game with [plan] for up to [frames] frames: a plan is made when
/// the game is at rest, and its inputs given one every [pace] frames.
/// [onFrame] sees each frame after it is drawn, and stops the play by
/// returning true.
Future<void> play(
  WidgetTester tester, {
  required Plan? Function() plan,
  required int frames,
  int pace = 3,
  Future<bool> Function(int frame)? onFrame,
}) async {
  Plan? now;
  for (var i = 0; i < frames; i++) {
    if (now == null || now.done) {
      now = plan() ?? now;
    } else if (i % pace == 0) {
      now.step();
    }
    await tester.pump(frame);
    if (await onFrame?.call(i) ?? false) return;
  }
}

/// Cube's screen, its game started from the menu.
Future<CubeScreenState> startCube(WidgetTester tester) async {
  await tapKey(tester, 'menu-cube');
  await tapGo(tester);
  return tester.state<CubeScreenState>(find.byType(CubeScreen));
}

/// A game of four glasses and four colours, from Custom.
Future<GameScreenState> startCross(WidgetTester tester) async {
  await tapKey(tester, 'menu-custom');
  await tapGo(tester);
  return tester.state<GameScreenState>(find.byType(GameScreen));
}

/// The Nightmare, from the campaign: the app must have been opened with
/// [campaignDone].
Future<GameScreenState> startNightmare(WidgetTester tester) async {
  await tapKey(tester, 'menu-campaign');
  await tapGo(tester);
  return tester.state<GameScreenState>(find.byType(GameScreen));
}
