import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/engine/rotation_transform.dart';
import 'package:rotathree/game/model/board.dart';
import 'package:rotathree/game/model/color.dart';
import 'package:rotathree/game/model/piece.dart';
import 'package:rotathree/game/model/position.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/state/game_state.dart';

const r = BlockColor.red;
const b = BlockColor.blue;
const y = BlockColor.yellow;
const g = BlockColor.green;

/// Length of an arm in the test boards: the central square starts here.
const arm = 6;

/// Rows of a glass (arm + centre); its floor is row `glassDepth - 1`.
const glassDepth = 16;

/// A stick lying across the glass.
Piece horizontal(List<BlockColor> colors) => Piece(colors);

/// A stick standing along the direction of travel (first colour on top).
Piece vertical(List<BlockColor> colors) =>
    Piece(colors, orientation: PieceOrientation.vertical);

/// A cell of the central square, row 0 on top, as a world position.
CellPosition at(int row, int col) => CellPosition(arm + row, arm + col);

/// An empty cross with a 10×10 centre and arms of [arm] cells.
Board emptyBoard() => Board(center: 10, arm: arm);

/// A board whose central square has its bottom-left corner filled in, e.g.
/// `['R R . B']`.
Board boardOf(List<String> centerRows) => emptyBoard()..paintCenter(centerRows);

/// Deterministic test setup: arms of six cells, all four pieces start at the
/// far end; the active piece steps once a second, the others every three.
const testConfig = GameConfig(
  seed: 7,
  armLength: arm,
  initialProgressStagger: 0,
  activeStepSeconds: 1,
  inactiveStepSeconds: 3,
);

GameEngine newEngine({
  GameConfig config = testConfig,
  List<String> center = const [],
}) {
  final engine = GameEngine(config: config);
  if (center.isNotEmpty) engine.board.paintCenter(center);
  return engine;
}

GlassView glassOf(GameEngine engine, Side side) => GlassView(engine.board, side);

/// Runs the timed phases (drop flight, flash, pop, fall) to their end.
void runUntilPlaying(GameEngine engine) {
  var guard = 0;
  while (engine.phase != GamePhase.playing && !engine.isGameOver) {
    engine.update(0.002);
    if (++guard > 200000) fail('engine never returned to playing');
  }
}

/// Steps the engine and records every phase it passes through.
List<GamePhase> recordPhases(GameEngine engine) {
  final phases = <GamePhase>[engine.phase];
  var guard = 0;
  while (engine.phase != GamePhase.playing && !engine.isGameOver) {
    engine.update(0.002);
    if (engine.phase != phases.last) phases.add(engine.phase);
    if (++guard > 200000) fail('engine never returned to playing');
  }
  return phases;
}
