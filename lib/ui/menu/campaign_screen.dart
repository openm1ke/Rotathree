import 'package:flutter/material.dart';

import '../../game/config/campaign.dart';
import '../data/progress.dart';
import '../format.dart';
import '../style.dart';
import '../widgets/controls.dart';

/// A single list, with the rules and completion state on each level.
class CampaignScreen extends StatelessWidget {
  const CampaignScreen({
    super.key,
    required this.progress,
    required this.colours,
    required this.onStart,
    required this.onInsane,
    required this.onBack,
  });
  final Progress progress;
  final List<Color> colours;
  final ValueChanged<int> onStart;
  final VoidCallback onInsane, onBack;

  @override
  Widget build(BuildContext context) => ScreenFrame(
    kicker: 'Режим',
    title: 'Кампания',
    onBack: onBack,
    footer: 'Уровни открываются по очереди · пройденные можно повторить',
    children: [
      for (var index = 0; index < campaignLevels.length; index++)
        _LevelRow(
          index: index,
          best: progress.best[index],
          colour: colours.first,
          status: index < progress.unlocked || (index == campaignLast && progress.completed)
              ? _LevelStatus.done
              : index == progress.unlocked
              ? _LevelStatus.open
              : _LevelStatus.locked,
          onTap: () => onStart(index),
        ),
      const SizedBox(height: 12),
      Section(
        title: 'Кошмар',
        note: '6 цветов · 4 стакана · скорость растёт каждую тысячу очков',
        children: [
          GoButton(
            label: progress.completed ? 'Играть' : 'После кампании',
            onPressed: progress.completed ? onInsane : null,
          ),
        ],
      ),
    ],
  );
}

enum _LevelStatus { done, open, locked }

class _LevelRow extends StatelessWidget {
  const _LevelRow({
    required this.index,
    required this.status,
    required this.best,
    required this.colour,
    required this.onTap,
  });
  final int index, best;
  final Color colour;
  final _LevelStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final level = campaignLevels[index];
    final locked = status == _LevelStatus.locked;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: Material(
          color: Palette.panel,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: status == _LevelStatus.open ? Palette.accent : Palette.line),
          ),
          child: InkWell(
            onTap: locked ? null : onTap,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Уровень ${index + 1}', style: Type.display(18))),
                      Text('Цель ${formatNumber(level.target)}', style: Type.body(12, color: Palette.textDim)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _Badge('Цвета: ${level.colours}', colour: colour),
                      _Badge('Стаканы: ${level.glasses}'),
                      _Badge(
                        'Скорость: ${level.activeStep.toString().replaceAll(RegExp(r'\.0$'), '').replaceAll('.', ',')} с/шаг',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    locked
                        ? 'Закрыто'
                        : status == _LevelStatus.open
                        ? 'Играть →'
                        : best > 0
                        ? '✓ Лучший: ${formatNumber(best)}'
                        : '✓ Пройден',
                    style: Type.body(11, color: status == _LevelStatus.open ? Palette.accent : Palette.textDim),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.label, {this.colour});
  final String label;
  final Color? colour;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: Palette.panelStrong,
      borderRadius: BorderRadius.circular(4),
      border: Border.all(color: Palette.line),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (colour != null) ...[Container(width: 8, height: 8, color: colour), const SizedBox(width: 5)],
        Text(label, style: Type.body(11, weight: FontWeight.w700)),
      ],
    ),
  );
}
