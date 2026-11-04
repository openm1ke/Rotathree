import '../i18n/strings.dart';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../cube/campaign.dart';
import '../../cube/rules.dart';
import '../../cube/save.dart';
import '../../game/config/campaign.dart';
import '../data/progress.dart';
import '../format.dart';
import '../layout.dart';
import '../style.dart';
import '../widgets/controls.dart';
import '../audio/sound_effects.dart';

/// The whole campaign on one screen, as on the web: the flat levels and the
/// Nightmare after them, then Cube's levels. Compact level tiles, with the
/// player's palette showing the colours in play.
class CampaignScreen extends StatefulWidget {
  const CampaignScreen({
    super.key,
    required this.progress,
    required this.colours,
    required this.onStart,
    required this.onInsane,
    required this.onBack,
    this.cubeProgress,
    this.cubeSaved,
    this.onCubeStart,
    this.onCubeResume,
    this.cube = false,
  });
  final Progress progress;
  final List<Color> colours;
  final ValueChanged<int> onStart;
  final VoidCallback onInsane, onBack;

  /// How far Cube's levels have been played; a level of them left
  /// unfinished, to go on with.
  final Progress? cubeProgress;
  final CubeSave? cubeSaved;
  final ValueChanged<int>? onCubeStart;
  final VoidCallback? onCubeResume;

  /// Opened from a level of Cube: its part is shown first.
  final bool cube;

  @override
  State<CampaignScreen> createState() => _CampaignScreenState();
}

class _CampaignScreenState extends State<CampaignScreen> {
  final _cubePart = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.cube) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final part = _cubePart.currentContext;
        if (part != null) Scrollable.ensureVisible(part);
      });
    }
  }

  static _LevelStatus _statusOf(Progress progress, int index, int last) =>
      index < progress.unlocked || (index == last && progress.completed)
          ? _LevelStatus.done
          : index == progress.unlocked
              ? _LevelStatus.open
              : _LevelStatus.locked;

  static int _passed(Progress progress, int count) => progress.completed ? count : progress.unlocked;

  @override
  Widget build(BuildContext context) {
    final tablet = isTablet(MediaQuery.sizeOf(context));
    final progress = widget.progress;
    final cube = widget.cubeProgress ?? defaultCubeProgress();
    final saved = widget.cubeSaved;
    // `taller`: room for a level's name on a tablet's tile.
    Widget tiles(List<Widget Function(bool tall)> levels, double minWidth, {double taller = 0}) => LayoutBuilder(
          builder: (context, constraints) {
            // A tablet shows four tiles across, each taller than it is wide,
            // so the levels fill the screen instead of huddling at the top.
            final columns = tablet ? 4 : math.max(1, ((constraints.maxWidth + 10) / minWidth).floor());
            final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
            return Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final level in levels)
                  SizedBox(
                    width: width,
                    height: tablet ? math.max(width * 1.15, tallTileHeight) + taller : null,
                    child: level(tablet),
                  ),
              ],
            );
          },
        );
    return TabletScale(
      child: ScreenFrame(
        kicker: 'Режим',
        title: 'Кампания',
        onBack: widget.onBack,
        footer: 'Уровни открываются по очереди · пройденные можно повторить',
        children: [
          // One child, so the whole page is built and scrolled as one.
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _PartHead(title: 'Стаканы · 2D', passed: _passed(progress, campaignLevels.length), count: campaignLevels.length),
              tiles([
                for (var index = 0; index < campaignLevels.length; index++)
                  (tall) {
                    final level = campaignLevels[index];
                    final step = level.activeStep.toString().replaceAll(RegExp(r'\.0$'), '').replaceAll('.', ',');
                    final status = _statusOf(progress, index, campaignLast);
                    final best = progress.best[index];
                    return _LevelTile(
                      key: ValueKey('campaign-level-$index'),
                      coloursKey: ValueKey('campaign-colours-$index'),
                      index: index,
                      target: level.target,
                      colours: widget.colours.take(level.colours).toList(),
                      rules: '${level.glasses} ст. · $step с/шаг',
                      description: 'Цветов: ${level.colours}. Стаканов: ${level.glasses}. Шаг: $step с. ${_stateOf(status)}'
                          '${best > 0 ? '. Лучший результат: ${formatNumber(best)}' : ''}',
                      tall: tall,
                      status: status,
                      autofocus: !widget.cube && index == progress.unlocked,
                      onTap: () => widget.onStart(index),
                    );
                  },
              ], 138),
              const SizedBox(height: 20),
              Section(
                title: 'Кошмар',
                note: '6 цветов · 4 стакана · скорость растёт каждую тысячу очков',
                children: [
                  GoButton(
                    label: progress.completed ? 'Играть' : 'После кампании',
                    onPressed: progress.completed ? widget.onInsane : null,
                  ),
                ],
              ),
              if (widget.onCubeStart != null) ...[
                const SizedBox(height: 16),
                _PartHead(
                  key: _cubePart,
                  title: 'Куб · 3D',
                  passed: _passed(cube, cubeCampaign.length),
                  count: cubeCampaign.length,
                ),
                if (saved?.level case final level?)
                  Section(
                    title: 'Уровень ${level + 1} не закончен',
                    note: () {
                      final game = CubeGame.restore(saved!.game);
                      return '${formatPoints(game.score)} · ${formatDuration(game.seconds)}';
                    }(),
                    children: [GoButton(label: 'Продолжить', expand: true, onPressed: widget.onCubeResume)],
                  ),
                tiles([
                  for (var index = 0; index < cubeCampaign.length; index++)
                    (tall) {
                      final level = cubeCampaign[index];
                      final status = _statusOf(cube, index, cubeCampaignLast);
                      final best = cube.best[index];
                      // Said in parts, each its own message in the catalog.
                      final description = [
                        level.title,
                        'Цветов: ${level.colours}',
                        'Куб ${level.width}, рукав ${level.arm}',
                        if (level.depthFalls) 'Стаканы спереди и сзади падают сами',
                        _stateOf(status),
                        if (best > 0) 'Лучший результат: ${formatNumber(best)}',
                      ];
                      return _LevelTile(
                        key: ValueKey('cube-level-$index'),
                        index: index,
                        target: level.target,
                        title: level.title,
                        colours: widget.colours.take(level.colours).toList(),
                        rules: 'куб ${level.width} · рукав ${level.arm}${level.depthFalls ? ' · глубина' : ''}',
                        description: description,
                        tall: tall,
                        status: status,
                        autofocus: widget.cube && index == cube.unlocked,
                        onTap: () => widget.onCubeStart!(index),
                      );
                    },
                ], 150, taller: 40),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

String _stateOf(_LevelStatus status) => switch (status) {
      _LevelStatus.locked => 'Закрыто',
      _LevelStatus.open => 'Доступен',
      _LevelStatus.done => 'Пройден',
    };

/// A part's name, and how much of it is passed.
class _PartHead extends StatelessWidget {
  const _PartHead({super.key, required this.title, required this.passed, required this.count});

  final String title;
  final int passed, count;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Expanded(
                  child: Text(context.tr(title).toUpperCase(), style: Type.display(20, color: Palette.accent)),
                ),
                LText('пройдено $passed из $count', style: Type.body(13, color: Palette.textDim)),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Stack(children: [
                Container(height: 4, color: Palette.line),
                FractionallySizedBox(
                  widthFactor: count == 0 ? 0 : passed / count,
                  child: Container(height: 4, color: Palette.accent),
                ),
              ]),
            ),
          ],
        ),
      );
}

