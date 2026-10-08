import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/engine/game_event.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/state/game_state.dart';

import 'helpers.dart';

/// Stacks blocks in lane 4 of the glass of [side], from its floor up to row
/// [topRow]. Colours alternate so the stack itself never matches.
void fillLane(GameEngine engine, Side side, {required int topRow}) {
  final glass = glassOf(engine, side);
  for (var row = topRow; row < glassDepth; row++) {
    glass.set(row, 4, row.isEven ? r : b);
  }
}

void main() {
  test('an empty glass has plenty of headroom', () {
    final engine = newEngine();
    for (final side in Side.values) {
      expect(engine.headroom(side), glassDepth);
      expect(engine.isCrowded(side), isFalse);
    }
  });

  test('a glass filled up to the far end of its arm ends the game', () {
    final engine = newEngine();
    fillLane(engine, Side.top, topRow: 1);
    engine.incoming.put(Side.top, horizontal([y, y, b]), column: 3);
    expect(engine.headroom(Side.top), 1);
    expect(engine.isCrowded(Side.top), isTrue);

    // The piece has nowhere to fall: on its first step it locks where it
    // appeared, and the next one has no room at all.
    engine.update(1.1);

    expect(engine.phase, GamePhase.gameOver);
    expect(engine.isGameOver, isTrue);
    expect(engine.state.gameOverSide!, Side.top);
    expect(engine.state.piecesPlaced, 1);
    expect(engine.drainEvents().whereType<GameEnded>(), hasLength(1));
  });

  test('one free row above the stack is still enough to go on', () {
    final engine = newEngine();
    fillLane(engine, Side.top, topRow: 2);
    engine.incoming.put(Side.top, horizontal([y, y, b]), column: 3);
    engine.update(2.1); // one step down, the next one locks it
    expect(engine.isGameOver, isFalse);
    expect(engine.state.piecesPlaced, 1);
    expect(engine.headroom(Side.top), 1);
    expect(engine.state.incoming[Side.top], isNotNull);
  });

  test('moving the piece out of the full lanes in time avoids the end', () {
    final engine = newEngine();
    fillLane(engine, Side.top, topRow: 1);
    engine.incoming.put(Side.top, horizontal([y, y, b]), column: 3);
    engine.moveActive(2); // lanes 5..7 are empty all the way down
    engine.dropActive();
    runUntilPlaying(engine);
    expect(engine.isGameOver, isFalse);
    expect(engine.board.centerRows().last, '. . . . B Y Y B . .');
  });

  test('an inactive glass that overflows ends the game too', () {
    final engine = newEngine();
    fillLane(engine, Side.right, topRow: 1);
    engine.incoming.put(Side.right, horizontal([y, y, b]), column: 3);
    expect(engine.activeSide, Side.top);
    expect(engine.isCrowded(Side.right), isTrue);
    engine.update(3.1); // an inactive piece takes three seconds per step
    expect(engine.phase, GamePhase.gameOver);
    expect(engine.state.gameOverSide!, Side.right);
  });

  test('a hard drop that fills the last row ends the game', () {
    final engine = newEngine();
    fillLane(engine, Side.top, topRow: 1);
    engine.incoming.put(Side.top, horizontal([y, y, b]), column: 3);
    engine.dropActive();
    runUntilPlaying(engine);
    expect(engine.phase, GamePhase.gameOver);
  });

  test('a pop that frees the far end saves the glass', () {
    final engine = newEngine();
    // Lane 4 is stacked up to row 1 and ends in two reds.
    final glass = glassOf(engine, Side.top);
    for (var row = 3; row < glassDepth; row++) {
      glass.set(row, 4, row.isEven ? y : b);
    }
    glass.set(1, 4, r);
    glass.set(2, 4, r);
    // A flat stick with a red in the middle rests on them at row 0.
    engine.incoming.put(Side.top, horizontal([b, r, y]), column: 3);
    engine.update(1.1);
    runUntilPlaying(engine);
    // Its middle red completed three in lane 4: they popped, the two outer
    // squares fell, and the far end is free again.
    expect(engine.state.matches, 1);
    expect(engine.isGameOver, isFalse);
    expect(engine.headroom(Side.top), greaterThan(1));
  });

  test('nothing happens after game over until restart', () {
    final engine = newEngine();
    fillLane(engine, Side.top, topRow: 1);
    engine.incoming.put(Side.top, horizontal([y, y, b]), column: 3);
    engine.update(1.1);
    expect(engine.isGameOver, isTrue);

    final elapsed = engine.state.elapsedSeconds;
    engine.switchSide(1);
    engine.moveActive(2);
    engine.dropActive();
    engine.update(3);
    expect(engine.activeSide, Side.top);
    expect(engine.state.elapsedSeconds, elapsed);
    expect(engine.phase, GamePhase.gameOver);

    engine.restart();
    expect(engine.phase, GamePhase.playing);
    expect(engine.board.isEmpty, isTrue);
    expect(engine.state.score, 0);
    expect(engine.state.gameOverSide, isNull);
    expect(engine.state.incoming, hasLength(4));
  });
}
