import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/model/piece.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/state/game_state.dart';

import 'helpers.dart';

void main() {
  group('four streams', () {
    test('four pieces exist at the same time', () {
      final engine = GameEngine(config: const GameConfig(seed: 1));
      expect(engine.state.incoming.keys.toSet(), Side.values.toSet());
      for (final side in Side.values) {
        final piece = engine.state.incoming[side]!;
        expect(piece.side, side);
        expect(piece.piece.length, 3);
        expect(piece.piece.isHorizontal, isTrue);
        expect(piece.column, 3); // centred in the ten lanes
      }
    });

    test('a new game staggers them: TOP, RIGHT, LEFT, then BOTTOM at the end', () {
      final engine = GameEngine(config: const GameConfig(seed: 1));
      final rows = {
        for (final side in Side.values) side: engine.state.incoming[side]!.row,
      };
      expect(rows[Side.top], greaterThan(rows[Side.right]!));
      expect(rows[Side.right], greaterThan(rows[Side.left]!));
      expect(rows[Side.left], greaterThan(rows[Side.bottom]!));
      expect(rows[Side.bottom], 0);
    });

    test('the active piece steps once a second, the others every three', () {
      final engine = newEngine();
      engine.update(3);
      expect(engine.state.incoming[Side.top]!.row, 3);
      for (final side in [Side.right, Side.bottom, Side.left]) {
        expect(engine.state.incoming[side]!.row, 1);
      }
      engine.update(3);
      expect(engine.state.incoming[Side.top]!.row, 6);
      expect(engine.state.incoming[Side.right]!.row, 2);
    });

    test('a step is a whole cell: between steps nothing moves', () {
      final engine = newEngine();
      engine.update(0.9);
      for (final side in Side.values) {
        expect(engine.state.incoming[side]!.row, 0);
      }
      expect(engine.state.incoming[Side.top]!.stepProgress, closeTo(0.9, 1e-9));
      expect(engine.state.incoming[Side.left]!.stepProgress, closeTo(0.3, 1e-9));
      engine.update(0.1);
      expect(engine.state.incoming[Side.top]!.row, 1);
      expect(engine.state.incoming[Side.top]!.stepProgress, 0);
      expect(engine.state.incoming[Side.left]!.row, 0);
    });

    test('the step intervals come from the config', () {
      final engine = newEngine(
        config: testConfig.copyWith(
          activeStepSeconds: 0.5,
          inactiveStepSeconds: 2,
        ),
      );
      engine.update(2);
      expect(engine.state.incoming[Side.top]!.row, 4);
      expect(engine.state.incoming[Side.right]!.row, 1);
    });

    test('each piece has its own position', () {
      final engine = newEngine();
      engine.incoming.put(Side.top, horizontal([r, b, y]), row: 5);
      engine.incoming.put(Side.right, horizontal([r, b, y]), row: 1);
      engine.update(3);
      expect(engine.state.incoming[Side.top]!.row, 8);
      expect(engine.state.incoming[Side.right]!.row, 2);
      expect(engine.state.incoming[Side.bottom]!.row, 1);
    });

    test('pieces of inactive sides keep falling', () {
      final engine = newEngine();
      expect(engine.activeSide, Side.top);
      engine.update(6);
      for (final side in [Side.right, Side.bottom, Side.left]) {
        expect(engine.state.incoming[side]!.row, 2);
      }
    });

    test('switching the active side does not reset anything', () {
      final engine = newEngine();
      engine.update(1.5);
      final before = {
        for (final side in Side.values)
          side: engine.state.incoming[side]!.copy(),
      };
      engine.switchSide(1);
      engine.switchSide(1);
      engine.switchSide(-1);
      for (final side in Side.values) {
        final piece = engine.state.incoming[side]!;
        expect(piece.row, before[side]!.row);
        expect(piece.stepProgress, before[side]!.stepProgress);
        expect(piece.piece, before[side]!.piece);
        expect(piece.column, before[side]!.column);
      }
    });

    test('the glass that becomes active speeds up, the one left slows down', () {
      final engine = newEngine();
      engine.update(1.5); // top: row 1, half-way to its next step
      final top = engine.state.incoming[Side.top]!;
      final right = engine.state.incoming[Side.right]!;
      expect(top.row, 1);
      expect(top.stepProgress, closeTo(0.5, 1e-9));
      expect(right.row, 0);
      expect(right.stepProgress, closeTo(0.5, 1e-9));

      engine.switchSide(1); // RIGHT is active now
      engine.update(0.5);
      // The right piece finished its half step in half a second…
      expect(right.row, 1);
      // …while the top piece, now waiting three seconds per step, did not.
      expect(top.row, 1);
      expect(top.stepProgress, closeTo(0.5 + 0.5 / 3, 1e-9));
    });

    test('moving and rotating only touch the active piece', () {
      final engine = newEngine();
      engine.incoming.put(Side.top, horizontal([r, b, y]), column: 3, row: 2);
      final right = engine.state.incoming[Side.right]!.copy();
      engine.moveActive(-2);
      engine.rotateActive();
      expect(engine.state.incoming[Side.top]!.column, 2);
      expect(engine.state.incoming[Side.top]!.piece.isVertical, isTrue);
      expect(engine.state.incoming[Side.right]!.column, right.column);
      expect(engine.state.incoming[Side.right]!.piece, right.piece);
    });
  });

  group('falling and locking', () {
    test('a piece does not stop at the centre: it steps on through it', () {
      final engine = newEngine();
      final piece = engine.incoming.put(Side.top, horizontal([r, b, y]), row: 5);
      engine.update(3);
      expect(piece.row, 8);
      expect(piece.row, greaterThan(arm));
      expect(engine.phase, GamePhase.playing);
      expect(engine.board.isEmpty, isTrue);
    });

    test('it reaches the floor, rests for one step, then locks', () {
      final engine = newEngine();
      final piece = engine.incoming
          .put(Side.top, horizontal([r, b, y]), column: 1, row: 14);

      engine.update(1);
      expect(piece.row, 15);
      expect(engine.state.incoming[Side.top], same(piece));

      engine.update(0.9); // still within the step it rests for
      expect(engine.state.incoming[Side.top], same(piece));
      expect(engine.board.isEmpty, isTrue);

      engine.update(0.1); // the next step is blocked: it locks
      expect(engine.board.centerRows().last, '. R B Y . . . . . .');
      expect(engine.state.piecesPlaced, 1);
      expect(engine.state.selfLocked, 1);
    });

    test('after locking a new piece appears at the far end of that glass', () {
      final engine = newEngine();
      engine.update(6);
      final old = engine.incoming
          .put(Side.top, horizontal([r, b, y]), column: 1, row: 15);
      engine.update(1);

      final fresh = engine.state.incoming[Side.top]!;
      expect(fresh, isNot(same(old)));
      expect(fresh.row, 0);
      expect(fresh.column, engine.incoming.spawnColumn);
      expect(fresh.piece.isHorizontal, isTrue);
      // The other three kept their own rows.
      expect(engine.state.incoming[Side.right]!.row, 2);
    });

    test('a piece rests and locks on blocks as well as on the floor', () {
      final engine = newEngine(center: ['. . . . B']);
      final piece = engine.incoming
          .put(Side.top, horizontal([r, r, y]), column: 3, row: 13);
      engine.update(1);
      expect(piece.row, 14); // one row above the floor, on the blue block
      engine.update(1);
      expect(engine.board.centerRows()[8], '. . . R R Y . . . .');
    });

    test('sliding it off a ledge lets it fall again', () {
      final engine = newEngine(center: ['. . . . B']);
      final piece = engine.incoming
          .put(Side.top, horizontal([r, b, y]), column: 3, row: 14);
      engine.update(0.5);

      engine.moveActive(2); // lanes 5..7 have nothing under them
      engine.update(0.5); // the step it would have locked on
      expect(engine.state.incoming[Side.top], same(piece));
      expect(piece.row, 15);

      engine.update(1);
      expect(engine.board.centerRows().last, '. . . . B R B Y . .');
    });

    test('an inactive piece falls along its own axis; the view stays put', () {
      final engine = newEngine();
      engine.incoming.put(Side.right, horizontal([r, b, y]), column: 0, row: 14);
      engine.update(6); // one slow step down, one more to lock
      expect(engine.activeSide, Side.top);
      // From the right glass it went across to the left wall of the centre.
      expect(engine.board.colorAt(at(0, 0)), r);
      expect(engine.board.colorAt(at(1, 0)), b);
      expect(engine.board.colorAt(at(2, 0)), y);
      expect(engine.state.incoming[Side.right]!.row, 0);
    });

    test('two pieces locking together are placed one after the other', () {
      final engine = newEngine();
      engine.incoming.put(Side.top, horizontal([r, b, y]),
          column: 0, row: 15, stepProgress: 1);
      engine.incoming.put(Side.bottom, horizontal([b, y, r]),
          column: 0, row: 15, stepProgress: 1);
      engine.update(0.01);
      expect(engine.state.piecesPlaced, 2);
      expect(engine.board.blockCount, 6);
      expect(engine.state.incoming, hasLength(4));
    });

    test('a piece coming up under the pile locks inside its own arm', () {
      final engine = newEngine(center: ['. . . . . . R B Y .']);
      // Seen from the bottom glass those blocks are lanes 1..3, right at the
      // border between its arm and the centre.
      final piece = engine.incoming
          .put(Side.bottom, horizontal([y, y, b]), column: 1, row: 4);
      engine.update(3);
      expect(piece.row, 5); // the last row of its arm
      engine.update(3);
      expect(engine.state.incoming, hasLength(4));
      // Locked in the bottom arm, one row outside the centre.
      expect(engine.board.at(16, 14), y);
      expect(engine.board.at(16, 13), y);
      expect(engine.board.at(16, 12), b);
      expect(engine.isGameOver, isFalse);
    });

    test('the countdown is the steps left plus the one it locks on', () {
      final engine = newEngine();
      engine.incoming.put(Side.top, horizontal([r, b, y]), row: 13);
      engine.incoming.put(Side.right, horizontal([r, b, y]), row: 13);
      // Two rows to the floor, then one blocked step.
      expect(engine.secondsToLock(Side.top), closeTo(3, 1e-9));
      expect(engine.secondsToLock(Side.right), closeTo(9, 1e-9));
      engine.update(0.5);
      expect(engine.secondsToLock(Side.top), closeTo(2.5, 1e-9));
      expect(engine.secondsToLock(Side.right), closeTo(8.5, 1e-9));
    });
  });

  group('moving the active piece', () {
    test('is clamped to the ten lanes of the glass', () {
      final engine = newEngine();
      engine.incoming.put(Side.top, horizontal([r, b, y]), column: 3);
      engine.moveActive(-10);
      expect(engine.activePiece!.column, 0);
      engine.moveActive(99);
      expect(engine.activePiece!.column, 7);

      engine.incoming.put(Side.top, vertical([r, b, y]), column: 3);
      engine.moveActive(99);
      expect(engine.activePiece!.column, 9);
    });

    test('a settled block stops it', () {
      final engine = newEngine();
      engine.board.set(arm + 4, arm + 6, b); // glass row 10, lane 6
      final piece = engine.incoming
          .put(Side.top, horizontal([r, b, y]), column: 3, row: 10);
      engine.moveActive(1);
      expect(piece.column, 3);
      engine.incoming.setColumn(engine.activeSide, 7, engine.board);
      expect(piece.column, 3);

      // Above the block the way is free.
      piece.row = 8;
      engine.incoming.setColumn(engine.activeSide, 7, engine.board);
      expect(piece.column, 7);
    });

    test('dragging slides it as far as it can go', () {
      final engine = newEngine();
      engine.board.set(arm + 4, arm + 8, b); // glass row 10, lane 8
      final piece = engine.incoming
          .put(Side.top, horizontal([r, b, y]), column: 1, row: 10);
      engine.incoming.setColumn(engine.activeSide, 7, engine.board);
      expect(piece.column, 5); // lanes 5..7, right up against the block
    });
  });

  group('rotating the active piece', () {
    test('turns around the middle square', () {
      final engine = newEngine();
      final piece = engine.incoming
          .put(Side.top, horizontal([r, b, y]), column: 3, row: 5);
      engine.rotateActive();
      expect(piece.piece, vertical([r, b, y]));
      expect(piece.column, 4);
      expect(piece.row, 4);
      engine.rotateActive();
      expect(piece.piece.orientation, PieceOrientation.horizontalFlipped);
      expect(piece.column, 3);
      expect(piece.row, 5);
      engine.rotateActive();
      expect(piece.piece.orientation, PieceOrientation.verticalFlipped);
      expect(piece.column, 4);
      expect(piece.row, 4);
      engine.rotateActive();
      expect(piece.piece, horizontal([r, b, y]));
      expect(piece.column, 3);
      expect(piece.row, 5);
    });

    test('can be turned the other way', () {
      final engine = newEngine();
      final piece = engine.incoming
          .put(Side.top, horizontal([r, b, y]), column: 3, row: 5);
      engine.rotateActive(clockwise: false);
      expect(piece.piece.orientation, PieceOrientation.verticalFlipped);
      engine.rotateActive();
      expect(piece.piece, horizontal([r, b, y]));
    });

    test('each of the four orientations lands with its colours that way', () {
      List<String> landed(int turns) {
        final engine = newEngine();
        engine.incoming.put(Side.top, horizontal([r, b, y]), column: 3, row: 5);
        for (var i = 0; i < turns; i++) {
          engine.rotateActive();
        }
        engine.dropActive();
        runUntilPlaying(engine);
        return engine.board.centerRows().sublist(7);
      }

      // Red on the left.
      expect(landed(0).last, '. . . R B Y . . . .');
      // Red on top.
      expect(landed(1), [
        '. . . . R . . . . .',
        '. . . . B . . . . .',
        '. . . . Y . . . . .',
      ]);
      // Red on the right.
      expect(landed(2).last, '. . . Y B R . . . .');
      // Red at the bottom.
      expect(landed(3), [
        '. . . . Y . . . . .',
        '. . . . B . . . . .',
        '. . . . R . . . . .',
      ]);
    });

    test('at the far end of the arm it is nudged down', () {
      final engine = newEngine();
      final piece = engine.incoming.put(Side.top, horizontal([r, b, y]), column: 3);
      engine.rotateActive();
      expect(piece.piece.isVertical, isTrue);
      expect(piece.column, 4);
      expect(piece.row, 0);
    });

    test('at the walls it is nudged sideways', () {
      final engine = newEngine();
      final left = engine.incoming
          .put(Side.top, vertical([r, b, y]), column: 0, row: 5);
      engine.rotateActive();
      expect(left.piece.isHorizontal, isTrue);
      expect(left.column, 0);

      final right = engine.incoming
          .put(Side.top, vertical([r, b, y]), column: 9, row: 5);
      engine.rotateActive();
      expect(right.piece.isHorizontal, isTrue);
      expect(right.column, 7);
    });

    test('with no room to turn it stays as it is', () {
      final engine = newEngine();
      final glass = glassOf(engine, Side.top);
      for (var row = 8; row <= 14; row++) {
        glass.set(row, 3, row.isEven ? r : b);
        glass.set(row, 5, row.isEven ? b : r);
      }
      final piece = engine.incoming
          .put(Side.top, vertical([y, y, b]), column: 4, row: 10);
      engine.rotateActive();
      expect(piece.piece.isVertical, isTrue);
      expect(piece.column, 4);
      expect(piece.row, 10);
    });

    test('does not disturb the wait for the next step', () {
      final engine = newEngine();
      final piece = engine.incoming
          .put(Side.top, horizontal([r, b, y]), column: 3, row: 5);
      engine.update(0.4);
      engine.rotateActive();
      engine.moveActive(1);
      expect(piece.stepProgress, closeTo(0.4, 1e-9));
    });

    test('never changes the colour order', () {
      final engine = newEngine();
      final piece = engine.incoming
          .put(Side.top, horizontal([r, r, b]), column: 3, row: 6);
      for (var i = 0; i < 5; i++) {
        engine.rotateActive();
        expect(piece.piece.colors, [r, r, b]);
      }
    });
  });

  group('falling pieces and new blocks', () {
    test('a piece overlapped by a new block backs off towards its own arm', () {
      final engine = newEngine();
      final piece = engine.incoming
          .put(Side.top, horizontal([r, b, y]), column: 3, row: 10);
      glassOf(engine, Side.top).set(10, 4, b); // appears inside the piece
      expect(engine.incoming.resolveOverlaps(engine.board), isEmpty);
      expect(piece.row, 9);
    });

    test('with nowhere to back off to, its glass is lost', () {
      final engine = newEngine();
      engine.incoming.put(Side.top, horizontal([r, b, y]), column: 3);
      glassOf(engine, Side.top).set(0, 4, b);
      expect(engine.incoming.resolveOverlaps(engine.board), [Side.top]);
    });

    test('pieces of two glasses pass through each other until one locks', () {
      final engine = newEngine();
      // Something for the left piece to stop against, beside the top lanes.
      engine.board.set(13, 12, g);
      // The top piece is about to step into world row 13, columns 9..11.
      final top = engine.incoming
          .put(Side.top, horizontal([r, r, y]), column: 3, row: 12);
      // The left piece already rests across exactly those cells and will
      // lock there in a second and a half.
      engine.incoming.put(Side.left, vertical([b, y, b]),
          column: 2, row: 9, stepProgress: 0.5);

      engine.update(1.2);
      expect(top.row, 13); // both occupy the same cells for a moment

      engine.update(0.4); // the left piece locks
      expect(engine.state.selfLocked, 1);
      expect(engine.board.at(13, 9), b);
      expect(engine.board.at(13, 10), y);
      expect(engine.board.at(13, 11), b);
      // The top piece is put back on top of the new blocks.
      expect(engine.state.incoming[Side.top], same(top));
      expect(top.row, 12);

      engine.update(0.5); // and locks there on its next step
      expect(engine.board.at(12, 9), r);
      expect(engine.board.at(12, 10), r);
      expect(engine.board.at(12, 11), y);
      expect(engine.isGameOver, isFalse);
    });
  });

  group('hard drop', () {
    test('is a short timed flight; the glass is empty meanwhile', () {
      final engine = newEngine();
      engine.incoming.put(Side.top, horizontal([r, b, y]), column: 2, row: 3);
      engine.dropActive();
      expect(engine.phase, GamePhase.pieceDropping);
      expect(engine.state.incoming[Side.top], isNull);
      expect(engine.state.drop!.startRow, 3);
      expect(engine.state.drop!.placement.row, glassDepth - 1);

      runUntilPlaying(engine);
      expect(engine.board.centerRows().last, '. . R B Y . . . . .');
      expect(engine.state.selfLocked, 0);
      expect(engine.state.incoming[Side.top]!.row, 0);
    });

    test('a longer fall takes longer', () {
      final near = newEngine();
      near.incoming.put(Side.top, horizontal([r, b, y]), row: 14);
      near.dropActive();
      final far = newEngine();
      far.incoming.put(Side.top, horizontal([r, b, y]), row: 0);
      far.dropActive();
      expect(far.state.phaseDuration, greaterThan(near.state.phaseDuration));
    });

    test('lands exactly where the preview said', () {
      final engine = newEngine(center: ['. . . B', '. . R B']);
      engine.incoming.put(Side.top, horizontal([y, y, r]), column: 1, row: 2);
      final preview = engine.previewDrop(Side.top)!;
      engine.dropActive();
      runUntilPlaying(engine);
      for (final cell in preview.cells) {
        expect(engine.board.colorAt(cell.position), cell.color);
      }
    });
  });

  group('pauseIncomingDuringCascade', () {
    // A single-colour stick pops itself on landing: a guaranteed match.
    double waitGainedDuringMatch({required bool pause}) {
      final engine = newEngine(
        config: testConfig.copyWith(pauseIncomingDuringCascade: pause),
      );
      engine.incoming.put(Side.top, horizontal([r, r, r]));
      engine.dropActive();
      while (engine.phase == GamePhase.pieceDropping) {
        engine.update(0.002);
      }
      expect(engine.phase, GamePhase.matching);
      expect(engine.incomingPaused, pause);
      final before = engine.state.incoming[Side.right]!.stepProgress;
      runUntilPlaying(engine);
      expect(engine.state.matches, 1);
      return engine.state.incoming[Side.right]!.stepProgress - before;
    }

    test('true: pieces stand still while the match resolves', () {
      expect(waitGainedDuringMatch(pause: true), closeTo(0, 2e-3));
    });

    test('false: their wait keeps running', () {
      // flash 0.16 s + pop 0.20 s of a three-second step.
      expect(waitGainedDuringMatch(pause: false), closeTo(0.36 / 3, 2e-3));
    });
  });
}
