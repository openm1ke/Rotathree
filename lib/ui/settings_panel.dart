import 'package:flutter/material.dart';

import '../game/config/game_config.dart';
import '../game/model/color.dart';
import 'input/dpad.dart';
import 'settings/pad_action.dart';
import 'settings/settings.dart';
import 'style.dart';
import 'widgets/controls.dart';

enum _Tab {
  controls('Управление'),
  game('Игра'),
  view('Интерфейс');

  const _Tab(this.title);

  final String title;
}

/// The settings, over whatever screen they were opened from. Every change
/// applies — and is saved — at once.
class SettingsPanel extends StatefulWidget {
  const SettingsPanel({
    super.key,
    required this.settings,
    required this.stored,
    required this.inGame,
    required this.onChanged,
    required this.onClose,
  });

  final Settings settings;

  /// False when the device refuses to keep the settings.
  final bool stored;

  /// True when opened over a running game: changing the rules restarts it.
  final bool inGame;
  final ValueChanged<Settings> onChanged;
  final VoidCallback onClose;

  @override
  State<SettingsPanel> createState() => _SettingsPanelState();
}

class _SettingsPanelState extends State<SettingsPanel> {
  _Tab _tab = _Tab.controls;

  Settings get _s => widget.settings;

  void _pads(PadOptions pads) => widget.onChanged(_s.copyWith(pads: pads));
  void _game(GameOptions game) => widget.onChanged(_s.copyWith(game: game));
  void _hud(HudOptions hud) => widget.onChanged(_s.copyWith(hud: hud));

  static const _shown = [(true, 'показывать'), (false, 'скрыть')];
  static const _onOff = [(true, 'вкл'), (false, 'выкл')];

