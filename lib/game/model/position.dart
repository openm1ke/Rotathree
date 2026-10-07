/// A cell of the central board: row 0 is the top row, column 0 the left one.
class CellPosition {
  const CellPosition(this.row, this.col);

  final int row;
  final int col;

  @override
  bool operator ==(Object other) =>
      other is CellPosition && other.row == row && other.col == col;

  @override
  int get hashCode => row * 131 + col;

  @override
  String toString() => '($row,$col)';
}
