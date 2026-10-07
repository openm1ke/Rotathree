import 'dart:math' as math;

import '../engine/cascade_resolver.dart';
import '../engine/game_engine.dart';
import '../engine/placement_engine.dart';
import '../model/board.dart';
import '../model/incoming_piece.dart';
import '../model/piece.dart';
import '../model/side.dart';
import '../state/game_state.dart';

/// How fast and how carefully a simulated player acts. The numbers are rough
/// guesses at human hand speed, not measurements.
class BotProfile {
  const BotProfile({
    required this.name,
    required this.thinkSeconds,
    required this.switchSeconds,
    required this.moveSeconds,
    required this.rotateSeconds,
    required this.mistakeChance,
  });

  final String name;

  /// Looking at the board and deciding where the next piece goes.
  final double thinkSeconds;

  /// One 90° turn of the cross, including re-orienting afterwards.
  final double switchSeconds;

  /// One lane of sideways movement.
  final double moveSeconds;
  final double rotateSeconds;

  /// Chance of placing a piece somewhere arbitrary instead of the best spot.
  final double mistakeChance;

  static const casual = BotProfile(
    name: 'casual',
    thinkSeconds: 1.3,
    switchSeconds: 0.55,
    moveSeconds: 0.20,
    rotateSeconds: 0.28,
    mistakeChance: 0.20,
  );

  static const average = BotProfile(
    name: 'average',
    thinkSeconds: 0.8,
    switchSeconds: 0.42,
    moveSeconds: 0.14,
    rotateSeconds: 0.20,
    mistakeChance: 0.08,
  );

  static const expert = BotProfile(
    name: 'expert',
    thinkSeconds: 0.4,
    switchSeconds: 0.30,
    moveSeconds: 0.09,
    rotateSeconds: 0.13,
    mistakeChance: 0.02,
  );

  static const all = [casual, average, expert];
}

/// A simulated player that drives a [GameEngine] through the same inputs a
/// person has, one action at a time and with human-like delays.
///
/// Used by the balance simulation (`tool/balance_sim.dart`) and by the
/// "auto-play" switch of the in-app lab panel.
class BotPlayer {
  BotPlayer(
    this.engine, {
    this.profile = BotProfile.average,
    math.Random? random,
  })  : _random = random ?? math.Random(0),
        _resolver = CascadeResolver(engine.config);

  final GameEngine engine;
  final BotProfile profile;
  final math.Random _random;
  final CascadeResolver _resolver;
  final PlacementEngine _placement = const PlacementEngine();

  _Plan? _plan;
  double _wait = 0;

  /// Number of pieces the bot decided about.
  int decisions = 0;

  /// Decisions where it had spare time and picked a glass other than the one
  /// whose piece was closest to locking.
  int choseNonUrgent = 0;

  /// Rough time to deal with one piece from start to finish.
  double get _serviceSeconds =>
      profile.thinkSeconds +
      2 * profile.switchSeconds +
      profile.rotateSeconds +
      4 * profile.moveSeconds;

  void tick(double seconds) {
    if (engine.isGameOver) return;
    if (_wait > 0) {
      _wait -= seconds;
      if (_wait > 0) return;
    }
    // While the board resolves, a person watches rather than types ahead.
    if (engine.phase != GamePhase.playing) return;

    final plan = _plan;
    if (plan == null) {
      _plan = _choose();
      _wait = _plan == null ? 0.1 : profile.thinkSeconds;
      return;
    }
    _act(plan);
  }

  void _act(_Plan plan) {
    final piece = engine.state.incoming[plan.side];
    if (!identical(piece, plan.piece) || piece == null) {
      _plan = null; // it locked by itself while we were busy
      return;
    }
    if (engine.activeSide != plan.side) {
      engine.switchSide(engine.activeSide.stepsTo(plan.side).sign);
      _wait = profile.switchSeconds;
      return;
    }
    if (engine.state.boardVersion != plan.boardVersion) {
      // Something else landed meanwhile: re-aim without re-thinking the glass.
      final best = _bestOption(piece);
      if (best == null) {
        _plan = null;
        return;
      }
      plan.retarget(best.placement, engine.state.boardVersion);
    }
    if (piece.piece.orientation != plan.orientation) {
      // One quarter turn per action; up to three to reach any orientation.
      final before = piece.piece.orientation;
      engine.rotateActive();
      if (piece.piece.orientation == before) {
        _plan = null; // no room to turn any more
        return;
      }
      _wait = profile.rotateSeconds;
      return;
    }
    if (piece.column != plan.column) {
      final before = piece.column;
      engine.moveActive((plan.column - piece.column).sign);
      if (piece.column == before) {
        _plan = null; // a block is in the way
        return;
      }
      _wait = profile.moveSeconds;
      return;
    }
    engine.dropActive();
    _plan = null;
    _wait = 0.05;
  }

