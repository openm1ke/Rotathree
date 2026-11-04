import 'package:flutter/widgets.dart';

import '../input/game_action.dart';
import '../i18n/strings.dart';
import '../input/pad_placement.dart';
import '../input/pad_shape.dart';
import '../style.dart';
import 'bindings.dart';

/// How the lines of a match explode: one animation for everything, or one per
/// kind of match.
enum ExplosionStyle { unified, varied, off }

class EffectOptions {
  const EffectOptions({
    this.explosion = ExplosionStyle.varied,
    this.screenShake = true,
    this.fieldBackground = true,
    this.turnMs = 260,
  });

  final ExplosionStyle explosion;

  /// Decorative animation behind the glasses and the game screen.
  final bool fieldBackground;

  /// Kicks and shakes of the field.
  final bool screenShake;

  /// Milliseconds the cross takes to turn a quarter; 0 turns it at once.
  final int turnMs;

  EffectOptions copyWith({ExplosionStyle? explosion, bool? screenShake, bool? fieldBackground, int? turnMs}) =>
      EffectOptions(
        explosion: explosion ?? this.explosion,
        screenShake: screenShake ?? this.screenShake,
        fieldBackground: fieldBackground ?? this.fieldBackground,
        turnMs: turnMs ?? this.turnMs,
      );
}

class HudOptions {
  const HudOptions({
    this.keyHints = true,
    this.nextPiece = true,
    this.nextPieceOpacity = 1,
    this.score = true,
    this.stats = true,
    this.opacity = 1,
  });

  /// The reminder of which key does what.
  final bool keyHints;

  /// A preview of the next stick above each glass's entry.
  final bool nextPiece;

  /// Opacity of the entire next-piece card, 0.1 … 1.
  final double nextPieceOpacity;

  /// The score, level and score-gain callouts.
  final bool score;

  /// Elapsed time and placed pieces.
  final bool stats;

  /// Opacity of the writing on the field, 0.1 … 1.
  final double opacity;

  HudOptions copyWith({bool? keyHints, bool? nextPiece, double? nextPieceOpacity, bool? score, bool? stats, double? opacity}) => HudOptions(
        keyHints: keyHints ?? this.keyHints,
        nextPiece: nextPiece ?? this.nextPiece,
        nextPieceOpacity: nextPieceOpacity ?? this.nextPieceOpacity,
        score: score ?? this.score,
        stats: stats ?? this.stats,
        opacity: opacity ?? this.opacity,
      );
}

/// Music and sound effect preferences. Volumes are stored from 0.0 to 1.0;
/// the effects start quiet, as on the web.
class AudioOptions {
  const AudioOptions({this.music = true, this.musicVolume = 0.1, this.sounds = true, this.soundsVolume = 0.3});

  final bool music;
  final double musicVolume;
  final bool sounds;
  final double soundsVolume;

  AudioOptions copyWith({bool? music, double? musicVolume, bool? sounds, double? soundsVolume}) => AudioOptions(
        music: music ?? this.music,
        musicVolume: musicVolume ?? this.musicVolume,
        sounds: sounds ?? this.sounds,
        soundsVolume: soundsVolume ?? this.soundsVolume,
      );
}

class Handling {
  const Handling({this.dasMs = 150, this.arrMs = 35});

  /// Delay before a held direction repeats, in milliseconds.
  final int dasMs;

  /// Interval between repeats, in milliseconds; 0 slides to the wall.
  final int arrMs;

  Handling copyWith({int? dasMs, int? arrMs}) =>
      Handling(dasMs: dasMs ?? this.dasMs, arrMs: arrMs ?? this.arrMs);
}

class PaletteSet {
  const PaletteSet({
    required this.id,
    required this.name,
    required this.colours,
    this.builtin = false,
  });

  final String id;
  final String name;

  /// One colour per colour slot, in the order of [colourNames].
  final List<Color> colours;

  /// Built-in sets cannot be changed; editing one copies it first.
  final bool builtin;

  PaletteSet copyWith({String? name, List<Color>? colours}) => PaletteSet(
        id: id,
        name: name ?? this.name,
        colours: colours ?? this.colours,
        builtin: builtin,
      );
}

