/// Block colours. The first `GameConfig.numberOfColors` of them are in play.
enum BlockColor {
  red('R'),
  blue('B'),
  yellow('Y'),
  green('G'),
  purple('P'),
  white('W');

  const BlockColor(this.symbol);

  /// One-letter code used by the text form of a board.
  final String symbol;

  static BlockColor? fromSymbol(String symbol) {
    for (final color in BlockColor.values) {
      if (color.symbol == symbol) return color;
    }
    return null;
  }
}
