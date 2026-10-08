import 'dart:math';

import '../config/game_config.dart';
import '../model/color.dart';
import '../model/piece.dart';

/// Rolls the colours of new sticks. Deterministic for a given seed.
class PieceGenerator {
  PieceGenerator(this.config, [Random? random]) : seed = config.seed ?? Random().nextInt(1 << 32) {
    _random = random ?? Random(seed);
  }

  final GameConfig config;
  int seed;
  late Random _random;
  int generated = 0;

  /// Rebuilds this platform's random stream without changing its algorithm.
  void restore(int savedSeed, int count) {
    seed = savedSeed;
    _random = Random(seed);
    generated = 0;
    for (var i = 0; i < count; i++) {
      next();
    }
  }

  List<BlockColor> get palette => BlockColor.values.sublist(0, config.numberOfColors);

  Piece next() {
    generated++;
    final colors = palette;
    final rolled = [for (var i = 0; i < config.pieceLength; i++) colors[_random.nextInt(colors.length)]];
    final isMono = rolled.every((color) => color == rolled.first);
    if (isMono && _random.nextDouble() >= config.monoPieceKeepChance) {
      // Single-colour sticks clear themselves on landing, so they are made
      // rarer than a fair roll would give: repaint one square.
      final others = colors.where((color) => color != rolled.first).toList();
      rolled[_random.nextInt(rolled.length)] = others[_random.nextInt(others.length)];
    }
    return Piece(rolled);
  }
}
