import 'dart:math';

import '../config/game_config.dart';
import '../model/board.dart';
import '../model/cell.dart';
import '../model/incoming_piece.dart';
import '../model/side.dart';
import '../state/game_state.dart';
import 'game_event.dart';
import 'gravity_resolver.dart';
import 'incoming_controller.dart';
import 'match_detector.dart';
import 'piece_generator.dart';
import 'placement_engine.dart';
import 'speed_ramp.dart';

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
      GamePhase.building =>
        true,
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

  // ------------------------------------------------------------- settings

  /// Changes the step times from now on. Pieces keep their progress.
  void setSteps(double activeStepSeconds, double inactiveStepSeconds) {
    _config = _config.copyWith(
      activeStepSeconds: activeStepSeconds,
      inactiveStepSeconds: inactiveStepSeconds,
    );
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
    return _placement.placementAt(
      board,
      side,
      piece.piece,
      piece.column,
      incoming.restRow(piece, board),
    );
  }

  /// Seconds until the piece of [side] locks if it is left alone.
  double? secondsToLock(Side side) {
    final piece = incoming.pieceAt(side);
    return piece == null ? null : incoming.secondsToLock(piece, board, activeSide);
  }

  /// Free rows at the far end of the glass of [side], in the lanes where its
  /// pieces appear. At 0 the next piece has no room and the game ends.
  int headroom(Side side) =>
      _placement.headroom(board, side, incoming.spawnColumn, _config.pieceLength);

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
        _events.add(PieceMoved(
          side,
          direction: move.delta.sign,
          blocked: moved < move.delta.abs(),
        ));
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
      _commit(
        _placement.placementAt(board, side, piece.piece, piece.column, piece.row),
        dropped: false,
      );
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
        _events.add(CellsPopped([
          for (final cell in match.cells) PlacedCell(cell, board.colorAt(cell)!),
        ]));
        for (final cell in match.cells) {
          board.set(cell.row, cell.col, null);
        }
        _changedBoard();
        s.activeMatch = null;
        final moves = _gravity.settle(
          board,
          s.activeSide,
          scope: _config.gravityScope,
          cleared: match.cells,
        );
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
    _enterPhase(
      s.combo == 1 ? GamePhase.matching : GamePhase.cascading,
      _config.matchPhaseSeconds,
    );
  }

  int _scoreFor(MatchResult match, int combo) {
    var score = 0;
    for (final run in match.runs) {
      score += _config.scoring.scoreForRun(
        run.length,
        combo,
        minMatchLength: _config.minMatchLength,
      );
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
