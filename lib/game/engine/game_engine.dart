import 'dart:math';

import '../config/game_config.dart';
import '../model/board.dart';
import '../model/cell.dart';
import '../model/incoming_piece.dart';
import '../model/color.dart';
import '../model/piece.dart';
import '../model/position.dart';
import '../model/side.dart';
import '../state/game_state.dart';
import 'game_event.dart';
import 'gravity_resolver.dart';
import 'incoming_controller.dart';
import 'match_detector.dart';
import 'piece_generator.dart';
import 'placement_engine.dart';
import 'speed_ramp.dart';
import 'snapshot_reader.dart';

const _epsilon = 1e-9;

/// A player action, queued while the board is busy.
sealed class _Input {
  const _Input();
}

final class _Turn extends _Input {
  const _Turn(this.quarterTurns);

  final int quarterTurns;
}

final class _Activate extends _Input {
  const _Activate(this.side);

  final Side side;
}

final class _Move extends _Input {
  const _Move(this.delta);

  final int delta;
}

final class _Rotate extends _Input {
  const _Rotate(this.clockwise);

  final bool clockwise;
}

final class _Drop extends _Input {
  const _Drop();
}

/// The whole game, independent of any UI.
///
/// Rules in short:
///  * the playfield is a cross: a central square and four arms. Each side owns
///    a glass — its arm plus the central square — and the glasses share the
///    centre. One to four of them are in play; a glass can be added later;
///  * the pieces fall at the same time, one per glass, a whole cell per step —
///    quickly in the active glass, slowly in the others — through the arm and
///    on through the centre. A piece whose next step is blocked locks instead;
///  * the player turns the cross to pick the active glass, slides and rotates
///    its piece and can drop it;
///  * lines of 3+ of a colour pop, the blocks above them fall and cascades
///    raise the combo multiplier;
///  * a glass that is full up to the far end of its arm ends the game.
///
/// Time only moves through [update].
class GameEngine {
  GameEngine({required GameConfig config, Random? random})
    : _startConfig = config,
      _config = config,
      incoming = IncomingController(config, PieceGenerator(config, random)) {
    restart();
  }

  final GameConfig _startConfig;
  GameConfig _config;
  final PlacementEngine _placement = const PlacementEngine();
  final GravityResolver _gravity = const GravityResolver();

  /// Falling pieces, one per glass in play.
  final IncomingController incoming;

  final List<_Input> _inputs = [];
  final List<GameEvent> _events = [];

  /// Glasses whose piece has locked and that get a new one as soon as the
  /// board has come to rest.
  final List<Side> _awaitingPiece = [];
  List<Side> _sides = const [];
  SpeedRamp? _ramp;
  double _rampBaseActive = 1;
  double _rampBaseInactive = 3;

  late GameState state;
  int _boardVersion = 0;

  /// Step times may change during a game (see [setSteps] and [setRamp]).
  GameConfig get config => _config;

  /// The glasses in play, in the order they came into play. Read-only.
  List<Side> get sides => _sides;

  Board get board => state.board;
  Side get activeSide => state.activeSide;
  GamePhase get phase => state.phase;
  bool get isGameOver => state.phase == GamePhase.gameOver;

  IncomingPiece? get activePiece => incoming.pieceAt(state.activeSide);

  /// True while falling pieces are frozen for a match or a new glass.
  bool get incomingPaused {
    if (!_config.pauseIncomingDuringCascade) return false;
    return switch (state.phase) {
      GamePhase.matching ||
      GamePhase.clearing ||
      GamePhase.settling ||
      GamePhase.cascading ||
      GamePhase.building => true,
      _ => false,
    };
  }

  void restart() {
    _config = _startConfig;
    _rampBaseActive = _config.activeStepSeconds;
    _rampBaseInactive = _config.inactiveStepSeconds;
    _sides = _startConfig.sides;
    incoming.setConfig(_config);
    _inputs.clear();
    _events.clear();
    _awaitingPiece.clear();
    incoming.reset(_sides);
    state = GameState(
      board: Board(center: _config.boardSize, arm: _config.armLength),
      incoming: incoming.pieces,
      activeSide: _sides.first,
    );
    _changedBoard();
  }

