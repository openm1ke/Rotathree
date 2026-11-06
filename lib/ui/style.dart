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

/// What a block of a skin is made of, under the marks on its face.
enum BlockBody {
  /// A cut stone: bevels lit from the top left, a domed face, a gloss.
  stone,

  /// Rounder and softer than a stone.
  die,

  /// A square with four hard bevels and a flat face, as the old games drew.
  retro,

  /// Dark glass lit from inside by a tube of its colour.
  neon,

  /// None: the marks — a cut gem — are the block.
  gem,
}

/// How a block is drawn: its colour and what is on its face. The game is
/// the same in every one — blocks of a slot match — only what tells the slots
/// apart changes.
enum BlockSkin {
  /// Cut stones in the slots' colours.
  classic('Классика', BlockBody.stone),

  /// Square blocks with four hard bevels, as the old falling-block games.
  retro('Ретро', BlockBody.retro),

  /// Dark glass, each block outlined by a glowing tube of its colour.
  neon('Неон', BlockBody.neon),

  /// A cut gem for each colour: a ruby rhombus, a hexagonal topaz, a round
  /// sapphire, an emerald…
  gems('Самоцветы', BlockBody.gem),

  /// Dice of one ivory: a slot is told by its number of pips.
  dice('Кости', BlockBody.die),

  /// Dice in the slots' colours with white pips: the colour and the number.
  colourDice('Цветные кости', BlockBody.die),

  /// Stones in the slots' colours, each with its own sign on it, for eyes
  /// that tell colours apart poorly.
  symbols('Знаки', BlockBody.stone);

  const BlockSkin(this.title, this.body);

  final String title;
  final BlockBody body;

  /// Whether the slots keep their colours.
  bool get coloured => this != dice;

  /// Whether a block's own body is dark, its colour only in its light.
  bool get darkBody => body == BlockBody.neon || body == BlockBody.gem;

  static BlockSkin fromName(Object? name) =>
      values.firstWhere((skin) => skin.name == name, orElse: () => classic);
}

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

  /// The ivory of the dice that have no colour.
  static const ivory = BlockTones(Color(0xFFF2EDE3), Color(0xFFFFFFFF), Color(0xFFB9AE9C));

  static List<BlockTones> _tones = [for (final c in classicColours) BlockTones.fromBase(c)];
  static List<Color> _colours = classicColours;
  static BlockSkin _skin = BlockSkin.classic;
  static int _revision = 0;

  /// Changes whenever the block colours or their skin change, so cached
  /// pictures can check.
  static int get revision => _revision;

  /// How the blocks are drawn now.
  static BlockSkin get skin => _skin;

  /// Replaces the colours of the block slots. [colours] has one per slot.
  static void setColours(List<Color> colours) => setLook(colours, _skin);

  /// Replaces the colours of the block slots and how they are drawn. A skin
  /// without colours gives every slot the same tones.
  static void setLook(List<Color> colours, BlockSkin skin) {
    if (identical(colours, _colours) && skin == _skin) return;
    _colours = colours;
    _skin = skin;
    _tones = skin.coloured ? [for (final c in colours) BlockTones.fromBase(c)] : List.filled(colours.length, ivory);
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

  /// Upright, equally spaced figures for numeric choices.
  static TextStyle number(double size, {Color color = Palette.text}) =>
      _style(size, FontWeight.w800, color: color, height: 1).copyWith(
        fontFeatures: const [
          FontFeature.tabularFigures(),
          FontFeature.liningFigures(),
        ],
      );

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