/// The names of the nine colour slots, in order.
const colourNames = [
  'Красный',
  'Синий',
  'Жёлтый',
  'Зелёный',
  'Фиолетовый',
  'Белый',
  'Оранжевый',
  'Голубой',
  'Розовый',
];

const builtinPalettes = [
  PaletteSet(id: 'classic', name: 'Классика', colours: classicColours, builtin: true),
  PaletteSet(
    id: 'pastel',
    name: 'Пастель',
    builtin: true,
    colours: [
      Color(0xFFFF8FA3),
      Color(0xFF8FC1FF),
      Color(0xFFFFE08A),
      Color(0xFF9FF0C4),
      Color(0xFFC9A8FF),
      Color(0xFFF4F6FB),
      Color(0xFFFFB88A),
      Color(0xFF9FF4FA),
      Color(0xFFFFB3DC),
    ],
  ),
  PaletteSet(
    id: 'neon',
    name: 'Неон',
    builtin: true,
    colours: [
      Color(0xFFFF2D6F),
      Color(0xFF1E90FF),
      Color(0xFFFFE600),
      Color(0xFF00FF9C),
      Color(0xFFB200FF),
      Color(0xFFFFFFFF),
      Color(0xFFFF7A00),
      Color(0xFF00E5FF),
      Color(0xFFFF00C8),
    ],
  ),
];

class Palettes {
  const Palettes({required this.active, required this.sets});

  /// The palette in use, with the built-in ones first.
  final String active;
  final List<PaletteSet> sets;

  PaletteSet get activeSet => sets.firstWhere((set) => set.id == active, orElse: () => sets.first);

  Palettes copyWith({String? active, List<PaletteSet>? sets}) =>
      Palettes(active: active ?? this.active, sets: sets ?? this.sets);

  factory Palettes.defaults() => Palettes(active: 'classic', sets: builtinPalettes);

  factory Palettes.fromJson(Object? raw) {
    if (raw is! Map) return Palettes.defaults();
    final builtinIds = {for (final set in builtinPalettes) set.id};
    final custom = <PaletteSet>[];
    final stored = raw['sets'];
    if (stored is List) {
      for (final item in stored) {
        if (item is! Map) continue;
        final id = item['id'];
        final name = item['name'];
        final colours = item['colours'];
        if (id is! String || name is! String || colours is! List) continue;
        if (id.isEmpty || builtinIds.contains(id)) continue;
        custom.add(PaletteSet(
          id: id,
          name: name.length > 24 ? name.substring(0, 24) : name,
          colours: [
            for (var i = 0; i < colourNames.length; i++)
              (i < colours.length ? colourFromHex(colours[i]) : null) ?? classicColours[i],
          ],
        ));
      }
    }
    final sets = [...builtinPalettes, ...custom];
    final active = raw['active'];
    return Palettes(
      active: active is String && sets.any((set) => set.id == active) ? active : 'classic',
      sets: sets,
    );
  }

  Map<String, Object> toJson() => {
        'active': active,
        'sets': [
          for (final set in sets)
            if (!set.builtin)
              {
                'id': set.id,
                'name': set.name,
                'colours': [for (final colour in set.colours) colourToHex(colour)],
              },
        ],
      };
}

/// `#rrggbb` as a colour, or null when the text is not one.
Color? colourFromHex(Object? raw) {
  if (raw is! String || !RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(raw)) return null;
  return Color(0xFF000000 | int.parse(raw.substring(1), radix: 16));
}

/// The colour as `#rrggbb`.
String colourToHex(Color colour) =>
    '#${(colour.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Cube's setup and how its picture looks (CubeOptions on the web).
class CubeOptions {
  const CubeOptions({
    this.colours = 4,
    this.width = 10,
    this.arm = 9,
    this.depthSticks = false,
    this.depthFalls = false,
    this.inactiveFalls = true,
    this.behind = true,
    this.edges = false,
    this.numbers = false,
    this.lane = true,
    this.nextPiece = true,
    this.depthHint = true,
    this.volumeEdges = true,
    this.xray = true,
    this.grid = true,
  });

