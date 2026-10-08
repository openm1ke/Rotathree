import 'dart:math' as math;
import 'dart:ui' show Color, Offset;

import '../../game/engine/game_engine.dart';
import '../../game/engine/game_event.dart';
import '../../game/engine/match_detector.dart';
import '../../game/engine/placement_engine.dart';
import '../../game/engine/rotation_transform.dart';
import '../../game/model/incoming_piece.dart';
import '../../game/model/piece.dart';
import '../../game/model/position.dart';
import '../../game/model/side.dart';
import '../../game/state/game_state.dart';
import '../data/settings.dart' show ExplosionStyle;
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

/// An expanding ring. A negative age means it has not started yet.
class Ring {
  Ring({
    required this.x,
    required this.y,
    required this.age,
    required this.life,
    required this.color,
    required this.reach,
  });

  final double x;
  final double y;
  double age;
  final double life;
  final Color color;
  final double reach;
}

/// The streak a hard drop leaves down its lane (glass coordinates).
class Beam {
  Beam({
    required this.side,
    required this.column,
    required this.width,
    required this.fromRow,
    required this.toRow,
    required this.life,
  });

  final Side side;
  final int column;
  final int width;
  final int fromRow;
  final int toRow;
  double age = 0;
  final double life;
}

/// A piece that has just locked: its cells flash and squash.
class Landing {
  Landing({required this.placement, required this.life, required this.dropped});

  final Placement placement;
  double age = 0;
  final double life;
  final bool dropped;
}

/// A bar of light laid over a line of popped blocks, in world cells.
class Flash {
  Flash({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.life,
    required this.color,
  });

  final double x0;
  final double y0;
  final double x1;
  final double y1;
  double age = 0;
  final double life;
  final Color color;
}

/// A whole-field wash of light for a triple clear.
class Veil {
  Veil({required this.life});

  double age = 0;
  final double life;
}

/// How one line of popped blocks explodes.
class _Signature {
  const _Signature({
    required this.shards,
    required this.speed,
    required this.rings,
    required this.flash,
    required this.shake,
    required this.gold,
  });

  final int shards;
  final double speed;
  final int rings;

  /// Seconds the bar of light lasts; 0 for no bar.
  final double flash;
  final double shake;
  final bool gold;
}

/// Explosions per length of line: 3, 4, 5 and 6 or more. Lines of six get the
/// most, in gold.
const _signatures = [
  _Signature(shards: 9, speed: 6.5, rings: 1, flash: 0, shake: 0.04, gold: false),
  _Signature(shards: 15, speed: 8, rings: 2, flash: 0.18, shake: 0.06, gold: false),
  _Signature(shards: 22, speed: 9.5, rings: 2, flash: 0.24, shake: 0.08, gold: false),
  _Signature(shards: 30, speed: 11, rings: 3, flash: 0.3, shake: 0.11, gold: true),
];

/// The one explosion the "unified" style uses for everything.
final _unified = _signatures[0];

const _quarter = math.pi / 2;

class _StepTrack {
  _StepTrack({
    required this.piece,
    required this.row,
    required this.orientation,
    required this.steppedAt,
  });

  final IncomingPiece piece;
  int row;
  PieceOrientation orientation;
  double steppedAt;
}

/// Purely visual state layered on top of the engine: the turn of the cross,
/// kicks and shakes, particles, flashes. Nothing here feeds back into the
/// rules.
class Effects {
  final math.Random _random = math.Random();

  /// Seconds of animation time.
  double clock = 0;

  /// Board kicks and shakes can be switched off in the settings.
  bool screenShake = true;

  /// Whether each kind of clear explodes in its own way.
  ExplosionStyle explosion = ExplosionStyle.varied;

  /// Seconds a quarter turn of the cross takes; 0 turns it at once.
  double turnSeconds = 0.26;

  /// How fast the cross is turning right now, 0 at rest … 1 at the fastest
  /// point of a turn. Fine lines fade by it so that they do not flicker.
  double turnMotion = 0;

