import 'dart:collection';
import 'dart:math' as math;

import '../config/game_config.dart';
import '../model/board.dart';
import '../model/cell.dart';
import '../model/incoming_piece.dart';
import '../model/side.dart';
import '../state/game_state.dart';
import 'cascade_resolver.dart';
import 'game_event.dart';
import 'gravity_resolver.dart';
import 'incoming_controller.dart';
import 'piece_generator.dart';
import 'placement_engine.dart';

/// The whole game, independent of Flutter.
///
/// Rules in short:
///  * the playfield is a cross: a central square and four arms. Each side
///    owns a glass — its arm plus the central square — and the four glasses
///    share the centre;
///  * four pieces fall at the same time, one per glass, a whole cell per
///    step — once a second in the active glass, once every three seconds in
///    the others — through the arm and on through the centre. A piece whose
///    next step is blocked by the floor of its glass (the far wall of the
///    centre) or by a block locks instead;
///  * the player turns the cross to pick the active glass, slides and rotates
///    its piece and can hard-drop it; the other three look after themselves;
///  * lines of 3+ of a colour pop, the blocks above them fall towards the
///    bottom of the screen and cascades raise the combo multiplier;
///  * a glass that is full up to the far end of its arm ends the game.
///
/// Time only moves through [update]. Player input is applied immediately
/// while [GamePhase.playing] and queued during every other phase.
class GameEngine {
  GameEngine({this.config = const GameConfig(), math.Random? random})
      : _generator = PieceGenerator(config, random),
        _resolver = CascadeResolver(config) {
    incoming = IncomingController(config, _generator);
    restart();
  }

  static const _epsilon = 1e-9;

  final GameConfig config;
  final PieceGenerator _generator;
  final CascadeResolver _resolver;
  final PlacementEngine _placement = const PlacementEngine();
  final Queue<_Input> _inputs = Queue<_Input>();
  final List<GameEvent> _events = [];

  /// Glasses whose piece has locked and that get a new one as soon as the
  /// board has come to rest.
  final List<Side> _awaitingPiece = [];

  late final IncomingController incoming;
  late GameState state;

  Board get board => state.board;
  Side get activeSide => state.activeSide;
  GamePhase get phase => state.phase;
  bool get isGameOver => state.isGameOver;
  IncomingPiece? get activePiece => incoming.pieceAt(state.activeSide);

  /// True while falling pieces are frozen for a match animation.
  bool get incomingPaused =>
      config.pauseIncomingDuringCascade &&
      (state.phase == GamePhase.matching ||
          state.phase == GamePhase.clearing ||
          state.phase == GamePhase.settling ||
          state.phase == GamePhase.cascading);

  void restart() {
    _inputs.clear();
    _events.clear();
    _awaitingPiece.clear();
    incoming.reset();
    state = GameState(
      board: Board(center: config.boardSize, arm: config.armLength),
      incoming: incoming.pieces,
    );
  }

  /// Returns the events raised since the last call and forgets them.
  List<GameEvent> drainEvents() {
    if (_events.isEmpty) return const [];
    final events = List<GameEvent>.of(_events);
    _events.clear();
    return events;
  }

  // ---------------------------------------------------------------- queries

  /// Where the piece of [side] comes to rest if it falls straight down from
  /// where it is; null when that glass has no piece at the moment.
  Placement? previewDrop(Side side) {
    final piece = incoming.pieceAt(side);
    if (piece == null) return null;
    return _placement.placementAt(
      state.board,
      side,
      piece.piece,
      piece.column,
      incoming.restRow(piece, state.board),
    );
  }

  /// Seconds until the piece of [side] locks if it is left alone.
  double? secondsToLock(Side side) {
    final piece = incoming.pieceAt(side);
    if (piece == null) return null;
    return incoming.secondsToLock(piece, state.board, state.activeSide);
  }

  /// Free rows at the far end of the glass of [side], in the lanes where its
  /// pieces appear. At 0 the next piece has no room and the game ends.
  int headroom(Side side) => _placement.headroom(
        state.board,
        side,
        incoming.spawnColumn,
        config.pieceLength,
      );

  /// True when the glass of [side] is close to overflowing.
  bool isCrowded(Side side) => headroom(side) <= config.crowdedHeadroom;

  // ------------------------------------------------------------------ input

