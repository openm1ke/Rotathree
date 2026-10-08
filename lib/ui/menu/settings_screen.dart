import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/bindings.dart';
import '../data/settings.dart';
import '../input/game_action.dart';
import '../style.dart';
import '../widgets/controls.dart';
import 'colour_picker.dart';

enum _Tab { controls, colours, effects, interface }

const _tabNames = {
  _Tab.controls: 'Управление',
  _Tab.colours: 'Цвета',
  _Tab.effects: 'Эффекты',
  _Tab.interface: 'Интерфейс',
};

/// The settings: keys and buttons, colours, effects and the look of the
/// field. Shown as a screen, or over a game with [overlay].
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    required this.settings,
    required this.stored,
    required this.onChange,
    required this.onBack,
    this.overlay = false,
  });

  final Settings settings;

  /// False when the device refuses to keep the settings.
  final bool stored;
  final ValueChanged<Settings> onChange;
  final VoidCallback onBack;

  /// Shown over a game rather than as a screen of its own.
  final bool overlay;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  _Tab _tab = _Tab.controls;

  /// The key slot waiting for its new key.
  ({GameAction action, int slot})? _capture;

  @override
  Widget build(BuildContext context) {
    final frame = Focus(
      autofocus: true,
      onKeyEvent: _onKey,
      child: ScreenFrame(
        kicker: widget.overlay ? 'В игре' : 'Меню',
        title: 'Настройки',
        onBack: widget.onBack,
        footer: widget.stored
            ? 'Всё сохраняется на этом устройстве сразу'
            : 'Браузер не даёт сохранить настройки: после перезапуска они сбросятся',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final tab in _Tab.values)
                OptionChip(
                  label: _tabNames[tab]!,
                  selected: _tab == tab,
                  onPressed: () => setState(() => _tab = tab),
                ),
            ],
          ),
          const SizedBox(height: 14),
          ...switch (_tab) {
            _Tab.controls => _controls(),
            _Tab.colours => _colours(),
            _Tab.effects => _effects(),
            _Tab.interface => _interface(),
          },
        ],
      ),
    );
    if (!widget.overlay) return frame;
    return ColoredBox(color: const Color(0xF2070710), child: frame);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final capture = _capture;
    if (capture == null || event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.physicalKey;
    final bindings = widget.settings.bindings;
    if (key == PhysicalKeyboardKey.escape) {
      setState(() => _capture = null);
    } else if (key == PhysicalKeyboardKey.backspace || key == PhysicalKeyboardKey.delete) {
      widget.onChange(widget.settings.copyWith(bindings: unbindKey(bindings, capture.action, capture.slot)));
      setState(() => _capture = null);
    } else {
      widget.onChange(widget.settings.copyWith(bindings: bindKey(bindings, capture.action, capture.slot, key)));
      setState(() => _capture = null);
    }
    return KeyEventResult.handled;
  }

  // --------------------------------------------------------------- controls

  List<Widget> _controls() {
    final s = widget.settings;
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          'Нажмите на действие, затем на новую клавишу. Esc — отмена, Backspace — очистить. '
          'Клавиша, занятая другим действием, переходит к новому.',
          style: Type.body(12, color: Palette.textDim),
        ),
      ),
      for (final group in ActionGroup.values)
        Section(
          title: group.title,
          children: [
            for (final action in keyActions)
              if (action.group == group) _bindingRow(action),
          ],
        ),
      Section(
        title: 'Автоповтор движения',
        children: [
          SliderRow(
            label: 'Задержка перед повтором (DAS)',
            value: s.handling.dasMs,
            min: 0,
            max: 300,
            step: 5,
            unit: 'мс',
            onChanged: (value) =>
                widget.onChange(s.copyWith(handling: s.handling.copyWith(dasMs: value.round()))),
          ),
          SliderRow(
            label: 'Интервал повтора (ARR)',
            value: s.handling.arrMs,
            min: 0,
            max: 100,
            step: 5,
            unit: 'мс',
            note: s.handling.arrMs == 0 ? 'сразу до стенки' : null,
            onChanged: (value) =>
                widget.onChange(s.copyWith(handling: s.handling.copyWith(arrMs: value.round()))),
          ),
        ],
      ),
      Section(
        title: 'Экранные кнопки',
        note: 'Что делает каждая кнопка левого и правого креста. Кнопки работают как клавиши.',
        children: [
          for (final slot in PadSlot.values)
            _padRow('Левый крест', slot, s.leftPad, (action) => widget.onChange(s.copyWith(leftPad: {...s.leftPad, slot: action}))),
          for (final slot in PadSlot.values)
            _padRow('Правый крест', slot, s.rightPad, (action) => widget.onChange(s.copyWith(rightPad: {...s.rightPad, slot: action}))),
        ],
      ),
      Center(
        child: OutlineButton(
          label: 'Сбросить управление',
          onPressed: () => widget.onChange(s.copyWith(
            bindings: defaultBindings(),
            handling: const Handling(),
            leftPad: defaultLeftPad,
            rightPad: defaultRightPad,
          )),
        ),
      ),
      const SizedBox(height: 20),
    ];
  }

  Widget _bindingRow(GameAction action) {
    final keys = widget.settings.bindings[action]!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(action.label, style: Type.body(14, weight: FontWeight.w800)),
                Text(action.hint, style: Type.body(11, color: Palette.textDim)),
              ],
            ),
          ),
          for (var slot = 0; slot < slotsPerAction; slot++)
            // The second slot only shows once the first is taken.
            if (slot <= keys.length) ...[
              Keycap(
                label: _capture?.action == action && _capture?.slot == slot
                    ? 'нажмите…'
                    : (slot < keys.length ? keyLabel(keys[slot]) : '+'),
                waiting: _capture?.action == action && _capture?.slot == slot,
                empty: slot >= keys.length,
                onPressed: () => setState(() {
                  final same = _capture?.action == action && _capture?.slot == slot;
                  _capture = same ? null : (action: action, slot: slot);
                }),
              ),
              const SizedBox(width: 6),
            ],
        ],
      ),
    );
  }

  Widget _padRow(String pad, PadSlot slot, PadLayout layout, ValueChanged<GameAction> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Text('$pad · ${slot.label}', style: Type.body(13, weight: FontWeight.w700)),
          ),
          DropdownButton<GameAction>(
            value: layout[slot]!,
            dropdownColor: Palette.panelStrong,
            underline: const SizedBox.shrink(),
            style: Type.body(13, color: Palette.accent, weight: FontWeight.w800),
            items: [
              for (final action in GameAction.values)
                DropdownMenuItem(value: action, child: Text(action.label)),
            ],
            onChanged: (action) {
              if (action != null) onChanged(action);
            },
          ),
        ],
      ),
    );
  }

  // ----------------------------------------------------------------- colours

  void _setPalettes(Palettes palettes) => widget.onChange(widget.settings.copyWith(palettes: palettes));

  String _newId() => 'custom-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';

  List<Widget> _colours() {
    final palettes = widget.settings.palettes;
    final active = palettes.activeSet;
    return [
      Section(
        title: 'Наборы',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final set in palettes.sets)
                OptionChip(
                  label: set.name,
                  selected: set.id == active.id,
                  onPressed: () => _setPalettes(palettes.copyWith(active: set.id)),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlineButton(label: 'Новый набор из текущего', onPressed: () => _copyActive(palettes, active)),
              if (!active.builtin)
                OutlineButton(
                  label: 'Удалить набор',
                  danger: true,
                  onPressed: () => _setPalettes(palettes.copyWith(
                    active: 'classic',
                    sets: [for (final set in palettes.sets) if (set.id != active.id) set],
                  )),
                ),
            ],
          ),
        ],
      ),
      Section(
        title: 'Цвета фигур · ${active.name}',
        note: 'Стандартные наборы не меняются: изменяя цвет, вы получаете свою копию.',
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var slot = 0; slot < colourNames.length; slot++)
                SizedBox(
                  width: 160,
                  child: ColourSwatch(
                    name: colourNames[slot],
                    colour: active.colours[slot],
                    onTap: () => _pick(slot, active),
                  ),
                ),
            ],
          ),
        ],
      ),
      Section(
        title: 'Так это выглядит',
        children: [
          Row(
            children: [
              for (final colour in active.colours)
                Expanded(
                  child: Container(
                    height: 28,
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(6)),
                  ),
                ),
            ],
          ),
        ],
      ),
    ];
  }

  void _copyActive(Palettes palettes, PaletteSet active) {
    final set = PaletteSet(
      id: _newId(),
      name: 'Мой набор ${palettes.sets.length - builtinPalettes.length + 1}',
      colours: List.of(active.colours),
    );
    _setPalettes(palettes.copyWith(active: set.id, sets: [...palettes.sets, set]));
  }

  Future<void> _pick(int slot, PaletteSet active) async {
    final picked = await showColourPicker(context, active.colours[slot], colourNames[slot]);
    if (picked == null || !mounted) return;
    final palettes = widget.settings.palettes;
    final colours = [
      for (var i = 0; i < active.colours.length; i++) i == slot ? picked : active.colours[i],
    ];
    if (active.builtin) {
      // A built-in set is copied before it is changed.
      final name = '${active.name} · мой';
      final set = PaletteSet(
        id: _newId(),
        name: name.length > 24 ? name.substring(0, 24) : name,
        colours: colours,
      );
      _setPalettes(palettes.copyWith(active: set.id, sets: [...palettes.sets, set]));
    } else {
      _setPalettes(palettes.copyWith(
        sets: [for (final set in palettes.sets) set.id == active.id ? set.copyWith(colours: colours) : set],
      ));
    }
  }

  // ----------------------------------------------------------------- effects

  void _setEffects(EffectOptions effects) => widget.onChange(widget.settings.copyWith(effects: effects));

  List<Widget> _effects() {
    final e = widget.settings.effects;
    return [
      Section(
        title: 'Взрывы',
        note: 'как взрываются линии после исчезновения фигур',
        children: [
          OptionGroup<ExplosionStyle>(
            label: 'Анимация взрыва',
            value: e.explosion,
            options: const [
              (value: ExplosionStyle.varied, label: 'Разная для каждого типа'),
              (value: ExplosionStyle.unified, label: 'Одна для всех'),
            ],
            onChanged: (explosion) => _setEffects(e.copyWith(explosion: explosion)),
          ),
          Text(
            'Разная: тройки, четвёрки и пятёрки взрываются по-своему, шесть и больше — с золотой вспышкой. '
            'Одновременные линии добавляют волны, три линии сразу — вспышку поля. Одна: все взрывы одинаковые.',
            style: Type.body(12, color: Palette.textDim),
          ),
        ],
      ),
      Section(
        title: 'Поле',
        children: [
          SwitchRow(
            label: 'Толчки и тряска поля',
            value: e.screenShake,
            onChanged: (screenShake) => _setEffects(e.copyWith(screenShake: screenShake)),
          ),
          SliderRow(
            label: 'Поворот поля',
            value: e.turnMs,
            min: 0,
            max: 600,
            step: 20,
            unit: 'мс',
            note: e.turnMs == 0 ? 'мгновенно' : null,
            onChanged: (value) => _setEffects(e.copyWith(turnMs: value.round())),
          ),
        ],
      ),
      Center(
        child: OutlineButton(
          label: 'Сбросить эффекты',
          onPressed: () => _setEffects(const EffectOptions()),
        ),
      ),
      const SizedBox(height: 20),
    ];
  }

  // --------------------------------------------------------------- interface

  void _setHud(HudOptions hud) => widget.onChange(widget.settings.copyWith(hud: hud));

  List<Widget> _interface() {
    final h = widget.settings.hud;
    return [
      Section(
        title: 'Надписи на поле',
        children: [
          SwitchRow(
            label: 'Подсказки клавиш',
            value: h.keyHints,
            on: 'показывать',
            off: 'скрыть',
            onChanged: (keyHints) => _setHud(h.copyWith(keyHints: keyHints)),
          ),
          SwitchRow(
            label: 'Очки, уровень и комбо',
            value: h.score,
            on: 'показывать',
            off: 'скрыть',
            onChanged: (score) => _setHud(h.copyWith(score: score)),
          ),
          SwitchRow(
            label: 'Время, фигуры, матчи',
            value: h.stats,
            on: 'показывать',
            off: 'скрыть',
            onChanged: (stats) => _setHud(h.copyWith(stats: stats)),
          ),
          SliderRow(
            label: 'Непрозрачность надписей',
            value: (h.opacity * 100).round(),
            min: 10,
            max: 100,
            step: 5,
            unit: '%',
            onChanged: (percent) => _setHud(h.copyWith(opacity: percent / 100)),
          ),
        ],
      ),
      Center(
        child: OutlineButton(
          label: 'Сбросить интерфейс',
          onPressed: () {
            final defaults = Settings.defaults();
            widget.onChange(widget.settings.copyWith(hud: defaults.hud, effects: defaults.effects));
          },
        ),
      ),
      const SizedBox(height: 20),
    ];
  }
}
