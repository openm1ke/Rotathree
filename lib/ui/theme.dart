import 'package:flutter/painting.dart';

import '../game/model/color.dart';

/// Dark sci-fi palette of the prototype.
abstract final class NeonPalette {
  static const background = Color(0xFF03050A);
  static const backgroundGlow = Color(0xFF0B1626);

  static const armGap = Color(0xFF0C121D);
  static const armCell = Color(0xFF06090F);
  static const boardGap = Color(0xFF16233A);
  static const boardCell = Color(0xFF080D17);

  static const outline = Color(0xFF38D9FF);
  static const outlineDim = Color(0xFF14475F);

  static const text = Color(0xFFDDF6FF);
  static const textDim = Color(0xFF6C8AA3);
  static const warning = Color(0xFFFFAE42);
  static const danger = Color(0xFFFF3D5E);

  static BlockTones block(BlockColor color) => switch (color) {
        BlockColor.red => const BlockTones(
            Color(0xFFFF8A9A), Color(0xFFFF2E4D), Color(0xFF9E0B27)),
        BlockColor.blue => const BlockTones(
            Color(0xFF8FB2FF), Color(0xFF2F6BFF), Color(0xFF0F2E9E)),
        BlockColor.yellow => const BlockTones(
            Color(0xFFFFEE9C), Color(0xFFFFCB2B), Color(0xFFA86F00)),
        BlockColor.green => const BlockTones(
            Color(0xFFA6F7CD), Color(0xFF2EDD88), Color(0xFF07804A)),
      };
}

/// Highlight, body and shadow tones of one glossy block colour.
class BlockTones {
  const BlockTones(this.light, this.base, this.dark);

  final Color light;
  final Color base;
  final Color dark;
}
