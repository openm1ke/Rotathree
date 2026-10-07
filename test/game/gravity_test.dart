import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/gravity_resolver.dart';
import 'package:rotathree/game/model/board.dart';
import 'package:rotathree/game/model/position.dart';
import 'package:rotathree/game/model/side.dart';

import 'helpers.dart';

void main() {
  const gravity = GravityResolver();

  test('a block falls to the floor', () {
    final board = emptyBoard()..set(arm + 2, arm + 4, r);
    final moves = gravity.settle(board, Side.top);
    expect(board.colorAt(at(9, 4)), r);
    expect(board.colorAt(at(2, 4)), isNull);
    expect(moves, hasLength(1));
    expect(moves.single.from, at(2, 4));
    expect(moves.single.to, at(9, 4));
    expect(moves.single.distance, 7);
  });

  test('a block falls onto another block', () {
    final board = emptyBoard()
      ..set(arm + 9, arm + 4, b)
      ..set(arm + 3, arm + 4, r);
    gravity.settle(board, Side.top);
    expect(board.colorAt(at(9, 4)), b);
    expect(board.colorAt(at(8, 4)), r);
    expect(board.blockCount, 2);
  });

  test('several blocks keep their order', () {
    final board = emptyBoard()
      ..set(arm + 1, arm, r)
      ..set(arm + 3, arm, b)
      ..set(arm + 6, arm, y);
    gravity.settle(board, Side.top);
    expect(board.colorAt(at(7, 0)), r);
    expect(board.colorAt(at(8, 0)), b);
    expect(board.colorAt(at(9, 0)), y);
  });

  test('gaps collapse in every lane', () {
    final board = boardOf([
      'B . Y',
      '. . .',
      'Y R .',
      '. . .',
      'R . B',
    ]);
    gravity.settle(board, Side.top);
    expect(board.centerRows().sublist(7), [
      'B . . . . . . . . .',
      'Y . Y . . . . . . .',
      'R R B . . . . . . .',
    ]);
  });

  test('a settled board does not move', () {
    final board = boardOf(['R .', 'B Y']);
    final before = board.copy();
    expect(gravity.settle(board, Side.top), isEmpty);
    expect(board.sameAs(before), isTrue);
  });

  test('a block in the active arm falls into the centre', () {
    final board = emptyBoard()..set(1, arm + 4, r); // second row of the top arm
    gravity.settle(board, Side.top);
    expect(board.colorAt(at(9, 4)), r);
  });

  test('blocks in the three other arms are outside the glass and stay', () {
    final board = emptyBoard()
      ..set(10, 2, r) // left arm
      ..set(10, 19, b) // right arm
      ..set(19, 10, y); // bottom arm, below the floor
    final before = board.copy();
    expect(gravity.settle(board, Side.top), isEmpty);
    expect(board.sameAs(before), isTrue);
  });

  test('down follows the active side', () {
    Board fallen(Side active) {
      final board = emptyBoard()..set(arm + 4, arm + 5, r);
      gravity.settle(board, active);
      return board;
    }

    expect(fallen(Side.top).colorAt(at(9, 5)), r); // world bottom
    expect(fallen(Side.right).colorAt(at(4, 0)), r); // world left
    expect(fallen(Side.bottom).colorAt(at(0, 5)), r); // world top
    expect(fallen(Side.left).colorAt(at(4, 9)), r); // world right
  });

  test('what hung under the floor falls once its own glass is on top', () {
    final board = emptyBoard()..set(17, arm + 4, y); // in the bottom arm
    expect(gravity.settle(board, Side.top), isEmpty);
    gravity.settle(board, Side.bottom);
    expect(board.at(17, arm + 4), isNull);
    expect(board.colorAt(at(0, 4)), y); // the floor of the bottom glass
  });

  test('aboveCleared only releases blocks over a popped cell', () {
    final board = emptyBoard()
      ..set(arm + 2, arm + 3, r) // above the popped cell at (5,3)
      ..set(arm + 2, arm + 6, b); // floating elsewhere: must stay
    final moves = gravity.settle(
      board,
      Side.top,
      scope: GravityScope.aboveCleared,
      cleared: {at(5, 3)},
    );
    expect(moves, hasLength(1));
    expect(board.colorAt(at(9, 3)), r);
    expect(board.colorAt(at(2, 6)), b);
  });

  test('aboveCleared leaves blocks below the popped cell alone', () {
    final board = emptyBoard()
      ..set(arm + 1, arm + 3, r)
      ..set(arm + 7, arm + 3, y); // floating below the popped cell
    gravity.settle(
      board,
      Side.top,
      scope: GravityScope.aboveCleared,
      cleared: {at(4, 3)},
    );
    expect(board.colorAt(at(7, 3)), y);
    expect(board.colorAt(at(6, 3)), r);
  });

  test('aboveCleared ignores cells popped in another arm', () {
    final board = emptyBoard()..set(arm + 2, arm + 3, r);
    final moves = gravity.settle(
      board,
      Side.top,
      scope: GravityScope.aboveCleared,
      cleared: {const CellPosition(10, 2)}, // a cell of the left arm
    );
    expect(moves, isEmpty);
  });
}
