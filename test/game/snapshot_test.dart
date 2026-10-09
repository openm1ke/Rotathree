import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/model/color.dart';
import 'package:rotathree/game/model/piece.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/state/game_state.dart';

void checkContinuation(GameEngine engine) {
  final restored = GameEngine(config: const GameConfig(glassCount: 1, seed: 317));
  restored.restoreSnapshot(jsonDecode(jsonEncode(engine.snapshot())));
  engine.drainEvents();
  expect(restored.snapshot(), engine.snapshot());
  for (var i = 0; i < 600 && !engine.isGameOver; i++) {
    if (i % 50 == 0) {
      engine.dropActive();
      restored.dropActive();
    }
    engine.update(0.05);
    restored.update(0.05);
    if (!engine.isGameOver) expect(restored.snapshot(), engine.snapshot());
    expect(restored.isGameOver, engine.isGameOver);
  }
}

void main() {
  test('resume preserves double-tap protection after a short drop', () {
    const config = GameConfig(glassCount: 1, seed: 317);
    final engine = GameEngine(config: config);
    engine.update(1.1);
    engine.incoming.put(Side.top, Piece([BlockColor.red, BlockColor.blue, BlockColor.yellow]),
        row: config.armLength + config.boardSize - 1);
    engine.dropActive();
    final restored = GameEngine(config: config)..restoreSnapshot(jsonDecode(jsonEncode(engine.snapshot())));
    restored.update(0.1);
    expect(restored.phase, GamePhase.playing);
    restored.dropActive();
    expect(restored.phase, GamePhase.playing);
    expect(restored.state.piecesPlaced, 1);
    restored.update(0.21);
    restored.dropActive();
    expect(restored.phase, GamePhase.pieceDropping);
  });

  test('old saves load but their buffered drops are discarded', () {
    const config = GameConfig(glassCount: 1, seed: 317);
    final engine = GameEngine(config: config);
    engine.incoming.put(Side.top, Piece([BlockColor.red, BlockColor.blue, BlockColor.yellow]));
    engine.dropActive();
    final raw = engine.snapshot()..remove('dropCooldown');
    raw['inputs'] = [
      {'kind': 'drop'},
      {'kind': 'move', 'value': 1},
    ];
    final restored = GameEngine(config: config)..restoreSnapshot(raw);
    restored.update(0.5);
    expect(restored.phase, GamePhase.playing);
    expect(restored.state.piecesPlaced, 1);
    expect(restored.activePiece!.column, restored.incoming.spawnColumn + 1);
  });

  test('resume keeps an in-flight drop, queued input and future pieces', () {
    final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 317));
    engine.dropActive();
    engine.moveActive(1);
    engine.rotateActive();
    engine.update(0.02);
    checkContinuation(engine);
  });
  test('resume does not score a pending match twice', () {
    final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 317));
    engine.incoming.put(Side.top, Piece([BlockColor.red, BlockColor.red, BlockColor.red]));
    engine.dropActive();
    engine.update(0.21);
    expect(engine.phase, GamePhase.matching);
    checkContinuation(engine);
  });
  test('resume completes a glass being built exactly once', () {
    final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 317));
    engine.addGlass();
    engine.switchSide(1);
    engine.update(0.5);
    checkContinuation(engine);
  });
  test('invalid saves cannot inject cells outside the field', () {
    final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 317));
    final raw = engine.snapshot();
    raw['board'] = [
      [0, 0, 0],
    ];
    expect(() => engine.restoreSnapshot(raw), throwsFormatException);
  });
  test('every animation phase of a clearing match can be resumed', () {
    const config = GameConfig(glassCount: 1, seed: 317);
    final engine = GameEngine(config: config);
    engine.board.paintCenter(['. Y . . . . . . . .', 'B . . . . . . . . .', 'R R . . . . . . . .']);
    engine.incoming.put(Side.top, Piece([BlockColor.red, BlockColor.blue, BlockColor.yellow]), column: 2);
    engine.dropActive();
    final visited = <GamePhase>{};
    for (var i = 0; i < 70; i++) {
      visited.add(engine.phase);
      final restored = GameEngine(config: config)..restoreSnapshot(jsonDecode(jsonEncode(engine.snapshot())));
      engine.update(0.05);
      restored.update(0.05);
      expect(restored.snapshot(), engine.snapshot());
    }
    expect(visited, {
      GamePhase.pieceDropping,
      GamePhase.matching,
      GamePhase.clearing,
      GamePhase.settling,
      GamePhase.playing,
    });
  });
}