  /// How many colours fall, and the sizes: the glasses' width (the centre
  /// cube's side) and their arms' length.
  static const colourRange = (3, 6);
  static const widthRange = (5, 12);
  static const armRange = (4, 12);

  factory CubeOptions.fromJson(Object? raw) {
    const base = CubeOptions();
    final map = raw is Map ? raw : const <Object?, Object?>{};
    bool flag(String key, bool fallback) => map[key] is bool ? map[key] as bool : fallback;
    return CubeOptions(
      colours: _intIn(map['colours'], colourRange.$1, colourRange.$2, base.colours),
      width: _intIn(map['width'], widthRange.$1, widthRange.$2, base.width),
      arm: _intIn(map['arm'], armRange.$1, armRange.$2, base.arm),
      depthSticks: flag('depthSticks', base.depthSticks),
      depthFalls: flag('depthFalls', base.depthFalls),
      inactiveFalls: flag('inactiveFalls', base.inactiveFalls),
      behind: flag('behind', base.behind),
      edges: flag('edges', base.edges),
      numbers: flag('numbers', base.numbers),
      lane: flag('lane', base.lane),
      nextPiece: flag('nextPiece', base.nextPiece),
      depthHint: flag('depthHint', base.depthHint),
      volumeEdges: flag('volumeEdges', base.volumeEdges),
      xray: flag('xray', base.xray),
      grid: flag('grid', base.grid),
    );
  }

  final int colours, width, arm;
  final bool depthSticks, depthFalls, inactiveFalls;
  final bool behind, edges, numbers, lane, nextPiece, depthHint, volumeEdges, xray, grid;

  CubeOptions copyWith({
    int? colours,
    int? width,
    int? arm,
    bool? depthSticks,
    bool? depthFalls,
    bool? inactiveFalls,
    bool? behind,
    bool? edges,
    bool? numbers,
    bool? lane,
    bool? nextPiece,
    bool? depthHint,
    bool? volumeEdges,
    bool? xray,
    bool? grid,
  }) =>
      CubeOptions(
        colours: colours ?? this.colours,
        width: width ?? this.width,
        arm: arm ?? this.arm,
        depthSticks: depthSticks ?? this.depthSticks,
        depthFalls: depthFalls ?? this.depthFalls,
        inactiveFalls: inactiveFalls ?? this.inactiveFalls,
        behind: behind ?? this.behind,
        edges: edges ?? this.edges,
        numbers: numbers ?? this.numbers,
        lane: lane ?? this.lane,
        nextPiece: nextPiece ?? this.nextPiece,
        depthHint: depthHint ?? this.depthHint,
        volumeEdges: volumeEdges ?? this.volumeEdges,
        xray: xray ?? this.xray,
        grid: grid ?? this.grid,
      );

  Map<String, Object> toJson() => {
        'colours': colours,
        'width': width,
        'arm': arm,
        'depthSticks': depthSticks,
        'depthFalls': depthFalls,
        'inactiveFalls': inactiveFalls,
        'behind': behind,
        'edges': edges,
        'numbers': numbers,
        'lane': lane,
        'nextPiece': nextPiece,
        'depthHint': depthHint,
        'volumeEdges': volumeEdges,
        'xray': xray,
        'grid': grid,
      };

  @override
  bool operator ==(Object other) => other is CubeOptions && _json(other) == _json(this);

  @override
  int get hashCode => _json(this).hashCode;

  static String _json(CubeOptions o) => o.toJson().toString();
}

class Settings {
  const Settings({
    required this.bindings,
    required this.handling,
    required this.palettes,
    required this.effects,
    required this.hud,
    required this.leftPad,
    required this.rightPad,
    this.padPositions = const PadPositions(),
    this.padShape = PadShape.square,
    this.padButtons = const {},
    this.language = LanguageChoice.auto,
    this.audio = const AudioOptions(),
    this.cube = const CubeOptions(),
    this.cubeLeftPad = defaultCubeLeftPad,
    this.cubeRightPad = defaultCubeRightPad,
  });

