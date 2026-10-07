import 'color.dart';
import 'position.dart';

/// The four ways a stick can lie, in the order a clockwise quarter turn
/// visits them. Named by where its *first* colour ends up.
enum PieceOrientation {
  /// Lying across the glass, first colour on the left.
  horizontal,

  /// Standing along the direction of travel, first colour on top.
  vertical,

  /// Lying across the glass, first colour on the right.
  horizontalFlipped,

  /// Standing along the direction of travel, first colour at the bottom.
  verticalFlipped;

  bool get isHorizontal => this == horizontal || this == horizontalFlipped;
  bool get isVertical => !isHorizontal;

  /// True for the two orientations in which the colours run backwards.
  bool get isFlipped => this == horizontalFlipped || this == verticalFlipped;

  /// The orientation after a clockwise quarter turn.
  PieceOrientation get clockwise => values[(index + 1) % values.length];

  /// The orientation after an anticlockwise quarter turn.
  PieceOrientation get anticlockwise =>
      values[(index + values.length - 1) % values.length];
}

/// A straight stick of coloured squares.
///
/// The colour order is fixed at creation and the squares can never be
/// rearranged. The stick can only be turned as a whole, a quarter turn at a
/// time, so its first colour can end up on the left, on top, on the right or
/// at the bottom.
class Piece {
  Piece(
    List<BlockColor> colors, {
    this.orientation = PieceOrientation.horizontal,
  }) : colors = List.unmodifiable(colors);

  final List<BlockColor> colors;
  final PieceOrientation orientation;

  int get length => colors.length;
  bool get isHorizontal => orientation.isHorizontal;
  bool get isVertical => orientation.isVertical;

  /// Cells taken across the glass.
  int get width => isHorizontal ? length : 1;

  /// Cells taken along the direction of travel.
  int get depth => isHorizontal ? 1 : length;

  /// The stick after a clockwise quarter turn.
  Piece rotated() => Piece(colors, orientation: orientation.clockwise);

  /// The stick after an anticlockwise quarter turn.
  Piece rotatedBack() => Piece(colors, orientation: orientation.anticlockwise);

  /// Offset of each square from the piece's top-left cell, in colour order.
  List<CellPosition> get offsets => [
        for (var i = 0; i < length; i++)
          _offset(orientation.isFlipped ? length - 1 - i : i),
      ];

  CellPosition _offset(int along) =>
      isHorizontal ? CellPosition(0, along) : CellPosition(along, 0);

  @override
  bool operator ==(Object other) {
    if (other is! Piece || other.orientation != orientation) return false;
    if (other.length != length) return false;
    for (var i = 0; i < length; i++) {
      if (other.colors[i] != colors[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(orientation, Object.hashAll(colors));

  @override
  String toString() =>
      '${colors.map((c) => c.symbol).join()}:${orientation.name}';
}
