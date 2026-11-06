import 'dart:math' as math;

import '../cube/cube_setup_screen.dart';
import '../i18n/strings.dart';
import 'package:flutter/material.dart';

import '../data/bindings.dart';
import '../data/settings.dart';
import '../field/block_look.dart';
import '../i18n/language_picker.dart';
import '../input/game_action.dart';
import '../input/pad_placement.dart';
import '../input/pad_shape.dart';
import '../input/pad_surface.dart';
import '../layout.dart';
import '../audio/sound_effects.dart';
import '../style.dart';
import '../widgets/controls.dart';
import 'colour_picker.dart';
import 'licenses.dart';

enum _Tab { controls, colours, effects, interface, sound, licenses }

const _tabNames = {
  _Tab.controls: 'Управление',
  _Tab.colours: 'Вид',
  _Tab.effects: 'Эффекты',
  _Tab.interface: 'Интерфейс',
  _Tab.sound: 'Звуки',
  _Tab.licenses: 'Лицензии',
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
    this.cube = false,
  });

  final Settings settings;

  /// False when the device refuses to keep the settings.
  final bool stored;
  final ValueChanged<Settings> onChange;
  final VoidCallback onBack;

  /// Shown over a game rather than as a screen of its own.
  final bool overlay;

  /// Opened over a game of Cube: its look comes first, and its pads.
  final bool cube;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  /// The button the controls tab is editing, shown outlined in the preview.
  PadSide _editSide = PadSide.left;
  PadSlot _editSlot = PadSlot.up;

  /// Which game's pad buttons are being laid out: the flat game's or Cube's.
  /// Where the pads are and how they look is the same for both.
  late ActionScope _padGame = widget.cube ? ActionScope.cube : ActionScope.flat;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(
      length: _Tab.values.length,
      vsync: this,
      initialIndex: widget.cube && !usesDesktopKeyboard ? _Tab.interface.index : 0,
    );
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
    // A column, not a strip across a wide window: 62 % of the window, at
    // least 640 and at most a menu's width, the same in a game as in the
    // menus; a narrower screen gives it all its width.
    final screen = MediaQuery.sizeOf(context).width;
    final page = LayoutBuilder(
      builder: (context, box) {
        final width = math.min(box.maxWidth, (screen * 0.62).clamp(640.0, tabletMenuWidth));
        return Center(child: SizedBox(width: width, child: frame));
      },
    );
    if (!widget.overlay) return page;
    return ColoredBox(color: const Color(0xF2070710), child: page);
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
          _Tab.licenses => licenseSections(context),
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

  List<Widget> _keyboardControls(Settings settings) => [
        for (final group in ActionGroup.values)
          Section(
            title: group.title,
            note: group == ActionGroup.piece ? 'Tab — выбрать кнопку, Enter — нажать, Esc — назад или пауза.' : null,
            children: [
              for (final action in keyActions.where((action) => action.group == group))
                if (settings.bindings[action]!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: LText(
                            action.label,
                            style: Type.body(14, weight: FontWeight.w800),
                          ),
                        ),
                        for (final key in settings.bindings[action]!)
                          Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Keycap(label: keyLabel(key)),
                          ),
                      ],
                    ),
                  ),
            ],
          ),
      ];

  Widget _repeatControls(Settings s) => Section(
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
  );

  Widget _dropControls(Settings s) => Section(
    title: 'Сброс',
    note: 'Мгновенный: фигура сразу встаёт на место, без полёта вниз — как в tetr.io.',
    children: [
      SwitchRow(
        label: 'Мгновенный сброс',
        value: s.handling.instantDrop,
        onChanged: (instant) => widget.onChange(s.copyWith(handling: s.handling.copyWith(instantDrop: instant))),
      ),
    ],
  );

  List<Widget> _controls() {
    final s = widget.settings;
    if (usesDesktopKeyboard) return [..._keyboardControls(s), _repeatControls(s), _dropControls(s)];
    final tweak = s.padButtons[_editSide]?[_editSlot] ?? const PadTweak();
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
            layouts: _padGame == ActionScope.cube ? (s.cubeLeftPad, s.cubeRightPad) : null,
            onDown: (_) {},
            onUp: (_) {},
            onEdit: (positions) => widget.onChange(s.copyWith(padPositions: positions)),
            highlight: (_editSide, _editSlot),
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
        title: 'Вид кнопок',
        note:
            'Форма и подписи одинаковы у обеих крестовин. Размер и сдвиг задаются для каждой кнопки отдельно: выбранная кнопка подсвечивается в поле.',
        children: [
          OptionGroup<PadShape>(
            label: 'Форма',
            value: s.padShape,
            options: [for (final shape in PadShape.values) (value: shape, label: shape.label)],
            onChanged: (shape) => widget.onChange(s.copyWith(padShape: shape)),
          ),
          SwitchRow(
            label: 'Подписи кнопок',
            value: s.hud.keyHints,
            on: 'показывать',
            off: 'скрыть',
            onChanged: (keyHints) => widget.onChange(s.copyWith(hud: s.hud.copyWith(keyHints: keyHints))),
          ),
          OptionGroup<PadSide>(
            label: 'Крестовина',
            value: _editSide,
            options: const [(value: PadSide.left, label: 'Левая'), (value: PadSide.right, label: 'Правая')],
            onChanged: (side) => setState(() => _editSide = side),
          ),
          OptionGroup<PadSlot>(
            label: 'Кнопка',
            value: _editSlot,
            options: [for (final slot in PadSlot.values) (value: slot, label: slot.label)],
            onChanged: (slot) => setState(() => _editSlot = slot),
          ),
          SliderRow(
            label: 'Размер кнопки',
            value: (tweak.scale * 100).roundToDouble(),
            min: 50,
            max: 150,
            step: 5,
            unit: '%',
            onChanged: (percent) => widget.onChange(s.withButton(_editSide, _editSlot, tweak.copyWith(scale: percent / 100))),
          ),
          SliderRow(
            label: 'Сдвиг по горизонтали',
            value: (tweak.dx * 100).roundToDouble(),
            min: -25,
            max: 25,
            step: 1,
            unit: '%',
            onChanged: (percent) => widget.onChange(s.withButton(_editSide, _editSlot, tweak.copyWith(dx: percent / 100))),
          ),
          SliderRow(
            label: 'Сдвиг по вертикали',
            value: (tweak.dy * 100).roundToDouble(),
            min: -25,
            max: 25,
            step: 1,
            unit: '%',
            onChanged: (percent) => widget.onChange(s.withButton(_editSide, _editSlot, tweak.copyWith(dy: percent / 100))),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: OutlineButton(
              label: 'Вернуть эту кнопку',
              onPressed: () => widget.onChange(s.withButton(_editSide, _editSlot, const PadTweak())),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: OutlineButton(
              label: 'Сбросить кнопки',
              onPressed: () => widget.onChange(
                s.copyWith(
                  leftPad: defaultLeftPad,
                  rightPad: defaultRightPad,
                  padPositions: const PadPositions(),
                  padShape: PadShape.square,
                  padButtons: const {},
                  hud: s.hud.copyWith(keyHints: true),
                ),
              ),
            ),
          ),
        ],
      ),
      _repeatControls(s),
      _dropControls(s),
      Section(
        title: 'Экранные кнопки',
        note: 'Что делает каждая кнопка левого и правого креста. Можно нажимать обе крестовины одновременно.',
        children: [
          OptionGroup<ActionScope>(
            square: true,
            label: 'Крестовины для',
            value: _padGame,
            options: const [(value: ActionScope.flat, label: '2D'), (value: ActionScope.cube, label: 'Куб')],
            onChanged: (game) => setState(() => _padGame = game),
          ),
          if (_padGame == ActionScope.flat) ...[
            for (final slot in PadSlot.values)
              _padRow(
                'Левая крестовина',
                slot,
                s.leftPad,
                ActionScope.flat,
                (action) => widget.onChange(s.copyWith(leftPad: {...s.leftPad, slot: action})),
              ),
            for (final slot in PadSlot.values)
              _padRow(
                'Правая крестовина',
                slot,
                s.rightPad,
                ActionScope.flat,
                (action) => widget.onChange(s.copyWith(rightPad: {...s.rightPad, slot: action})),
              ),
          ] else ...[
            for (final slot in PadSlot.values)
              _padRow(
                'Левая крестовина',
                slot,
                s.cubeLeftPad,
                ActionScope.cube,
                (action) => widget.onChange(s.copyWith(cubeLeftPad: {...s.cubeLeftPad, slot: action})),
              ),
            for (final slot in PadSlot.values)
              _padRow(
                'Правая крестовина',
                slot,
                s.cubeRightPad,
                ActionScope.cube,
                (action) => widget.onChange(s.copyWith(cubeRightPad: {...s.cubeRightPad, slot: action})),
              ),
          ],
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
              cubeLeftPad: defaultCubeLeftPad,
              cubeRightPad: defaultCubeRightPad,
              padPositions: const PadPositions(),
              padShape: PadShape.square,
              padButtons: const {},
              hud: s.hud.copyWith(keyHints: true),
            ),
          ),
        ),
      ),
      const SizedBox(height: 20),
    ];
  }

  Widget _padRow(String pad, PadSlot slot, PadLayout layout, ActionScope game, ValueChanged<GameAction> onChanged) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: LText('$pad · ${slot.label}', maxLines: 1, softWrap: false, style: Type.body(13, weight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 10),
          // Cube's actions have long names: the choice takes what room there is.
          Flexible(
            child: DropdownButton<GameAction>(
              value: layout[slot]!,
              isExpanded: true,
              dropdownColor: Palette.panelStrong,
              underline: const SizedBox.shrink(),
              style: Type.body(13, color: Palette.accent, weight: FontWeight.w800),
              items: [
                for (final action in GameAction.values)
                  if (action.inScope(game))
                    DropdownMenuItem(
                      value: action,
                      child: LText(action.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
              ],
              onChanged: (action) {
                if (action != null) onChanged(action);
              },
            ),
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
    final skin = widget.settings.skin;
    return [
      Section(
        title: 'Блоки',
        note: 'Как выглядят фигуры в обеих играх. Совпадают по-прежнему блоки одного цвета.',
        children: [
          LayoutBuilder(
            builder: (context, box) {
              final width = box.maxWidth >= 520 ? (box.maxWidth - 10) / 2 : box.maxWidth;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final option in BlockSkin.values)
                    SizedBox(
                      width: width,
                      child: _SkinCard(
                        key: ValueKey('skin-${option.name}'),
                        skin: option,
                        colours: active.colours,
                        selected: option == skin,
                        onTap: () => widget.onChange(widget.settings.copyWith(skin: option)),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
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
          LayoutBuilder(
            builder: (context, box) => Center(
              child: BlockRow(
                skin: skin,
                colours: active.colours,
                height: (box.maxWidth / active.colours.length).clamp(20.0, 48.0),
              ),
            ),
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
              (value: ExplosionStyle.off, label: 'выкл'),
            ],
            onChanged: (explosion) => _setEffects(e.copyWith(explosion: explosion)),
          ),
          LText(
            'Разная — эффект зависит от совпадения. Одна — одинаковые взрывы. Выкл — без частиц и вспышек.',
            style: Type.body(12, color: Palette.textDim),
          ),
        ],
      ),
      Section(
        title: 'Поле',
        children: [
          SwitchRow(
            label: 'Фоновая анимация поля',
            value: e.fieldBackground,
            onChanged: (fieldBackground) => _setEffects(e.copyWith(fieldBackground: fieldBackground)),
          ),
          LText('Отключите для снижения нагрузки на устройство.', style: Type.body(12, color: Palette.textDim)),
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
    // Cube's switches: over its game, the first thing on the tab.
    final cubeLook = CubeLookSection(
      title: 'Куб',
      note: 'Что показывать в режиме «Куб»',
      cube: widget.settings.cube,
      onChange: (cube) => widget.onChange(widget.settings.copyWith(cube: cube)),
    );
    return [
      if (widget.cube) cubeLook,
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
        title: 'Игровое поле',
        children: [
          SwitchRow(
            label: 'Следующая фигура',
            value: h.nextPiece,
            on: 'показывать',
            off: 'скрыть',
            onChanged: (nextPiece) => _setHud(h.copyWith(nextPiece: nextPiece)),
          ),
          if (h.nextPiece)
            SliderRow(
              label: 'Непрозрачность подсказки',
              value: (h.nextPieceOpacity * 100).round(),
              min: 10,
              max: 100,
              step: 5,
              unit: '%',
              onChanged: (percent) => _setHud(h.copyWith(nextPieceOpacity: percent / 100)),
            ),
          SwitchRow(
            label: 'Очки и уровень',
            value: h.score,
            on: 'показывать',
            off: 'скрыть',
            onChanged: (score) => _setHud(h.copyWith(score: score)),
          ),
          SwitchRow(
            label: 'Время и фигуры',
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
      if (!widget.cube) cubeLook,
      Center(
        child: OutlineButton(
          label: 'Сбросить интерфейс',
          onPressed: () {
            final defaults = Settings.defaults();
            final cube = widget.settings.cube;
            // Cube's look goes back to its default; its game stays as set.
            final look = const CubeOptions().copyWith(
              colours: cube.colours,
              width: cube.width,
              arm: cube.arm,
              depthFalls: cube.depthFalls,
              inactiveFalls: cube.inactiveFalls,
            );
            widget.onChange(widget.settings.copyWith(hud: defaults.hud, effects: defaults.effects, cube: look));
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
      Section(
        title: 'Звуки игры',
        note: 'Ходы, линии, кнопки и итоги уровня',
        children: [
          SwitchRow(
            label: 'Звуки',
            value: audio.sounds,
            on: 'вкл',
            off: 'выкл',
            onChanged: (sounds) => setAudio(audio.copyWith(sounds: sounds)),
          ),
          SliderRow(
            label: 'Громкость звуков',
            value: (audio.soundsVolume * 100).round(),
            min: 0,
            max: 100,
            step: 5,
            unit: '%',
            onChanged: (value) => setAudio(audio.copyWith(soundsVolume: value / 100)),
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

/// One way to draw the blocks: five of them drawn so, and its name.
class _SkinCard extends StatelessWidget {
  const _SkinCard({super.key, required this.skin, required this.colours, required this.selected, required this.onTap});

  final BlockSkin skin;
  final List<Color> colours;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(14);
    return Semantics(
      button: true,
      selected: selected,
      label: context.tr(skin.title),
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: radius,
          onTap: clicking(onTap),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: radius,
              color: selected ? Palette.accent.withValues(alpha: 0.1) : Palette.panel,
              border: Border.all(color: selected ? Palette.accent : Palette.line, width: selected ? 1.5 : 1),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: BlockRow(skin: skin, colours: colours, count: 5, height: 36),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: LText(skin.title, style: Type.body(15, weight: FontWeight.w800, color: selected ? Palette.accent : Palette.text)),
                    ),
                    if (selected) const Icon(Icons.check_circle_rounded, size: 20, color: Palette.accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