  /// Returns the events raised since the last call and forgets them.
  List<GameEvent> drainEvents() {
    final events = List<GameEvent>.of(_events);
    _events.clear();
    return events;
  }

  /// Includes in-flight drops, cascades and queued input: closing the app
  /// during an animation must not lose or duplicate a placed piece.
  Map<String, Object?> snapshot() => {
    'version': 1,
    'center': board.center,
    'arm': board.arm,
    'board': [
      for (final b in board.blocks) [b.position.row, b.position.col, b.color.index],
    ],
    'sides': [for (final side in _sides) side.index],
    'activeSide': activeSide.index,
    'incoming': [
      for (final p in incoming.pieces.values)
        {
          'side': p.side.index,
          'piece': _pieceJson(p.piece),
          'row': p.row,
          'column': p.column,
          'progress': p.stepProgress,
        },
    ],
    'phase': phase.index,
    'phaseElapsed': state.phaseElapsed,
    'phaseDuration': state.phaseDuration,
    'score': state.score,
    'combo': state.combo,
    'bestCombo': state.bestCombo,
    'matches': state.matches,
    'clearedCells': state.clearedCells,
    'piecesPlaced': state.piecesPlaced,
    'selfLocked': state.selfLocked,
    'elapsedSeconds': state.elapsedSeconds,
    'speedLevel': state.speedLevel,
    'buildingSide': state.buildingSide?.index,
    'drop': state.drop == null
        ? null
        : {
            'side': state.drop!.placement.side.index,
            'piece': _pieceJson(state.drop!.placement.piece),
            'column': state.drop!.placement.column,
            'row': state.drop!.placement.row,
            'startRow': state.drop!.startRow,
          },
    'moves': [
      for (final m in state.moves) [m.from.row, m.from.col, m.to.row, m.to.col, m.color.index],
    ],
    'waiting': [for (final side in _awaitingPiece) side.index],
    'inputs': [
      for (final input in _inputs)
        switch (input) {
          _Turn(:final quarterTurns) => {'kind': 'turn', 'value': quarterTurns},
          _Activate(:final side) => {'kind': 'activate', 'value': side.index},
          _Move(:final delta) => {'kind': 'move', 'value': delta},
          _Rotate(:final clockwise) => {'kind': 'rotate', 'value': clockwise},
          _Drop() => {'kind': 'drop'},
        },
    ],
    'activeStep': config.activeStepSeconds,
    'inactiveStep': config.inactiveStepSeconds,
    'rampBaseActive': _rampBaseActive,
    'rampBaseInactive': _rampBaseInactive,
    'randomSeed': incoming.generator.seed,
    'generated': incoming.generator.generated,
  };

