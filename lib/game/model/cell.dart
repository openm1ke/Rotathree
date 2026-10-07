import 'color.dart';
import 'position.dart';

/// A coloured block at a board position.
class PlacedCell {
  const PlacedCell(this.position, this.color);

  final CellPosition position;
  final BlockColor color;

  @override
  bool operator ==(Object other) =>
      other is PlacedCell && other.position == position && other.color == color;

  @override
  int get hashCode => Object.hash(position, color);

  @override
  String toString() => '${color.symbol}@$position';
}
