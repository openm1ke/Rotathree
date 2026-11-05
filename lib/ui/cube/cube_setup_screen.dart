import 'package:flutter/material.dart';

import '../../cube/save.dart';
import '../../cube/rules.dart';
import '../data/settings.dart';
import '../data/stats.dart';
import '../../game/config/modes.dart';
import '../format.dart';
import '../i18n/strings.dart';
import '../input/dpad.dart';
import '../input/game_action.dart';
import '../style.dart';
import '../widgets/controls.dart';

/// Where a pad button is, as the list of Cube's pads names it.
const _slotSigns = {
  PadSlot.up: '↑',
  PadSlot.left: '←',
  PadSlot.right: '→',
  PadSlot.down: '↓',
  PadSlot.center: 'центр',
};

/// Cube's own screen (webapp/src/components/CubeSetupScreen.tsx): what it
/// is, how it is played, the endless game's rules and the picture's look.
/// Its levels are in the campaign.
class CubeSetupScreen extends StatelessWidget {
  const CubeSetupScreen({
    super.key,
    required this.settings,
    required this.stats,
    required this.colours,
    required this.onChange,
    required this.onStart,
    required this.onTutorial,
    required this.onBack,
    this.saved,
    this.onResume,
  });

  final Settings settings;
  final Stats stats;
  final List<Color> colours;
  final ValueChanged<CubeOptions> onChange;
  final VoidCallback onStart;

  /// Cube's lessons, again.
  final VoidCallback onTutorial;
  final VoidCallback onBack;

  /// The game left unfinished, to go on with instead of a new one.
  final CubeSave? saved;
  final VoidCallback? onResume;

  @override
  Widget build(BuildContext context) {
    final cube = settings.cube;
    final best = stats.modes[ModeId.cube]?.bestScore ?? 0;
    final saved = this.saved;
    final kept = saved == null ? null : CubeGame.restore(saved.game);
    List<({int value, String label})> range((int, int) r) => [for (var n = r.$1; n <= r.$2; n++) (value: n, label: '$n')];
    return ScreenFrame(
      kicker: 'Режим',
      title: 'Куб',
      onBack: onBack,
      actions: [OutlineButton(square: true, label: 'Обучение', onPressed: onTutorial)],
      footer: 'Уровни куба — в «Кампании», после 2D-уровней',
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: LText(
            'На экране — четыре стакана куба, вид спереди. За ними и перед ними ещё два: в каждой клетке видно ближайший '
            'блок, и линии собираются из того, что видно. Опрокиньте куб — и то, что лежало в глубине, станет новой '
            'картинкой: она осыплется и лопнет по своим линиям.',
            style: Type.body(13, color: Palette.textDim),
          ),
        ),
        Section(
          title: 'Свободная игра',
          children: [
            OptionGroup<int>(
              square: true,
              label: 'Цвета',
              value: cube.colours,
              options: range(CubeOptions.colourRange),
              onChanged: (value) => onChange(cube.copyWith(colours: value)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (final colour in colours.take(cube.colours))
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2)),
                    ),
                ],
              ),
            ),
            OptionGroup<int>(
              square: true,
              label: 'Ширина стакана',
              note: 'и сторона куба в середине',
              value: cube.width,
              options: range(CubeOptions.widthRange),
              onChanged: (value) => onChange(cube.copyWith(width: value)),
            ),
            OptionGroup<int>(
              square: true,
              label: 'Длина рукава',
              note: 'в клетках',
              value: cube.arm,
              options: range(CubeOptions.armRange),
              onChanged: (value) => onChange(cube.copyWith(arm: value)),
            ),
            SwitchRow(
              square: true,
              label: 'Фигуры в других стаканах падают сами',
              value: cube.inactiveFalls,
              onChanged: (value) => onChange(cube.copyWith(inactiveFalls: value)),
            ),
            if (cube.inactiveFalls)
              SwitchRow(
                square: true,
                label: 'Стаканы спереди и сзади падают сами',
                value: cube.depthFalls,
                onChanged: (value) => onChange(cube.copyWith(depthFalls: value)),
              ),
          ],
        ),
        CubeLookSection(cube: cube, onChange: onChange),
        Section(
          title: 'Управление',
          children: [
            for (final (side, layout) in [('Левая', settings.cubeLeftPad), ('Правая', settings.cubeRightPad)])
              for (final slot in PadSlot.values)
                if (layout[slot]! != GameAction.none)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 104,
                          child: Row(children: [
                            Icon(padActionIcon(layout[slot]!), size: 16, color: Palette.accent),
                            const SizedBox(width: 6),
                            Flexible(child: LText('$side: ${_slotSigns[slot]}', style: Type.body(12, color: Palette.textDim))),
                          ]),
                        ),
                        Expanded(child: LText(layout[slot]!.hint, style: Type.body(12.5))),
                      ],
                    ),
                  ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Palette.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LText(best > 0 ? 'Рекорд: ${formatNumber(best)}' : 'Рекорда ещё нет', style: Type.body(15, weight: FontWeight.w800)),
              const SizedBox(height: 4),
              LText(
                'куб ${cube.width}×${cube.width}×${cube.width} · рукав: ${formatCells(cube.arm)} · скорость растёт с очками',
                style: Type.body(13, color: Palette.textDim),
              ),
              if (kept != null) ...[
                const SizedBox(height: 8),
                LText(
                  'Партия не закончена: ${formatPoints(kept.score)} · ${formatDuration(kept.seconds)}',
                  style: Type.body(13, color: Palette.accent),
                ),
              ],
            ],
          ),
        ),
        if (saved != null) ...[
          GoButton(square: true, label: 'Продолжить', expand: true, onPressed: onResume),
          const SizedBox(height: 8),
          OutlineButton(square: true, label: 'Новая игра', onPressed: onStart),
        ] else
          GoButton(square: true, label: 'Играть', expand: true, onPressed: onStart),
      ],
    );
  }
}