/// The least a tablet tile is tall: its text at the tablet scale needs this much.
const tallTileHeight = 240.0;

enum _LevelStatus { done, open, locked }

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    super.key,
    required this.index,
    required this.target,
    required this.status,
    required this.colours,
    required this.rules,
    required this.description,
    required this.onTap,
    this.autofocus = false,
    this.coloursKey,
    this.title,
    this.tall = false,
  });
  final int index, target;
  final List<Color> colours;
  final _LevelStatus status;
  final String rules;

  /// Read out and shown on a long press: one message, or parts of one, each
  /// translated on its own.
  final Object description;
  final String? title;
  final Key? coloursKey;
  final VoidCallback onTap;
  final bool autofocus;

  /// On a tablet the tile is stretched to its height and its contents spread out.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final s = tabletScale(MediaQuery.sizeOf(context));
    final locked = status == _LevelStatus.locked;
    final description = switch (this.description) {
      final List<String> parts => parts.map(context.tr).join('. '),
      final text => context.tr('$text'),
    };
    return Semantics(
      button: true,
      enabled: !locked,
      excludeSemantics: true,
      label: context.tr('Уровень ${index + 1}, цель $target'),
      hint: description,
      onTap: locked ? null : onTap,
      child: Tooltip(
        message: description,
        child: Opacity(
          opacity: locked ? 0.45 : 1,
          child: Material(
            color: Palette.panel,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4 * s),
              side: BorderSide(color: status == _LevelStatus.open ? Palette.accent : Palette.line),
            ),
            child: InkWell(
              autofocus: usesDesktopKeyboard && autofocus,
              focusColor: Palette.accent.withValues(alpha: 0.25),
              onTap: locked ? null : clicking(onTap),
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
                    if (title != null) ...[
                      const SizedBox(height: 6),
                      // One line, shrunk to fit a narrow tile.
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: LText(title!, maxLines: 1, style: Type.body(12.5, weight: FontWeight.w800, height: 1.2)),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Row(
                      key: coloursKey,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (slot, colour) in colours.indexed) ...[
                          if (slot > 0) SizedBox(width: 4 * s),
                          Container(
                            width: 10 * s,
                            height: 10 * s,
                            decoration: BoxDecoration(
                              color: colour,
                              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    LText(rules, style: Type.body(11)),
                    const SizedBox(height: 8),
                    LText('Цель ${formatNumber(target)}', style: Type.body(12, color: Palette.textDim)),
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