  factory Settings.defaults() => Settings(
        bindings: defaultBindings(),
        handling: const Handling(),
        palettes: Palettes.defaults(),
        effects: const EffectOptions(),
        hud: const HudOptions(),
        leftPad: defaultLeftPad,
        rightPad: defaultRightPad,
      );

  /// Makes sense of whatever was stored; anything missing or out of range
  /// falls back to its default.
  factory Settings.fromJson(Object? raw) {
    final base = Settings.defaults();
    final map = raw is Map ? raw : const <Object?, Object?>{};
    Map<Object?, Object?> section(String key) {
      final value = map[key];
      return value is Map ? value : const {};
    }

    final handling = section('handling');
    final effects = section('effects');
    final hud = section('hud');
    final audio = section('audio');
    final pads = section('pads');
    return Settings(
      language: LanguageChoice.fromJson(map['language']),
      padPositions: PadPositions.fromJson(map['padPositions']),
      bindings: sanitizeBindings(map['bindings']),
      handling: Handling(
        dasMs: _intIn(handling['dasMs'], 0, 400, base.handling.dasMs),
        arrMs: _intIn(handling['arrMs'], 0, 150, base.handling.arrMs),
      ),
      palettes: Palettes.fromJson(map['palettes']),
      effects: EffectOptions(
        explosion: ExplosionStyle.values.firstWhere((style) => style.name == effects['explosion'], orElse: () => ExplosionStyle.varied),
        fieldBackground: effects['fieldBackground'] != false,
        screenShake: effects['screenShake'] != false,
        turnMs: _intIn(effects['turnMs'], 0, 800, base.effects.turnMs),
      ),
      hud: HudOptions(
        keyHints: hud['keyHints'] != false,
        nextPiece: hud['nextPiece'] != false,
        nextPieceOpacity: _doubleIn(hud['nextPieceOpacity'], 0.1, 1, base.hud.nextPieceOpacity),
        score: hud['score'] != false,
        stats: hud['stats'] != false,
        opacity: _doubleIn(hud['opacity'], 0.1, 1, base.hud.opacity),
      ),
      audio: AudioOptions(
        music: audio['music'] != false,
        musicVolume: _doubleIn(audio['volume'], 0, 1, base.audio.musicVolume),
        sounds: audio['sounds'] != false,
        soundsVolume: _doubleIn(audio['soundsVolume'], 0, 1, base.audio.soundsVolume),
      ),
      leftPad: _padFromJson(pads['left'], base.leftPad, ActionScope.flat),
      rightPad: _padFromJson(pads['right'], base.rightPad, ActionScope.flat),
      cube: CubeOptions.fromJson(map['cube']),
      cubeLeftPad: _padFromJson(section('cubePads')['left'], defaultCubeLeftPad, ActionScope.cube),
      cubeRightPad: _padFromJson(section('cubePads')['right'], defaultCubeRightPad, ActionScope.cube),
      padShape: PadShape.fromName(pads['shape']),
      padButtons: _buttonsFromJson(pads['buttons']),
    );
  }

  final LanguageChoice language;
  final Bindings bindings;
  final Handling handling;
  final Palettes palettes;
  final EffectOptions effects;
  final HudOptions hud;
  final PadLayout leftPad;
  final PadLayout rightPad;
  final PadPositions padPositions;

  /// The outline of every pad button.
  final PadShape padShape;

  /// Size and place of single buttons, by pad. Only buttons that differ from
  /// their default are kept here.
  final Map<PadSide, PadTweaks> padButtons;
  final AudioOptions audio;

  /// Cube's setup and look.
  final CubeOptions cube;

  /// What Cube's pads do; where they are and how they look is the flat
  /// game's.
  final PadLayout cubeLeftPad;
  final PadLayout cubeRightPad;

  /// The same settings with one button of one pad changed. A default tweak
  /// removes the entry.
  Settings withButton(PadSide side, PadSlot slot, PadTweak tweak) {
    final pad = {...?padButtons[side]};
    if (tweak.isDefault) {
      pad.remove(slot);
    } else {
      pad[slot] = tweak;
    }
    return copyWith(padButtons: {...padButtons, side: pad});
  }