  /// Turns the cross by [quarterTurns] steps of TOP → RIGHT → BOTTOM → LEFT.
  void switchSide(int quarterTurns) => _submit(_Input.turn(quarterTurns));

  /// Makes [side] the active one, turning the short way round.
  void activateSide(Side side) => _submit(_Input.activate(side));

  /// Slides the active piece across its glass.
  void moveActive(int delta) => _submit(_Input.move(delta));

  /// Slides the active piece towards an absolute lane (dragging).
  void setActiveColumn(int column) => _submit(_Input.column(column));

  /// Turns the active piece a quarter turn, clockwise unless told otherwise.
  void rotateActive({bool clockwise = true}) =>
      _submit(_Input.rotate(clockwise: clockwise));

  /// Sends the active piece straight down to where it lands.
  void dropActive() => _submit(const _Input.drop());

  void _submit(_Input input) {
    if (isGameOver) return;
    if (state.phase == GamePhase.playing && _inputs.isEmpty) {
      _apply(input);
      return;
    }
    // A drag sends a stream of lane updates; only the latest one matters.
    if (input.kind == _InputKind.column &&
        _inputs.isNotEmpty &&
        _inputs.last.kind == _InputKind.column) {
      _inputs.removeLast();
    }
    if (_inputs.length < config.maxQueuedInputs) _inputs.add(input);
  }

  void _flushInputs() {
    while (_inputs.isNotEmpty && state.phase == GamePhase.playing) {
      _apply(_inputs.removeFirst());
    }
  }

  void _apply(_Input input) {
    final side = state.activeSide;
    switch (input.kind) {
      case _InputKind.turn:
        _turn(input.value);
      case _InputKind.activate:
        _turn(side.stepsTo(Side.values[input.value]));
      case _InputKind.move:
        incoming.move(side, input.value, state.board);
      case _InputKind.column:
        incoming.setColumn(side, input.value, state.board);
      case _InputKind.rotate:
        incoming.rotate(side, state.board, clockwise: input.value > 0);
      case _InputKind.drop:
        _beginDrop();
    }
  }

  void _turn(int quarterTurns) {
    final from = state.activeSide;
    final to = from.turned(quarterTurns);
    if (to == from) return;
    state.activeSide = to;
    _events.add(SideSwitched(from, to, quarterTurns));

    // By default the structure turns as one rigid body and nothing falls.
    if (!config.settleAfterBoardRotation) return;
    final moves = _resolver.settleAll(state.board, to);
    if (moves.isEmpty) return;
    state.combo = 0;
    _startFalling(moves);
  }

  // ------------------------------------------------------------------- time

  /// Advances the game by [seconds] of game time.
  void update(double seconds) {
    var left = seconds;
    while (left > _epsilon && !isGameOver) {
      if (state.phase == GamePhase.playing) {
        final next = incoming.secondsToNextStep(state.activeSide);
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
        final step = math.min(left, math.max(remaining, 0.0));
        state.phaseElapsed += step;
        _advanceClock(step);
        left -= step;
        if (state.phaseElapsed >= state.phaseDuration - _epsilon) {
          _completePhase();
        }
      }
    }
  }

  void _advanceClock(double seconds) {
    state.elapsedSeconds += seconds;
    if (!incomingPaused) incoming.advance(seconds, state.activeSide);
  }

