import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/engine/rotation_transform.dart';
import 'package:rotathree/game/model/position.dart';
import 'package:rotathree/game/model/side.dart';

import 'helpers.dart';

void main() {
  test('the default field: a 10×10 centre with arms of nine cells', () {
    const config = GameConfig();
    expect(config.boardSize, 10);
    expect(config.armLength, 9);
    expect(config.gridSize, 28);
    expect(config.glassDepth, 19);
    final board = GameEngine(config: config).board;
    expect(board.size, 28);
    expect(board.center, 10);
    expect(GlassView(board, Side.top).depth, 19);
  });

  group('the cross', () {
    test('is a 10×10 centre with four arms of six cells', () {
      final board = emptyBoard();
      expect(board.size, 22);
      var inside = 0;
      for (var row = 0; row < board.size; row++) {
        for (var col = 0; col < board.size; col++) {
          if (board.isInside(row, col)) inside++;
        }
      }
      expect(inside, 100 + 4 * 60);
    });

    test('has no corners', () {
      final board = emptyBoard();
      expect(board.isInside(0, 0), isFalse);
      expect(board.isInside(5, 5), isFalse);
      expect(board.isInside(0, 21), isFalse);
      expect(board.isInside(21, 0), isFalse);
      expect(board.isInside(21, 21), isFalse);
      expect(board.isInside(-1, 10), isFalse);
      expect(board.isInside(10, 22), isFalse);
    });

    test('knows the centre from the arms', () {
      final board = emptyBoard();
      expect(board.isInside(0, 10), isTrue); // far end of the top arm
      expect(board.isCenter(0, 10), isFalse);
      expect(board.isCenter(6, 6), isTrue);
      expect(board.isCenter(15, 15), isTrue);
      expect(board.isInside(10, 21), isTrue); // far end of the right arm
      expect(board.isCenter(10, 16), isFalse);
    });

    test('paints and prints its central square', () {
      final board = boardOf(['R . B', 'Y Y .']);
      expect(board.colorAt(at(8, 0)), r);
      expect(board.colorAt(at(8, 2)), b);
      expect(board.colorAt(at(9, 1)), y);
      expect(board.blockCount, 4);
      expect(board.centerRows().sublist(8), [
        'R . B . . . . . . .',
        'Y Y . . . . . . . .',
      ]);
    });

    test('copies are independent', () {
      final board = boardOf(['R B Y']);
      final copy = board.copy();
      expect(copy.sameAs(board), isTrue);
      copy.set(0, 10, g);
      expect(copy.sameAs(board), isFalse);
      expect(board.at(0, 10), isNull);
    });
  });

  group('a glass is one arm plus the centre', () {
    test('is ten lanes wide and sixteen rows deep', () {
      final glass = GlassView(emptyBoard(), Side.top);
      expect(glass.lanes, 10);
      expect(glass.depth, glassDepth);
    });

    test('row 0 is the far end of its own arm', () {
      final board = emptyBoard();
      expect(GlassView(board, Side.top).toWorld(0, 0), const CellPosition(0, 6));
      expect(GlassView(board, Side.right).toWorld(0, 0), const CellPosition(6, 21));
      expect(GlassView(board, Side.bottom).toWorld(0, 0), const CellPosition(21, 15));
      expect(GlassView(board, Side.left).toWorld(0, 0), const CellPosition(15, 0));
    });

    test('the floor is the far wall of the centre', () {
      final board = emptyBoard();
      for (var lane = 0; lane < 10; lane++) {
        expect(GlassView(board, Side.top).toWorld(15, lane).row, 15);
        expect(GlassView(board, Side.right).toWorld(15, lane).col, 6);
        expect(GlassView(board, Side.bottom).toWorld(15, lane).row, 6);
        expect(GlassView(board, Side.left).toWorld(15, lane).col, 15);
      }
    });

    test('rows 6..15 are the centre, shared by all four glasses', () {
      final board = emptyBoard();
      for (final side in Side.values) {
        final glass = GlassView(board, side);
        for (var row = 0; row < glass.depth; row++) {
          for (var lane = 0; lane < glass.lanes; lane++) {
            final world = glass.toWorld(row, lane);
            expect(board.isInside(world.row, world.col), isTrue);
            expect(board.isCenter(world.row, world.col), row >= arm);
            expect(glass.fromWorld(world), CellPosition(row, lane));
          }
        }
      }
    });

    test('a cell of another arm is not in the glass', () {
      final board = emptyBoard();
      final top = GlassView(board, Side.top);
      expect(top.fromWorld(const CellPosition(10, 0)), isNull); // left arm
      expect(top.fromWorld(const CellPosition(10, 21)), isNull); // right arm
      expect(top.fromWorld(const CellPosition(21, 10)), isNull); // bottom arm
      expect(top.fromWorld(const CellPosition(0, 10)), const CellPosition(0, 4));
      expect(top.isFree(-1, 0), isFalse);
      expect(top.isFree(16, 0), isFalse);
      expect(top.isFree(0, 10), isFalse);
    });

    test('reads and writes through to the board', () {
      final board = emptyBoard();
      final right = GlassView(board, Side.right);
      right.set(15, 0, r); // floor of the right glass = left wall of the centre
      expect(board.colorAt(at(0, 0)), r);
      expect(GlassView(board, Side.top).at(6, 0), r);
      expect(right.isFree(15, 0), isFalse);
    });
  });
}
