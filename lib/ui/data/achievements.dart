import 'dart:math' as math;

import '../../cube/campaign.dart';
import '../../game/config/campaign.dart';
import '../../game/config/modes.dart';
import '../format.dart';
import 'progress.dart';
import 'stats.dart';

/// What the achievements are judged on: what the app keeps anyway, so that
/// a player who was already playing is given what they had earned.
class AchievementFacts {
  const AchievementFacts({required this.stats, required this.progress, required this.cubeProgress});

  final Stats stats;
  final Progress progress;
  final Progress cubeProgress;

  ModeStats mode(ModeId id) => stats.modes[id] ?? const ModeStats();
  Iterable<ModeStats> get _modes => ModeId.values.map(mode);

  int get levelsPassed => progress.completed ? campaignLevels.length : progress.unlocked;
  int get cubeLevelsPassed => cubeProgress.completed ? cubeCampaign.length : cubeProgress.unlocked;
  int get cubeGames => mode(ModeId.cube).games + mode(ModeId.cubeCampaign).games;
  int get games => _modes.fold(0, (sum, m) => sum + m.games);
  int get matches => _modes.fold(0, (sum, m) => sum + m.totalMatches);
  int get minutes => (_modes.fold(0.0, (sum, m) => sum + m.totalSeconds) / 60).floor();
  int get bestScore => _modes.fold(0, (best, m) => math.max(best, m.bestScore));
  int get bestCombo => _modes.fold(0, (best, m) => math.max(best, m.bestCombo));
}

/// Where an achievement is listed.
enum AchievementGroup {
  lessons('Обучение'),
  campaign('Кампания'),
  cube('Куб'),
  mastery('Мастерство'),
  devotion('Постоянство');

  const AchievementGroup(this.title);
  final String title;
}

class Achievement {
  const Achievement({
    required this.id,
    required this.group,
    required this.title,
    required this.description,
    required this.picture,
    this.goal = 1,
    this.count,
  });

  /// Its name for Steam and for the save; never changed once released.
  final String id;
  final AchievementGroup group;
  final String title;
  final String description;

  /// One of the block pictures.
  final String picture;

  /// How much of [count] earns it.
  final int goal;

  /// How far along the player is. Without it, the achievement is given when
  /// something happens (a tutorial played through), not judged on the facts.
  final int Function(AchievementFacts facts)? count;

  bool earnedBy(AchievementFacts facts) => count != null && count!(facts) >= goal;

  /// How far along, up to [goal]; for the ones worth showing a bar for.
  int? progressOf(AchievementFacts facts) => goal > 1 && count != null ? math.min(goal, count!(facts)) : null;
}

const lessonsPlayed = 'LESSONS';
const cubeLessonsPlayed = 'CUBE_LESSONS';

