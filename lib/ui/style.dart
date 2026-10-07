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

  /// Zen: the level, its bar, the level-up announcement.
  static const zen = Color(0xFF7DF0C5);
  static const zenDeep = Color(0xFF12B886);
  static const zenBlue = Color(0xFF2A6DF4);

  /// The gradient of the main button and of everything "go".
  static const go = [Color(0xFFFF2E7E), Color(0xFFA53BFF)];
}

/// Tones of one block colour.
class BlockTones {
  const BlockTones(this.base, this.light, this.dark);

  final Color base;
  final Color light;
  final Color dark;

  static const _tones = {
    BlockColor.red: BlockTones(Color(0xFFFF3D5E), Color(0xFFFF96A8), Color(0xFFA8132F)),
    BlockColor.blue: BlockTones(Color(0xFF3B82FF), Color(0xFF93BBFF), Color(0xFF1646B8)),
    BlockColor.yellow: BlockTones(Color(0xFFFFC531), Color(0xFFFFE696), Color(0xFFB97C00)),
    BlockColor.green: BlockTones(Color(0xFF2FD985), Color(0xFF93F2C2), Color(0xFF0D8A4D)),
    BlockColor.purple: BlockTones(Color(0xFFA65CFF), Color(0xFFD6B3FF), Color(0xFF5A1FBD)),
    BlockColor.white: BlockTones(Color(0xFFE4EAFA), Color(0xFFFFFFFF), Color(0xFF8A94B4)),
  };

  static BlockTones of(BlockColor color) => _tones[color]!;
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
