import 'dart:math' as math;
import 'dart:ui' show Color;

import '../../game/engine/game_engine.dart';
import '../../game/engine/game_event.dart';
import '../../game/engine/placement_engine.dart';
import '../../game/engine/rotation_transform.dart';
import '../../game/model/color.dart';
import '../../game/model/incoming_piece.dart';
import '../../game/model/piece.dart';
import '../../game/model/position.dart';
import '../../game/model/side.dart';
import '../../game/state/game_state.dart';
import '../style.dart';

/// One shard or spark. Positions are in cells, relative to the centre of the
/// cross, in the world frame (they turn with the cross).
class Particle {
  Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.size,
    required this.life,
    required this.color,
  });

  double x;
  double y;
  double vx;
  double vy;
  final double size;
  final double life;
  final Color color;
  double age = 0;
}

/// An expanding ring where blocks popped.
class Ring {
  Ring({
    required this.x,
    required this.y,
    required this.life,
    required this.color,
    required this.reach,
    this.age = 0,
  });

  final double x;
  final double y;
  final double life;
  final Color color;
  final double reach;

  /// Negative while the ring has not started yet.
  double age;
}

/// The streak a hard drop leaves down its lane (glass coordinates).
class Beam {
  Beam({
    required this.side,
    required this.column,
    required this.width,
    required this.fromRow,
    required this.toRow,
  });

  final Side side;
  final int column;
  final int width;
  final int fromRow;
  final int toRow;
  final double life = 0.32;
  double age = 0;
}

/// A piece that has just locked: its cells flash and squash.
class Landing {
  Landing(this.placement, {required this.dropped});

  final Placement placement;
  final bool dropped;
  final double life = 0.24;
  double age = 0;
}

class _StepTrack {
  _StepTrack(this.piece, this.steppedAt)
      : row = piece.row,
        orientation = piece.piece.orientation;

  final IncomingPiece piece;
  int row;
  PieceOrientation orientation;
  double steppedAt;
}

/// Purely visual state layered on top of the engine: the turn of the cross,
/// kicks and shakes, particles, flashes. Nothing here feeds back into the
/// rules.
class Effects {
  Effects({math.Random? random}) : _random = random ?? math.Random();

  static const _quarter = math.pi / 2;

  /// Slide of a piece into its next cell, in seconds.
  static const stepSlideSeconds = 0.07;

  final math.Random _random;

  /// Seconds of animation time.
  double clock = 0;

  /// Board kicks and shakes can be switched off in the settings.
  bool screenShake = true;

  /// How strongly each glass is lit as the active one, 0..1.
  final Map<Side, double> activeness = {for (final side in Side.values) side: 0};
  final List<Particle> particles = [];
  final List<Ring> rings = [];
  final List<Beam> beams = [];
  final List<Landing> landings = [];

  /// Offset of the whole field, in cells: a spring that is kicked by drops
  /// and bumps and pulls itself back.
  double kickX = 0;
  double kickY = 0;
  double _kickVx = 0;
  double _kickVy = 0;

  /// Random jitter, in cells; decays quickly.
  double _shake = 0;
  double shakeX = 0;
  double shakeY = 0;

  /// Extra zoom on a combo; decays to 0.
  double punch = 0;

  /// Seconds a quarter turn of the cross takes; 0 turns it at once. Set from
  /// the settings.
  double turnSeconds = 0.26;

  /// How fast the cross is turning right now, 0 at rest … 1 at the fastest
  /// point of a turn. Fine lines fade by it so that they do not flicker.
  double turnMotion = 0;

  // The view angle is counted in quarter turns; negative is anticlockwise.
  double _fromTurns = 0;
  double _toTurns = 0;

  /// Speed at the start of the current turn, in quarter turns a second.
  double _turnVelocity = 0;
  double _turnStartedAt = double.negativeInfinity;
  double _turnDuration = 0;

  final Map<Side, _StepTrack> _steps = {};
  Object? _burstMatch;

  void reset(Side active) {
    clock = 0;
    particles.clear();
    rings.clear();
    beams.clear();
    landings.clear();
    _steps.clear();
    _burstMatch = null;
    kickX = kickY = _kickVx = _kickVy = 0;
    _shake = shakeX = shakeY = punch = 0;
    _fromTurns = _toTurns = -active.index.toDouble();
    _turnVelocity = turnMotion = 0;
    _turnStartedAt = double.negativeInfinity;
    for (final side in Side.values) {
      activeness[side] = side == active ? 1 : 0;
    }
  }

  double get _turnProgress {
    if (_turnDuration <= 0) return 1;
    return ((clock - _turnStartedAt) / _turnDuration).clamp(0.0, 1.0);
  }

