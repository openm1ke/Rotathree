import 'package:flutter/material.dart';

import '../../game/config/campaign.dart';
import '../data/progress.dart';
import '../style.dart';
import '../widgets/controls.dart';

/// The first screen: a column of large entries, the progress on the side.
class MainMenu extends StatelessWidget {
  const MainMenu({
    super.key,
    required this.progress,
    required this.onCampaign,
    required this.onCustom,
    required this.onStatistics,
    required this.onSettings,
    this.hasSavedGames = false,
    this.onResume,
    this.onTutorial,
    this.tutorialDone = false,
  });

  final Progress progress;
  final VoidCallback onCampaign;
  final VoidCallback onCustom;
  final VoidCallback onStatistics;
  final VoidCallback onSettings;
  final bool hasSavedGames;
  final VoidCallback? onResume, onTutorial;
  final bool tutorialDone;

  @override
  Widget build(BuildContext context) {
    final opened = progress.unlocked + (progress.completed ? 1 : 0);
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (final colour in classicColours)
                Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.symmetric(horizontal: 3),
                  decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(3)),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              style: Type.display(46, spacing: 1),
              children: [
                const TextSpan(text: 'ROTA'),
                TextSpan(
                  text: 'THREE',
                  style: TextStyle(color: Palette.accent),
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Четыре стакана. Один центр. Три в ряд.',
            style: Type.body(13, color: Palette.textDim),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          if (hasSavedGames && onResume != null) ...[
            GoButton(label: 'Продолжить', expand: true, onPressed: onResume),
            const SizedBox(height: 12),
          ],
          if (onTutorial != null)
            _NavItem(
              number: '▶',
              title: 'Обучение',
              caption: tutorialDone
                  ? 'Повторить первые шаги и управление'
                  : 'Первые шаги: попробуйте правила на практике',
              onTap: onTutorial!,
            ),
          _NavItem(
            number: '01',
            title: 'Campaign',
            caption: 'Пятнадцать уровней: от одного стакана до четырёх',
            onTap: onCampaign,
          ),
          _NavItem(number: '02', title: 'Custom', caption: 'Своя игра: стаканы, цвета и скорость', onTap: onCustom),
          _NavItem(
            number: '03',
            title: 'Statistics',
            caption: 'Очки, фигуры и рекорды по режимам',
            onTap: onStatistics,
          ),
          _NavItem(
            number: '04',
            title: 'Settings',
            caption: 'Крестовины, цвета, эффекты, интерфейс',
            onTap: onSettings,
          ),
          const SizedBox(height: 16),
          _InfoCard(
            kicker: 'Кампания',
            value: progress.completed ? 'пройдена' : 'уровень ${progress.unlocked + 1} из ${campaignLevels.length}',
            fraction: opened / campaignLevels.length,
          ),
          _InfoCard(
            kicker: 'Безумие',
            value: progress.completed ? 'открыто' : 'откроется после кампании',
            locked: !progress.completed,
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.number, required this.title, required this.caption, required this.onTap});

  final String number;
  final String title;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Palette.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: Palette.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Text(number, style: Type.label(12, color: Palette.accent)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: Type.display(22)),
                      Text(caption, style: Type.body(12, color: Palette.textDim)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Palette.textDim),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.kicker, required this.value, this.fraction, this.locked = false});

  final String kicker;
  final String value;
  final double? fraction;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: locked ? 0.55 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kicker.toUpperCase(), style: Type.label(11, color: Palette.accent)),
            const SizedBox(height: 4),
            Text(value, style: Type.body(15, weight: FontWeight.w800)),
            if (fraction != null) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(
                  children: [
                    Container(height: 6, color: Palette.line),
                    FractionallySizedBox(
                      widthFactor: fraction!.clamp(0.0, 1.0),
                      child: Container(height: 6, color: Palette.accent),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