/// What Cube's picture shows besides the game, each one a switch: the same
/// on Cube's screen and in the settings.
class CubeLookSection extends StatelessWidget {
  const CubeLookSection({super.key, required this.cube, required this.onChange, this.title = 'Вид куба', this.note});

  final CubeOptions cube;
  final ValueChanged<CubeOptions> onChange;
  final String title;
  final String? note;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, bool, CubeOptions Function(bool))>[
      ('Следующие фигуры над стаканами', cube.nextPiece, (v) => cube.copyWith(nextPiece: v)),
      ('Сетка клеток в стаканах', cube.grid, (v) => cube.copyWith(grid: v)),
      ('Рёбра стаканов в объёме (3D-сетка)', cube.volumeEdges, (v) => cube.copyWith(volumeEdges: v)),
      ('Линии объёма вокруг стаканов', cube.depthHint, (v) => cube.copyWith(depthHint: v)),
      ('Спрятанные фигуры сквозь блоки в объёме', cube.xray, (v) => cube.copyWith(xray: v)),
      ('Спрятанные блоки: метка цвета за клеткой', cube.behind, (v) => cube.copyWith(behind: v)),
      ('Дорожка до места посадки', cube.lane, (v) => cube.copyWith(lane: v)),
      ('Фигуры спереди и сзади, которыми не управляете', cube.depthSticks, (v) => cube.copyWith(depthSticks: v)),
      ('Рёбра стаканов и во время игры', cube.edges, (v) => cube.copyWith(edges: v)),
      ('Номера стаканов', cube.numbers, (v) => cube.copyWith(numbers: v)),
    ];
    return Section(
      title: title,
      note: note,
      children: [
        for (final (label, value, change) in rows)
          SwitchRow(square: true, label: label, value: value, onChanged: (v) => onChange(change(v))),
      ],
    );
  }
}
