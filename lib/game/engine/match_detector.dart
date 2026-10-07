import '../model/board.dart';
import '../model/color.dart';
import '../model/position.dart';

/// One straight line of same-coloured cells.
class MatchRun {
  const MatchRun({
    required this.color,
    required this.cells,
    required this.isHorizontal,
  });

  final BlockColor color;
  final List<CellPosition> cells;
  final bool isHorizontal;

  int get length => cells.length;
}

class MatchResult {
  const MatchResult(this.runs, this.cells);

  static const none = MatchResult([], {});

  final List<MatchRun> runs;

  /// Union of all matched cells; a cell shared by two lines appears once.
  final Set<CellPosition> cells;

  bool get isEmpty => runs.isEmpty;
  bool get isNotEmpty => runs.isNotEmpty;
}

/// Finds horizontal and vertical lines of 3+ cells of one colour anywhere on
/// the cross — in the central square, in an arm, or across the border between
/// them. Diagonals do not count. Works in world coordinates: a line is a line
/// whichever way the cross is turned.
class MatchDetector {
  const MatchDetector({this.minLength = 3});

  final int minLength;

  MatchResult find(Board board) {
    final runs = <MatchRun>[];
    final n = board.size;
    for (var i = 0; i < n; i++) {
      _scanLine(board, runs, isHorizontal: true, index: i);
      _scanLine(board, runs, isHorizontal: false, index: i);
    }
    if (runs.isEmpty) return MatchResult.none;
    return MatchResult(runs, {for (final run in runs) ...run.cells});
  }

  void _scanLine(
    Board board,
    List<MatchRun> runs, {
    required bool isHorizontal,
    required int index,
  }) {
    final n = board.size;
    CellPosition cell(int k) =>
        isHorizontal ? CellPosition(index, k) : CellPosition(k, index);

    var start = 0;
    while (start < n) {
      // Cells outside the cross are always empty, so they end a line too.
      final color = board.colorAt(cell(start));
      var end = start + 1;
      if (color != null) {
        while (end < n && board.colorAt(cell(end)) == color) {
          end++;
        }
        if (end - start >= minLength) {
          runs.add(MatchRun(
            color: color,
            cells: [for (var k = start; k < end; k++) cell(k)],
            isHorizontal: isHorizontal,
          ));
        }
      }
      start = end;
    }
  }
}
