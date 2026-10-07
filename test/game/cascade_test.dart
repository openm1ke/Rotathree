import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/config/score_rules.dart';
import 'package:rotathree/game/engine/cascade_resolver.dart';
import 'package:rotathree/game/engine/game_event.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/state/game_state.dart';

import 'helpers.dart';

void main() {
  group('ScoreRules', () {
    const rules = ScoreRules();

    test('longer lines are worth more', () {
      expect(rules.scoreForRun(3, 1), 100);
      expect(rules.scoreForRun(4, 1), 200);
      expect(rules.scoreForRun(5, 1), 300);
      expect(rules.scoreForRun(6, 1), 400);
      expect(rules.scoreForRun(2, 1), 0);
    });

    test('the combo level multiplies the line value', () {
      expect(rules.scoreForRun(3, 2), 200);
      expect(rules.scoreForRun(4, 3), 600);
    });
  });

  group('CascadeResolver', () {
    final resolver = CascadeResolver(const GameConfig());

    test('a stable board resolves to nothing', () {
      final board = boardOf(['R B R', 'B R B']);
      final result = resolver.resolve(board, Side.top);
      expect(result.isEmpty, isTrue);
      expect(result.maxCombo, 0);
    });

    test('match → pop → fall → second match gives combo 2', () {
      // The red column pops, the blue block on top of it falls into the gap
      // of the bottom row and completes four blues.
      final board = boardOf([
        '. . B .',
        '. . R .',
        '. . R .',
        'B B R B',
      ]);
      final result = resolver.resolve(board, Side.top);

      expect(result.maxCombo, 2);
      expect(result.steps[0].combo, 1);
      expect(result.steps[0].match.cells, {at(7, 2), at(8, 2), at(9, 2)});
      expect(result.steps[0].score, 100);
      expect(result.steps[0].moves.single.from, at(6, 2));
      expect(result.steps[0].moves.single.to, at(9, 2));
      expect(result.steps[1].combo, 2);
      expect(result.steps[1].match.runs.single.length, 4);
      expect(result.steps[1].score, 200 * 2);
      expect(result.totalScore, 500);
      expect(board.isEmpty, isTrue);
    });

    test('lines popped in the same round share one combo level', () {
      final board = boardOf([
        'Y Y Y . . . .',
        'B R B . R R R',
      ]);
      final result = resolver.resolve(board, Side.top);
      expect(result.maxCombo, 1);
      expect(result.runCount, 2);
      expect(result.totalScore, 200);
      expect(board.centerRows().last, 'B R B . . . . . . .');
    });

    test('three rounds give combo 3', () {
      // Reds pop → B lands next to "B B" (combo 2) → Y lands next to "Y Y"
      // (combo 3).
      final board = boardOf([
        '. . Y . .',
        '. . B . .',
        '. . R . .',
        '. . R . .',
        'Y Y R B B',
      ]);
      final result = resolver.resolve(board, Side.top);
      expect(result.maxCombo, 3);
      expect(result.totalScore, 100 + 100 * 2 + 100 * 3);
      expect(board.isEmpty, isTrue);
    });
  });

  group('cascade inside the engine', () {
    test('dropping the piece that starts a cascade reaches combo 2', () {
      final engine = newEngine(center: ['B B R B']);
      engine.incoming.put(Side.top, vertical([b, r, r]), column: 2);

      engine.dropActive();
      expect(engine.phase, GamePhase.pieceDropping);
      final phases = recordPhases(engine);

      expect(phases, [
        GamePhase.pieceDropping,
        GamePhase.matching,
        GamePhase.clearing,
        GamePhase.settling,
        GamePhase.cascading,
        GamePhase.clearing,
        GamePhase.playing,
      ]);
      expect(engine.state.bestCombo, 2);
      expect(engine.state.combo, 0); // chain is over
      expect(engine.state.score, 500);
      expect(engine.state.matches, 2);
      expect(engine.state.clearedCells, 7);
      expect(engine.board.isEmpty, isTrue);

      final events = engine.drainEvents();
      expect(events.whereType<MatchScored>().map((e) => e.combo), [1, 2]);
      expect(events.whereType<CellsPopped>().map((e) => e.cells.length), [3, 4]);
    });

    test('falling takes longer the further a block has to fall', () {
      double fallPhaseSeconds({required bool withHighBlock}) {
        final engine = newEngine(center: ['B B R B']);
        // A block hanging at the top of the centre falls nine rows when the
        // glass settles; the blue one above the reds only three.
        if (withHighBlock) engine.board.set(arm, arm + 7, y);
        engine.incoming.put(Side.top, vertical([b, r, r]), column: 2);
        engine.dropActive();
        while (engine.phase != GamePhase.settling) {
          engine.update(0.002);
        }
        return engine.state.phaseDuration;
      }

      final near = fallPhaseSeconds(withHighBlock: false);
      final far = fallPhaseSeconds(withHighBlock: true);
      expect(near, closeTo(testConfig.fallPhaseSeconds(3), 1e-9));
      expect(far, closeTo(testConfig.fallPhaseSeconds(9), 1e-9));
      expect(testConfig.fallSeconds(9), greaterThan(testConfig.fallSeconds(3)));
      expect(far, greaterThan(near));
    });

    test('the animated engine ends on the same board as the resolver', () {
      const rows = [
        '. . Y . .',
        '. . B . .',
        'Y Y . B B',
      ];
      final engine = newEngine(center: rows);
      engine.incoming.put(Side.top, vertical([r, r, r]), column: 7);
      engine.dropActive();
      runUntilPlaying(engine);

      final reference = boardOf(rows);
      for (final row in [7, 8, 9]) {
        reference.set(arm + row, arm + 7, r);
      }
      CascadeResolver(engine.config).resolve(reference, Side.top);
      expect(engine.board.sameAs(reference), isTrue);
    });

    test('a placement without a match goes straight back to playing', () {
      final engine = newEngine();
      engine.incoming.put(Side.top, horizontal([r, b, y]), column: 0);
      engine.dropActive();
      expect(recordPhases(engine), [GamePhase.pieceDropping, GamePhase.playing]);
      expect(engine.state.score, 0);
      expect(engine.board.centerRows().last, 'R B Y . . . . . . .');
    });
  });
}
