import 'dart:convert';

import '../../game/config/game_config.dart';
import 'pad_action.dart';

/// The part of the game configuration the player can change.
class GameOptions {
  const GameOptions({
    this.activeStepSeconds = 1,
    this.inactiveStepSeconds = 3,
    this.armLength = 9,
    this.glassCount = 4,
    this.numberOfColors = 3,
    this.gravityScope = GravityScope.wholeGlass,
    this.settleAfterBoardRotation = false,
  });

  final double activeStepSeconds;
  final double inactiveStepSeconds;
  final int armLength;

  /// Glasses in play, 2 to 4: the player's own plus one to three more.
  final int glassCount;
  final int numberOfColors;
  final GravityScope gravityScope;
  final bool settleAfterBoardRotation;

  /// The full engine configuration for these options. The animation timings
  /// are the snappy ones of the browser version.
  GameConfig toConfig({int? seed}) => GameConfig(
        activeStepSeconds: activeStepSeconds,
        inactiveStepSeconds: inactiveStepSeconds,
        armLength: armLength,
        glassCount: glassCount,
        numberOfColors: numberOfColors,
        gravityScope: gravityScope,
        settleAfterBoardRotation: settleAfterBoardRotation,
        dropBaseSeconds: 0.06,
        dropSecondsPerCell: 0.008,
        matchSeconds: 0.16,
        clearSeconds: 0.2,
        fallBaseSeconds: 0.09,
        fallSecondsPerRootCell: 0.1,
        fallBounceSeconds: 0.12,
        seed: seed,
      );

  GameOptions copyWith({
    double? activeStepSeconds,
    double? inactiveStepSeconds,
    int? armLength,
    int? glassCount,
    int? numberOfColors,
    GravityScope? gravityScope,
    bool? settleAfterBoardRotation,
  }) =>
      GameOptions(
        activeStepSeconds: activeStepSeconds ?? this.activeStepSeconds,
        inactiveStepSeconds: inactiveStepSeconds ?? this.inactiveStepSeconds,
        armLength: armLength ?? this.armLength,
        glassCount: glassCount ?? this.glassCount,
        numberOfColors: numberOfColors ?? this.numberOfColors,
        gravityScope: gravityScope ?? this.gravityScope,
        settleAfterBoardRotation:
            settleAfterBoardRotation ?? this.settleAfterBoardRotation,
      );

  Map<String, Object?> toJson() => {
        'activeStepSeconds': activeStepSeconds,
        'inactiveStepSeconds': inactiveStepSeconds,
        'armLength': armLength,
        'glassCount': glassCount,
        'numberOfColors': numberOfColors,
        'gravityScope': gravityScope.name,
        'settleAfterBoardRotation': settleAfterBoardRotation,
      };

  factory GameOptions.fromJson(Object? raw) {
    const base = GameOptions();
    if (raw is! Map) return base;
    return GameOptions(
      activeStepSeconds:
          _number(raw['activeStepSeconds'], 0.1, 5, base.activeStepSeconds),
      inactiveStepSeconds:
          _number(raw['inactiveStepSeconds'], 0.2, 10, base.inactiveStepSeconds),
      armLength: _number(raw['armLength'], 3, 12, base.armLength).round(),
      glassCount: _number(raw['glassCount'], 2, 4, base.glassCount).round(),
      numberOfColors:
          _number(raw['numberOfColors'], 3, 6, base.numberOfColors).round(),
      gravityScope: raw['gravityScope'] == GravityScope.aboveCleared.name
          ? GravityScope.aboveCleared
          : GravityScope.wholeGlass,
      settleAfterBoardRotation: raw['settleAfterBoardRotation'] == true,
    );
  }

  /// Identifies the rules: a game cannot go on when this changes.
  String get key => jsonEncode(toJson());
}

/// The two pads at the bottom of the screen.
class PadOptions {
  const PadOptions({
    this.left = defaultLeftPad,
    this.right = defaultRightPad,
    this.scale = 1,
    this.opacity = 0.9,
    this.dasMs = 150,
    this.arrMs = 35,
    this.haptics = true,
    this.fieldGestures = false,
  });

  final PadLayout left;
  final PadLayout right;

  /// Size of the pads, 0.8 … 1.25 of the standard one.
  final double scale;
  final double opacity;

  /// Delayed auto shift: milliseconds a direction is held before it repeats.
  final int dasMs;

  /// Auto repeat rate: milliseconds between repeats; 0 slides to the wall.
  final int arrMs;

  /// A short buzz on every press.
  final bool haptics;

  /// Dragging the piece and swiping on the field itself, as well as the pads.
  final bool fieldGestures;

  PadOptions copyWith({
    PadLayout? left,
    PadLayout? right,
    double? scale,
    double? opacity,
    int? dasMs,
    int? arrMs,
    bool? haptics,
    bool? fieldGestures,
  }) =>
      PadOptions(
        left: left ?? this.left,
        right: right ?? this.right,
        scale: scale ?? this.scale,
        opacity: opacity ?? this.opacity,
        dasMs: dasMs ?? this.dasMs,
        arrMs: arrMs ?? this.arrMs,
        haptics: haptics ?? this.haptics,
        fieldGestures: fieldGestures ?? this.fieldGestures,
      );

