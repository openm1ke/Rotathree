import '../i18n/strings.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/config/campaign.dart';
import '../data/progress.dart';
import '../format.dart';
import '../style.dart';
import '../widgets/controls.dart';

/// Compact level tiles, with the player's palette showing the colours in play.
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
      Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 712),
          child: Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = math.max(1, ((constraints.maxWidth + 10) / 138).floor());
                  final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
                  return Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var index = 0; index < campaignLevels.length; index++)
                        SizedBox(
                          width: width,
                          child: _LevelTile(
                            index: index,
                            best: progress.best[index],
                            colours: colours,
                            status: index < progress.unlocked || (index == campaignLast && progress.completed)
                                ? _LevelStatus.done
                                : index == progress.unlocked
                                ? _LevelStatus.open
                                : _LevelStatus.locked,
                            onTap: () => onStart(index),
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 20),
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
          ),
        ),
      ),
    ],
  );
}

enum _LevelStatus { done, open, locked }

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.index,
    required this.status,
    required this.best,
    required this.colours,
    required this.onTap,
  });
  final int index, best;
  final List<Color> colours;
  final _LevelStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final level = campaignLevels[index];
    final locked = status == _LevelStatus.locked;
    final step = level.activeStep.toString().replaceAll(RegExp(r'\.0$'), '').replaceAll('.', ',');
    final state = locked
        ? 'Закрыто'
        : status == _LevelStatus.open
        ? 'Доступен'
        : 'Пройден';
    final description =
        'Цветов: ${level.colours}. Стаканов: ${level.glasses}. Шаг: $step с. $state'
        '${best > 0 ? '. Лучший результат: ${formatNumber(best)}' : ''}';
    return Semantics(
      key: ValueKey('campaign-level-$index'),
      button: true,
      enabled: !locked,
      excludeSemantics: true,
      label: context.tr('Уровень ${index + 1}, цель ${level.target}'),
      hint: context.tr(description),
      onTap: locked ? null : onTap,
      child: Tooltip(
        message: context.tr(description),
        child: Opacity(
          opacity: locked ? 0.45 : 1,
          child: Material(
            color: Palette.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
              side: BorderSide(color: status == _LevelStatus.open ? Palette.accent : Palette.line),
            ),
            child: InkWell(
              onTap: locked ? null : onTap,
              borderRadius: BorderRadius.circular(4),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        LText((index + 1).toString().padLeft(2, '0'), style: Type.display(24)),
                        Icon(
                          locked
                              ? Icons.lock_outline_rounded
                              : status == _LevelStatus.done
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          size: 16,
                          color: status == _LevelStatus.open
                              ? Palette.accent
                              : status == _LevelStatus.done
                              ? classicColours[3]
                              : Palette.textDim,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      key: ValueKey('campaign-colours-$index'),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (var slot = 0; slot < level.colours; slot++) ...[
                          if (slot > 0) const SizedBox(width: 4),
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: colours[slot],
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    LText('${level.glasses} ст. · $step с/шаг', style: Type.body(11)),
                    const SizedBox(height: 8),
                    LText('Цель ${formatNumber(level.target)}', style: Type.body(12, color: Palette.textDim)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