  @override
  Widget build(BuildContext context) {
    return Scrim(
      strength: 0.8,
      onTapOutside: widget.onClose,
      child: SafeArea(
        minimum: const EdgeInsets.all(10),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: DialogCard(
            width: double.infinity,
            scrollable: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 10),
                  child: Row(
                    children: [
                      Expanded(child: Text('НАСТРОЙКИ', style: Type.display(26))),
                      Pressable(
                        onPressed: widget.onClose,
                        builder: (context, pressed) => Padding(
                          padding: const EdgeInsets.all(10),
                          child: Text(
                            'ЗАКРЫТЬ',
                            key: const ValueKey('settings-close'),
                            style: Type.display(13, color: Palette.textDim, spacing: 0.8),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: _Tabs(tab: _tab, onChanged: (tab) => setState(() => _tab = tab)),
                ),
                const SizedBox(height: 6),
                const Divider(height: 1, color: Palette.line),
                Flexible(
                  child: SingleChildScrollView(
                    key: ValueKey(_tab),
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: switch (_tab) {
                      _Tab.controls => _buildControls(),
                      _Tab.game => _buildGame(),
                      _Tab.view => _buildView(),
                    },
                  ),
                ),
                const Divider(height: 1, color: Palette.line),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
                  child: Text(
                    widget.stored
                        ? 'Настройки сохраняются на устройстве сразу и остаются после перезапуска игры.'
                        : 'Не удаётся сохранить настройки на устройстве: после перезапуска игры они сбросятся.',
                    style: Type.body(
                      11.5,
                      color: widget.stored ? Palette.textFaint : Palette.warning,
                      weight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --------------------------------------------------------------- controls

  Widget _buildControls() {
    final pads = _s.pads;
    Widget pad(String title, PadLayout layout, ValueChanged<PadLayout> onChanged) =>
        _Group(
          title: title,
          children: [
            for (final slot in PadSlot.values)
              _SlotRow(
                slot: slot,
                action: layout[slot]!,
                onChanged: (action) => onChanged({...layout, slot: action}),
              ),
          ],
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _Hint(
          'Внизу экрана две крестовины. Нажмите на действие, чтобы назначить '
          'кнопке другое; одно и то же действие можно поставить на несколько кнопок.',
        ),
        pad('Левая крестовина', pads.left, (left) => _pads(pads.copyWith(left: left))),
        pad('Правая крестовина', pads.right, (right) => _pads(pads.copyWith(right: right))),
        _Group(
          title: 'Кнопки',
          children: [
            _Choice<double>(
              label: 'Размер крестовин',
              value: pads.scale,
              options: const [(0.85, 'меньше'), (1.0, 'обычные'), (1.15, 'крупнее')],
              onChanged: (scale) => _pads(pads.copyWith(scale: scale)),
            ),
            _SliderRow(
              label: 'Непрозрачность кнопок',
              value: (pads.opacity * 100).roundToDouble(),
              min: 30,
              max: 100,
              step: 5,
              unit: '%',
              onChanged: (percent) => _pads(pads.copyWith(opacity: percent / 100)),
            ),
            _Choice<bool>(
              label: 'Вибрация',
              value: pads.haptics,
              options: _onOff,
              onChanged: (haptics) => _pads(pads.copyWith(haptics: haptics)),
            ),
            _Choice<bool>(
              label: 'Жесты на поле',
              note: 'тап по центру — поворот, перетаскивание фигуры, свайп вниз — сброс',
              value: pads.fieldGestures,
              options: _onOff,
              onChanged: (on) => _pads(pads.copyWith(fieldGestures: on)),
            ),
          ],
        ),
        _Group(
          title: 'Автоповтор движения',
          children: [
            _SliderRow(
              label: 'Задержка перед повтором',
              value: pads.dasMs.toDouble(),
              min: 0,
              max: 300,
              step: 5,
              unit: 'мс',
              onChanged: (ms) => _pads(pads.copyWith(dasMs: ms.round())),
            ),
            _SliderRow(
              label: 'Интервал повтора',
              value: pads.arrMs.toDouble(),
              min: 0,
              max: 100,
              step: 5,
              unit: 'мс',
              note: pads.arrMs == 0 ? 'сразу до стенки' : null,
              onChanged: (ms) => _pads(pads.copyWith(arrMs: ms.round())),
            ),
          ],
        ),
        _Reset('Сбросить управление', () => _pads(const PadOptions())),
      ],
    );
  }

  // ------------------------------------------------------------------- game

  Widget _buildGame() {
    final game = _s.game;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.inGame)
          const _Hint('Изменение правил начнёт новую партию.', warning: true),
        _Group(
          title: 'Скорость падения',
          children: [
            _Choice<double>(
              label: 'Шаг в активном стакане',
              value: game.activeStepSeconds,
              options: const [(0.5, '0.5 с'), (0.75, '0.75 с'), (1.0, '1 с'), (1.5, '1.5 с')],
              onChanged: (seconds) => _game(game.copyWith(activeStepSeconds: seconds)),
            ),
            _Choice<double>(
              label: 'Шаг в остальных стаканах',
              value: game.inactiveStepSeconds,
              options: const [
                (1.5, '1.5 с'),
                (2.0, '2 с'),
                (3.0, '3 с'),
                (4.0, '4 с'),
                (6.0, '6 с'),
              ],
              onChanged: (seconds) => _game(game.copyWith(inactiveStepSeconds: seconds)),
            ),
          ],
        ),
        _Group(
          title: 'Поле',
          children: [
            _Choice<int>(
              label: 'Длина рукава, клеток',
              value: game.armLength,
              options: const [(6, '6'), (8, '8'), (9, '9'), (10, '10')],
              onChanged: (cells) => _game(game.copyWith(armLength: cells)),
            ),
            _Choice<int>(
              label: 'Дополнительных стаканов',
              note: 'кроме вашего: меньше стаканов — спокойнее игра',
              value: game.glassCount - 1,
              options: const [(1, '1'), (2, '2'), (3, '3')],
              onChanged: (extra) => _game(game.copyWith(glassCount: extra + 1)),
            ),
            _Choice<int>(
              label: 'Цветов',
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final color in BlockColor.values.take(game.numberOfColors))
                    Container(
                      width: 13,
                      height: 13,
                      margin: const EdgeInsets.only(left: 5),
                      decoration: BoxDecoration(
                        color: BlockTones.of(color).base,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                ],
              ),
              value: game.numberOfColors,
              options: const [(3, '3'), (4, '4'), (5, '5'), (6, '6')],
              onChanged: (colors) => _game(game.copyWith(numberOfColors: colors)),
            ),
          ],
        ),
        _Group(
          title: 'Правила',
          children: [
            _Choice<GravityScope>(
              label: 'После хлопка падает',
              value: game.gravityScope,
              options: const [
                (GravityScope.wholeGlass, 'всё без опоры'),
                (GravityScope.aboveCleared, 'только над дырой'),
              ],
              onChanged: (scope) => _game(game.copyWith(gravityScope: scope)),
            ),
            _Choice<bool>(
              label: 'Стакан оседает при повороте',
              value: game.settleAfterBoardRotation,
              options: const [(false, 'нет'), (true, 'да')],
              onChanged: (settle) =>
                  _game(game.copyWith(settleAfterBoardRotation: settle)),
            ),
          ],
        ),
        _Reset('Сбросить правила', () => _game(const GameOptions())),
      ],
    );
  }

  // -------------------------------------------------------------- interface

  Widget _buildView() {
    final hud = _s.hud;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(
          title: 'Поворот поля',
          children: [
            _SliderRow(
              label: 'Длительность поворота',
              value: _s.turnMs.toDouble(),
              min: 0,
              max: 600,
              step: 20,
              unit: 'мс',
              note: _s.turnMs == 0 ? 'мгновенно' : null,
              onChanged: (ms) => widget.onChanged(_s.copyWith(turnMs: ms.round())),
            ),
            _Choice<bool>(
              label: 'Толчки и тряска поля',
              value: _s.screenShake,
              options: _onOff,
              onChanged: (shake) => widget.onChanged(_s.copyWith(screenShake: shake)),
            ),
          ],
        ),
        _Group(
          title: 'Надписи',
          children: [
            _Choice<bool>(
              label: 'Подписи на кнопках',
              value: hud.padLabels,
              options: _shown,
              onChanged: (shown) => _hud(hud.copyWith(padLabels: shown)),
            ),
            _Choice<bool>(
              label: 'Очки и комбо',
              note: 'слева сверху; в дзене — и уровень',
              value: hud.score,
              options: _shown,
              onChanged: (shown) => _hud(hud.copyWith(score: shown)),
            ),
            _Choice<bool>(
              label: 'Время, фигуры, матчи',
              value: hud.stats,
              options: _shown,
              onChanged: (shown) => _hud(hud.copyWith(stats: shown)),
            ),
            _SliderRow(
              label: 'Непрозрачность надписей',
              value: (hud.opacity * 100).roundToDouble(),
              min: 10,
              max: 100,
              step: 5,
              unit: '%',
              onChanged: (percent) => _hud(hud.copyWith(opacity: percent / 100)),
            ),
          ],
        ),
        _Reset(
          'Сбросить интерфейс',
          () => widget.onChanged(_s.copyWith(
            hud: const HudOptions(),
            turnMs: Settings.defaultTurnMs,
            screenShake: true,
          )),
        ),
      ],
    );
  }
}

class _Tabs extends StatelessWidget {
  const _Tabs({required this.tab, required this.onChanged});

  final _Tab tab;
  final ValueChanged<_Tab> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final item in _Tab.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(item),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 120),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: item == tab
                        ? Palette.accent.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      item.title.toUpperCase(),
                      style: Type.display(
                        12.5,
                        spacing: 0.5,
                        color: item == tab ? Colors.white : Palette.textDim,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text, {this.warning = false});

  final String text;
  final bool warning;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Text(
          text,
          style: Type.body(
            12.5,
            color: warning ? Palette.warning : Palette.textDim,
            weight: FontWeight.w400,
            height: 1.5,
          ),
        ),
      );
}