  void restoreSnapshot(Object? raw) {
    final r = SnapshotReader(raw);
    if (r.integer('version', max: 1) != 1 || r.integer('center') != board.center || r.integer('arm') != board.arm) {
      throw const FormatException('Incompatible game save');
    }
    final restoredBoard = Board(center: board.center, arm: board.arm);
    final occupied = <CellPosition>{};
    for (final rawCell in r.list('board', max: board.size * board.size)) {
      final c = _tuple(rawCell, 3);
      final pos = CellPosition(c[0], c[1]);
      if (!restoredBoard.isInside(pos.row, pos.col) ||
          !occupied.add(pos) ||
          c[2] < 0 ||
          c[2] >= config.numberOfColors) {
        throw const FormatException('Invalid board cell');
      }
      restoredBoard.set(pos.row, pos.col, BlockColor.values[c[2]]);
    }
    final sides = r.list('sides', max: 4).map(_readSide).toList();
    if (sides.isEmpty || sides.toSet().length != sides.length) throw const FormatException('Invalid glasses');
    final active = _readSide(r.data['activeSide']);
    if (!sides.contains(active)) throw const FormatException('Invalid active glass');
    final phase = GamePhase.values[r.integer('phase', max: GamePhase.values.length - 2)];
    final restored = GameState(board: restoredBoard, incoming: incoming.pieces, activeSide: active)
      ..phase = phase
      ..phaseElapsed = r.number('phaseElapsed', max: 60)
      ..phaseDuration = r.number('phaseDuration', max: 60)
      ..score = r.integer('score')
      ..combo = r.integer('combo')
      ..bestCombo = r.integer('bestCombo')
      ..matches = r.integer('matches')
      ..clearedCells = r.integer('clearedCells')
      ..piecesPlaced = r.integer('piecesPlaced')
      ..selfLocked = r.integer('selfLocked')
      ..elapsedSeconds = r.number('elapsedSeconds')
      ..speedLevel = r.integer('speedLevel');
    if (restored.phaseElapsed > restored.phaseDuration) throw const FormatException('Invalid phase time');
    final building = r.data['buildingSide'];
    restored.buildingSide = building == null ? null : _readSide(building);
    if (phase == GamePhase.building && (restored.buildingSide == null || !sides.contains(restored.buildingSide))) {
      throw const FormatException('Invalid building glass');
    }
    final rawDrop = r.data['drop'];
    if (rawDrop != null) {
      final d = SnapshotReader(rawDrop);
      final side = _readSide(d.data['side']);
      final piece = _readPiece(d.data['piece']);
      final row = d.integer('row', max: config.glassDepth - 1);
      final column = d.integer('column', max: config.boardSize - 1);
      if (!sides.contains(side) || !_placement.fits(restoredBoard, side, piece, row, column)) {
        throw const FormatException('Invalid drop');
      }
      restored.drop = DropInFlight(
        placement: _placement.placementAt(restoredBoard, side, piece, column, row),
        startRow: d.integer('startRow', max: row),
      );
    }
    if ((phase == GamePhase.pieceDropping) != (restored.drop != null)) throw const FormatException('Missing drop');
    if (phase == GamePhase.matching || phase == GamePhase.clearing || phase == GamePhase.cascading) {
      restored.activeMatch = MatchDetector(minLength: config.minMatchLength).find(restoredBoard);
      if (restored.activeMatch!.isEmpty) throw const FormatException('Missing match');
    }
    restored.moves = [
      for (final rawMove in r.list('moves', max: board.size * board.size)) _readMove(rawMove, restoredBoard),
    ];
    final waiting = r.list('waiting', max: 4).map(_readSide).toList();
    if (waiting.any((s) => !sides.contains(s))) throw const FormatException('Invalid waiting glass');
    final pieces = <IncomingPiece>[];
    for (final rawPiece in r.list('incoming', max: 4)) {
      final p = SnapshotReader(rawPiece);
      final side = _readSide(p.data['side']);
      final piece = _readPiece(p.data['piece']);
      final row = p.integer('row', max: config.glassDepth - 1);
      final column = p.integer('column', max: config.boardSize - 1);
      if (!sides.contains(side) ||
          pieces.any((p) => p.side == side) ||
          !_placement.fits(restoredBoard, side, piece, row, column)) {
        throw const FormatException('Invalid incoming piece');
      }
      pieces.add(
        IncomingPiece(side: side, piece: piece, column: column, row: row, stepProgress: p.number('progress', max: 1)),
      );
    }
    final inputs = [for (final input in r.list('inputs', max: config.maxQueuedInputs)) _readInput(input)];
    final partition = [
      for (final p in pieces) p.side,
      ...waiting,
      if (restored.drop != null) restored.drop!.placement.side,
      if (phase == GamePhase.building) restored.buildingSide!,
    ];
    if (partition.length != sides.length || partition.toSet().length != sides.length) {
      throw const FormatException('Incomplete saved glasses');
    }
    final activeStep = r.number('activeStep', min: 0.01, max: 60);
    final inactiveStep = r.number('inactiveStep', min: 0.01, max: 60);
    final baseActive = r.number('rampBaseActive', min: 0.01, max: 60);
    final baseInactive = r.number('rampBaseInactive', min: 0.01, max: 60);
    final seed = r.integer('randomSeed', max: 1 << 32);
    final generated = r.integer('generated', max: 100000);
    setSteps(activeStep, inactiveStep);
    _rampBaseActive = baseActive;
    _rampBaseInactive = baseInactive;
    incoming.generator.restore(seed, generated);
    incoming.pieces.clear();
    for (final p in pieces) {
      incoming.pieces[p.side] = p;
    }
    incoming.softDrop = false;
    _sides = sides;
    _awaitingPiece
      ..clear()
      ..addAll(waiting);
    _inputs
      ..clear()
      ..addAll(inputs);
    _events.clear();
    state = restored;
    _changedBoard();
  }