  /// The turn as a cubic that starts at the speed the cross already had and
  /// comes to rest exactly on its target: from standstill that is a plain
  /// ease in and out with no overshoot, and a turn ordered while another is
  /// still running carries on from it without a jerk.
  double _turnsAt(double s) {
    final s2 = s * s;
    final s3 = s2 * s;
    return (2 * s3 - 3 * s2 + 1) * _fromTurns +
        (s3 - 2 * s2 + s) * _turnDuration * _turnVelocity +
        (3 * s2 - 2 * s3) * _toTurns;
  }

  /// Speed of the turn at [s], in quarter turns a second.
  double _turnSpeedAt(double s) {
    if (_turnDuration <= 0 || s >= 1) return 0;
    final s2 = s * s;
    return (6 * s2 - 6 * s) * (_fromTurns - _toTurns) / _turnDuration +
        (3 * s2 - 4 * s + 1) * _turnVelocity;
  }

  /// Current rotation of the cross in radians (positive is clockwise).
  double get viewAngle => _turnsAt(_turnProgress) * _quarter;

  /// The angle the cross is turning towards, in quarter turns.
  double get targetTurns => _toTurns;

  /// How much of a cell the piece still has to slide to reach its row.
  double slideLeft(IncomingPiece piece) {
    final track = _steps[piece.side];
    if (track == null || !identical(track.piece, piece)) return 0;
    final t = math.min(1.0, (clock - track.steppedAt) / stepSlideSeconds);
    return (1 - t) * (1 - t);
  }

  /// Reacts to what the engine did since the last frame.
  void consume(List<GameEvent> events, GameEngine engine) {
    final active = engine.activeSide;
    for (final event in events) {
      switch (event) {
        case SideSwitched():
          final s = _turnProgress;
          final speed = _turnSpeedAt(s);
          _fromTurns = _turnsAt(s);
          _toTurns -= event.quarterTurns;
          final distance = (_toTurns - _fromTurns).abs();
          // A half turn takes half as long again, not twice as long.
          _turnDuration = turnSeconds * (1 + 0.5 * math.max(0.0, distance - 1));
          // Faster than this at the start and the curve would swing past its
          // target.
          final limit = _turnDuration > 0 ? 3 * distance / _turnDuration : 0.0;
          _turnVelocity = speed.clamp(-limit, limit);
          _turnStartedAt = clock;
        case PieceMoved():
          if (event.blocked) _kick(event.direction * 0.14, 0);
        case PieceRotated():
          if (event.blocked) _addShake(0.05);
        case PieceDropped():
          final drop = engine.state.drop;
          if (drop != null) {
            beams.add(Beam(
              side: event.side,
              column: drop.placement.column,
              width: drop.piece.width,
              fromRow: drop.startRow,
              toRow: drop.placement.row,
            ));
          }
        case PieceLanded():
          landings.add(Landing(event.placement, dropped: event.dropped));
          // The field recoils the way the piece was travelling on screen.
          final (dx, dy) = _travelOnScreen(
            RotationTransform.slotOfSide(active, event.placement.side),
          );
          final force = event.dropped ? 0.3 : 0.08;
          _kick(dx * force, dy * force);
          if (event.dropped) _sparks(event.placement, engine);
        case MatchScored():
          _addShake(0.05 + 0.04 * event.combo);
          if (screenShake) punch = math.min(0.06, 0.012 * event.combo);
        case CellsPopped():
        case GameEnded():
          break;
      }
    }
  }

  /// Advances every animation by [seconds].
  void update(double seconds, GameEngine engine) {
    clock += seconds;
    final state = engine.state;

    // The moment matched blocks start to pop, they burst.
    final match = state.activeMatch;
    if (state.phase == GamePhase.clearing &&
        match != null &&
        !identical(match, _burstMatch)) {
      _burstMatch = match;
      _burst(match.cells, engine);
    }

    _trackSteps(engine);

    // A turn from standstill peaks at 1.5 quarter turns per `turnSeconds`.
    turnMotion =
        math.min(1.0, _turnSpeedAt(_turnProgress).abs() * turnSeconds / 1.5);

    // Spring back to rest.
    const stiffness = 520.0;
    const damping = 30.0;
    _kickVx += (-stiffness * kickX - damping * _kickVx) * seconds;
    _kickVy += (-stiffness * kickY - damping * _kickVy) * seconds;
    kickX += _kickVx * seconds;
    kickY += _kickVy * seconds;
    _shake *= math.exp(-14 * seconds);
    shakeX = (_random.nextDouble() * 2 - 1) * _shake;
    shakeY = (_random.nextDouble() * 2 - 1) * _shake;
    punch *= math.exp(-9 * seconds);

    final drag = math.max(0.0, 1 - 3.4 * seconds);
    for (final particle in particles) {
      particle.age += seconds;
      particle.x += particle.vx * seconds;
      particle.y += particle.vy * seconds;
      particle.vx *= drag;
      particle.vy *= drag;
    }
    particles.removeWhere((particle) => particle.age >= particle.life);
    for (final ring in rings) {
      ring.age += seconds;
    }
    rings.removeWhere((ring) => ring.age >= ring.life);
    for (final beam in beams) {
      beam.age += seconds;
    }
    beams.removeWhere((beam) => beam.age >= beam.life);
    for (final landing in landings) {
      landing.age += seconds;
    }
    landings.removeWhere((landing) => landing.age >= landing.life);

    final rate = math.min(1.0, seconds * 18);
    for (final side in Side.values) {
      final target = side == engine.activeSide ? 1.0 : 0.0;
      activeness[side] = activeness[side]! + (target - activeness[side]!) * rate;
    }
  }