/// Every achievement, in the order they are listed.
final List<Achievement> achievements = [
  const Achievement(
    id: lessonsPlayed,
    group: AchievementGroup.lessons,
    title: 'Ученик',
    description: 'Пройти обучение до конца',
    picture: 'tutorial',
  ),
  const Achievement(
    id: cubeLessonsPlayed,
    group: AchievementGroup.lessons,
    title: 'Ученик куба',
    description: 'Пройти обучение Куба до конца',
    picture: 'cube',
  ),
  for (final (id, goal, title, description) in [
    ('LEVEL_1', 1, 'Первый стакан', 'Пройти первый уровень кампании'),
    ('LEVEL_4', 4, 'Все четыре стакана', 'Пройти четыре уровня кампании'),
    ('LEVEL_8', 8, 'Полпути', 'Пройти восемь уровней кампании'),
    ('CAMPAIGN', campaignLevels.length, 'Кампания пройдена', 'Пройти все уровни кампании'),
  ])
    Achievement(
      id: id,
      group: AchievementGroup.campaign,
      title: title,
      description: description,
      picture: 'campaign',
      goal: goal,
      count: (f) => f.levelsPassed,
    ),
  Achievement(
    id: 'NIGHTMARE',
    group: AchievementGroup.campaign,
    title: 'Добро пожаловать в кошмар',
    description: 'Сыграть партию в «Кошмаре»',
    picture: 'nightmare',
    count: (f) => f.mode(ModeId.insane).games,
  ),
  for (final (id, goal, title) in [
    ('NIGHTMARE_10K', 10000, 'Пережить кошмар'),
    ('NIGHTMARE_25K', 25000, 'Повелитель кошмара'),
  ])
    Achievement(
      id: id,
      group: AchievementGroup.campaign,
      title: title,
      description: 'Набрать ${formatNumber(goal)} очков в «Кошмаре»',
      picture: 'nightmare',
      goal: goal,
      count: (f) => f.mode(ModeId.insane).bestScore,
    ),
  Achievement(
    id: 'CUBE',
    group: AchievementGroup.cube,
    title: 'Шесть стаканов',
    description: 'Сыграть партию в Куб',
    picture: 'cube',
    count: (f) => f.cubeGames,
  ),
  for (final (id, goal, title, description) in [
    ('CUBE_LEVEL_1', 1, 'Первая грань', 'Пройти первый уровень Куба'),
    ('CUBE_LEVEL_4', 4, 'Глубина', 'Пройти четыре уровня Куба'),
    ('CUBE_CAMPAIGN', cubeCampaign.length, 'Мастер куба', 'Пройти все уровни Куба'),
  ])
    Achievement(
      id: id,
      group: AchievementGroup.cube,
      title: title,
      description: description,
      picture: 'cube',
      goal: goal,
      count: (f) => f.cubeLevelsPassed,
    ),
  Achievement(
    id: 'CUBE_5K',
    group: AchievementGroup.cube,
    title: 'Объёмное мышление',
    description: 'Набрать ${formatNumber(5000)} очков в бесконечном Кубе',
    picture: 'cube',
    goal: 5000,
    count: (f) => f.mode(ModeId.cube).bestScore,
  ),
  for (final (id, goal, title) in [
    ('SCORE_10K', 10000, 'Пять цифр'),
    ('SCORE_50K', 50000, 'Рекордсмен'),
  ])
    Achievement(
      id: id,
      group: AchievementGroup.mastery,
      title: title,
      description: 'Набрать ${formatNumber(goal)} очков за одну партию',
      picture: 'trophy',
      goal: goal,
      count: (f) => f.bestScore,
    ),
  for (final (id, goal, title) in [
    ('COMBO_3', 3, 'Цепная реакция'),
    ('COMBO_5', 5, 'Каскад'),
  ])
    Achievement(
      id: id,
      group: AchievementGroup.mastery,
      title: title,
      description: 'Собрать комбо ×$goal',
      picture: 'trophy',
      goal: goal,
      count: (f) => f.bestCombo,
    ),
  Achievement(
    id: 'CUSTOM',
    group: AchievementGroup.mastery,
    title: 'Свои правила',
    description: 'Сыграть партию в «Кастоме»',
    picture: 'custom',
    count: (f) => f.mode(ModeId.custom).games,
  ),
  for (final (id, goal, title) in [
    ('GAMES_10', 10, 'Втянулся'),
    ('GAMES_100', 100, 'Завсегдатай'),
  ])
    Achievement(
      id: id,
      group: AchievementGroup.devotion,
      title: title,
      description: 'Сыграть ${formatNumber(goal)} партий',
      picture: 'statistics',
      goal: goal,
      count: (f) => f.games,
    ),
  for (final (id, goal, title) in [
    ('LINES_100', 100, 'Сотня линий'),
    ('LINES_1000', 1000, 'Тысяча линий'),
  ])
    Achievement(
      id: id,
      group: AchievementGroup.devotion,
      title: title,
      description: 'Собрать ${formatNumber(goal)} линий',
      picture: 'statistics',
      goal: goal,
      count: (f) => f.matches,
    ),
  for (final (id, goal, title, description) in [
    ('HOUR', 60, 'Час за стаканами', 'Провести в играх час'),
    ('TEN_HOURS', 600, 'Десять часов', 'Провести в играх десять часов'),
  ])
    Achievement(
      id: id,
      group: AchievementGroup.devotion,
      title: title,
      description: description,
      picture: 'statistics',
      goal: goal,
      count: (f) => f.minutes,
    ),
];

/// The achievements earned, each with when: milliseconds since the epoch.
class AchievementLog {
  const AchievementLog(this.unlocked);

  factory AchievementLog.fromJson(Object? raw) => AchievementLog({
    if (raw is Map)
      for (final MapEntry(:key, :value) in raw.entries)
        if (key is String && value is num && value.isFinite) key: value.round(),
  });

  /// Kept whole, those of a later version too.
  final Map<String, int> unlocked;

  bool has(String id) => unlocked.containsKey(id);
  int get count => achievements.where((a) => has(a.id)).length;

  AchievementLog withUnlocked(Iterable<String> ids, int at) => AchievementLog({
    ...unlocked,
    for (final id in ids)
      if (!has(id)) id: at,
  });

  Map<String, int> toJson() => unlocked;

  /// The achievements [facts] earn that are not yet here, in list order.
  List<Achievement> newlyEarned(AchievementFacts facts) => [
    for (final achievement in achievements)
      if (!has(achievement.id) && achievement.earnedBy(facts)) achievement,
  ];
}

Achievement? achievementById(String id) {
  for (final achievement in achievements) {
    if (achievement.id == id) return achievement;
  }
  return null;
}
