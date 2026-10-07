import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../game/config/game_config.dart';
import '../game/engine/game_engine.dart';
import '../game/engine/rotation_transform.dart';
import '../game/model/color.dart';
import '../game/model/incoming_piece.dart';
import '../game/model/position.dart';
import '../game/model/side.dart';
import '../game/state/game_state.dart';
import 'theme.dart';
import 'view_effects.dart';

/// Screen slot of the cross under a point, in the turned view: [top] is
/// always the arm of the active glass.
enum CrossZone { center, top, right, bottom, left, outside }

/// Shared measurements of the cross inside its square widget.
class CrossGeometry {
  CrossGeometry(this.size, GameConfig config)
      : boardSize = config.boardSize,
        armLength = config.armLength,
        cell = size.shortestSide / config.gridSize;

  final Size size;
  final int boardSize;
  final int armLength;

  /// Side of one cell in logical pixels.
  final double cell;

  CrossZone zoneAt(Offset point) {
    final x = (point.dx - size.width / 2) / cell;
    final y = (point.dy - size.height / 2) / cell;
    final half = boardSize / 2;
    final reach = half + armLength;
    if (x.abs() <= half && y.abs() <= half) return CrossZone.center;
    if (x.abs() <= half && y.abs() <= reach) {
      return y < 0 ? CrossZone.top : CrossZone.bottom;
    }
    if (y.abs() <= half && x.abs() <= reach) {
      return x > 0 ? CrossZone.right : CrossZone.left;
    }
    return CrossZone.outside;
  }
}

/// The whole playfield: four glasses sharing the central square, their
/// falling pieces, settled blocks and every engine-driven animation.
class CrossBoard extends StatelessWidget {
  const CrossBoard({
    super.key,
    required this.engine,
    required this.fx,
    required this.repaint,
  });

  final GameEngine engine;
  final ViewEffects fx;

  /// Ticks once per frame.
  final Listenable repaint;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: CrossPainter(engine: engine, fx: fx, repaint: repaint),
      ),
    );
  }
}