  Map<String, Object> _pieceJson(Piece p) => {
    'colors': [for (final c in p.colors) c.index],
    'orientation': p.orientation.index,
  };
  Piece _readPiece(Object? raw) {
    final r = SnapshotReader(raw);
    final colors = r.list('colors', max: config.pieceLength);
    if (colors.length != config.pieceLength || colors.any((c) => c is! int || c < 0 || c >= config.numberOfColors)) {
      throw const FormatException('Invalid piece');
    }
    return Piece([
      for (final c in colors) BlockColor.values[c as int],
    ], orientation: PieceOrientation.values[r.integer('orientation', max: 3)]);
  }

  Side _readSide(Object? value) {
    if (value is! int || value < 0 || value > 3) throw const FormatException('Invalid side');
    return Side.values[value];
  }

  List<int> _tuple(Object? raw, int length) {
    if (raw is! List || raw.length != length || raw.any((v) => v is! int)) {
      throw const FormatException('Invalid coordinates');
    }
    return List<int>.from(raw);
  }

  BlockMove _readMove(Object? raw, Board board) {
    final m = _tuple(raw, 5);
    if (!board.isInside(m[0], m[1]) || !board.isInside(m[2], m[3]) || m[4] < 0 || m[4] >= config.numberOfColors) {
      throw const FormatException('Invalid block move');
    }
    return BlockMove(CellPosition(m[0], m[1]), CellPosition(m[2], m[3]), BlockColor.values[m[4]]);
  }

  _Input _readInput(Object? raw) {
    final r = SnapshotReader(raw);
    return switch (r.data['kind']) {
      'turn' => _Turn(r.integer('value', min: -2, max: 2)),
      'activate' => _Activate(_readSide(r.data['value'])),
      'move' => _Move(r.integer('value', min: -config.boardSize, max: config.boardSize)),
      'rotate' when r.data['value'] is bool => _Rotate(r.data['value'] as bool),
      'drop' => const _Drop(),
      _ => throw const FormatException('Invalid input'),
    };
  }

  // ------------------------------------------------------------- settings

  /// Changes the step times from now on. Pieces keep their progress.
  void setSteps(double activeStepSeconds, double inactiveStepSeconds) {
    _config = _config.copyWith(activeStepSeconds: activeStepSeconds, inactiveStepSeconds: inactiveStepSeconds);
    incoming.setConfig(_config);
  }

  /// Makes the speed rise with the score (or stops it when null). The current
  /// step times are the ones it starts from.
  void setRamp(SpeedRamp? ramp) {
    _ramp = ramp;
    _rampBaseActive = _config.activeStepSeconds;
    _rampBaseInactive = _config.inactiveStepSeconds;
    state.speedLevel = 0;
  }

