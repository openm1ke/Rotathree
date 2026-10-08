import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/engine/game_event.dart';
import 'package:rotathree/game/engine/placement_engine.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/sim/bot_player.dart';
import 'package:rotathree/game/state/game_state.dart';

import 'helpers.dart';

void main() {
  test('input during a drop is queued and replayed in order', () {
    final engine = newEngine();
    engine.incoming.put(Side.top, horizontal([r, b, y]), column: 0);
    engine.incoming.put(Side.right, horizontal([b, b, y]), column: 3, row: 2);
    engine.dropActive();
    expect(engine.phase, GamePhase.pieceDropping);

    // Typed ahead while the first piece is still in the air.
    engine.switchSide(1);
    engine.moveActive(-3);
    engine.rotateActive();
    expect(engine.activeSide, Side.top); // not applied yet

    runUntilPlaying(engine);
    expect(engine.activeSide, Side.right);
    final piece = engine.state.incoming[Side.right]!;
    expect(piece.piece.isVertical, isTrue);
    expect(piece.column, 1); // slid to lane 0, then pivoted to lane 1
  });

  test('the input queue is bounded', () {
    final engine = newEngine(config: testConfig.copyWith(maxQueuedInputs: 3));
    engine.incoming.put(Side.top, horizontal([r, b, y]));
    engine.dropActive();
    for (var i = 0; i < 10; i++) {
      engine.switchSide(1);
    }
    runUntilPlaying(engine);
    expect(engine.activeSide, Side.left); // only three turns were kept
  });

  test('events tell the UI what happened', () {
    final engine = newEngine();
    engine.incoming.put(Side.top, horizontal([r, r, r]), column: 2);
    engine.switchSide(1);
    engine.switchSide(-1);
    engine.dropActive();
    runUntilPlaying(engine);
    final events = engine.drainEvents();
    expect(events.whereType<SideSwitched>(), hasLength(2));
    expect(events.whereType<PieceDropped>().single.side, Side.top);
    expect(events.whereType<PieceLanded>().single.dropped, isTrue);
    expect(events.whereType<MatchScored>().single.score, 100);
    expect(events.whereType<CellsPopped>().single.cells, hasLength(3));
    expect(engine.drainEvents(), isEmpty);
  });

  test('the same seed and inputs give the same game', () {
    GameEngine play() {
      final engine = GameEngine(config: const GameConfig(seed: 99));
      final inputs = Random(5);
      for (var i = 0; i < 3000 && !engine.isGameOver; i++) {
        switch (inputs.nextInt(6)) {
          case 0:
            engine.switchSide(1);
          case 1:
            engine.moveActive(inputs.nextInt(7) - 3);
          case 2:
            engine.rotateActive();
          case 3:
            engine.dropActive();
        }
        engine.update(0.05);
      }
      return engine;
    }

    final a = play();
    final b = play();
    expect(a.board.sameAs(b.board), isTrue);
    expect(a.state.score, b.state.score);
    expect(a.state.piecesPlaced, b.state.piecesPlaced);
    expect(a.state.elapsedSeconds, b.state.elapsedSeconds);
  });

  test('how the frame time is sliced does not change the game', () {
    GameEngine play(double step) {
      final engine = GameEngine(config: const GameConfig(seed: 5));
      for (var t = 0.0; t < 40 - 1e-9 && !engine.isGameOver; t += step) {
        engine.update(step);
      }
      return engine;
    }

    final coarse = play(0.25);
    final fine = play(0.0125);
    expect(coarse.board.sameAs(fine.board), isTrue);
    expect(coarse.state.piecesPlaced, fine.state.piecesPlaced);
    expect(coarse.state.piecesPlaced, greaterThan(0));
  });

  test('random play keeps the engine consistent', () {
    const placement = PlacementEngine();
    for (var seed = 0; seed < 25; seed++) {
      final engine = GameEngine(
        config: GameConfig(
          seed: seed,
          activeStepSeconds: 0.3,
          inactiveStepSeconds: 0.6,
          settleAfterBoardRotation: seed.isOdd,
          gravityScope:
              seed % 3 == 0 ? GravityScope.aboveCleared : GravityScope.wholeGlass,
          pauseIncomingDuringCascade: seed % 4 != 0,
        ),
      );
      final inputs = Random(seed);
      var steps = 0;
      while (!engine.isGameOver && steps < 6000) {
        steps++;
        switch (inputs.nextInt(10)) {
          case 0:
            engine.switchSide(inputs.nextBool() ? 1 : -1);
          case 1:
            engine.activateSide(Side.values[inputs.nextInt(4)]);
          case 2:
            engine.moveActive(inputs.nextInt(9) - 4);
          case 3:
            engine.rotateActive();
          case 4:
            engine.dropActive();
          case 5:
            engine.incoming.setColumn(engine.activeSide, inputs.nextInt(12) - 1, engine.board);
        }
        engine.update(inputs.nextDouble() * 0.08);

        final state = engine.state;
        final board = state.board;
        // No falling piece ever overlaps a settled block or leaves its glass.
        for (final piece in state.incoming.values) {
          expect(
            placement.fits(board, piece.side, piece.piece, piece.row, piece.column),
            isTrue,
            reason: 'seed $seed step $steps: $piece overlaps the board',
          );
        }
        // Blocks only ever lie inside the cross.
        for (final block in board.blocks) {
          expect(board.isInside(block.position.row, block.position.col), isTrue);
        }
        // Matched cells are counted when found and removed when popped.
        expect(
          board.blockCount,
          state.piecesPlaced * 3 -
              state.clearedCells +
              (state.activeMatch?.cells.length ?? 0),
        );
        if (state.phase == GamePhase.playing) {
          expect(state.incoming, hasLength(4));
          expect(state.activeMatch, isNull);
          expect(state.moves, isEmpty);
          expect(state.drop, isNull);
        }
      }
      expect(engine.state.piecesPlaced, greaterThan(0));
    }
  });

  test('a bot plays a whole game through the public inputs', () {
    final engine = GameEngine(
      config: const GameConfig(
        seed: 3,
        activeStepSeconds: 0.3,
        inactiveStepSeconds: 0.6,
      ),
    );
    final bot = BotPlayer(engine, profile: BotProfile.casual, random: Random(3));
    for (var i = 0; i < 60 * 600 && !engine.isGameOver; i++) {
      bot.tick(1 / 60);
      engine.update(1 / 60);
    }
    expect(engine.isGameOver, isTrue);
    expect(engine.state.piecesPlaced, greaterThan(5));
    expect(bot.decisions, greaterThan(0));
  });
}
