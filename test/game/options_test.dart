import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/config/zen_levels.dart';
import 'package:rotathree/game/engine/game_event.dart';
import 'package:rotathree/game/engine/match_detector.dart';
import 'package:rotathree/game/engine/piece_generator.dart';
import 'package:rotathree/game/model/color.dart';
import 'package:rotathree/game/model/side.dart';

import 'helpers.dart';

void main() {
  group('fewer glasses', () {
    test('two glasses are neighbours and every switch leads to the other one', () {
      final engine = newEngine(config: testConfig.copyWith(glassCount: 2));
      expect(engine.state.incoming.keys.toList(), [Side.top, Side.right]);
      engine.switchSide(-1); // nothing on the left: on round to the glass there is
      expect(engine.activeSide, Side.right);
      engine.switchSide(-1);
      expect(engine.activeSide, Side.top);
      engine.switchSide(1);
      expect(engine.activeSide, Side.right);
      engine.switchSide(2); // there is no glass opposite
      engine.activateSide(Side.bottom); // nor at the bottom
      expect(engine.activeSide, Side.right);
      // The cross turns the short way, whichever button was pressed.
      final turns = [
        for (final event in engine.drainEvents())
          if (event is SideSwitched) event.quarterTurns,
      ];
      expect(turns, [1, -1, 1]);
    });

    test('three glasses leave out the one opposite the start', () {
      final engine = newEngine(config: testConfig.copyWith(glassCount: 3));
      expect(engine.state.incoming.keys.toList(), [Side.top, Side.right, Side.left]);
      final visited = <Side>[];
      for (var i = 0; i < 3; i++) {
        engine.switchSide(1);
        visited.add(engine.activeSide);
      }
      expect(visited, [Side.right, Side.left, Side.top]);
      engine.switchSide(2);
      expect(engine.activeSide, Side.top); // nothing opposite the top
      engine.switchSide(-1);
      engine.switchSide(2);
      expect(engine.activeSide, Side.right); // left and right face each other
    });

    test('a locked piece is replaced in its own glass and no other appears', () {
      final engine = newEngine(config: testConfig.copyWith(glassCount: 2));
      engine.incoming.put(Side.top, horizontal([r, b, y]), column: 0);
      engine.dropActive();
      runUntilPlaying(engine);
      engine.update(30);
      expect(engine.state.incoming.keys.toSet(), {Side.top, Side.right});
      for (final block in engine.board.blocks) {
        // Nothing ever lands in the arms that are not in play.
        expect(block.position.row < arm + 10 && block.position.col >= arm, isTrue);
      }
    });

    test('the default is still all four', () {
      expect(const GameConfig().sides, Side.values);
      expect(newEngine().state.incoming.length, 4);
    });
  });

  group('soft drop', () {
    test('speeds up the fall but not the wait before locking', () {
      final engine = newEngine();
      final piece = engine.incoming.put(Side.top, horizontal([r, b, y]), column: 0, row: 5);
      engine.setSoftDrop(true);
      engine.update(0.5);
      expect(piece.row, 15); // ten rows in half a second
      engine.update(0.5);
      expect(engine.state.incoming[Side.top], same(piece)); // still there
      engine.update(0.6);
      expect(engine.board.at(arm + 9, arm), r);
    });

    test('does nothing to the glasses that are not active, and ends on restart', () {
      final engine = newEngine();
      engine.setSoftDrop(true);
      engine.update(0.5);
      expect(engine.state.incoming[Side.right]!.row, 0);
      expect(engine.state.incoming[Side.top]!.row, greaterThan(5));
      engine.restart();
      engine.update(0.5);
      expect(engine.state.incoming[Side.top]!.row, 0);
    });
  });

  group('six colours', () {
    test('the generator uses exactly the colours in play', () {
      for (final palette in [3, 4, 5, 6]) {
        final generator = PieceGenerator(GameConfig(seed: 3, numberOfColors: palette));
        final seen = <BlockColor>{};
        for (var i = 0; i < 400; i++) {
          seen.addAll(generator.next().colors);
        }
        expect(seen, BlockColor.values.take(palette).toSet());
      }
    });

    test('purple and white are painted and matched like any other', () {
      final board = boardOf(['P P P W G W']);
      expect(board.at(arm + 9, arm), BlockColor.purple);
      expect(board.at(arm + 9, arm + 3), BlockColor.white);
      final match = const MatchDetector(minLength: 3).find(board);
      expect(match.runs.map((run) => run.color), [BlockColor.purple]);
    });
  });

  group('events for the screen', () {
    test('a move against the wall and a turn with no room are reported as blocked', () {
      final engine = newEngine();
      engine.incoming.put(Side.top, horizontal([r, b, y]), column: 1, row: 10);
      engine.moveActive(-1);
      engine.moveActive(-1);
      final moves = engine.drainEvents().whereType<PieceMoved>().toList();
      expect(moves.map((move) => move.blocked), [false, true]);
      expect(moves.every((move) => move.direction == -1), isTrue);

      final glass = glassOf(engine, Side.top);
      for (var row = 8; row <= 14; row++) {
        glass.set(row, 3, row.isEven ? r : b);
        glass.set(row, 5, row.isEven ? b : r);
      }
      engine.incoming.put(Side.top, vertical([y, y, b]), column: 4, row: 10);
      engine.rotateActive();
      expect(engine.drainEvents().whereType<PieceRotated>().single.blocked, isTrue);
    });
  });

  group('zen levels', () {
    test('each level asks for a little more than the last', () {
      expect([1, 2, 3, 4].map(ZenLevels.target), [1000, 1500, 2000, 2500]);
      expect([1, 2, 3, 4].map(ZenLevels.start), [0, 1000, 2500, 4500]);
    });

    test('the level follows the total score', () {
      expect(ZenLevels.levelOf(0), 1);
      expect(ZenLevels.levelOf(999), 1);
      expect(ZenLevels.levelOf(1000), 2);
      expect(ZenLevels.levelOf(2499), 2);
      expect(ZenLevels.levelOf(2500), 3);
      // One big cascade can carry the score over more than one line.
      expect(ZenLevels.levelOf(4600), 4);
      for (var level = 1; level < 30; level++) {
        expect(ZenLevels.levelOf(ZenLevels.start(level)), level);
        expect(ZenLevels.levelOf(ZenLevels.start(level + 1) - 100), level);
      }
    });

    test('progress is counted inside the level and never runs past its target', () {
      expect(ZenLevels.into(0, 1), 0);
      expect(ZenLevels.into(1300, 2), 300);
      // Still shown as level 1 while the cascade that finished it plays out.
      expect(ZenLevels.into(1300, 1), 1000);
      expect(ZenLevels.into(900, 2), 0);
    });
  });
}