class _Group extends StatelessWidget {
  const _Group({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title.toUpperCase(), style: Type.label(11, color: Palette.accent)),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

/// A label with its choices as chips under it.
class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.note,
    this.trailing,
  });

  final String label;
  final String? note;

  /// A small picture after the label.
  final Widget? trailing;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(child: Text(label, style: Type.body(14))),
              ?trailing,
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                note!,
                style: Type.body(11.5, color: Palette.textFaint, weight: FontWeight.w400),
              ),
            ),
          const SizedBox(height: 7),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (option, text) in options)
                ChipButton(
                  label: text,
                  selected: option == value,
                  onPressed: () => onChanged(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
    this.note,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final double step;
  final String unit;
  final String? note;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: Type.body(14))),
              Text(
                '${value.round()} $unit${note == null ? '' : ' · $note'}',
                style: Type.body(14, weight: FontWeight.w800),
              ),
            ],
          ),
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 4,
              activeTrackColor: Palette.accent,
              inactiveTrackColor: Colors.white.withValues(alpha: 0.12),
              thumbColor: Palette.accent,
              overlayColor: Palette.accent.withValues(alpha: 0.16),
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 18),
              trackShape: const RoundedRectSliderTrackShape(),
              tickMarkShape: SliderTickMarkShape.noTickMark,
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: ((max - min) / step).round(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// One button of a pad and the action on it; tapping the action opens the
/// list to choose another.
class _SlotRow extends StatelessWidget {
  const _SlotRow({required this.slot, required this.action, required this.onChanged});

  final PadSlot slot;
  final PadAction action;
  final ValueChanged<PadAction> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 5),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white.withValues(alpha: 0.06))),
      ),
      child: Row(
        children: [
          Expanded(child: Text(slot.label, style: Type.body(14, weight: FontWeight.w800))),
          PopupMenuButton<PadAction>(
            initialValue: action,
            onSelected: onChanged,
            tooltip: '',
            padding: EdgeInsets.zero,
            color: Palette.bgRaised,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Palette.lineStrong),
            ),
            itemBuilder: (context) => [
              for (final option in PadAction.values)
                PopupMenuItem<PadAction>(
                  value: option,
                  height: 42,
                  child: Row(
                    children: [
                      Icon(
                        padActionIcon(option),
                        size: 20,
                        color: option == action ? Palette.accent : Palette.textDim,
                      ),
                      const SizedBox(width: 12),
                      Text(
                        option == PadAction.none ? 'Ничего' : option.label,
                        style: Type.body(
                          14,
                          weight: option == action ? FontWeight.w800 : FontWeight.w600,
                          color: option == action ? Colors.white : Palette.text,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Container(
              key: ValueKey('slot-${slot.name}'),
              constraints: const BoxConstraints(minWidth: 176),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(8),
                border: const Border(
                  top: BorderSide(color: Palette.lineStrong),
                  left: BorderSide(color: Palette.lineStrong),
                  right: BorderSide(color: Palette.lineStrong),
                  bottom: BorderSide(color: Palette.lineStrong, width: 3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    padActionIcon(action),
                    size: 18,
                    color: action == PadAction.none ? Palette.textFaint : Palette.text,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    action == PadAction.none ? 'Ничего' : action.label,
                    style: Type.body(
                      14,
                      weight: FontWeight.w800,
                      color: action == PadAction.none ? Palette.textFaint : Palette.text,
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Reset extends StatelessWidget {
  const _Reset(this.label, this.onPressed);

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 250,
          child: GameButton(label: label, onPressed: onPressed),
        ),
      );
}
