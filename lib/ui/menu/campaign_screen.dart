import '../i18n/strings.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../game/config/campaign.dart';
import '../data/progress.dart';
import '../format.dart';
import '../layout.dart';
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
  Widget build(BuildContext context) {
    final tablet = isTablet(MediaQuery.sizeOf(context));
    return TabletScale(
      child: ScreenFrame(
        kicker: 'Режим',
        title: 'Кампания',
        onBack: onBack,
        footer: 'Уровни открываются по очереди · пройденные можно повторить',
        children: [
          // One child, so the whole page is built and scrolled as one.
          Column(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  // A tablet shows four tiles across, each taller than it is wide,
                  // so the levels fill the screen instead of huddling at the top.
                  final columns = tablet ? 4 : math.max(1, ((constraints.maxWidth + 10) / 138).floor());
                  final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
                  return Wrap(
                    alignment: WrapAlignment.center,
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      for (var index = 0; index < campaignLevels.length; index++)
                        SizedBox(
                          width: width,
                          height: tablet ? math.max(width * 1.15, tallTileHeight) : null,
                          child: _LevelTile(
                            index: index,
                            best: progress.best[index],
                            colours: colours,
                            tall: tablet,
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
        ],
      ),
    );
  }
}

/// The least a tablet tile is tall: its text at the tablet scale needs this much.
const tallTileHeight = 240.0;

enum _LevelStatus { done, open, locked }

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.index,
    required this.status,
    required this.best,
    required this.colours,
    required this.onTap,
    this.tall = false,
  });
  final int index, best;
  final List<Color> colours;
  final _LevelStatus status;
  final VoidCallback onTap;

  /// On a tablet the tile is stretched to its height and its contents spread out.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final s = tabletScale(MediaQuery.sizeOf(context));
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
              borderRadius: BorderRadius.circular(4 * s),
              side: BorderSide(color: status == _LevelStatus.open ? Palette.accent : Palette.line),
            ),
            child: InkWell(
              onTap: locked ? null : onTap,
              borderRadius: BorderRadius.circular(4 * s),
              child: Padding(
                padding: EdgeInsets.all(12 * s),
                child: Column(
                  mainAxisAlignment: tall ? MainAxisAlignment.spaceEvenly : MainAxisAlignment.start,
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
                          size: 16 * s,
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
                          if (slot > 0) SizedBox(width: 4 * s),
                          Container(
                            width: 10 * s,
                            height: 10 * s,
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
