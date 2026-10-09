import 'package:flutter/widgets.dart';

import '../game/model/color.dart';

/// Colours of the interface — the same tokens as the browser version.
abstract final class Palette {
  static const bg = Color(0xFF07070C);
  static const bgRaised = Color(0xFF11111B);
  static const panel = Color(0x0BFFFFFF);
  static const panelStrong = Color(0xF012121E);
  static const line = Color(0x1CFFFFFF);
  static const lineStrong = Color(0x42FFFFFF);

  static const text = Color(0xFFECEFF9);
  static const textDim = Color(0xFF8B90A8);
  static const textFaint = Color(0xFF5D6178);

  static const accent = Color(0xFF78CDFF);
  static const accentStrong = Color(0xFF36A9FF);
  static const pink = Color(0xFFFF3D8B);
  static const violet = Color(0xFF8F5BFF);
  static const orange = Color(0xFFFF9A2E);
  static const danger = Color(0xFFFF4664);
  static const warning = Color(0xFFFFB03B);

  // Fixed brand colors from the approved wordmark, independent of player palettes.
  static const brandRed = Color(0xFFFF145E);
  static const brandBlue = Color(0xFF1689FF);
  static const brandYellow = Color(0xFFFFC400);
  static const brandGreen = Color(0xFF00D982);
  static const brandViolet = Color(0xFFAB50FA);

  /// The gradient of the main button and of everything "go".
  static const go = [Color(0xFFFF2E7E), Color(0xFFA53BFF)];
}

/// The colours of the classic set, one per colour slot of [BlockColor].
const classicColours = <Color>[
  Color(0xFFFF3D5E),
  Color(0xFF3B82FF),
  Color(0xFFFFC531),
  Color(0xFF2FD985),
  Color(0xFFA65CFF),
  Color(0xFFE4EAFA),
  Color(0xFFFF8A2E),
  Color(0xFF2EE6F0),
  Color(0xFFFF5FB0),
];

/// Tones of one block colour, for the bevel of a block.
class BlockTones {
  const BlockTones(this.base, this.light, this.dark);

  /// Lighter and darker tones of [base] (theme.ts `toneOf`).
  factory BlockTones.fromBase(Color base) {
    final channels = [base.r * 255, base.g * 255, base.b * 255];
    Color shade(double Function(double channel) change) => Color.fromARGB(
          255,
          change(channels[0]).round().clamp(0, 255),
          change(channels[1]).round().clamp(0, 255),
          change(channels[2]).round().clamp(0, 255),
        );
    return BlockTones(
      base,
      shade((c) => c + (255 - c) * 0.45),
      shade((c) => c * (1 - 0.35)),
    );
  }

  final Color base;
  final Color light;
  final Color dark;

  static List<BlockTones> _tones = [for (final c in classicColours) BlockTones.fromBase(c)];
  static int _revision = 0;

  /// Changes whenever the block colours change, so cached pictures can check.
  static int get revision => _revision;

  /// Replaces the colours of the block slots. [colours] has one per slot.
  static void setColours(List<Color> colours) {
    _tones = [for (final c in colours) BlockTones.fromBase(c)];
    _revision++;
  }

  static BlockTones of(BlockColor color) => _tones[color.index];
}

/// Exo 2, as in the browser version. The Latin and the Cyrillic halves of the
/// typeface are two font files, so the second is named as the fallback.
abstract final class Type {
  static const family = 'Exo2';
  static const fallback = ['Exo2Cyrillic'];

  static TextStyle _style(
    double size,
    FontWeight weight, {
    bool italic = false,
    Color color = Palette.text,
    double? spacing,
    double? height,
    List<Shadow>? shadows,
  }) =>
      TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: size,
        fontWeight: weight,
        fontStyle: italic ? FontStyle.italic : FontStyle.normal,
        color: color,
        letterSpacing: spacing,
        height: height,
        shadows: shadows,
        decoration: TextDecoration.none,
      );

  /// Heavy slanted capitals: titles, numbers, buttons.
  static TextStyle display(
    double size, {
    Color color = Palette.text,
    double? spacing,
    double height = 1,
    List<Shadow>? shadows,
  }) =>
      _style(size, FontWeight.w900,
          italic: true, color: color, spacing: spacing, height: height, shadows: shadows);

  /// Small tracked capitals above a number.
  static TextStyle label(double size, {Color color = Palette.textDim}) =>
      _style(size, FontWeight.w800, color: color, spacing: size * 0.16, height: 1.1);

  /// Plain reading text.
  static TextStyle body(
    double size, {
    Color color = Palette.text,
    FontWeight weight = FontWeight.w600,
    double height = 1.35,
  }) =>
      _style(size, weight, color: color, height: height);

  /// A glow behind bright text.
  static List<Shadow> glow(Color color, double blur) =>
      [Shadow(color: color, blurRadius: blur)];
}

/// The curves of the browser version.
abstract final class Motion {
  /// Quick out, long soft landing.
  static const snap = Cubic(0.2, 0.9, 0.25, 1);

  /// Overshoots a little and settles.
  static const back = Cubic(0.2, 1.6, 0.35, 1);
}