  /// How strongly each glass is lit as the active one, 0..1, by side index.
  final List<double> activeness = [1, 0, 0, 0];
  final List<Particle> particles = [];
  final List<Ring> rings = [];
  final List<Beam> beams = [];
  final List<Landing> landings = [];
  final List<Flash> flashes = [];
  final List<Veil> veils = [];

  /// Offset of the whole field, in cells: a spring that is kicked by drops
  /// and bumps and pulls itself back.
  double kickX = 0;
  double kickY = 0;
  double _kickVx = 0;
  double _kickVy = 0;

  /// Random jitter amplitude, in cells; decays quickly.
  double _shake = 0;
  double shakeX = 0;
  double shakeY = 0;

  /// Extra zoom on a combo; decays to 0.
  double punch = 0;

  // The view angle is counted in quarter turns; negative is anticlockwise.
  double _fromTurns = 0;
  double _toTurns = 0;

  /// Speed at the start of the current turn, in quarter turns a second.
  double _turnVelocity = 0;
  double _turnStartedAt = double.negativeInfinity;
  double _turnDuration = 0;

  final Map<Side, _StepTrack> _steps = {};
  MatchResult? _burstMatch;

  /// Slide of a piece into its next cell, in seconds.
  static const stepSlideSeconds = 0.07;

  void reset(Side active) {
    clock = 0;
    particles.clear();
    rings.clear();
    beams.clear();
    landings.clear();
    flashes.clear();
    veils.clear();
    _steps.clear();
    _burstMatch = null;
    kickX = 0;
    kickY = 0;
    _kickVx = 0;
    _kickVy = 0;
    _shake = 0;
    shakeX = 0;
    shakeY = 0;
    punch = 0;
    _fromTurns = -active.index.toDouble();
    _toTurns = _fromTurns;
    _turnVelocity = 0;
    turnMotion = 0;
    _turnStartedAt = double.negativeInfinity;
    _turnDuration = 0;
    for (final side in Side.values) {
      activeness[side.index] = side == active ? 1 : 0;
    }
  }

  double get _turnProgress {
    if (_turnDuration <= 0) return 1;
    return ((clock - _turnStartedAt) / _turnDuration).clamp(0.0, 1.0).toDouble();
  }

  /// The turn as a cubic that starts at the speed the cross already had and
  /// comes to rest exactly on its target: from standstill that is a plain ease
  /// in and out with no overshoot, and a turn ordered while another is still
  /// running carries on from it without a jerk.
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
    return ((6 * s2 - 6 * s) * (_fromTurns - _toTurns)) / _turnDuration +
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
        case SideSwitched(:final quarterTurns):
          final s = _turnProgress;
          final speed = _turnSpeedAt(s);
          _fromTurns = _turnsAt(s);
          _toTurns -= quarterTurns;
          final distance = (_toTurns - _fromTurns).abs();
          // A half turn takes half as long again, not twice as long.
          _turnDuration = turnSeconds * (1 + 0.5 * math.max(0, distance - 1));
          // Faster than this at the start and the curve would swing past its
          // target.
          final limit = _turnDuration > 0 ? (3 * distance) / _turnDuration : 0.0;
          _turnVelocity = speed.clamp(-limit, limit).toDouble();
          _turnStartedAt = clock;
        case PieceMoved(:final direction, :final blocked):
          if (blocked) _kick(direction * 0.14, 0);
        case PieceRotated(:final blocked):
          if (blocked) _addShake(0.05);
        case PieceDropped(:final side):
          final drop = engine.state.drop;
          if (drop != null) {
            beams.add(Beam(
              side: side,
              column: drop.placement.column,
              width: drop.placement.piece.isHorizontal ? drop.placement.piece.length : 1,
              fromRow: drop.startRow,
              toRow: drop.placement.row,
              life: 0.32,
            ));
          }
        case PieceLanded(:final placement, :final dropped):
          landings.add(Landing(placement: placement, life: 0.24, dropped: dropped));
          // The field recoils the way the piece was travelling on screen.
          final (dx, dy) = _travelOnScreen(RotationTransform.slotOfSide(active, placement.side));
          final force = dropped ? 0.3 : 0.08;
          _kick(dx * force, dy * force);
          if (dropped) _sparks(placement, engine);
        case MatchScored(:final combo):
          _addShake(0.05 + 0.04 * combo);
          if (screenShake) punch = math.min(0.06, 0.012 * combo);
        case GlassAdded(:final side):
          // A ring runs out from the far end of the glass as it is finished.
          final config = engine.config;
          final far = _farEnd(side, config.armLength + config.boardSize / 2);
          rings.add(Ring(
            x: far.dx,
            y: far.dy,
            age: 0,
            life: 0.7,
            color: const Color(0xFF78CDFF),
            reach: 3,
          ));
          _addShake(0.04);
        default:
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
    if (state.phase == GamePhase.clearing && match != null && !identical(match, _burstMatch)) {
      _burstMatch = match;
      _burst(match, engine);
    }