  /// Every piece whose step is due moves one row down. The first one that
  /// cannot move locks where it is; the board then changes, so any others
  /// still due wait until play resumes.
  void _stepDuePieces() {
    for (final side in incoming.dueSides(state.activeSide)) {
      if (incoming.step(side, state.board)) continue;
      final piece = incoming.take(side)!;
      state.selfLocked++;
      _commit(
        _placement.placementAt(
          state.board,
          side,
          piece.piece,
          piece.column,
          piece.row,
        ),
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
    state.drop = DropInFlight(placement: placement, startRow: piece.row);
    _events.add(PieceDropped(piece.side));
    _enterPhase(
      GamePhase.pieceDropping,
      config.dropSeconds((placement.row - piece.row).toDouble()),
    );
  }

  /// Writes a piece into the board and resolves what follows from it.
  void _commit(Placement placement, {required bool dropped}) {
    for (final cell in placement.cells) {
      state.board.set(cell.position.row, cell.position.col, cell.color);
    }
    state.boardVersion++;
    state.piecesPlaced++;
    state.combo = 0;
    _awaitingPiece.add(placement.side);
    _events.add(PieceLanded(placement, dropped: dropped));
    if (!_makeRoomForFallingPieces()) return;
    _checkMatches();
  }

  /// Falling pieces pass through each other, so a block that has just
  /// appeared may sit inside one of them; such a piece backs off towards its
  /// own arm. Returns false when one of them has nowhere to go: game over.
  bool _makeRoomForFallingPieces() {
    final crushed = incoming.resolveOverlaps(state.board);
    if (crushed.isEmpty) return true;
    _endGame(GameOverInfo(side: crushed.first));
    return false;
  }

  void _completePhase() {
    switch (state.phase) {
      case GamePhase.pieceDropping:
        final drop = state.drop!;
        state.drop = null;
        _commit(drop.placement, dropped: true);

      case GamePhase.matching:
      case GamePhase.cascading:
        _enterPhase(GamePhase.clearing, config.clearPhaseSeconds);

      case GamePhase.clearing:
        final match = state.activeMatch!;
        _events.add(CellsPopped([
          for (final cell in match.cells)
            PlacedCell(cell, state.board.colorAt(cell)!),
        ]));
        _resolver.clear(state.board, match);
        state.boardVersion++;
        state.activeMatch = null;
        final moves =
            _resolver.settleAfterClear(state.board, state.activeSide, match);
        if (moves.isEmpty) {
          _checkMatches();
        } else {
          _startFalling(moves);
        }

      case GamePhase.settling:
        state.moves = const [];
        _checkMatches();

      case GamePhase.playing:
      case GamePhase.gameOver:
        break;
    }
  }

  /// Blocks have been moved to where they fall; show them falling.
  void _startFalling(List<BlockMove> moves) {
    state.boardVersion++;
    state.moves = moves;
    final furthest = moves.fold(0, (far, move) => math.max(far, move.distance));
    _enterPhase(GamePhase.settling, config.fallPhaseSeconds(furthest));
    _makeRoomForFallingPieces();
  }

  void _checkMatches() {
    final match = _resolver.findMatches(state.board);
    if (match.isEmpty) {
      _finishResolution();
      return;
    }
    state.combo++;
    if (state.combo > state.bestCombo) state.bestCombo = state.combo;
    final score = _resolver.scoreFor(match, state.combo);
    state.score += score;
    state.matches += match.runs.length;
    state.clearedCells += match.cells.length;
    state.activeMatch = match;
    _events.add(MatchScored(combo: state.combo, score: score, match: match));
    _enterPhase(
      state.combo == 1 ? GamePhase.matching : GamePhase.cascading,
      config.matchPhaseSeconds,
    );
  }

  void _finishResolution() {
    state.combo = 0;
    _enterPhase(GamePhase.playing, 0);

    // The board is at rest: refill the glasses whose piece has locked.
    for (final side in List<Side>.of(_awaitingPiece)) {
      _awaitingPiece.remove(side);
      if (incoming.spawn(side, state.board) == null) {
        _endGame(GameOverInfo(side: side));
        return;
      }
    }
    // Queued input next, so a move typed during the animation still counts;
    // pieces due to step are picked up by the update loop right after.
    _flushInputs();
  }

  void _enterPhase(GamePhase phase, double duration) {
    state.phase = phase;
    state.phaseElapsed = 0;
    state.phaseDuration = duration;
  }

  void _endGame(GameOverInfo info) {
    state.gameOver = info;
    _inputs.clear();
    _enterPhase(GamePhase.gameOver, 0);
    _events.add(GameEnded(info));
  }
}

enum _InputKind { turn, activate, move, column, rotate, drop }

class _Input {
  const _Input(this.kind, this.value);

  const _Input.turn(int quarterTurns) : this(_InputKind.turn, quarterTurns);
  _Input.activate(Side side) : this(_InputKind.activate, side.index);
  const _Input.move(int delta) : this(_InputKind.move, delta);
  const _Input.column(int column) : this(_InputKind.column, column);
  const _Input.rotate({required bool clockwise})
      : this(_InputKind.rotate, clockwise ? 1 : -1);
  const _Input.drop() : this(_InputKind.drop, 0);

  final _InputKind kind;
  final int value;
}
