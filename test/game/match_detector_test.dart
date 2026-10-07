import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/engine/match_detector.dart';
import 'package:rotathree/game/model/position.dart';

import 'helpers.dart';

void main() {
  const detector = MatchDetector();

  test('horizontal line of 3', () {
    final result = detector.find(boardOf(['B R R R Y']));
    expect(result.runs, hasLength(1));
    expect(result.runs.single.isHorizontal, isTrue);
    expect(result.runs.single.color, r);
    expect(result.cells, {at(9, 1), at(9, 2), at(9, 3)});
  });

  test('vertical line of 3', () {
    final result = detector.find(boardOf(['Y', 'Y', 'Y', 'B']));
    expect(result.runs, hasLength(1));
    expect(result.runs.single.isHorizontal, isFalse);
    expect(result.cells, {at(6, 0), at(7, 0), at(8, 0)});
  });

  test('horizontal line of 4 is one match of four cells', () {
    final result = detector.find(boardOf(['B B B B']));
    expect(result.runs, hasLength(1));
    expect(result.runs.single.length, 4);
    expect(result.cells, hasLength(4));
  });

  test('vertical line of 5', () {
    final result = detector.find(boardOf(['R', 'R', 'R', 'R', 'R']));
    expect(result.runs, hasLength(1));
    expect(result.runs.single.length, 5);
    expect(result.cells, hasLength(5));
  });

  test('two separate lines are found together', () {
    final result = detector.find(boardOf([
      'Y Y Y . . . .',
      'B R B . R R R',
    ]));
    expect(result.runs, hasLength(2));
    expect(result.cells, {
      at(8, 0), at(8, 1), at(8, 2),
      at(9, 4), at(9, 5), at(9, 6),
    });
  });

  test('crossing lines share their common cell once', () {
    final result = detector.find(boardOf([
      '. R .',
      '. R .',
      'B R B',
      'R R R',
    ]));
    // Vertical run of four in column 1 and horizontal run of three in row 9.
    expect(result.runs, hasLength(2));
    expect(result.cells, hasLength(6));
    expect(result.cells, contains(at(9, 1)));
  });

  test('different colours do not match', () {
    expect(detector.find(boardOf(['R B R B Y R'])).isEmpty, isTrue);
  });

  test('two in a row is not enough', () {
    expect(detector.find(boardOf(['R R B B Y Y'])).isEmpty, isTrue);
  });

  test('diagonals do not match', () {
    final result = detector.find(boardOf([
      'R . .',
      'B R .',
      'Y B R',
    ]));
    expect(result.isEmpty, isTrue);
  });

  test('a gap splits a line', () {
    expect(detector.find(boardOf(['R R . R R'])).isEmpty, isTrue);
  });

  test('a line inside an arm counts', () {
    final board = emptyBoard();
    for (var col = 9; col <= 11; col++) {
      board.set(2, col, b); // three cells of the top arm
    }
    final result = detector.find(board);
    expect(result.runs, hasLength(1));
    expect(result.cells, {
      const CellPosition(2, 9),
      const CellPosition(2, 10),
      const CellPosition(2, 11),
    });
  });

  test('a line may run across the border between an arm and the centre', () {
    final board = emptyBoard()
      ..set(4, 10, y) // top arm
      ..set(5, 10, y) // top arm, last row
      ..set(6, 10, y) // top row of the centre
      ..set(10, 4, r) // left arm
      ..set(10, 5, r) // left arm, last column
      ..set(10, 6, r); // left column of the centre
    final result = detector.find(board);
    expect(result.runs, hasLength(2));
    expect(result.cells, hasLength(6));
  });

  test('an empty board has no matches', () {
    expect(detector.find(emptyBoard()).isEmpty, isTrue);
  });
}
