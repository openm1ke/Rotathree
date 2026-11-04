import 'package:flutter/material.dart';

import '../data/achievements.dart';
import '../format.dart';
import '../i18n/strings.dart';
import '../style.dart';
import '../widgets/block_picture.dart';
import '../widgets/controls.dart';

/// Every achievement by its group: the ones earned, and how far along the
/// others are.
class AchievementsScreen extends StatelessWidget {
  const AchievementsScreen({super.key, required this.log, required this.facts, required this.onBack});

  final AchievementLog log;
  final AchievementFacts facts;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      kicker: 'Результаты',
      title: 'Достижения',
      onBack: onBack,
      footer: 'Засчитывается и то, что сыграно раньше',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: AchievementsSummary(earned: log.count, total: achievements.length),
        ),
        for (final group in AchievementGroup.values)
          Section(
            title: group.title,
            children: [
              for (final achievement in achievements.where((a) => a.group == group))
                _AchievementRow(
                  key: ValueKey('achievement-${achievement.id}'),
                  achievement: achievement,
                  earned: log.has(achievement.id),
                  progress: achievement.progressOf(facts),
                ),
            ],
          ),
      ],
    );
  }
}

/// How many achievements are earned, in words and as a bar; with a way to
/// all of them when [onOpen] is given.
class AchievementsSummary extends StatelessWidget {
  const AchievementsSummary({super.key, required this.earned, required this.total, this.onOpen});

  final int earned;
  final int total;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          const BlockPicture('trophy', size: 30),
          const SizedBox(width: 12),
          Expanded(child: LText('Открыто $earned из $total', style: Type.body(15, weight: FontWeight.w800))),
        ],
      ),
      const SizedBox(height: 10),
      _Bar(done: total == 0 ? 0 : earned / total, colour: Palette.brandYellow),
      if (onOpen != null) ...[
        const SizedBox(height: 12),
        OutlineButton(key: const ValueKey('open-achievements'), label: 'Все достижения', onPressed: onOpen),
      ],
    ],
  );
}

class _AchievementRow extends StatelessWidget {
  const _AchievementRow({super.key, required this.achievement, required this.earned, required this.progress});

  final Achievement achievement;
  final bool earned;

  /// How far along, for one counted toward a goal.
  final int? progress;

  @override
  Widget build(BuildContext context) {
    final progress = this.progress;
    final counted = !earned && progress != null;
    final state = earned
        ? context.tr('Открыто')
        : counted
            ? '${formatNumber(progress)} / ${formatNumber(achievement.goal)}'
            : context.tr('Не открыто');
    return Semantics(
      container: true,
      excludeSemantics: true,
      label: '${context.tr(achievement.title)}. ${context.tr(achievement.description)}. ${context.tr(state)}',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            BlockPicture(achievement.picture, size: 34, dimmed: !earned),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LText(
                    achievement.title,
                    style: Type.body(14.5, weight: FontWeight.w800, color: earned ? Palette.text : Palette.textDim),
                  ),
                  LText(achievement.description, style: Type.body(12.5, color: Palette.textDim)),
                  if (counted) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Expanded(child: _Bar(done: progress / achievement.goal, colour: Palette.accent)),
                        const SizedBox(width: 10),
                        LText(state, style: Type.number(11.5, color: Palette.textDim)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            if (earned) ...[
              const SizedBox(width: 8),
              Icon(Icons.check_rounded, size: 20, color: classicColours[3]),
            ],
          ],
        ),
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.done, required this.colour});

  final double done;
  final Color colour;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(3),
    child: Stack(
      children: [
        Container(height: 4, color: Palette.line),
        FractionallySizedBox(
          widthFactor: done.clamp(0.0, 1.0),
          child: Container(height: 4, color: colour),
        ),
      ],
    ),
  );
}