    _trackSteps(engine);

    // A turn from standstill peaks at 1.5 quarter turns per turnSeconds.
    turnMotion = math.min(1, (_turnSpeedAt(_turnProgress).abs() * turnSeconds) / 1.5);

    // Spring back to rest.
    const stiffness = 520.0;
    const damping = 30.0;
    _kickVx += (-stiffness * kickX - damping * _kickVx) * seconds;
    _kickVy += (-stiffness * kickY - damping * _kickVy) * seconds;
    kickX += _kickVx * seconds;
    kickY += _kickVy * seconds;
    _shake *= math.exp(-14 * seconds);
    punch *= math.exp(-9 * seconds);
    // Everything comes to a dead stop instead of creeping towards it for
    // ever: a field at rest is drawn on whole pixels, and a field that is
    // known to be at rest need not be drawn again.
    if (_shake < 1e-4) _shake = 0;
    if (punch < 1e-5) punch = 0;
    if (kickX.abs() < 1e-4 && _kickVx.abs() < 1e-3) {
      kickX = 0;
      _kickVx = 0;
    }
    if (kickY.abs() < 1e-4 && _kickVy.abs() < 1e-3) {
      kickY = 0;
      _kickVy = 0;
    }
    shakeX = (_random.nextDouble() * 2 - 1) * _shake;
    shakeY = (_random.nextDouble() * 2 - 1) * _shake;

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
    for (final flash in flashes) {
      flash.age += seconds;
    }
    flashes.removeWhere((flash) => flash.age >= flash.life);
    for (final veil in veils) {
      veil.age += seconds;
    }
    veils.removeWhere((veil) => veil.age >= veil.life);