class CrossPainter extends CustomPainter {
  CrossPainter({
    required this.engine,
    required this.fx,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GameEngine engine;
  final ViewEffects fx;

  static const _quarter = math.pi / 2;

  static final RRect _blockShape = RRect.fromRectAndRadius(
    Rect.fromCenter(center: Offset.zero, width: 0.88, height: 0.88),
    const Radius.circular(0.2),
  );

  ui.Picture? _grid;
  int _gridKey = -1;
  final Map<int, _BlockPaints> _blockPaints = {};
  double _blockPaintsAngle = double.nan;

  @override
  bool shouldRepaint(CrossPainter oldDelegate) =>
      oldDelegate.engine != engine || oldDelegate.fx != fx;

  @override
  void paint(Canvas canvas, Size size) {
    final config = engine.config;
    final state = engine.state;
    final n = config.boardSize;
    final arm = config.armLength;
    final half = n / 2;
    final geometry = CrossGeometry(size, config);
    final unit = geometry.cell * fx.viewScale;
    final angle = fx.viewAngle;

    // Everything inside this block is drawn in cell units, in the world frame
    // of the cross, and turned as a whole by the view angle. The game model
    // itself is never rotated.
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(unit);
    canvas.rotate(angle);

    canvas.drawPicture(_gridPicture(n, arm));
    _paintActiveGlass(canvas, half, arm);
    for (final piece in state.incoming.values) {
      _paintLane(canvas, piece, half, arm);
    }
    _paintSettled(canvas, state, half, arm, angle);
    _paintParticles(canvas);
    for (final piece in state.incoming.values) {
      _paintGhost(canvas, piece, half, arm);
    }
    for (final piece in state.incoming.values) {
      _paintIncoming(canvas, piece, half, arm, angle);
    }
    _paintDrop(canvas, state, half, arm, angle);
    for (final side in Side.values) {
      _paintCrowdedWarning(canvas, side, half, arm);
    }
    for (final piece in state.incoming.values) {
      _paintCountdown(canvas, piece, half, arm, angle, unit);
    }
    canvas.restore();

    _paintBanner(canvas, size, geometry.cell);
  }

  // ------------------------------------------------------------- playfield

  RRect _cellShape(double x, double y) => RRect.fromRectAndRadius(
        Rect.fromLTWH(x + 0.04, y + 0.04, 0.92, 0.92),
        const Radius.circular(0.12),
      );

  /// The static grid of all five areas, recorded once.
  ui.Picture _gridPicture(int n, int arm) {
    final key = n * 1000 + arm;
    if (_grid != null && _gridKey == key) return _grid!;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final half = n / 2;
    final reach = half + arm;

    final armGap = Paint()..color = NeonPalette.armGap;
    final armCell = Paint()..color = NeonPalette.armCell;
    for (final side in Side.values) {
      canvas.save();
      canvas.rotate(side.index * _quarter);
      canvas.drawRect(Rect.fromLTRB(-half, -reach, half, -half), armGap);
      for (var row = 0; row < arm; row++) {
        for (var col = 0; col < n; col++) {
          canvas.drawRRect(_cellShape(-half + col, -reach + row), armCell);
        }
      }
      canvas.restore();
    }

    final boardCell = Paint()..color = NeonPalette.boardCell;
    canvas.drawRect(
      Rect.fromLTRB(-half, -half, half, half),
      Paint()..color = NeonPalette.boardGap,
    );
    for (var row = 0; row < n; row++) {
      for (var col = 0; col < n; col++) {
        canvas.drawRRect(_cellShape(-half + col, -half + row), boardCell);
      }
    }

    // Faint outline of the whole cross.
    final cross = Path()
      ..moveTo(-half, -reach)
      ..lineTo(half, -reach)
      ..lineTo(half, -half)
      ..lineTo(reach, -half)
      ..lineTo(reach, half)
      ..lineTo(half, half)
      ..lineTo(half, reach)
      ..lineTo(-half, reach)
      ..lineTo(-half, half)
      ..lineTo(-reach, half)
      ..lineTo(-reach, -half)
      ..lineTo(-half, -half)
      ..close();
    canvas.drawPath(
      cross,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.06
        ..strokeJoin = StrokeJoin.round
        ..color = NeonPalette.outlineDim,
    );

    _grid = recorder.endRecording();
    _gridKey = key;
    return _grid!;
  }

  /// The active glass is one tall box: its arm and the central square,
  /// brighter than the rest and framed with a glow.
  void _paintActiveGlass(Canvas canvas, double half, int arm) {
    for (final side in Side.values) {
      final lit = fx.activeness[side]!;
      if (lit < 0.01) continue;
      canvas.save();
      canvas.rotate(side.index * _quarter);
      final glass = Rect.fromLTRB(-half, -half - arm, half, half);
      canvas.drawRect(
        glass,
        Paint()..color = NeonPalette.outline.withValues(alpha: 0.075 * lit),
      );
      canvas.drawRect(
        glass,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.34
          ..color = NeonPalette.outline.withValues(alpha: 0.5 * lit)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.38),
      );
      canvas.drawRect(
        glass,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.1
          ..strokeJoin = StrokeJoin.round
          ..color = Color.lerp(
            NeonPalette.outlineDim,
            const Color(0xFF9CEBFF),
            lit,
          )!,
      );
      canvas.restore();
    }
  }

  /// The hatched strip from a piece to where it will land.
  void _paintLane(Canvas canvas, IncomingPiece piece, double half, int arm) {
    final placement = engine.previewDrop(piece.side);
    if (placement == null) return;
    final lit = fx.activeness[piece.side]!;
    final farEnd = -half - arm;
    final left = -half + piece.column;
    final width = piece.piece.width.toDouble();
    final top = farEnd + _shownRow(piece) + piece.piece.depth;
    final bottom = farEnd + placement.row;
    if (bottom - top < 0.05) return;

    final strength = 0.35 + 0.65 * lit;
    canvas.save();
    canvas.rotate(piece.side.index * _quarter);
    final lane = Rect.fromLTRB(left, top, left + width, bottom);
    canvas.drawRect(
      lane,
      Paint()..color = NeonPalette.outline.withValues(alpha: 0.06 * strength),
    );
    canvas.clipRect(lane);
    final hatch = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.09
      ..color = NeonPalette.outline.withValues(alpha: 0.16 * strength);
    final rise = width * 0.5;
    for (var y = top; y < bottom + rise; y += 0.5) {
      canvas.drawLine(Offset(left, y), Offset(left + width, y - rise), hatch);
    }
    canvas.restore();
  }

  // ----------------------------------------------------------------- blocks

  void _paintSettled(
    Canvas canvas,
    GameState state,
    double half,
    int arm,
    double angle,
  ) {
    final board = state.board;
    final grid = board.size;
    final origin = -grid / 2;
    final matched = state.activeMatch?.cells ?? const <CellPosition>{};
    final moving = <CellPosition>{for (final move in state.moves) move.to};

    // Cells still squashing from a landing are drawn in their own pass.
    final squashing = <CellPosition>{};
    for (final landing in fx.landings) {
      for (final cell in landing.placement.cells) {
        final p = cell.position;
        if (board.colorAt(p) == cell.color &&
            !matched.contains(p) &&
            !moving.contains(p)) {
          squashing.add(p);
        }
      }
    }

    for (final block in board.blocks) {
      final p = block.position;
      if (matched.contains(p) || moving.contains(p) || squashing.contains(p)) {
        continue;
      }
      _paintBlock(canvas, origin + p.col + 0.5, origin + p.row + 0.5,
          block.color, 0, angle);
    }

    // Falling: each block accelerates over its own distance, so short falls
    // land first, and wobbles once when it arrives.
    if (state.moves.isNotEmpty) {
      final side = state.activeSide;
      canvas.save();
      canvas.rotate(side.index * _quarter);
      for (final move in state.moves) {
        final from = RotationTransform.worldToView(move.from, side, grid);
        final to = RotationTransform.worldToView(move.to, side, grid);
        final fallSeconds = engine.config.fallSeconds(move.distance);
        final t = (state.phaseElapsed / fallSeconds).clamp(0.0, 1.0);
        final row = from.row + (to.row - from.row) * t * t;
        var scaleX = 1.0;
        var scaleY = 1.0 + 0.10 * math.sin(t * math.pi); // stretched in flight
        if (t >= 1) {
          final bounceSeconds = engine.config.fallBounceSeconds /
              engine.config.animationSpeed;
          final b = ((state.phaseElapsed - fallSeconds) / bounceSeconds)
              .clamp(0.0, 1.0);
          final wave = math.sin(b * math.pi) * (1 - b);
          scaleY = 1 - 0.26 * wave;
          scaleX = 1 + 0.15 * wave;
        }
        _paintBlock(
          canvas,
          origin + to.col + 0.5,
          origin + row + 0.5 + 0.44 * (1 - math.min(scaleY, 1.0)),
          move.color,
          side.index,
          angle,
          scaleX: scaleX,
          scaleY: scaleY,
        );
      }
      canvas.restore();
    }

    // Match: flash to white and swell, then pop — the block collapses while
    // its shards (see ViewEffects) fly off.
    if (matched.isNotEmpty) {
      final t = state.phaseProgress;
      final popping = state.phase == GamePhase.clearing;
      final scale = popping
          ? 1.18 * math.max(0.0, 1 - t * 1.6)
          : 1 + 0.18 * (1 - (1 - t) * (1 - t));
      final flash = popping ? 0.95 : 0.25 + 0.7 * t;
      for (final p in matched) {
        final color = board.colorAt(p);
        if (color == null || scale <= 0.01) continue;
        _paintBlock(canvas, origin + p.col + 0.5, origin + p.row + 0.5, color,
            0, angle, scaleX: scale, scaleY: scale, flash: flash);
      }
    }

    // Landing: a quick squash and rebound along the direction of the fall.
    for (final landing in fx.landings) {
      final u = ((fx.clock - landing.startedAt) / ViewEffects.landingSeconds)
          .clamp(0.0, 1.0);
      final wave = math.sin(u * math.pi * 2) * (1 - u);
      final scaleY = 1 - 0.24 * wave;
      final scaleX = 1 + 0.14 * wave;
      final side = landing.placement.side;
      canvas.save();
      canvas.rotate(side.index * _quarter);
      for (final cell in landing.placement.cells) {
        if (!squashing.contains(cell.position)) continue;
        final v = RotationTransform.worldToView(cell.position, side, grid);
        _paintBlock(
          canvas,
          origin + v.col + 0.5,
          origin + v.row + 0.5 + 0.44 * (1 - scaleY),
          cell.color,
          side.index,
          angle,
          scaleX: scaleX,
          scaleY: scaleY,
        );
      }
      canvas.restore();
    }
  }

  void _paintParticles(Canvas canvas) {
    final paint = Paint();
    for (final particle in fx.particles) {
      final strength = particle.strength;
      paint.color = particle.color.withValues(alpha: strength);
      final size = particle.size * (0.5 + 0.5 * strength);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(particle.x, particle.y),
            width: size,
            height: size,
          ),
          Radius.circular(size * 0.25),
        ),
        paint,
      );
    }
  }

  /// The row a piece is drawn at: its real row, minus what is left of the
  /// short slide after its last step.
  double _shownRow(IncomingPiece piece) =>
      piece.row - fx.slideLeft(piece, engine.config.stepSlideSeconds);

  /// Outline of where a piece will come to rest.
  void _paintGhost(Canvas canvas, IncomingPiece piece, double half, int arm) {
    final placement = engine.previewDrop(piece.side);
    if (placement == null) return;
    // No ghost once the piece is there.
    if (placement.row == piece.row) return;
    final lit = fx.activeness[piece.side]!;
    final strength = 0.32 + 0.68 * lit;

    canvas.save();
    canvas.rotate(piece.side.index * _quarter);
    final offsets = piece.piece.offsets;
    for (var i = 0; i < offsets.length; i++) {
      final tones = NeonPalette.block(piece.piece.colors[i]);
      final shape = _blockShape.shift(Offset(
        -half + piece.column + offsets[i].col + 0.5,
        -half - arm + placement.row + offsets[i].row + 0.5,
      ));
      canvas.drawRRect(
        shape,
        Paint()..color = tones.base.withValues(alpha: 0.16 * strength),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.07
          ..color = tones.base.withValues(alpha: 0.85 * strength),
      );
    }
    canvas.restore();
  }

  void _paintIncoming(
    Canvas canvas,
    IncomingPiece piece,
    double half,
    int arm,
    double angle,
  ) {
    final side = piece.side;
    final lit = fx.activeness[side]!;
    final secondsLeft = engine.secondsToLock(side) ?? 0;
    final urgent = secondsLeft < 3.0;
    final urgency = _urgencyColor(secondsLeft);

    canvas.save();
    canvas.rotate(side.index * _quarter);

    final top = -half - arm + _shownRow(piece);
    final left = -half + piece.column.toDouble();
    final bounds = Rect.fromLTWH(
      left,
      top,
      piece.piece.width.toDouble(),
      piece.piece.depth.toDouble(),
    );

    // Halo: bright for the active piece, coloured when it is about to lock.
    final haloColor = urgent
        ? urgency
        : Color.lerp(NeonPalette.outlineDim, const Color(0xFFE8FBFF), lit)!;
    final haloStrength = math.max(lit, urgent ? 0.8 : 0.0);
    if (haloStrength > 0.01) {
      final halo = RRect.fromRectAndRadius(
        bounds.inflate(0.06),
        const Radius.circular(0.26),
      );
      canvas.drawRRect(
        halo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.3
          ..color = haloColor.withValues(alpha: 0.6 * haloStrength)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.3),
      );
      canvas.drawRRect(
        halo,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.07
          ..color = haloColor.withValues(alpha: haloStrength),
      );
    }

    // A piece nobody is steering that is about to lock gets a tilted frame —
    // "look here".
    if (urgent && lit < 0.5) {
      final pulse = 0.55 + 0.45 * math.sin(fx.clock * 9);
      final reach = math.max(bounds.width, bounds.height) / 2 + 0.75;
      canvas.save();
      canvas.translate(bounds.center.dx, bounds.center.dy);
      canvas.rotate(0.22);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: reach * 2, height: reach * 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.08
          ..color = urgency.withValues(alpha: pulse * (1 - lit)),
      );
      canvas.restore();
    }

    final offsets = piece.piece.offsets;
    for (var i = 0; i < offsets.length; i++) {
      _paintBlock(
        canvas,
        left + offsets[i].col + 0.5,
        top + offsets[i].row + 0.5,
        piece.piece.colors[i],
        side.index,
        angle,
      );
    }
    canvas.restore();
  }

  /// A hard-dropped piece streaking down to where it lands.
  void _paintDrop(
    Canvas canvas,
    GameState state,
    double half,
    int arm,
    double angle,
  ) {
    final drop = state.drop;
    if (drop == null) return;
    final t = state.phaseProgress;
    final eased = t * t; // accelerating
    final depth =
        drop.startRow + (drop.placement.row - drop.startRow) * eased;
    final piece = drop.piece;
    final top = -half - arm + depth;
    final left = -half + drop.placement.column.toDouble();

    canvas.save();
    canvas.rotate(drop.side.index * _quarter);

    // Light trail behind the piece.
    final trail = math.min(depth - drop.startRow, 1.0 + 4.0 * t);
    if (trail > 0.05) {
      canvas.drawRect(
        Rect.fromLTRB(left + 0.08, top - trail, left + piece.width - 0.08, top),
        Paint()
          ..shader = ui.Gradient.linear(
            Offset(0, top - trail),
            Offset(0, top),
            [const Color(0x00FFFFFF), const Color(0x40FFFFFF)],
          ),
      );
    }
    final offsets = piece.offsets;
    for (var i = 0; i < offsets.length; i++) {
      _paintBlock(
        canvas,
        left + offsets[i].col + 0.5,
        top + offsets[i].row + 0.5,
        piece.colors[i],
        drop.side.index,
        angle,
        scaleY: 1 + 0.12 * t,
      );
    }
    canvas.restore();
  }

  /// A glass that is nearly full up to its far end pulses red there.
  void _paintCrowdedWarning(Canvas canvas, Side side, double half, int arm) {
    if (engine.isGameOver || !engine.isCrowded(side)) return;
    final pulse = 0.5 + 0.5 * math.sin(fx.clock * 8);
    final farEnd = -half - arm;
    canvas.save();
    canvas.rotate(side.index * _quarter);
    canvas.drawRect(
      Rect.fromLTRB(-half, farEnd - 0.14, half, farEnd + 0.14),
      Paint()
        ..color = NeonPalette.danger.withValues(alpha: 0.35 + 0.6 * pulse)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.14),
    );
    canvas.drawRect(
      Rect.fromLTRB(-half, farEnd, half, -half),
      Paint()..color = NeonPalette.danger.withValues(alpha: 0.05 + 0.07 * pulse),
    );
    canvas.restore();
  }

  /// Seconds until the piece locks by itself, written upright next to the
  /// far end of its glass.
  void _paintCountdown(
    Canvas canvas,
    IncomingPiece piece,
    double half,
    int arm,
    double angle,
    double unit,
  ) {
    final side = piece.side;
    final secondsLeft = engine.secondsToLock(side) ?? 0;
    final lit = fx.activeness[side]!;

    final painter = TextPainter(
      text: TextSpan(
        text: secondsLeft.toStringAsFixed(1),
        style: TextStyle(
          color: secondsLeft < 3.0
              ? _urgencyColor(secondsLeft)
              : Color.lerp(NeonPalette.textDim, NeonPalette.text, lit),
          fontSize: 0.82 * unit,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    canvas.rotate(side.index * _quarter);
    canvas.translate(-half - 1.5, -half - arm + 0.8);
    canvas.rotate(-(angle + side.index * _quarter));
    canvas.scale(1 / unit);
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
    painter.dispose();
  }

  Color _urgencyColor(double secondsLeft) {
    if (secondsLeft < 1.5) return NeonPalette.danger;
    if (secondsLeft < 3.0) return NeonPalette.warning;
    return NeonPalette.outline;
  }

  /// One glossy block centred at ([cx], [cy]). [quarter] is the extra turn of
  /// the canvas at this point, so the light can keep coming from the top-left
  /// of the *screen* however the cross is rotated.
  void _paintBlock(
    Canvas canvas,
    double cx,
    double cy,
    BlockColor color,
    int quarter,
    double viewAngle, {
    double scaleX = 1,
    double scaleY = 1,
    double flash = 0,
  }) {
    final paints = _paintsFor(color, quarter, viewAngle);
    canvas.save();
    canvas.translate(cx, cy);
    if (scaleX != 1 || scaleY != 1) canvas.scale(scaleX, scaleY);
    canvas.drawRRect(_blockShape, paints.body);
    canvas.drawRRect(_blockShape, paints.gloss);
    canvas.drawRRect(_blockShape, paints.rim);
    if (flash > 0) {
      canvas.drawRRect(
        _blockShape,
        Paint()..color = Color.fromRGBO(255, 255, 255, flash.clamp(0.0, 1.0)),
      );
    }
    canvas.restore();
  }

  _BlockPaints _paintsFor(BlockColor color, int quarter, double viewAngle) {
    if (viewAngle != _blockPaintsAngle) {
      _blockPaints.clear();
      _blockPaintsAngle = viewAngle;
    }
    return _blockPaints.putIfAbsent(color.index * 4 + quarter % 4, () {
      final tones = NeonPalette.block(color);
      final rotation = viewAngle + quarter * _quarter;
      final sin = math.sin(rotation);
      final cos = math.cos(rotation);
      // A screen-space direction expressed in the turned local frame.
      Offset local(double x, double y) =>
          Offset(x * cos + y * sin, -x * sin + y * cos);
      final down = local(0, 0.46);
      return _BlockPaints(
        body: Paint()
          ..shader = ui.Gradient.linear(
            -down,
            down,
            [tones.light, tones.base, tones.dark],
            const [0.0, 0.42, 1.0],
          ),
        gloss: Paint()
          ..shader = ui.Gradient.radial(
            local(-0.15, -0.19),
            0.34,
            const [Color(0xD0FFFFFF), Color(0x00FFFFFF)],
          ),
        rim: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.05
          ..color = tones.dark,
      );
    });
  }

  // ----------------------------------------------------------------- banner

  /// "2× COMBO" in the empty corner at the top-left of the field, tilted.
  void _paintBanner(Canvas canvas, Size size, double cell) {
    final banner = fx.banner;
    if (banner == null) return;
    final u = ((fx.clock - banner.startedAt) / ViewEffects.bannerSeconds)
        .clamp(0.0, 1.0);
    final pop = u < 0.14
        ? 0.5 + 0.65 * (u / 0.14)
        : 1.15 - 0.15 * math.min(1.0, (u - 0.14) / 0.1);
    final alpha = u < 0.7 ? 1.0 : 1 - (u - 0.7) / 0.3;
    final isCombo = banner.combo > 1;

    TextPainter text(String value, double fontSize, Color color) => TextPainter(
          text: TextSpan(
            text: value,
            style: TextStyle(
              color: color.withValues(alpha: alpha),
              fontSize: fontSize,
              height: 1.0,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
              shadows: [
                Shadow(
                  color: color.withValues(alpha: 0.75 * alpha),
                  blurRadius: 14,
                ),
                Shadow(
                  color: const Color(0xFF000000).withValues(alpha: alpha),
                  blurRadius: 5,
                ),
              ],
            ),
          ),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.center,
        )..layout();

    final lines = [
      if (isCombo) ...[
        text('${banner.combo}×', 2.0 * cell, NeonPalette.warning),
        text('COMBO', 1.05 * cell, NeonPalette.warning),
      ],
      text('+${banner.score}', (isCombo ? 0.95 : 1.35) * cell, NeonPalette.text),
    ];

    final arm = engine.config.armLength;
    canvas.save();
    // Centre of the top-left corner square left free by the cross.
    canvas.translate(arm * cell / 2, arm * cell / 2);
    canvas.rotate(-0.16);
    canvas.scale(pop);
    final height = lines.fold(0.0, (sum, line) => sum + line.height);
    var y = -height / 2;
    for (final line in lines) {
      line.paint(canvas, Offset(-line.width / 2, y));
      y += line.height;
      line.dispose();
    }
    canvas.restore();
  }
}

class _BlockPaints {
  const _BlockPaints({
    required this.body,
    required this.gloss,
    required this.rim,
  });

  final Paint body;
  final Paint gloss;
  final Paint rim;
}