  /// A level has been finished: rings roll out from the centre of the cross
  /// and confetti in the colours in play flies after them.
  void celebrate(int colors) {
    for (var i = 0; i < 3; i++) {
      rings.add(Ring(
        x: 0,
        y: 0,
        age: -0.16 * i,
        life: 0.9,
        color: const Color(0xFFFFFFFF),
        reach: 13,
      ));
    }
    for (var i = 0; i < 150; i++) {
      final tones = BlockTones.of(BlockColor.values[i % colors]);
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = 8 + _random.nextDouble() * 26;
      particles.add(Particle(
        x: math.cos(angle) * 0.6,
        y: math.sin(angle) * 0.6,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        size: 0.14 + _random.nextDouble() * 0.22,
        life: 0.7 + _random.nextDouble() * 0.8,
        color: i % 4 == 0
            ? const Color(0xFFFFFFFF)
            : i.isEven
                ? tones.light
                : tones.base,
      ));
    }
    if (screenShake) punch = 0.05;
  }

  void _kick(double x, double y) {
    if (!screenShake) return;
    _kickVx += x * 46;
    _kickVy += y * 46;
  }

  void _addShake(double amount) {
    if (screenShake) _shake = math.max(_shake, amount);
  }

  void _trackSteps(GameEngine engine) {
    for (final side in Side.values) {
      final piece = engine.state.incoming[side];
      final track = _steps[side];
      if (piece == null) {
        _steps.remove(side);
      } else if (track == null || !identical(track.piece, piece)) {
        // A new piece slides in from beyond the far end.
        _steps[side] = _StepTrack(piece, clock);
      } else {
        // A rotation also shifts the row; only a plain step down slides.
        if (piece.row > track.row && piece.piece.orientation == track.orientation) {
          track.steppedAt = clock;
        }
        track.row = piece.row;
        track.orientation = piece.piece.orientation;
      }
    }
  }

  /// Shards and a ring for every popped block.
  void _burst(Set<CellPosition> cells, GameEngine engine) {
    final board = engine.board;
    final half = board.size / 2;
    for (final cell in cells) {
      final color = board.colorAt(cell);
      if (color == null) continue;
      final tones = BlockTones.of(color);
      final x = -half + cell.col + 0.5;
      final y = -half + cell.row + 0.5;
      rings.add(Ring(x: x, y: y, life: 0.34, color: tones.base, reach: 1.25));
      for (var i = 0; i < 9; i++) {
        final angle = _random.nextDouble() * math.pi * 2;
        final speed = 2.5 + _random.nextDouble() * 6.5;
        particles.add(Particle(
          x: x + (_random.nextDouble() - 0.5) * 0.5,
          y: y + (_random.nextDouble() - 0.5) * 0.5,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed,
          size: 0.1 + _random.nextDouble() * 0.16,
          life: 0.3 + _random.nextDouble() * 0.3,
          color: i % 3 == 0
              ? const Color(0xFFFFFFFF)
              : i % 3 == 1
                  ? tones.light
                  : tones.base,
        ));
      }
    }
  }

  /// A few sparks where a hard-dropped piece hits.
  void _sparks(Placement placement, GameEngine engine) {
    final half = engine.board.size / 2;
    for (final cell in placement.cells) {
      for (var i = 0; i < 4; i++) {
        final angle = _random.nextDouble() * math.pi * 2;
        final speed = 1.5 + _random.nextDouble() * 3.5;
        particles.add(Particle(
          x: -half + cell.position.col + 0.5,
          y: -half + cell.position.row + 0.5,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed,
          size: 0.06 + _random.nextDouble() * 0.08,
          life: 0.18 + _random.nextDouble() * 0.2,
          color: const Color(0xFFFFFFFF),
        ));
      }
    }
  }

  /// Screen direction in which a piece shown in [slot] travels.
  static (double, double) _travelOnScreen(Side slot) => switch (slot) {
        Side.top => (0, 1),
        Side.right => (-1, 0),
        Side.bottom => (0, -1),
        Side.left => (1, 0),
      };
}