  Settings copyWith({
    LanguageChoice? language,
    Bindings? bindings,
    Handling? handling,
    Palettes? palettes,
    EffectOptions? effects,
    HudOptions? hud,
    PadLayout? leftPad,
    PadLayout? rightPad,
    PadPositions? padPositions,
    PadShape? padShape,
    Map<PadSide, PadTweaks>? padButtons,
    AudioOptions? audio,
    CubeOptions? cube,
    PadLayout? cubeLeftPad,
    PadLayout? cubeRightPad,
  }) =>
      Settings(
        language: language ?? this.language,
        bindings: bindings ?? this.bindings,
        handling: handling ?? this.handling,
        palettes: palettes ?? this.palettes,
        effects: effects ?? this.effects,
        hud: hud ?? this.hud,
        leftPad: leftPad ?? this.leftPad,
        rightPad: rightPad ?? this.rightPad,
        padPositions: padPositions ?? this.padPositions,
        padShape: padShape ?? this.padShape,
        padButtons: padButtons ?? this.padButtons,
        audio: audio ?? this.audio,
        cube: cube ?? this.cube,
        cubeLeftPad: cubeLeftPad ?? this.cubeLeftPad,
        cubeRightPad: cubeRightPad ?? this.cubeRightPad,
      );

  Map<String, Object?> toJson() => {
        'language': language.name,
        'bindings': {
          for (final action in keyActions)
            action.name: [for (final key in bindings[action]!) keyToJson(key)],
        },
        'handling': {'dasMs': handling.dasMs, 'arrMs': handling.arrMs},
        'palettes': palettes.toJson(),
        'effects': {
          'explosion': effects.explosion.name,
          'fieldBackground': effects.fieldBackground,
          'screenShake': effects.screenShake,
          'turnMs': effects.turnMs,
        },
        'hud': {
          'keyHints': hud.keyHints,
          'nextPiece': hud.nextPiece,
          'nextPieceOpacity': hud.nextPieceOpacity,
          'score': hud.score,
          'stats': hud.stats,
          'opacity': hud.opacity,
        },
        'audio': {
          'music': audio.music,
          'volume': audio.musicVolume,
          'sounds': audio.sounds,
          'soundsVolume': audio.soundsVolume,
        },
        'padPositions': padPositions.toJson(),
        'cube': cube.toJson(),
        'cubePads': {
          'left': {for (final slot in PadSlot.values) slot.name: cubeLeftPad[slot]!.name},
          'right': {for (final slot in PadSlot.values) slot.name: cubeRightPad[slot]!.name},
        },
        'pads': {
          'left': {for (final slot in PadSlot.values) slot.name: leftPad[slot]!.name},
          'right': {for (final slot in PadSlot.values) slot.name: rightPad[slot]!.name},
          'shape': padShape.name,
          'buttons': {
            for (final side in PadSide.values)
              side.name: {
                for (final entry in (padButtons[side] ?? const <PadSlot, PadTweak>{}).entries)
                  if (!entry.value.isDefault) entry.key.name: entry.value.toJson(),
              },
          },
        },
      };
}

Map<PadSide, PadTweaks> _buttonsFromJson(Object? raw) {
  if (raw is! Map) return const {};
  return {
    for (final side in PadSide.values)
      if (raw[side.name] is Map)
        side: {
          for (final slot in PadSlot.values)
            if ((raw[side.name] as Map)[slot.name] != null)
              slot: PadTweak.fromJson((raw[side.name] as Map)[slot.name]),
        },
  };
}

int _intIn(Object? value, num min, num max, int fallback) =>
    value is num && value.isFinite ? value.clamp(min, max).round() : fallback;

double _doubleIn(Object? value, double min, double max, double fallback) =>
    value is num && value.isFinite ? value.clamp(min, max).toDouble() : fallback;

/// A pad's layout as stored; an action of the other game is not taken.
PadLayout _padFromJson(Object? raw, PadLayout fallback, ActionScope game) {
  if (raw is! Map) return fallback;
  return {
    for (final slot in PadSlot.values)
      slot: switch (GameAction.byName(raw[slot.name])) {
        final action? when action.inScope(game) => action,
        _ => fallback[slot]!,
      },
  };
}