  _Plan? _choose() {
    double left(IncomingPiece piece) => engine.secondsToLock(piece.side) ?? 0;

    final pieces = engine.state.incoming.values.toList()
      ..sort((a, b) {
        final byTime = left(a).compareTo(left(b));
        return byTime != 0 ? byTime : a.side.index.compareTo(b.side.index);
      });
    if (pieces.isEmpty) return null;

    final options = <IncomingPiece, _Option>{};
    for (final piece in pieces) {
      final best = _bestOption(piece);
      if (best != null) options[piece] = best;
    }
    if (options.isEmpty) return null;

    final urgent = pieces.first;
    IncomingPiece chosen;
    if (left(urgent) < 2 * _serviceSeconds && options.containsKey(urgent)) {
      chosen = urgent;
    } else {
      // Time to spare: go where the best move is, leaning towards pieces
      // that will lock sooner.
      chosen = _bestOf(options, urgencyWeight: 20, left: left);
      if (!identical(chosen, urgent)) choseNonUrgent++;
    }
    decisions++;

    var target = options[chosen]!.placement;
    if (_random.nextDouble() < profile.mistakeChance) {
      final all = _options(chosen);
      target = all[_random.nextInt(all.length)].placement;
    }
    return _Plan(chosen, target, engine.state.boardVersion);
  }

  IncomingPiece _bestOf(
    Map<IncomingPiece, _Option> options, {
    required double urgencyWeight,
    required double Function(IncomingPiece) left,
  }) {
    IncomingPiece? best;
    var bestValue = double.negativeInfinity;
    options.forEach((piece, option) {
      // 1 for a piece about to lock, 0 for one with twenty seconds or more.
      final urgency = 1 - (left(piece) / 20).clamp(0.0, 1.0);
      final value = option.value + urgencyWeight * urgency;
      if (value > bestValue) {
        bestValue = value;
        best = piece;
      }
    });
    return best!;
  }

  /// Everything the player could do with [piece] from where it is: turn it
  /// to any of its four orientations, slide it as far as the blocks allow,
  /// drop it.
  List<_Option> _options(IncomingPiece piece) {
    final board = engine.board;
    final result = <_Option>[];
    final starts = <IncomingPiece>[piece];
    while (starts.length < PieceOrientation.values.length) {
      final turned = engine.incoming.rotated(starts.last, board);
      if (turned == null) break;
      starts.add(turned);
    }
    for (final start in starts) {
      for (final column in engine.incoming.reachableColumns(start, board)) {
        final placement = _placement.computeDrop(
          board,
          start.side,
          start.piece,
          column,
          fromRow: start.row,
        );
        if (placement != null) {
          result.add(_Option(placement, _evaluate(placement)));
        }
      }
    }
    return result;
  }

  _Option? _bestOption(IncomingPiece piece) {
    _Option? best;
    for (final option in _options(piece)) {
      if (best == null || option.value > best.value) best = option;
    }
    return best;
  }

  /// Scores the board that results from [placement] with its side on top.
  double _evaluate(Placement placement) {
    final config = engine.config;
    final board = engine.board.copy();
    for (final cell in placement.cells) {
      board.set(cell.position.row, cell.position.col, cell.color);
    }
    final cascade = _resolver.resolve(board, placement.side);

    var value = 0.0;
    value += 6.0 * cascade.clearedCells;
    value += 25.0 * math.max(0, cascade.maxCombo - 1);
    value -= 1.0 * board.blockCount;
    value += 0.5 * _sameColorNeighbours(board);
    // Lower in the glass is better: it leaves more room above.
    value += 0.3 * placement.row;

    // A glass that fills up to its far end loses the game.
    for (final side in Side.values) {
      final room = _placement.headroom(
        board,
        side,
        engine.incoming.spawnColumn,
        config.pieceLength,
      );
      if (room == 0) {
        value -= 500.0;
      } else if (room < config.armLength) {
        final shortfall = config.armLength - room;
        value -= 4.0 * shortfall * shortfall;
      }
    }
    return value;
  }

  int _sameColorNeighbours(Board board) {
    var pairs = 0;
    for (var row = 0; row < board.size; row++) {
      for (var col = 0; col < board.size; col++) {
        final color = board.at(row, col);
        if (color == null) continue;
        if (col + 1 < board.size && board.at(row, col + 1) == color) pairs++;
        if (row + 1 < board.size && board.at(row + 1, col) == color) pairs++;
      }
    }
    return pairs;
  }
}

class _Option {
  const _Option(this.placement, this.value);

  final Placement placement;
  final double value;
}

class _Plan {
  _Plan(this.piece, Placement target, this.boardVersion)
      : orientation = target.piece.orientation,
        column = target.column;

  final IncomingPiece piece;
  PieceOrientation orientation;
  int column;
  int boardVersion;

  Side get side => piece.side;

  void retarget(Placement target, int version) {
    orientation = target.piece.orientation;
    column = target.column;
    boardVersion = version;
  }
}
