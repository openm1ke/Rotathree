import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/engine/game_event.dart';
import 'package:rotathree/game/engine/rotation_transform.dart';
import 'package:rotathree/game/model/position.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/state/game_state.dart';

import 'helpers.dart';

void main() {
  group('switching the active side', () {
    test('TOP → RIGHT → BOTTOM → LEFT → TOP', () {
      final engine = newEngine();
      expect(engine.activeSide, Side.top);
      engine.switchSide(1);
      expect(engine.activeSide, Side.right);
      engine.switchSide(1);
      expect(engine.activeSide, Side.bottom);
      engine.switchSide(1);
      expect(engine.activeSide, Side.left);
      engine.switchSide(1);
      expect(engine.activeSide, Side.top);
    });

    test('and backwards', () {
      final engine = newEngine();
      engine.switchSide(-1);
      expect(engine.activeSide, Side.left);
      engine.switchSide(-1);
      expect(engine.activeSide, Side.bottom);
    });

    test('activating a side turns the short way round', () {
      final engine = newEngine();
      engine.activateSide(Side.left);
      engine.activateSide(Side.right);
      engine.activateSide(Side.right); // already active: nothing happens
      final turns = engine
          .drainEvents()
          .whereType<SideSwitched>()
          .map((e) => e.quarterTurns)
          .toList();
      expect(turns, [-1, 2]);
      expect(engine.activeSide, Side.right);
    });

    test('Side helpers', () {
      expect(Side.top.next, Side.right);
      expect(Side.left.next, Side.top);
      expect(Side.top.previous, Side.left);
      expect(Side.right.opposite, Side.left);
      expect(Side.bottom.stepsTo(Side.right), -1);
      expect(Side.bottom.stepsTo(Side.top), 2);
    });

    test('the piece being controlled changes with the side', () {
      final engine = newEngine();
      final top = engine.state.incoming[Side.top];
      final right = engine.state.incoming[Side.right];
      expect(engine.activePiece, same(top));
      engine.switchSide(1);
      expect(engine.activePiece, same(right));
    });
  });

  group('RotationTransform', () {
    const n = 22; // the whole grid: 10 + 2 × 6

    test('the top-left view cell of each side', () {
      CellPosition world(Side side) =>
          RotationTransform.viewToWorld(const CellPosition(0, 0), side, n);
      expect(world(Side.top), const CellPosition(0, 0));
      expect(world(Side.right), const CellPosition(0, 21));
      expect(world(Side.bottom), const CellPosition(21, 21));
      expect(world(Side.left), const CellPosition(21, 0));
    });

    test('world → view', () {
      const cell = CellPosition(2, 7);
      expect(RotationTransform.worldToView(cell, Side.top, n), const CellPosition(2, 7));
      expect(RotationTransform.worldToView(cell, Side.right, n), const CellPosition(14, 2));
      expect(RotationTransform.worldToView(cell, Side.bottom, n), const CellPosition(19, 14));
      expect(RotationTransform.worldToView(cell, Side.left, n), const CellPosition(7, 19));
    });

    test('view ↔ world round-trips for every cell and side', () {
      for (final side in Side.values) {
        final seen = <CellPosition>{};
        for (var row = 0; row < n; row++) {
          for (var col = 0; col < n; col++) {
            final view = CellPosition(row, col);
            final world = RotationTransform.viewToWorld(view, side, n);
            expect(RotationTransform.worldToView(world, side, n), view);
            seen.add(world);
          }
        }
        expect(seen, hasLength(n * n)); // a bijection
      }
    });

    test('a turn maps the cross onto itself', () {
      final board = emptyBoard();
      for (final side in Side.values) {
        for (var row = 0; row < n; row++) {
          for (var col = 0; col < n; col++) {
            final world =
                RotationTransform.viewToWorld(CellPosition(row, col), side, n);
            expect(
              board.isInside(world.row, world.col),
              board.isInside(row, col),
            );
          }
        }
      }
    });

    test('one step of "down" in the view is one step of down in the world', () {
      for (final side in Side.values) {
        final a = RotationTransform.viewToWorld(const CellPosition(3, 4), side, n);
        final b = RotationTransform.viewToWorld(const CellPosition(4, 4), side, n);
        final down = RotationTransform.down(side);
        expect(CellPosition(b.row - a.row, b.col - a.col), down);
      }
    });

    test('which glass is drawn in which screen slot', () {
      // With RIGHT active: RIGHT on top, BOTTOM right, LEFT below, TOP left.
      expect(RotationTransform.sideAtSlot(Side.right, Side.top), Side.right);
      expect(RotationTransform.sideAtSlot(Side.right, Side.right), Side.bottom);
      expect(RotationTransform.sideAtSlot(Side.right, Side.bottom), Side.left);
      expect(RotationTransform.sideAtSlot(Side.right, Side.left), Side.top);
      for (final active in Side.values) {
        for (final side in Side.values) {
          final slot = RotationTransform.slotOfSide(active, side);
          expect(RotationTransform.sideAtSlot(active, slot), side);
        }
      }
    });
  });

  group('the board under rotation', () {
    const rows = [
      '. . . . Y',
      'R . . B Y',
      'R B Y B R',
    ];

    test('placed colours do not change and nothing falls', () {
      final engine = newEngine(center: rows);
      engine.board.set(3, 10, g); // a block in the top arm, too
      final before = engine.board.copy();
      for (var i = 0; i < 4; i++) {
        engine.switchSide(1);
        expect(engine.phase, GamePhase.playing);
        expect(engine.board.sameAs(before), isTrue);
      }
    });

    test('every glass sees the same centre, only turned', () {
      final engine = newEngine(center: rows);
      final total = engine.board.blockCount;
      for (final side in Side.values) {
        final glass = glassOf(engine, side);
        var count = 0;
        for (var row = 0; row < glass.depth; row++) {
          for (var lane = 0; lane < glass.lanes; lane++) {
            final color = glass.at(row, lane);
            if (color == null) continue;
            count++;
            expect(row, greaterThanOrEqualTo(arm)); // all of it is in the centre
            expect(engine.board.colorAt(glass.toWorld(row, lane)), color);
          }
        }
        expect(count, total);
      }
    });

    test('after a turn the next piece falls along the new down', () {
      final engine = newEngine(center: rows);
      engine.switchSide(1); // RIGHT is now on top
      engine.incoming.put(Side.right, horizontal([b, y, b]), column: 0);
      engine.dropActive();
      runUntilPlaying(engine);
      // Lanes 0..2 on the floor of the right glass: the left wall of the
      // centre, rows 0..2.
      expect(engine.board.colorAt(at(0, 0)), b);
      expect(engine.board.colorAt(at(1, 0)), y);
      expect(engine.board.colorAt(at(2, 0)), b);
    });

    test('after a match blocks fall relative to the new down', () {
      final engine = newEngine();
      engine.board.set(arm + 4, arm + 5, y); // somewhere in the middle
      engine.switchSide(1); // RIGHT active: down is towards the world left
      engine.incoming.put(Side.right, horizontal([r, r, r]), column: 7);
      engine.dropActive();
      runUntilPlaying(engine);
      expect(engine.state.matches, 1);
      expect(engine.board.colorAt(at(4, 5)), isNull);
      expect(engine.board.colorAt(at(4, 0)), y);
    });

    test('settleAfterBoardRotation = true lets the new glass settle on a turn', () {
      final engine = newEngine(
        config: testConfig.copyWith(settleAfterBoardRotation: true),
        center: ['R . . B'],
      );
      engine.switchSide(1);
      expect(engine.phase, GamePhase.settling);
      runUntilPlaying(engine);
      // Down is the world left: both blocks of row 9 slide to the left wall.
      expect(engine.board.centerRows().last, 'R B . . . . . . . .');
    });

    test('a re-settle that lines up three pops them', () {
      final engine = newEngine(
        config: testConfig.copyWith(settleAfterBoardRotation: true),
        center: ['R . R . . R'],
      );
      engine.switchSide(1);
      runUntilPlaying(engine);
      expect(engine.state.matches, 1);
      expect(engine.state.bestCombo, 1);
      expect(engine.board.isEmpty, isTrue);
    });
  });
}