  /// Brings the next glass into play: its arm grows, and its first piece
  /// appears at the far end once the building phase is over. Returns the
  /// glass, or null when all four are in play or the board is busy.
  Side? addGlass() {
    if (state.phase != GamePhase.playing) return null;
    Side? side;
    for (final candidate in glassOrder) {
      if (!_sides.contains(candidate)) {
        side = candidate;
        break;
      }
    }
    if (side == null) return null;
    _sides = [..._sides, side];
    state.buildingSide = side;
    _enterPhase(GamePhase.building, _config.buildSeconds);
    return side;
  }

  // ------------------------------------------------------------- queries

  /// Where the piece of [side] comes to rest if it falls straight down from
  /// where it is; null when that glass has no piece at the moment.
  Placement? previewDrop(Side side) {
    final piece = incoming.pieceAt(side);
    if (piece == null) return null;
    return _placement.placementAt(board, side, piece.piece, piece.column, incoming.restRow(piece, board));
  }

  /// The row where the piece of [side] comes to rest if it falls straight
  /// down; null when that glass has no piece at the moment.
  int? restRow(Side side) {
    final piece = incoming.pieceAt(side);
    return piece == null ? null : incoming.restRow(piece, board);
  }

  /// Seconds until the piece of [side] locks if it is left alone.
  double? secondsToLock(Side side) {
    final piece = incoming.pieceAt(side);
    return piece == null ? null : incoming.secondsToLock(piece, board, activeSide);
  }

  /// Free rows at the far end of the glass of [side], in the lanes where its
  /// pieces appear. At 0 the next piece has no room and the game ends.
  int headroom(Side side) => _placement.headroom(board, side, incoming.spawnColumn, _config.pieceLength);

  /// True when the glass of [side] is close to overflowing.
  bool isCrowded(Side side) => headroom(side) <= _config.crowdedHeadroom;

  // ---------------------------------------------------------------- input

  /// Turns the cross: ±1 goes on to the next glass in play, 2 goes to the
  /// glass opposite if there is one.
  void switchSide(int quarterTurns) => _submit(_Turn(quarterTurns));

  /// Makes [side] the active one, turning the short way round.
  void activateSide(Side side) => _submit(_Activate(side));

  /// Slides the active piece across its glass.
  void moveActive(int delta) => _submit(_Move(delta));

  /// Turns the active piece a quarter turn.
  void rotateActive({bool clockwise = true}) => _submit(_Rotate(clockwise));

  /// Sends the active piece straight down to where it lands.
  void dropActive() => _submit(const _Drop());

  /// Holds or releases soft drop: while held, the active piece steps fast.
  void setSoftDrop(bool held) => incoming.softDrop = held;

  void _submit(_Input input) {
    if (isGameOver) return;
    if (state.phase == GamePhase.playing && _inputs.isEmpty) {
      _apply(input);
      return;
    }
    if (_inputs.length < _config.maxQueuedInputs) _inputs.add(input);
  }

  void _flushInputs() {
    while (_inputs.isNotEmpty && state.phase == GamePhase.playing) {
      _apply(_inputs.removeAt(0));
    }
  }

  void _apply(_Input input) {
    final side = activeSide;
    switch (input) {
      case _Turn turn:
        _turnTo(_sideAfter(side, turn.quarterTurns));
      case _Activate activate:
        if (_sides.contains(activate.side)) _turnTo(activate.side);
      case _Move move:
        if (incoming.pieceAt(side) == null) break;
        final moved = incoming.move(side, move.delta, board);
        _events.add(PieceMoved(side, direction: move.delta.sign, blocked: moved < move.delta.abs()));
      case _Rotate rotate:
        if (incoming.pieceAt(side) == null) break;
        final turned = incoming.rotate(side, board, clockwise: rotate.clockwise);
        _events.add(PieceRotated(side, blocked: !turned));
      case _Drop():
        _beginDrop();
    }
  }

  /// The glass a turn of [quarterTurns] leads to from [side]. A single step
  /// skips the sides that are not in play; any other turn only happens when a
  /// glass is exactly there.
  Side _sideAfter(Side side, int quarterTurns) {
    if (quarterTurns.abs() != 1) {
      final to = side.turned(quarterTurns);
      return _sides.contains(to) ? to : side;
    }
    var to = side.turned(quarterTurns);
    while (!_sides.contains(to)) {
      to = to.turned(quarterTurns);
    }
    return to;
  }