    final rate = math.min(1.0, seconds * 18);
    for (final side in Side.values) {
      final target = side == engine.activeSide ? 1.0 : 0.0;
      final next = activeness[side.index] + (target - activeness[side.index]) * rate;
      activeness[side.index] = (target - next).abs() < 0.002 ? target : next;
    }
  }

  /// True when nothing is animating: no turn, no shake, no particles. Two
  /// frames drawn while this holds look the same unless the game moved.
  bool get settled =>
      particles.isEmpty &&
      rings.isEmpty &&
      beams.isEmpty &&
      landings.isEmpty &&
      flashes.isEmpty &&
      veils.isEmpty &&
      kickX == 0 &&
      kickY == 0 &&
      _shake == 0 &&
      punch == 0 &&
      _turnProgress >= 1 &&
      activeness.every((lit) => lit == 0 || lit == 1);

  /// What is left of the current turn, in radians: 0 once the cross has
  /// arrived. Blocks are drawn upright at the end of the turn, so until then
  /// each of them is turned by this much.
  double get turnLeft => viewAngle - _toTurns * _quarter;

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
        _steps[side] = _StepTrack(
          piece: piece,
          row: piece.row,
          orientation: piece.piece.orientation,
          steppedAt: clock,
        );
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

  /// Every popped block bursts. In the varied style each line shows its own
  /// kind of explosion; several lines at once send a wave out from each of
  /// them, and three or more also flash the whole field.
  void _burst(MatchResult match, GameEngine engine) {
    final board = engine.board;
    final half = board.size / 2;
    Offset at(CellPosition cell) => Offset(-half + cell.col + 0.5, -half + cell.row + 0.5);
    final varied = explosion == ExplosionStyle.varied;
    final shot = <CellPosition>{};

    for (final run in match.runs) {
      final sig = varied ? _signatures[math.min(6, run.length) - 3] : _unified;
      for (final cell in run.cells) {
        if (!shot.add(cell)) continue;
        final color = board.colorAt(cell);
        if (color == null) continue;
        final p = at(cell);
        final tones = BlockTones.of(color);
        _shards(p, tones, sig);
        for (var r = 0; r < sig.rings; r++) {
          rings.add(Ring(
            x: p.dx,
            y: p.dy,
            age: -0.05 * r,
            life: 0.34 + 0.05 * r,
            color: tones.base,
            reach: 1.25 + 0.3 * r,
          ));
        }
      }
      if (varied) {
        if (sig.flash > 0) {
          final a = at(run.cells.first);
          final b = at(run.cells.last);
          flashes.add(Flash(
            x0: math.min(a.dx, b.dx) - 0.5,
            y0: math.min(a.dy, b.dy) - 0.5,
            x1: math.max(a.dx, b.dx) + 0.5,
            y1: math.max(a.dy, b.dy) + 0.5,
            life: sig.flash,
            color: sig.gold ? const Color(0xFFFFD76A) : const Color(0xFFFFFFFF),
          ));
        }
        _addShake(sig.shake);
      }
    }

    if (varied && match.runs.length >= 2) {
      for (var i = 1; i < match.runs.length; i++) {
        final run = match.runs[i];
        final mid = at(run.cells[run.cells.length ~/ 2]);
        rings.add(Ring(
          x: mid.dx,
          y: mid.dy,
          age: -0.08 * i,
          life: 0.55,
          color: const Color(0xFFFFFFFF),
          reach: 2.6,
        ));
      }
      _addShake(0.03 * (match.runs.length - 1));
    }
    if (varied && match.runs.length >= 3) veils.add(Veil(life: 0.2));
  }

  void _shards(Offset p, BlockTones tones, _Signature sig) {
    for (var i = 0; i < sig.shards; i++) {
      final angle = _random.nextDouble() * math.pi * 2;
      final speed = 2.5 + _random.nextDouble() * sig.speed;
      final gold = sig.gold && i % 4 == 0;
      particles.add(Particle(
        x: p.dx + (_random.nextDouble() - 0.5) * 0.5,
        y: p.dy + (_random.nextDouble() - 0.5) * 0.5,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed,
        size: 0.1 + _random.nextDouble() * 0.16,
        life: 0.3 + _random.nextDouble() * 0.3,
        color: gold
            ? const Color(0xFFFFD76A)
            : i % 3 == 0
                ? const Color(0xFFFFFFFF)
                : i % 3 == 1
                    ? tones.light
                    : tones.base,
      ));
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
}

/// The point at the far end of a glass, in world cells from the centre.
Offset _farEnd(Side side, double reach) {
  final turn = side.index * _quarter;
  return Offset(reach * math.sin(turn), -reach * math.cos(turn));
}

/// Screen direction in which a piece shown in [slot] travels.
(double, double) _travelOnScreen(Side slot) => switch (slot) {
      Side.top => (0.0, 1.0),
      Side.right => (-1.0, 0.0),
      Side.bottom => (0.0, -1.0),
      Side.left => (1.0, 0.0),
    };
