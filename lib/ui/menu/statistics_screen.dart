import 'package:flutter/material.dart';

import '../../game/config/modes.dart';
import '../data/progress.dart';
import '../data/stats.dart';
import '../format.dart';
import '../style.dart';
import '../widgets/controls.dart';

const _descriptions = {
  ModeId.campaign: 'Пятнадцать уровней, каждый со своей целью очков',
  ModeId.insane: 'Шесть цветов, четыре стакана, скорость растёт',
  ModeId.custom: 'Своя настройка, скорость — по желанию',
};

/// Totals and records of every mode, and the last runs.
class StatisticsScreen extends StatelessWidget {
  const StatisticsScreen({
    super.key,
    required this.stats,
    required this.progress,
    required this.onBack,
  });

  final Stats stats;
  final Progress progress;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return ScreenFrame(
      kicker: 'Результаты',
      title: 'Статистика',
      onBack: onBack,
      children: [
        for (final mode in ModeId.values)
          _ModeCard(mode: mode, stats: stats.modes[mode]!, progress: progress),
        Section(
          title: 'Последние партии',
          children: [
            if (stats.recent.isEmpty)
              Text(
                'Пока ни одной партии. Первая появится здесь после конца игры.',
                style: Type.body(13, color: Palette.textDim),
              )
            else
              for (final run in stats.recent) _RunRow(run: run),
          ],
        ),
      ],
    );
  }
}

class _ModeCard extends StatelessWidget {
  const _ModeCard({required this.mode, required this.stats, required this.progress});

  final ModeId mode;
  final ModeStats stats;
  final Progress progress;

  @override
  Widget build(BuildContext context) {
    final average = stats.games > 0 ? (stats.totalPieces / stats.games).round() : 0;
    final campaign = mode == ModeId.campaign;
    final lines = [
      ('Партий', '${stats.games}'),
      if (campaign)
        ('Кампания пройдена', stats.completed > 0 ? '${stats.completed} раз' : 'нет'),
      ('Лучший счёт', formatNumber(stats.bestScore)),
      ('Очков всего', formatNumber(stats.totalScore)),
      ('Фигур всего', formatNumber(stats.totalPieces)),
      ('Фигур за партию', '$average'),
      ('Матчей всего', formatNumber(stats.totalMatches)),
      ('Лучшее комбо', '×${stats.bestCombo}'),
      (campaign ? 'Лучший уровень' : 'Лучшая скорость', campaign ? '${stats.bestLevel}' : '×${stats.bestLevel}'),
      ('Время в играх', formatDuration(stats.totalSeconds)),
    ];
    return Section(
      title: campaign
          ? (progress.completed ? 'Кампания · пройдена' : 'Кампания · уровень ${progress.unlocked + 1}')
          : 'Режим',
      note: _descriptions[mode],
      children: [
        Text(modeTitle(mode), style: Type.display(22)),
        const SizedBox(height: 8),
        for (final (label, value) in lines)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(label, style: Type.body(13, color: Palette.textDim))),
                Text(value, style: Type.body(14, weight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}

class _RunRow extends StatelessWidget {
  const _RunRow({required this.run});

  final RunRecord run;

  String get _outcome {
    if (run.mode == ModeId.campaign) {
      return run.completed ? 'кампания пройдена' : 'уровень ${run.level}';
    }
    return 'скорость ${run.level}';
  }

  String get _when {
    final at = DateTime.fromMillisecondsSinceEpoch(run.at);
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(at.day)}.${two(at.month)} ${two(at.hour)}:${two(at.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(width: 84, child: Text(_when, style: Type.body(12, color: Palette.textDim))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${modeTitle(run.mode)} · $_outcome', style: Type.body(13, weight: FontWeight.w800)),
                Text(
                  '${formatDuration(run.seconds)} · ${run.pieces} фиг. · ×${run.bestCombo}',
                  style: Type.body(12, color: Palette.textDim),
                ),
              ],
            ),
          ),
          Text(formatNumber(run.score), style: Type.body(15, weight: FontWeight.w900, color: Palette.accent)),
        ],
      ),
    );
  }
}