  void _turnTo(Side to) {
    final from = activeSide;
    if (to == from) return;
    state.activeSide = to;
    // The cross always turns the short way round.
    _events.add(SideSwitched(from: from, to: to, quarterTurns: from.stepsTo(to)));

    // By default the structure turns as one rigid body and nothing falls.
    if (!_config.settleAfterBoardRotation) return;
    final moves = _gravity.settle(board, to);
    if (moves.isEmpty) return;
    state.combo = 0;
    _startFalling(moves);
  }

  // ----------------------------------------------------------------- time

  /// Advances the game by [seconds] of game time.
  void update(double seconds) {
    var left = seconds;
    while (left > _epsilon && !isGameOver) {
      if (state.phase == GamePhase.playing) {
        final next = incoming.secondsToNextStep(activeSide, board);
        if (next == null || next > left) {
          _advanceClock(left);
          left = 0;
        } else {
          _advanceClock(next);
          left -= next;
          _stepDuePieces();
        }
      } else {
        final remaining = state.phaseDuration - state.phaseElapsed;
        final step = min(left, max(remaining, 0.0));
        state.phaseElapsed += step;
        _advanceClock(step);
        left -= step;
        if (state.phaseElapsed >= state.phaseDuration - _epsilon) _completePhase();
      }
    }
  }

  void _advanceClock(double seconds) {
    state.elapsedSeconds += seconds;
    if (!incomingPaused) incoming.advance(seconds, activeSide, board);
  }

  /// Every piece whose step is due moves one row down. The first one that
  /// cannot move locks where it is; the board then changes, so any others
  /// still due wait until play resumes.
  void _stepDuePieces() {
    for (final side in incoming.dueSides(activeSide)) {
      if (incoming.step(side, board)) {
        _events.add(PieceStepped(side));
        continue;
      }
      final piece = incoming.take(side)!;
      state.selfLocked++;
      _commit(_placement.placementAt(board, side, piece.piece, piece.column, piece.row), dropped: false);
      return;
    }
  }

  void _beginDrop() {
    final piece = activePiece;
    if (piece == null) return;
    final placement = previewDrop(piece.side)!;
    incoming.take(piece.side);
    final cells = placement.row - piece.row;
    state.drop = DropInFlight(placement: placement, startRow: piece.row);
    _events.add(PieceDropped(piece.side, cells: cells));
    _enterPhase(GamePhase.pieceDropping, _config.dropSeconds(cells));
  }

  /// Writes a piece into the board and resolves what follows from it.
  void _commit(Placement placement, {required bool dropped}) {
    for (final cell in placement.cells) {
      board.set(cell.position.row, cell.position.col, cell.color);
    }
    _changedBoard();
    state.piecesPlaced++;
    state.combo = 0;
    _awaitingPiece.add(placement.side);
    _events.add(PieceLanded(placement, dropped: dropped));
    if (!_makeRoomForFallingPieces()) return;
    _checkMatches();
  }

  /// Falling pieces pass through each other, so a block that has just appeared
  /// may sit inside one of them; such a piece backs off towards its own arm.
  /// Returns false when one of them has nowhere to go: game over.
  bool _makeRoomForFallingPieces() {
    final crushed = incoming.resolveOverlaps(board);
    if (crushed.isEmpty) return true;
    _endGame(crushed.first);
    return false;
  }

