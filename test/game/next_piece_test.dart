import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/model/side.dart';

import 'helpers.dart';

void main() {
  test('each glass spawns its own preview even when another glass locks first', () {
    final engine = newEngine();
    final next = {for (final side in engine.sides) side: engine.incoming.nextPieceAt(side)!};
    final generated = engine.incoming.generator.generated;
    engine.moveActive(1);
    engine.rotateActive();
    engine.switchSide(1);
    for (final side in engine.sides) {
      expect(engine.incoming.nextPieceAt(side), same(next[side]));
    }
    expect(engine.incoming.generator.generated, generated);
    for (final side in [Side.right, Side.bottom, Side.top, Side.left]) {
      engine.incoming.take(side);
      expect(engine.incoming.spawn(side, engine.board)!.piece, same(next[side]));
    }
  });

  test('a hard drop keeps the preview until it becomes the falling piece', () {
    final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 317));
    final next = engine.incoming.nextPieceAt(Side.top)!;
    engine.dropActive();
    expect(engine.incoming.nextPieceAt(Side.top), same(next));
    runUntilPlaying(engine);
    expect(engine.activePiece!.piece, same(next));
    expect(engine.incoming.nextPieceAt(Side.top), isNot(same(next)));
  });

  test('new campaign glasses get a queue when construction finishes', () {
    final engine = GameEngine(config: const GameConfig(glassCount: 1, seed: 317));
    final top = engine.incoming.nextPieceAt(Side.top);
    engine.addGlass();
    expect(engine.incoming.nextPieceAt(Side.right), isNull);
    runUntilPlaying(engine);
    expect(engine.incoming.nextPieceAt(Side.right), isNotNull);
    expect(engine.incoming.nextPieceAt(Side.top), same(top));
  });

  test('all previews and the future stream survive save and resume', () {
    final engine = newEngine();
    final restored = newEngine()..restoreSnapshot(jsonDecode(jsonEncode(engine.snapshot())));
    for (var turn = 0; turn < 12; turn++) {
      final side = engine.sides[turn % engine.sides.length];
      expect(restored.incoming.nextPieceAt(side), engine.incoming.nextPieceAt(side));
      final expected = engine.incoming.nextPieceAt(side);
      expect(engine.incoming.spawn(side, engine.board)!.piece, expected);
      expect(restored.incoming.spawn(side, restored.board)!.piece, expected);
      expect(restored.snapshot(), engine.snapshot());
    }
  });

  test('legacy saves keep current pieces and receive a persistent preview queue', () {
    final engine = newEngine();
    final raw = engine.snapshot()..remove('next');
    final restored = newEngine()..restoreSnapshot(raw);
    for (final side in engine.sides) {
      expect(restored.incoming.pieceAt(side)!.piece, engine.incoming.pieceAt(side)!.piece);
      expect(restored.incoming.nextPieceAt(side), isNotNull);
    }
    final again = newEngine()..restoreSnapshot(jsonDecode(jsonEncode(restored.snapshot())));
    expect(again.snapshot(), restored.snapshot());
  });

  test('invalid or incomplete preview queues cannot enter a save', () {
    final engine = newEngine();
    for (final bad in [[], [for (var i = 0; i < 4; i++) (engine.snapshot()['next'] as List).first]]) {
      final raw = engine.snapshot()..['next'] = bad;
      expect(() => engine.restoreSnapshot(raw), throwsFormatException);
    }
  });
}
