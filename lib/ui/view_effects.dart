import 'dart:math' as math;
import 'dart:ui' show Color;

import '../game/engine/game_engine.dart';
import '../game/engine/game_event.dart';
import '../game/engine/match_detector.dart';
import '../game/engine/placement_engine.dart';
import '../game/model/incoming_piece.dart';
import '../game/model/piece.dart';
import '../game/model/side.dart';
import '../game/state/game_state.dart';
import 'theme.dart';

/// A piece that has just locked and is still squashing.
class LandingEffect {
  const LandingEffect(this.placement, this.startedAt);

  final Placement placement;
  final double startedAt;
}

/// The short text that pops up beside the field after a match.
class BannerEffect {
  const BannerEffect({
    required this.combo,
    required this.score,
    required this.startedAt,
  });

  final int combo;
  final int score;
  final double startedAt;
}

/// One shard of a popped block. Positions are in cells, relative to the
/// centre of the cross, in the world frame (they turn with the cross).
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

  /// 1 when born, 0 when gone.
  double get strength => (1 - age / life).clamp(0.0, 1.0);
}

/// Purely visual state layered on top of the engine: the turn of the cross,
/// highlight fades, landing squash, pop particles, combo banner. Nothing here
/// feeds back into the rules.
class ViewEffects {
  ViewEffects({required this.rotationSeconds});

  static const landingSeconds = 0.26;
  static const bannerSeconds = 1.2;
  static const _shardsPerBlock = 7;

  final double rotationSeconds;
  final math.Random _random = math.Random(1);

  /// Game-time clock all effects are measured against.
  double clock = 0;

  /// How strongly each glass is lit as the active one, 0..1.
  final Map<Side, double> activeness = {
    for (final side in Side.values) side: side == Side.top ? 1.0 : 0.0,
  };

  final List<LandingEffect> landings = [];
  final List<Particle> particles = [];
  BannerEffect? banner;

  /// The match whose blocks have already been turned into particles.
  MatchResult? _burstMatch;

  /// When the piece of each glass last moved a row, for its short slide.
  final Map<Side, _StepTrack> _steps = {};

  // The view angle is counted in quarter turns; negative is counter-clockwise.
  double _fromTurns = 0;
  double _toTurns = 0;
  double _turnStartedAt = double.negativeInfinity;
  double _turnDuration = 0;

  double get _turnProgress {
    if (_turnDuration <= 0) return 1;
    return ((clock - _turnStartedAt) / _turnDuration).clamp(0.0, 1.0);
  }

  bool get isTurning => _turnProgress < 1;

  /// Current rotation of the cross in radians (canvas convention: positive is
  /// clockwise on screen).
  double get viewAngle {
    final t = _turnProgress;
    final eased = 1 - math.pow(1 - t, 3).toDouble();
    return (_fromTurns + (_toTurns - _fromTurns) * eased) * math.pi / 2;
  }

  /// The cross shrinks a little mid-turn so its corners stay on screen.
  double get viewScale => 1 - 0.08 * math.sin(math.pi * _turnProgress);

  /// How much of a cell the piece still has to slide to reach its row: 1
  /// right after a step, 0 once it has arrived. The step itself is instant
  /// in the engine; this only softens how it looks.
  double slideLeft(IncomingPiece piece, double slideSeconds) {
    final track = _steps[piece.side];
    if (track == null || !identical(track.piece, piece)) return 0;
    final t = ((clock - track.steppedAt) / slideSeconds).clamp(0.0, 1.0);
    return (1 - t) * (1 - t);
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
        if (piece.row > track.row &&
            piece.piece.orientation == track.orientation) {
          track.steppedAt = clock;
        }
        track.row = piece.row;
        track.orientation = piece.piece.orientation;
      }
    }
  }

  void reset(Side active) {
    clock = 0;
    _steps.clear();
    landings.clear();
    particles.clear();
    banner = null;
    _burstMatch = null;
    _fromTurns = _toTurns = -active.index.toDouble();
    _turnStartedAt = double.negativeInfinity;
    for (final side in Side.values) {
      activeness[side] = side == active ? 1.0 : 0.0;
    }
  }

  /// Advances the effects and consumes the engine's events. The events are
  /// returned so the screen can add haptics and overlays.
  List<GameEvent> update(double seconds, GameEngine engine) {
    clock += seconds;

    final events = engine.drainEvents();
    for (final event in events) {
      switch (event) {
        case SideSwitched():
          // Bringing the next side to the top turns the cross anticlockwise.
          _fromTurns = viewAngle / (math.pi / 2);
          _toTurns -= event.quarterTurns;
          _turnStartedAt = clock;
          _turnDuration =
              rotationSeconds * (1 + 0.5 * (event.quarterTurns.abs() - 1));
        case PieceLanded():
          landings.add(LandingEffect(event.placement, clock));
        case MatchScored():
          banner = BannerEffect(
            combo: event.combo,
            score: event.score,
            startedAt: clock,
          );
        case PieceDropped():
        case CellsPopped():
        case GameEnded():
          break;
      }
    }

    _trackSteps(engine);

    // The moment matched blocks start to pop, they burst into shards.
    final state = engine.state;
    final match = state.activeMatch;
    if (state.phase == GamePhase.clearing &&
        match != null &&
        !identical(match, _burstMatch)) {
      _burstMatch = match;
      _burst(match, engine);
    }

    for (final particle in particles) {
      particle.age += seconds;
      particle.x += particle.vx * seconds;
      particle.y += particle.vy * seconds;
      final drag = math.max(0.0, 1 - 3.2 * seconds);
      particle.vx *= drag;
      particle.vy *= drag;
    }
    particles.removeWhere((particle) => particle.age >= particle.life);

    final rate = math.min(1.0, seconds * 14);
    for (final side in Side.values) {
      final target = side == engine.activeSide ? 1.0 : 0.0;
      activeness[side] = activeness[side]! + (target - activeness[side]!) * rate;
    }
    landings.removeWhere((l) => clock - l.startedAt > landingSeconds);
    if (banner != null && clock - banner!.startedAt > bannerSeconds) {
      banner = null;
    }
    return events;
  }

  void _burst(MatchResult match, GameEngine engine) {
    final board = engine.board;
    final half = board.size / 2;
    for (final cell in match.cells) {
      final color = board.colorAt(cell);
      if (color == null) continue;
      final tones = NeonPalette.block(color);
      for (var i = 0; i < _shardsPerBlock; i++) {
        final angle = _random.nextDouble() * math.pi * 2;
        final speed = 2.2 + _random.nextDouble() * 4.5;
        particles.add(Particle(
          x: -half + cell.col + 0.5 + (_random.nextDouble() - 0.5) * 0.5,
          y: -half + cell.row + 0.5 + (_random.nextDouble() - 0.5) * 0.5,
          vx: math.cos(angle) * speed,
          vy: math.sin(angle) * speed,
          size: 0.12 + _random.nextDouble() * 0.14,
          life: 0.32 + _random.nextDouble() * 0.28,
          color: i.isEven ? tones.light : tones.base,
        ));
      }
    }
  }
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
