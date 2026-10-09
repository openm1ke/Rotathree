import '../i18n/strings.dart';
import 'package:flutter/material.dart';

import '../data/settings.dart';
import '../i18n/language_picker.dart';
import '../input/game_action.dart';
import '../input/pad_placement.dart';
import '../input/pad_surface.dart';
import '../style.dart';
import '../widgets/controls.dart';
import 'colour_picker.dart';

enum _Tab { controls, colours, effects, interface, sound }

const _tabNames = {
  _Tab.controls: 'Управление',
  _Tab.colours: 'Цвета',
  _Tab.effects: 'Эффекты',
  _Tab.interface: 'Интерфейс',
  _Tab.sound: 'Звуки',
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

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _Tab.values.length, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frame = Focus(
      autofocus: true,
      child: ScreenFrame(
        kicker: widget.overlay ? 'В игре' : 'Меню',
        title: 'Настройки',
        onBack: widget.onBack,
        body: Column(
          children: [
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              labelPadding: const EdgeInsets.symmetric(horizontal: 14),
              labelColor: Palette.accent,
              unselectedLabelColor: Palette.textDim,
              labelStyle: Type.body(14, weight: FontWeight.w800),
              indicatorColor: Palette.accent,
              dividerColor: Palette.line,
              tabs: [for (final tab in _Tab.values) Tab(child: LText(_tabNames[tab]!))],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [for (final tab in _Tab.values) _page(tab)],
              ),
            ),
          ],
        ),
      ),
    );
    if (!widget.overlay) return frame;
    return ColoredBox(color: const Color(0xF2070710), child: frame);
  }

  Widget _page(_Tab tab) {
    return ListView(
      key: PageStorageKey(tab),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        ...switch (tab) {
          _Tab.controls => _controls(),
          _Tab.colours => _colours(),
          _Tab.effects => _effects(),
          _Tab.interface => _interface(),
          _Tab.sound => _sound(),
        },
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LText(
            widget.stored
                ? 'Всё сохраняется на этом устройстве сразу'
                : 'Не удалось сохранить данные на устройстве. Проверьте свободное место.',
            style: Type.body(12, color: Palette.textDim),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- controls

  List<Widget> _controls() {
    final s = widget.settings;
    return [
      Section(
        title: 'Размер и положение',
        note:
            'Перетащите крестовины внутри выделенной области под полем. Они остаются в пределах экрана и не перекрывают друг друга.',
        children: [
          Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: Palette.bg, borderRadius: BorderRadius.circular(8)),
            child: LText('Игровое поле', style: Type.body(13, color: Palette.textDim)),
          ),
          PadSurface(
            settings: s,
            onDown: (_) {},
            onUp: (_) {},
            onEdit: (positions) => widget.onChange(s.copyWith(padPositions: positions)),
          ),
          for (final side in PadSide.values)
            SliderRow(
              label: side == PadSide.left ? 'Размер левой крестовины' : 'Размер правой крестовины',
              value: s.padPositions[side].size,
              min: 136,
              max: 216,
              step: 4,
              unit: 'px',
              onChanged: (value) => widget.onChange(
                s.copyWith(
                  padPositions: s.padPositions.withSide(side, s.padPositions[side].copyWith(size: value.toDouble())),
                ),
              ),
            ),
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
            onChanged: (value) => widget.onChange(s.copyWith(handling: s.handling.copyWith(dasMs: value.round()))),
          ),
          SliderRow(
            label: 'Интервал повтора (ARR)',
            value: s.handling.arrMs,
            min: 0,
            max: 100,
            step: 5,
            unit: 'мс',
            note: s.handling.arrMs == 0 ? 'сразу до стенки' : null,
            onChanged: (value) => widget.onChange(s.copyWith(handling: s.handling.copyWith(arrMs: value.round()))),
          ),
        ],
      ),
      Section(
        title: 'Экранные кнопки',
        note: 'Что делает каждая кнопка левого и правого креста. Можно нажимать обе крестовины одновременно.',
        children: [
          for (final slot in PadSlot.values)
            _padRow(
              'Левый крест',
              slot,
              s.leftPad,
              (action) => widget.onChange(s.copyWith(leftPad: {...s.leftPad, slot: action})),
            ),
          for (final slot in PadSlot.values)
            _padRow(
              'Правый крест',
              slot,
              s.rightPad,
              (action) => widget.onChange(s.copyWith(rightPad: {...s.rightPad, slot: action})),
            ),
        ],
      ),
      Center(
        child: OutlineButton(
          label: 'Сбросить управление',
          onPressed: () => widget.onChange(
            s.copyWith(
              handling: const Handling(),
              leftPad: defaultLeftPad,
              rightPad: defaultRightPad,
              padPositions: const PadPositions(),
            ),
          ),
        ),
      ),
      const SizedBox(height: 20),
    ];
  }

  Widget _padRow(String pad, PadSlot slot, PadLayout layout, ValueChanged<GameAction> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: LText('$pad · ${slot.label}', style: Type.body(13, weight: FontWeight.w700)),
          ),
          DropdownButton<GameAction>(
            value: layout[slot]!,
            dropdownColor: Palette.panelStrong,
            underline: const SizedBox.shrink(),
            style: Type.body(13, color: Palette.accent, weight: FontWeight.w800),
            items: [
              for (final action in GameAction.values) DropdownMenuItem(value: action, child: LText(action.label)),
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
                  translate: set.builtin,
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
                  onPressed: () => _setPalettes(
                    palettes.copyWith(
                      active: 'classic',
                      sets: [
                        for (final set in palettes.sets)
                          if (set.id != active.id) set,
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      Section(
        title: '${context.tr('Цвета фигур')} · ${active.builtin ? context.tr(active.name) : active.name}',
        translateTitle: false,
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
      name: context.tr('Мой набор ${palettes.sets.length - builtinPalettes.length + 1}'),
      colours: List.of(active.colours),
    );
    _setPalettes(palettes.copyWith(active: set.id, sets: [...palettes.sets, set]));
  }

  Future<void> _pick(int slot, PaletteSet active) async {
    final picked = await showColourPicker(context, active.colours[slot], colourNames[slot]);
    if (picked == null || !mounted) return;
    final palettes = widget.settings.palettes;
    final colours = [for (var i = 0; i < active.colours.length; i++) i == slot ? picked : active.colours[i]];
    if (active.builtin) {
      // A built-in set is copied before it is changed.
      final name = context.tr('${context.tr(active.name)} · мой');
      final set = PaletteSet(id: _newId(), name: name.length > 24 ? name.substring(0, 24) : name, colours: colours);
      _setPalettes(palettes.copyWith(active: set.id, sets: [...palettes.sets, set]));
    } else {
      _setPalettes(
        palettes.copyWith(
          sets: [for (final set in palettes.sets) set.id == active.id ? set.copyWith(colours: colours) : set],
        ),
      );
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
          LText(
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
        child: OutlineButton(label: 'Сбросить эффекты', onPressed: () => _setEffects(const EffectOptions())),
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
        title: 'Язык',
        note: 'Авто — по языку устройства',
        children: [
          LanguagePicker(
            value: widget.settings.language,
            onChanged: (language) => widget.onChange(widget.settings.copyWith(language: language)),
          ),
        ],
      ),
      Section(
        title: 'Надписи на поле',
        children: [
          SwitchRow(
            label: 'Подписи экранных кнопок',
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

  // --------------------------------------------------------------------- sound

  List<Widget> _sound() {
    final audio = widget.settings.audio;
    void setAudio(AudioOptions next) => widget.onChange(widget.settings.copyWith(audio: next));
    return [
      Section(
        title: 'Музыка',
        note: 'Треки плавно переходят друг в друга',
        children: [
          SwitchRow(
            label: 'Фоновая музыка',
            value: audio.music,
            on: 'вкл',
            off: 'выкл',
            onChanged: (music) => setAudio(audio.copyWith(music: music)),
          ),
          SliderRow(
            label: 'Громкость музыки',
            value: (audio.musicVolume * 100).round(),
            min: 0,
            max: 100,
            step: 5,
            unit: '%',
            onChanged: (value) => setAudio(audio.copyWith(musicVolume: value / 100)),
          ),
        ],
      ),
      Center(
        child: OutlineButton(
          label: 'Сбросить звук',
          onPressed: () => setAudio(const AudioOptions()),
        ),
      ),
      const SizedBox(height: 20),
    ];
  }
}
