import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/engine/placement_engine.dart';
import 'package:rotathree/game/engine/rotation_transform.dart';
import 'package:rotathree/game/model/cell.dart';
import 'package:rotathree/game/model/position.dart';
import 'package:rotathree/game/model/side.dart';

import 'helpers.dart';

void main() {
  const engine = PlacementEngine();
  const floor = glassDepth - 1;

  group('falling down the top glass', () {
    test('goes through the arm and the centre to the empty floor', () {
      final placement =
          engine.computeDrop(emptyBoard(), Side.top, horizontal([r, b, y]), 3)!;
      expect(placement.row, floor);
      expect(placement.cells, [
        PlacedCell(at(9, 3), r),
        PlacedCell(at(9, 4), b),
        PlacedCell(at(9, 5), y),
      ]);
    });

    test('horizontal stick rests on the highest block under it', () {
      final board = boardOf([
        '. . . . B',
        '. . . R B',
      ]);
      final placement =
          engine.computeDrop(board, Side.top, horizontal([r, b, y]), 2)!;
      // Lane 4 is two blocks high, so the stick stops two rows above the floor.
      expect(placement.cells.map((c) => c.position), [at(7, 2), at(7, 3), at(7, 4)]);
    });

    test('vertical stick stands on the floor, first colour on top', () {
      final placement =
          engine.computeDrop(emptyBoard(), Side.top, vertical([r, b, y]), 6)!;
      expect(placement.row, floor - 2);
      expect(placement.cells, [
        PlacedCell(at(7, 6), r),
        PlacedCell(at(8, 6), b),
        PlacedCell(at(9, 6), y),
      ]);
    });

    test('vertical stick stands on existing blocks', () {
      final board = boardOf(['B', 'R']);
      final placement =
          engine.computeDrop(board, Side.top, vertical([r, b, y]), 0)!;
      expect(placement.cells.map((c) => c.position), [at(5, 0), at(6, 0), at(7, 0)]);
    });

    test('stops directly above a floating block instead of passing it', () {
      final board = emptyBoard()..set(arm + 4, arm + 5, b);
      final placement =
          engine.computeDrop(board, Side.top, horizontal([r, b, y]), 4)!;
      expect(placement.cells.first.position, at(3, 4));
    });

    test('at the left and right walls of the glass', () {
      final board = emptyBoard();
      final left = engine.computeDrop(board, Side.top, horizontal([r, b, y]), 0)!;
      expect(left.cells.map((c) => c.position), [at(9, 0), at(9, 1), at(9, 2)]);
      final right = engine.computeDrop(board, Side.top, horizontal([r, b, y]), 7)!;
      expect(right.cells.map((c) => c.position), [at(9, 7), at(9, 8), at(9, 9)]);
      final upright = engine.computeDrop(board, Side.top, vertical([r, b, y]), 9)!;
      expect(upright.cells.map((c) => c.position), [at(7, 9), at(8, 9), at(9, 9)]);
    });

    test('a lane outside the glass is not a placement', () {
      final board = emptyBoard();
      expect(engine.computeDrop(board, Side.top, horizontal([r, b, y]), -1), isNull);
      expect(engine.computeDrop(board, Side.top, horizontal([r, b, y]), 8), isNull);
      expect(engine.computeDrop(board, Side.top, vertical([r, b, y]), 10), isNull);
    });

    test('a stack that fills the centre is continued inside the arm', () {
      final board = emptyBoard();
      final glass = GlassView(board, Side.top);
      for (var row = arm; row < glassDepth; row++) {
        glass.set(row, 4, row.isEven ? r : b);
      }
      final placement =
          engine.computeDrop(board, Side.top, horizontal([y, y, b]), 3)!;
      expect(placement.row, arm - 1);
      // World row 5 is the last row of the top arm, just above the centre.
      expect(placement.cells.map((c) => c.position), const [
        CellPosition(5, 9),
        CellPosition(5, 10),
        CellPosition(5, 11),
      ]);
    });

    test('can start part of the way down', () {
      final board = emptyBoard()..set(arm + 2, arm + 4, b);
      // From the far end the stick stops on the block; from below it, it
      // carries on to the floor.
      expect(engine.landingRow(board, Side.top, horizontal([r, b, y]), 3), arm + 1);
      expect(
        engine.landingRow(board, Side.top, horizontal([r, b, y]), 3, fromRow: arm + 3),
        floor,
      );
      expect(
        engine.landingRow(board, Side.top, horizontal([r, b, y]), 3, fromRow: arm + 2),
        isNull, // it would start inside the block
      );
    });

    test('an empty glass offers 8 horizontal and 10 vertical placements, '
        'each with the colours either way round', () {
      expect(
        engine.allPlacements(emptyBoard(), Side.top, horizontal([r, b, y])),
        hasLength(36),
      );
    });

    test('never changes the board', () {
      final board = boardOf(['R B Y']);
      final before = board.copy();
      engine.computeDrop(board, Side.top, vertical([r, b, y]), 1);
      expect(board.sameAs(before), isTrue);
    });
  });

  group('falling down the other glasses', () {
    // A piece enters through its own side and moves straight away from it.
    test('RIGHT: flies to the left wall of the centre', () {
      final placement =
          engine.computeDrop(emptyBoard(), Side.right, horizontal([r, b, y]), 0)!;
      expect(placement.cells, [
        PlacedCell(at(0, 0), r),
        PlacedCell(at(1, 0), b),
        PlacedCell(at(2, 0), y),
      ]);
    });

    test('BOTTOM: flies to the top wall of the centre', () {
      final placement =
          engine.computeDrop(emptyBoard(), Side.bottom, horizontal([r, b, y]), 0)!;
      expect(placement.cells, [
        PlacedCell(at(0, 9), r),
        PlacedCell(at(0, 8), b),
        PlacedCell(at(0, 7), y),
      ]);
    });

    test('LEFT: flies to the right wall of the centre', () {
      final placement =
          engine.computeDrop(emptyBoard(), Side.left, horizontal([r, b, y]), 0)!;
      expect(placement.cells, [
        PlacedCell(at(9, 9), r),
        PlacedCell(at(8, 9), b),
        PlacedCell(at(7, 9), y),
      ]);
    });

    test('RIGHT: a vertical stick leads with its last colour', () {
      final placement =
          engine.computeDrop(emptyBoard(), Side.right, vertical([r, b, y]), 4)!;
      expect(placement.cells, [
        PlacedCell(at(4, 2), r),
        PlacedCell(at(4, 1), b),
        PlacedCell(at(4, 0), y),
      ]);
    });

    test('a pile on the floor is met from below inside the bottom arm', () {
      // Blocks on the bottom row of the centre are the first thing a piece
      // coming up the bottom glass runs into: it stops under them, in its
      // own arm, instead of being shut out.
      final board = boardOf(['R B Y']);
      final placement =
          engine.computeDrop(board, Side.bottom, horizontal([y, y, b]), 7)!;
      expect(placement.row, arm - 1);
      expect(placement.cells.map((c) => c.position), const [
        CellPosition(16, 8),
        CellPosition(16, 7),
        CellPosition(16, 6),
      ]);
      for (final cell in placement.cells) {
        expect(board.isCenter(cell.position.row, cell.position.col), isFalse);
      }
      // Beside the pile the way to the far wall is open.
      expect(
        engine.landingRow(board, Side.bottom, horizontal([y, y, b]), 3),
        floor,
      );
    });
  });

  group('headroom', () {
    test('an empty glass has all sixteen rows free', () {
      expect(engine.headroom(emptyBoard(), Side.top, 3, 3), glassDepth);
    });

    test('is limited by the tallest of the lanes asked about', () {
      final board = emptyBoard();
      final glass = GlassView(board, Side.top);
      glass.set(9, 3, r);
      glass.set(4, 5, b);
      expect(engine.headroom(board, Side.top, 3, 3), 4);
      expect(engine.headroom(board, Side.top, 3, 2), 9);
      expect(engine.headroom(board, Side.top, 6, 3), glassDepth);
    });

    test('is zero when a block sits at the far end', () {
      final board = emptyBoard()..set(0, arm + 4, r);
      expect(engine.headroom(board, Side.top, 3, 3), 0);
      expect(engine.computeDrop(board, Side.top, horizontal([r, b, y]), 3), isNull);
    });
  });
}
