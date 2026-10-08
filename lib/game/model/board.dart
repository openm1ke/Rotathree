import 'cell.dart';
import 'color.dart';
import 'position.dart';

/// The whole cross of settled blocks: the central square and the four arms
/// around it, stored in a square grid in the fixed world frame. The four
/// corner squares of that grid are outside the cross and always empty.
/// Turning the view never touches this data.
class Board {
  Board({this.center = 10, this.arm = 6})
      : size = center + 2 * arm,
        _cells = List<BlockColor?>.filled(
          (center + 2 * arm) * (center + 2 * arm),
          null,
        );

  /// Side of the central square.
  final int center;

  /// Length of each arm.
  final int arm;

  /// Side of the enclosing grid.
  final int size;

  /// Grows with every write, so that anything worked out from the board (a
  /// landing row, a drawn layer) can tell when it is out of date.
  int version = 0;

  final List<BlockColor?> _cells;

  bool _inCentralBand(int index) => index >= arm && index < arm + center;

  /// Whether the cell belongs to the cross.
  bool isInside(int row, int col) {
    if (row < 0 || row >= size || col < 0 || col >= size) return false;
    return _inCentralBand(row) || _inCentralBand(col);
  }

  /// Whether the cell belongs to the central square.
  bool isCenter(int row, int col) => _inCentralBand(row) && _inCentralBand(col);

  BlockColor? at(int row, int col) => _cells[row * size + col];

  BlockColor? colorAt(CellPosition position) => at(position.row, position.col);

  void set(int row, int col, BlockColor? color) {
    assert(isInside(row, col), 'cell ($row,$col) is outside the cross');
    _cells[row * size + col] = color;
    version++;
  }

  bool isFree(int row, int col) => isInside(row, col) && at(row, col) == null;

  int get blockCount => _cells.where((cell) => cell != null).length;

  bool get isEmpty => _cells.every((cell) => cell == null);

  Iterable<PlacedCell> get blocks sync* {
    for (var row = 0; row < size; row++) {
      for (var col = 0; col < size; col++) {
        final color = at(row, col);
        if (color != null) yield PlacedCell(CellPosition(row, col), color);
      }
    }
  }

  Board copy() {
    final other = Board(center: center, arm: arm);
    other._cells.setAll(0, _cells);
    return other;
  }

  void clear() {
    _cells.fillRange(0, _cells.length, null);
    version++;
  }

  /// Overwrites this board with the contents of [other] (same shape).
  void copyFrom(Board other) {
    _cells.setAll(0, other._cells);
    version++;
  }

  bool sameAs(Board other) {
    if (other.size != size || other.arm != arm) return false;
    for (var i = 0; i < _cells.length; i++) {
      if (_cells[i] != other._cells[i]) return false;
    }
    return true;
  }

  /// Fills the central square from text rows such as `'R R . B'`. Rows are
  /// aligned to its bottom and columns to its left, so a test only has to
  /// spell out the occupied corner. `.` is an empty cell; spaces are ignored.
  void paintCenter(List<String> rows) {
    final firstRow = arm + center - rows.length;
    for (var i = 0; i < rows.length; i++) {
      final symbols = rows[i].replaceAll(' ', '');
      for (var col = 0; col < symbols.length; col++) {
        set(firstRow + i, arm + col, BlockColor.fromSymbol(symbols[col]));
      }
    }
  }

  /// The central square as text, top row first.
  List<String> centerRows() => [
        for (var row = arm; row < arm + center; row++)
          [
            for (var col = arm; col < arm + center; col++)
              at(row, col)?.symbol ?? '.',
          ].join(' '),
      ];

  /// The whole grid as text; cells outside the cross are blank.
  @override
  String toString() => [
        for (var row = 0; row < size; row++)
          [
            for (var col = 0; col < size; col++)
              isInside(row, col) ? at(row, col)?.symbol ?? '.' : ' ',
          ].join(' '),
      ].join('\n');
}
