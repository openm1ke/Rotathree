import 'package:flutter/material.dart';

import '../../game/config/campaign.dart';
import '../data/progress.dart';
import '../format.dart';
import '../style.dart';
import '../widgets/controls.dart';

/// The levels, grouped by the number of colours. A level is open when every
/// level before it is finished; finished levels can be played again.
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
  final VoidCallback onInsane;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final groups = <int, List<int>>{};
    for (var index = 0; index < campaignLevels.length; index++) {
      groups.putIfAbsent(campaignLevels[index].colours, () => []).add(index);
    }
    return ScreenFrame(
      kicker: 'Режим',
      title: 'Кампания',
      onBack: onBack,
      footer: 'Уровни открываются по очереди · очки считаются за уровень',
      children: [
        for (final group in groups.entries)
          Section(
            title: '${group.key} цвета',
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    for (final colour in colours.take(group.key))
                      Container(
                        width: 12,
                        height: 12,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
                      ),
                  ],
                ),
              ),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final index in group.value)
                    _LevelCard(
                      index: index,
                      status: _statusOf(index),
                      best: progress.best[index],
                      onTap: () => onStart(index),
                    ),
                ],
              ),
            ],
          ),
        Section(
          title: 'Безумие',
          note: '6 цветов, 4 стакана. Скорость растёт с каждой тысячей очков, пока стакан не заполнится до конца.',
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    progress.completed ? 'Открыто после кампании' : 'Закрыто: пройдите кампанию',
                    style: Type.body(13, color: Palette.textDim),
                  ),
                ),
                GoButton(
                  label: progress.completed ? 'Играть' : 'Закрыто',
                  onPressed: progress.completed ? onInsane : null,
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  _LevelStatus _statusOf(int index) {
    if (index < progress.unlocked || (index == campaignLast && progress.completed)) {
      return _LevelStatus.done;
    }
    return index == progress.unlocked ? _LevelStatus.open : _LevelStatus.locked;
  }
}

enum _LevelStatus { done, open, locked }

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.index, required this.status, required this.best, required this.onTap});

  final int index;
  final _LevelStatus status;
  final int best;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final level = campaignLevels[index];
    final locked = status == _LevelStatus.locked;
    final accent = status == _LevelStatus.open ? Palette.accent : Palette.lineStrong;
    return SizedBox(
      width: 150,
      child: Opacity(
        opacity: locked ? 0.45 : 1,
        child: Material(
          color: Palette.panelStrong,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: accent, width: status == _LevelStatus.open ? 1.5 : 1),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: locked ? null : onTap,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text('${index + 1}', style: Type.display(22)),
                      const Spacer(),
                      Row(
                        children: [
                          for (var g = 0; g < 4; g++)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 3),
                              decoration: BoxDecoration(
                                color: g < level.glasses ? Palette.accent : Palette.line,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(formatNumber(level.target), style: Type.body(16, weight: FontWeight.w800)),
                  Text(
                    '${level.glasses} ст · ${level.activeStep < 1 ? 'быстрее' : 'обычная скорость'}',
                    style: Type.body(11, color: Palette.textDim),
                  ),
                  if (status == _LevelStatus.done && best > 0)
                    Text('лучший ${formatNumber(best)}', style: Type.body(11, color: Palette.warning)),
                  if (locked) Text('закрыто', style: Type.body(11, color: Palette.textFaint)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