  void _completePhase() {
    final s = state;
    switch (s.phase) {
      case GamePhase.pieceDropping:
        final drop = s.drop!;
        s.drop = null;
        _commit(drop.placement, dropped: true);
      case GamePhase.matching:
      case GamePhase.cascading:
        _enterPhase(GamePhase.clearing, _config.clearPhaseSeconds);
      case GamePhase.clearing:
        final match = s.activeMatch!;
        _events.add(CellsPopped([for (final cell in match.cells) PlacedCell(cell, board.colorAt(cell)!)]));
        for (final cell in match.cells) {
          board.set(cell.row, cell.col, null);
        }
        _changedBoard();
        s.activeMatch = null;
        final moves = _gravity.settle(board, s.activeSide, scope: _config.gravityScope, cleared: match.cells);
        if (moves.isEmpty) {
          _checkMatches();
        } else {
          _startFalling(moves);
        }
      case GamePhase.settling:
        s.moves = const [];
        _checkMatches();
      case GamePhase.building:
        final side = s.buildingSide!;
        s.buildingSide = null;
        // The arm is empty, so the first piece always finds room.
        incoming.spawn(side, board);
        _events.add(GlassAdded(side));
        _enterPhase(GamePhase.playing, 0);
        _flushInputs();
      case GamePhase.playing:
      case GamePhase.gameOver:
        break;
    }
  }

  /// Blocks have been moved to where they fall; show them falling.
  void _startFalling(List<BlockMove> moves) {
    state.moves = moves;
    _changedBoard();
    final furthest = moves.fold<int>(0, (far, move) => max(far, move.distance));
    _events.add(BlocksFell(moves));
    _enterPhase(GamePhase.settling, _config.fallPhaseSeconds(furthest));
    _makeRoomForFallingPieces();
  }

  void _checkMatches() {
    final s = state;
    final match = MatchDetector(minLength: _config.minMatchLength).find(board);
    if (match.isEmpty) {
      _finishResolution();
      return;
    }
    s.combo++;
    if (s.combo > s.bestCombo) s.bestCombo = s.combo;
    final score = _scoreFor(match, s.combo);
    s.score += score;
    s.matches += match.runs.length;
    s.clearedCells += match.cells.length;
    s.activeMatch = match;
    _events.add(MatchScored(combo: s.combo, score: score, match: match));
    _applyRamp();
    _enterPhase(s.combo == 1 ? GamePhase.matching : GamePhase.cascading, _config.matchPhaseSeconds);
  }

  int _scoreFor(MatchResult match, int combo) {
    var score = 0;
    for (final run in match.runs) {
      score += _config.scoring.scoreForRun(run.length, combo, minMatchLength: _config.minMatchLength);
    }
    return score;
  }

  /// Steps the speed up when the score has passed another multiple of the
  /// ramp's interval.
  void _applyRamp() {
    final ramp = _ramp;
    if (ramp == null) return;
    final level = state.score ~/ ramp.everyPoints;
    if (level == state.speedLevel) return;
    state.speedLevel = level;
    final factor = pow(ramp.factor, level).toDouble();
    final activeStep = max(ramp.minActive, _rampBaseActive * factor);
    final inactiveStep = max(ramp.minInactive, _rampBaseInactive * factor);
    setSteps(activeStep, inactiveStep);
    _events.add(SpeedUp(level: level, activeStep: activeStep, inactiveStep: inactiveStep));
  }

  void _finishResolution() {
    state.combo = 0;
    _enterPhase(GamePhase.playing, 0);

    // The board is at rest: refill the glasses whose piece has locked.
    final waiting = List<Side>.of(_awaitingPiece);
    _awaitingPiece.clear();
    for (final side in waiting) {
      if (incoming.spawn(side, board) == null) {
        _endGame(side);
        return;
      }
    }
    // Queued input next, so a move typed during the animation still counts.
    _flushInputs();
  }

  /// Gives the state a new [GameState.boardVersion]: the board has changed.
  void _changedBoard() => state.boardVersion = ++_boardVersion;

  void _enterPhase(GamePhase phase, double duration) {
    state.phase = phase;
    state.phaseElapsed = 0;
    state.phaseDuration = duration;
  }

  void _endGame(Side side) {
    state.gameOverSide = side;
    _inputs.clear();
    _enterPhase(GamePhase.gameOver, 0);
    _events.add(GameEnded(side));
  }
}
