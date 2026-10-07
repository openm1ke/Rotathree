import 'dart:math';

import '../config/game_config.dart';
import '../model/color.dart';
import '../model/piece.dart';

/// Rolls the colours of new sticks. Deterministic for a given seed.
class PieceGenerator {
  PieceGenerator(this.config, [Random? random])
      : _random = random ?? Random(config.seed);

  final GameConfig config;
  final Random _random;

  List<BlockColor> get palette =>
      BlockColor.values.sublist(0, config.numberOfColors);

  Piece next() {
    final colors = palette;
    final rolled = [
      for (var i = 0; i < config.pieceLength; i++)
        colors[_random.nextInt(colors.length)],
    ];
    final isMono = rolled.every((color) => color == rolled.first);
    if (isMono && _random.nextDouble() >= config.monoPieceKeepChance) {
      // Single-colour sticks clear themselves on landing, so they are made
      // rarer than a fair roll would give: repaint one square.
      final others = colors.where((color) => color != rolled.first).toList();
      rolled[_random.nextInt(rolled.length)] =
          others[_random.nextInt(others.length)];
    }
    return Piece(rolled);
  }
}