  Map<String, Object?> toJson() => {
        'left': _layoutToJson(left),
        'right': _layoutToJson(right),
        'scale': scale,
        'opacity': opacity,
        'dasMs': dasMs,
        'arrMs': arrMs,
        'haptics': haptics,
        'fieldGestures': fieldGestures,
      };

  factory PadOptions.fromJson(Object? raw) {
    const base = PadOptions();
    if (raw is! Map) return base;
    return PadOptions(
      left: _layoutFromJson(raw['left'], defaultLeftPad),
      right: _layoutFromJson(raw['right'], defaultRightPad),
      scale: _number(raw['scale'], 0.8, 1.25, base.scale),
      opacity: _number(raw['opacity'], 0.3, 1, base.opacity),
      dasMs: _number(raw['dasMs'], 0, 400, base.dasMs).round(),
      arrMs: _number(raw['arrMs'], 0, 150, base.arrMs).round(),
      haptics: raw['haptics'] != false,
      fieldGestures: raw['fieldGestures'] == true,
    );
  }

  static Map<String, String> _layoutToJson(PadLayout layout) =>
      {for (final slot in PadSlot.values) slot.name: layout[slot]!.name};

  static PadLayout _layoutFromJson(Object? raw, PadLayout fallback) => {
        for (final slot in PadSlot.values)
          slot: raw is Map
              ? PadAction.byName(raw[slot.name], fallback[slot]!)
              : fallback[slot]!,
      };
}

/// What is written in the corners of the field, and how strongly.
class HudOptions {
  const HudOptions({
    this.padLabels = true,
    this.score = true,
    this.stats = true,
    this.opacity = 1,
  });

  /// The name of its action under every pad button.
  final bool padLabels;

  /// The score, the level and the combo callouts.
  final bool score;

  /// Time, pieces, matches, best combo.
  final bool stats;

  /// Opacity of the writing on the field, 0.1 … 1.
  final double opacity;

  HudOptions copyWith({
    bool? padLabels,
    bool? score,
    bool? stats,
    double? opacity,
  }) =>
      HudOptions(
        padLabels: padLabels ?? this.padLabels,
        score: score ?? this.score,
        stats: stats ?? this.stats,
        opacity: opacity ?? this.opacity,
      );

  Map<String, Object?> toJson() => {
        'padLabels': padLabels,
        'score': score,
        'stats': stats,
        'opacity': opacity,
      };

  factory HudOptions.fromJson(Object? raw) {
    const base = HudOptions();
    if (raw is! Map) return base;
    return HudOptions(
      padLabels: raw['padLabels'] != false,
      score: raw['score'] != false,
      stats: raw['stats'] != false,
      opacity: _number(raw['opacity'], 0.1, 1, base.opacity),
    );
  }
}

/// Everything the player can set up. Immutable; saved as one JSON document.
class Settings {
  const Settings({
    this.pads = const PadOptions(),
    this.game = const GameOptions(),
    this.hud = const HudOptions(),
    this.turnMs = defaultTurnMs,
    this.screenShake = true,
  });

  static const defaultTurnMs = 260;

  final PadOptions pads;
  final GameOptions game;
  final HudOptions hud;

  /// Milliseconds the cross takes to turn a quarter; 0 turns it at once.
  final int turnMs;

  /// Board kicks and shakes on drops and pops.
  final bool screenShake;

  Settings copyWith({
    PadOptions? pads,
    GameOptions? game,
    HudOptions? hud,
    int? turnMs,
    bool? screenShake,
  }) =>
      Settings(
        pads: pads ?? this.pads,
        game: game ?? this.game,
        hud: hud ?? this.hud,
        turnMs: turnMs ?? this.turnMs,
        screenShake: screenShake ?? this.screenShake,
      );

  Map<String, Object?> toJson() => {
        'pads': pads.toJson(),
        'game': game.toJson(),
        'hud': hud.toJson(),
        'turnMs': turnMs,
        'screenShake': screenShake,
      };

  /// Makes sense of whatever was stored; anything missing or out of range
  /// falls back to its default.
  factory Settings.fromJson(Object? raw) {
    if (raw is! Map) return const Settings();
    return Settings(
      pads: PadOptions.fromJson(raw['pads']),
      game: GameOptions.fromJson(raw['game']),
      hud: HudOptions.fromJson(raw['hud']),
      turnMs: _number(raw['turnMs'], 0, 800, defaultTurnMs).round(),
      screenShake: raw['screenShake'] != false,
    );
  }

  String encode() => jsonEncode(toJson());

  static Settings decode(String? text) {
    if (text == null || text.isEmpty) return const Settings();
    try {
      return Settings.fromJson(jsonDecode(text));
    } on FormatException {
      return const Settings();
    }
  }
}

double _number(Object? value, num min, num max, num fallback) =>
    value is num && value.isFinite
        ? value.clamp(min, max).toDouble()
        : fallback.toDouble();
