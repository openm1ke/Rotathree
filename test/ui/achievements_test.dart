import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/cube/campaign.dart';
import 'package:rotathree/game/config/campaign.dart';
import 'package:rotathree/game/config/modes.dart';
import 'package:rotathree/ui/app.dart';
import 'package:rotathree/ui/data/achievements.dart';
import 'package:rotathree/ui/data/progress.dart';
import 'package:rotathree/ui/data/stats.dart';
import 'package:rotathree/ui/i18n/strings.dart';
import 'package:rotathree/ui/menu/achievements_screen.dart';
import 'package:rotathree/ui/widgets/achievement_toast.dart';
import 'package:rotathree/ui/widgets/block_picture.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget_test.dart' show settle;

Stats statsWith(Map<ModeId, ModeStats> modes) => Stats(
  modes: {for (final mode in ModeId.values) mode: modes[mode] ?? const ModeStats()},
  recent: const [],
);

AchievementFacts facts({Map<ModeId, ModeStats> modes = const {}, Progress? progress, Progress? cube}) =>
    AchievementFacts(
      stats: statsWith(modes),
      progress: progress ?? Progress.initial(),
      cubeProgress: cube ?? defaultCubeProgress(),
    );

Set<String> earned(AchievementFacts facts) => const AchievementLog({}).newlyEarned(facts).map((a) => a.id).toSet();

void main() {
  test('every achievement has its own id, a picture, and English for its words', () async {
    final english = AppStrings('en', await AppStrings.catalog());
    final cyrillic = RegExp('[А-Яа-яЁё]');
    expect(achievements.map((a) => a.id).toSet(), hasLength(achievements.length));
    for (final achievement in achievements) {
      expect(achievement.id, matches(RegExp(r'^[A-Z][A-Z0-9_]*$')));
      expect(blockPictures, contains(achievement.picture));
      for (final words in [achievement.title, achievement.description, achievement.group.title]) {
        expect(english.tr(words), isNot(contains(cyrillic)), reason: words);
      }
    }
    expect(english.tr('Набрать 10 000 очков в «Кошмаре»'), 'Score 10,000 points in Nightmare');
    expect(english.tr('Открыто 3 из 26'), 'Unlocked 3 of 26');
  });

  test('nothing is earned before playing; results earn what they reach and no more', () {
    expect(earned(facts()), isEmpty);
    expect(
      earned(facts(progress: Progress.initial().levelFinished(0, 1300).levelFinished(1, 1900).levelFinished(2, 2500).levelFinished(3, 2600))),
      {'LEVEL_1', 'LEVEL_4'},
    );
    var campaign = Progress.initial();
    for (var level = 0; level < campaignLevels.length; level++) {
      campaign = campaign.levelFinished(level, campaignLevels[level].target);
    }
    expect(earned(facts(progress: campaign)), {'LEVEL_1', 'LEVEL_4', 'LEVEL_8', 'CAMPAIGN'});
    var cube = defaultCubeProgress();
    for (var level = 0; level < cubeCampaign.length; level++) {
      cube = cube.levelFinished(level, cubeCampaign[level].target);
    }
    expect(earned(facts(cube: cube)), {'CUBE_LEVEL_1', 'CUBE_LEVEL_4', 'CUBE_CAMPAIGN'});

    final played = facts(modes: {
      ModeId.insane: const ModeStats(games: 2, bestScore: 12000, totalMatches: 60, bestCombo: 3, totalSeconds: 1500),
      ModeId.cube: const ModeStats(games: 1, bestScore: 4900, totalMatches: 50, totalSeconds: 2200),
      ModeId.custom: const ModeStats(games: 7, bestScore: 900, totalMatches: 10, bestCombo: 2, totalSeconds: 100),
    });
    // 10 games, 120 lines, 63 minutes; the best game 12 000, a ×3 combo.
    expect(earned(played), {
      'NIGHTMARE', 'NIGHTMARE_10K', 'CUBE', 'SCORE_10K', 'COMBO_3', 'CUSTOM', 'GAMES_10', 'LINES_100', 'HOUR',
    });
    final cubeFive = achievements.firstWhere((a) => a.id == 'CUBE_5K');
    expect(cubeFive.progressOf(played), 4900);
    expect(achievements.firstWhere((a) => a.id == 'NIGHTMARE').progressOf(played), isNull);
    // Tutorials are given when they are played through, never judged.
    expect(earned(played).intersection({lessonsPlayed, cubeLessonsPlayed}), isEmpty);
  });

  test('the log keeps when each was earned, and what a later version earned', () {
    final log = AchievementLog.fromJson({'LEVEL_1': 100, 'FROM_LATER': 200, 'BROKEN': 'x', 'NAN': double.nan});
    expect(log.unlocked, {'LEVEL_1': 100, 'FROM_LATER': 200});
    expect(log.count, 1);
    final next = log.withUnlocked(['LEVEL_1', 'LEVEL_4'], 300);
    expect(next.unlocked, {'LEVEL_1': 100, 'FROM_LATER': 200, 'LEVEL_4': 300});
    expect(AchievementLog.fromJson(jsonDecode(jsonEncode(next.toJson()))).unlocked, next.unlocked);
    expect(AchievementLog.fromJson('nonsense').unlocked, isEmpty);
    final progress = Progress.initial().levelFinished(0, 1300);
    expect(next.newlyEarned(facts(progress: progress)), isEmpty);
  });

  testWidgets('a card comes for each achievement in turn, then goes', (tester) async {
    final toasts = AchievementToasts();
    addTearDown(toasts.dispose);
    await tester.pumpWidget(MaterialApp(home: Stack(children: [AchievementToast(toasts: toasts)])));
    expect(find.text('Достижение открыто'), findsNothing);
    toasts.add([achievementById('LEVEL_1')!, achievementById('LEVEL_4')!]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Первый стакан'), findsOneWidget);
    expect(find.text('Крест собран'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Первый стакан'), findsNothing);
    expect(find.text('Крест собран'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Достижение открыто'), findsNothing);
    expect(toasts.current, isNull);
  });

  testWidgets('what was earned before is given quietly, counted in the statistics and listed', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    SharedPreferences.setMockInitialValues({
      'rotathree.tutorial.v1': 'true',
      'rotathree.progress.v1': jsonEncode(Progress.initial().levelFinished(0, 1300).toJson()),
      'rotathree.stats.v1': jsonEncode(
        statsWith({ModeId.insane: const ModeStats(games: 1, bestScore: 12000, totalMatches: 40)}).toJson(),
      ),
    });
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);
    expect(find.text('Достижение открыто'), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    final saved = AchievementLog.fromJson(jsonDecode(prefs.getString('rotathree.achievements.v1')!));
    expect(saved.unlocked.keys.toSet(), {'LEVEL_1', 'NIGHTMARE', 'NIGHTMARE_10K', 'SCORE_10K'});

    await tester.tap(find.byKey(const ValueKey('menu-statistics')));
    await settle(tester);
    expect(find.text('Открыто 4 из ${achievements.length}'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('open-achievements')));
    await settle(tester);
    expect(find.byType(AchievementsScreen), findsOneWidget);
    expect(find.byKey(const ValueKey('achievement-LEVEL_1')), findsOneWidget);
    // Not earned yet, with how far along it is: the best Nightmare so far.
    await tester.scrollUntilVisible(find.text('12\u00a0000 / 25\u00a0000'), 200);
    expect(find.text('12\u00a0000 / 25\u00a0000'), findsOneWidget);
  });
}
