import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../game/config/game_config.dart';
import '../../game/engine/game_engine.dart';
import '../../game/engine/rotation_transform.dart';
import '../../game/model/color.dart';
import '../../game/model/incoming_piece.dart';
import '../../game/model/position.dart';
import '../../game/model/side.dart';
import '../../game/state/game_state.dart';
import '../style.dart';
import 'effects.dart';

/// Where a touch landed, in the turned view.
enum FieldZone { center, top, right, bottom, left, outside }

/// Measurements of the cross on a square canvas. Everything inside is drawn
/// in cell units.
class FieldGeometry {
  FieldGeometry(this.size, GameConfig config)
      : n = config.boardSize,
        arm = config.armLength,
        grid = config.gridSize;

  /// The cross is drawn a touch smaller than its canvas so that glows and
  /// the recoil of a hard drop are not clipped at the edges.
  static const fit = 0.965;

  /// Side of the square canvas, in logical pixels.
  final double size;
  final int n;
  final int arm;
  final int grid;

  double get half => n / 2;
  double get reach => n / 2 + arm;

  /// A cell of the grid the canvas is divided into.
  double get cell => size / grid;

  /// A cell as drawn at rest.
  double get drawnCell => cell * fit;

  /// The corner squares the cross leaves free, as a fraction of the canvas.
  double get cornerFraction => arm / grid;

  /// Which part of the cross is under a point of the canvas.
  FieldZone zoneAt(Offset point) {
    final cx = (point.dx - size / 2) / drawnCell;
    final cy = (point.dy - size / 2) / drawnCell;
    if (cx.abs() <= half && cy.abs() <= half) return FieldZone.center;
    if (cx.abs() <= half && cy.abs() <= reach) {
      return cy < 0 ? FieldZone.top : FieldZone.bottom;
    }
    if (cy.abs() <= half && cx.abs() <= reach) {
      return cx > 0 ? FieldZone.right : FieldZone.left;
    }
    return FieldZone.outside;
  }
}

/// Draws the whole playfield: the glasses sharing the central square, their
/// falling pieces, settled blocks and every effect.
///
/// Everything is drawn in cell units, in the world frame of the cross, and
/// turned as a whole by the view angle. The game model itself never rotates.
class FieldPainter extends CustomPainter {
  FieldPainter({
    required this.engine,
    required this.fx,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GameEngine engine;
  final Effects fx;

  static const _quarter = math.pi / 2;
  static const _accent = Color(0xFF78CDFF);
  static const _ice = Color(0xFFF0FAFF);
  static const _white = Color(0xFFFFFFFF);

  static final Map<BlockColor, ui.Picture> _sprites = {};

  @override
  bool shouldRepaint(FieldPainter oldDelegate) =>
      oldDelegate.engine != engine || oldDelegate.fx != fx;

  @override
  void paint(Canvas canvas, Size size) {
    final config = engine.config;
    final state = engine.state;
    final g = FieldGeometry(size.width, config);
    if (g.cell <= 0) return;
    final px = 1 / g.drawnCell;
    final scale = g.drawnCell * _viewScale(g);
    final origin = Offset(
      size.width / 2 + (fx.kickX + fx.shakeX) * g.cell,
      size.height / 2 + (fx.kickY + fx.shakeY) * g.cell,
    );

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale);
    canvas.rotate(fx.viewAngle);

    final building = state.phase == GamePhase.building ? state.buildingSide : null;
    final grow = building == null ? 1.0 : 1 - math.pow(1 - state.phaseProgress, 3).toDouble();
    _drawField(
      canvas,
      g,
      px,
      engine.sides,
      1 - 0.7 * fx.turnMotion,
      growing: building,
      grow: grow,
    );
    _drawActiveGlass(canvas, g, px);
    for (final side in engine.sides) {
      _drawCrowdedWarning(canvas, g, px, side);
    }
    for (final beam in fx.beams) {
      _drawBeam(canvas, g, beam);
    }
    for (final piece in state.incoming.values) {
      _drawAim(canvas, g, px, piece);
    }
    _drawSettled(canvas, g, state);
    _drawFlashes(canvas, g);
    _drawRings(canvas, px);
    _drawParticles(canvas);
    for (final piece in state.incoming.values) {
      _drawIncoming(canvas, g, px, piece);
    }
    _drawDrop(canvas, g, state);
    canvas.restore();

    for (final piece in state.incoming.values) {
      _drawCountdown(canvas, g, origin, scale, piece);
    }
  }

  /// Zoom of the cross. Turned off its axes, the corners of the arms reach
  /// further out than the canvas is wide, so mid-turn the cross shrinks by
  /// exactly as much as it takes to keep them in — and not a bit more,
  /// because a field that pumps in and out is tiring to watch.
  double _viewScale(FieldGeometry g) {
    final cos = math.cos(fx.viewAngle).abs();
    final sin = math.sin(fx.viewAngle).abs();
    final extent = math.max(g.reach * cos + g.half * sin, g.reach * sin + g.half * cos);
    final room = g.grid / 2 / FieldGeometry.fit - 0.25;
    return math.min(1.0, room / extent) + fx.punch;
  }

  // ---------------------------------------------------------------- sprites

  /// One recorded block per colour: flat, with a lit top edge and a shaded
  /// bottom one, a cell wide and centred on the origin.
  static int _spriteRevision = -1;

  static ui.Picture _sprite(BlockColor color) {
    if (_spriteRevision != BlockTones.revision) {
      _sprites.clear();
      _spriteRevision = BlockTones.revision;
    }
    return _sprites.putIfAbsent(color, () {
        final tones = BlockTones.of(color);
        final recorder = ui.PictureRecorder();
        final g = Canvas(recorder);
        const pad = 0.045;
        const radius = 0.16;
        const inset = 0.16;
        final body = Rect.fromLTRB(-0.5 + pad, -0.5 + pad, 0.5 - pad, 0.5 - pad);
        g.drawRRect(
          RRect.fromRectAndRadius(body, const Radius.circular(radius)),
          Paint()
            ..shader = ui.Gradient.linear(
              body.topCenter,
              body.bottomCenter,
              [tones.light, tones.base, tones.dark],
              const [0, 0.3, 1],
            ),
        );
        // A flat face set into the bevel, with a soft highlight across its top.
        final face = RRect.fromRectAndRadius(
          Rect.fromLTRB(-0.5 + inset, -0.5 + inset, 0.5 - inset, 0.5 - inset),
          const Radius.circular(radius * 0.6),
        );
        g.drawRRect(face, Paint()..color = tones.base);
        g.drawRRect(
          face,
          Paint()
            ..shader = ui.Gradient.linear(
              face.outerRect.topCenter,
              face.outerRect.center,
              const [Color(0x61FFFFFF), Color(0x00FFFFFF)],
            ),
        );
        return recorder.endRecording();
    });
  }

  static final _flashShape = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-0.455, -0.455, 0.455, 0.455),
    const Radius.circular(0.15),
  );

  /// Draws one block centred at ([x], [y]). [quarter] is the extra turn of
  /// the canvas at this point, so the block's lit edge ends up facing the top
  /// of the screen however the cross is turned.
  void _block(
    Canvas canvas,
    BlockColor color,
    double x,
    double y,
    int quarter, {
    double scaleX = 1,
    double scaleY = 1,
    double flash = 0,
  }) {
    canvas.save();
    canvas.translate(x, y);
    if (scaleX != 1 || scaleY != 1) canvas.scale(scaleX, scaleY);
    canvas.rotate(-(fx.targetTurns + quarter) * _quarter);
    canvas.drawPicture(_sprite(color));
    if (flash > 0) {
      canvas.drawRRect(
        _flashShape,
        Paint()..color = _white.withValues(alpha: math.min(1.0, flash)),
      );
    }
    canvas.restore();
  }

  // -------------------------------------------------------------- playfield

  /// The cross: the central square and the arm of every glass in play.
  /// [lines] fades the grid while the cross is turning.
  void _drawField(
    Canvas canvas,
    FieldGeometry g,
    double px,
    List<Side> sides,
    double lines, {
    Side? growing,
    double grow = 1,
  }) {
    final half = g.half;
    final reach = g.reach;
    final n = g.n.toDouble();
    final arm = g.arm.toDouble();

    final armFill = Paint()..color = const Color(0x06FFFFFF);
    final armGrid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = px
      ..color = _white.withValues(alpha: 0.045 * lines);
    for (final side in sides) {
      // A glass being built grows out of the centre.
      final length = side == growing ? arm * grow : arm;
      final armRect = Rect.fromLTWH(-half, -half - length, n, length);
      canvas.save();
      canvas.rotate(side.index * _quarter);
      canvas.drawRect(armRect, armFill);
      canvas.save();
      canvas.clipRect(armRect);
      final path = Path();
      for (var i = 1; i < g.n; i++) {
        path
          ..moveTo(-half + i, -reach)
          ..lineTo(-half + i, -half);
      }
      for (var j = 1; j < g.arm; j++) {
        path
          ..moveTo(-half, -reach + j)
          ..lineTo(half, -reach + j);
      }
      canvas.drawPath(path, armGrid);
      canvas.restore();
      canvas.restore();
    }
    if (growing != null && grow < 1) {
      // The leading edge of the glass that is growing.
      canvas.save();
      canvas.rotate(growing.index * _quarter);
      final edge = -half - arm * grow;
      canvas.drawLine(
        Offset(-half, edge),
        Offset(half, edge),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2 * px
          ..color = _accent.withValues(alpha: 0.9 * (1 - grow)),
      );
      canvas.restore();
    }

    canvas.drawRect(
      Rect.fromLTWH(-half, -half, n, n),
      Paint()..color = const Color(0x0DFFFFFF),
    );
    final centre = Path();
    for (var i = 1; i < g.n; i++) {
      centre
        ..moveTo(-half + i, -half)
        ..lineTo(-half + i, half)
        ..moveTo(-half, -half + i)
        ..lineTo(half, -half + i);
    }
    canvas.drawPath(
      centre,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = px
        ..color = _white.withValues(alpha: 0.07 * lines),
    );

    // Outline of the whole cross — an arm where a glass is in play, the wall
    // of the centre where there is none — and of the centre, brighter.
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * px
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0x29FFFFFF);
    for (final side in Side.values) {
      canvas.save();
      canvas.rotate(side.index * _quarter);
      final path = Path()..moveTo(-half, -half);
      if (sides.contains(side)) {
        final top = side == growing ? -half - arm * grow : -reach;
        path
          ..lineTo(-half, top)
          ..lineTo(half, top)
          ..lineTo(half, -half);
      } else {
        path.lineTo(half, -half);
      }
      canvas.drawPath(path, outline);
      canvas.restore();
    }
    canvas.drawRect(
      Rect.fromLTWH(-half, -half, n, n),
      outline..color = const Color(0x38FFFFFF),
    );
  }

  /// The active glass is one tall well — its arm and the central square —
  /// open at the top, with bright walls and a heavy floor.
  void _drawActiveGlass(Canvas canvas, FieldGeometry g, double px) {
    final half = g.half;
    final reach = g.reach;
    for (final side in Side.values) {
      final lit = fx.activeness[side.index];
      if (lit < 0.01) continue;
      canvas.save();
      canvas.rotate(side.index * _quarter);

      final well = Rect.fromLTRB(-half, -reach, half, half);
      canvas.drawRect(
        well,
        Paint()
          ..shader = ui.Gradient.linear(
            well.topCenter,
            well.bottomCenter,
            [
              _accent.withValues(alpha: 0.13 * lit),
              _accent.withValues(alpha: 0.035 * lit),
            ],
          ),
      );

      final walls = Path()
        ..moveTo(-half, -reach)
        ..lineTo(-half, half)
        ..lineTo(half, half)
        ..lineTo(half, -reach);
      final floor = Path()
        ..moveTo(-half, half)
        ..lineTo(half, half);
      // A soft halo first, then the crisp lines on top of it.
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 5 * px
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * px)
        ..color = _accent.withValues(alpha: 0.6 * lit);
      canvas.drawPath(walls, glow);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.2 * px
        ..color = _ice.withValues(alpha: 0.95 * lit);
      canvas.drawPath(walls, line);
      canvas.drawPath(floor, line..strokeWidth = 4.5 * px);
      canvas.restore();
    }
  }

  /// A glass that is nearly full up to its far end pulses red there.
  void _drawCrowdedWarning(Canvas canvas, FieldGeometry g, double px, Side side) {
    final over = engine.isGameOver;
    if (over ? engine.state.gameOverSide != side : !engine.isCrowded(side)) {
      return;
    }
    final half = g.half;
    final reach = g.reach;
    final pulse = over ? 1.0 : 0.5 + 0.5 * math.sin(fx.clock * 9);
    canvas.save();
    canvas.rotate(side.index * _quarter);
    final wash = Rect.fromLTRB(-half, -reach, half, -half);
    canvas.drawRect(
      wash,
      Paint()
        ..shader = ui.Gradient.linear(
          wash.topCenter,
          wash.bottomCenter,
          [
            Palette.danger.withValues(alpha: 0.1 + 0.2 * pulse),
            Palette.danger.withValues(alpha: 0.02),
          ],
        ),
    );
    final edge = Path()
      ..moveTo(-half, -reach)
      ..lineTo(half, -reach);
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * px
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * px)
        ..color = Palette.danger.withValues(alpha: 0.8),
    );
    canvas.drawPath(
      edge,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * px
        ..color = Palette.danger.withValues(alpha: 0.5 + 0.5 * pulse),
    );
    canvas.restore();
  }

  /// The streak a hard drop leaves down its lane.
  void _drawBeam(Canvas canvas, FieldGeometry g, Beam beam) {
    final t = beam.age / beam.life;
    final fade = (1 - t) * (1 - t);
    final rect = Rect.fromLTRB(
      -g.half + beam.column,
      -g.reach + beam.fromRow,
      -g.half + beam.column + beam.width,
      -g.reach + beam.toRow,
    );
    if (rect.height <= 0) return;
    canvas.save();
    canvas.rotate(beam.side.index * _quarter);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(
          rect.topCenter,
          rect.bottomCenter,
          [const Color(0x00FFFFFF), _white.withValues(alpha: 0.34 * fade)],
        ),
    );
    canvas.restore();
  }

  /// Where a piece will land: the lane of the active one, and an outline of
  /// its resting place. Pieces nobody is steering only show theirs faintly
  /// until they are about to lock.
  void _drawAim(Canvas canvas, FieldGeometry g, double px, IncomingPiece piece) {
    final placement = engine.previewDrop(piece.side);
    if (placement == null || placement.row == piece.row || engine.isGameOver) {
      return;
    }
    final lit = fx.activeness[piece.side.index];
    final urgent = (engine.secondsToLock(piece.side) ?? 99) < 6;
    final strength = math.max(lit, urgent ? 0.4 : 0.16);

    final left = -g.half + piece.column;
    final top = -g.reach + piece.row - fx.slideLeft(piece) + piece.piece.depth;
    final bottom = -g.reach + placement.row;

    canvas.save();
    canvas.rotate(piece.side.index * _quarter);
    if (lit > 0.05 && bottom > top) {
      final lane = Rect.fromLTRB(left, top, left + piece.piece.width, bottom);
      canvas.drawRect(
        lane,
        Paint()
          ..shader = ui.Gradient.linear(
            lane.topCenter,
            lane.bottomCenter,
            [
              _white.withValues(alpha: 0.02 * lit),
              _white.withValues(alpha: 0.085 * lit),
            ],
          ),
      );
    }
    final offsets = piece.piece.offsets;
    for (var i = 0; i < offsets.length; i++) {
      final tone = BlockTones.of(piece.piece.colors[i]).base;
      final shape = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left + offsets[i].col + 0.07,
          -g.reach + placement.row + offsets[i].row + 0.07,
          0.86,
          0.86,
        ),
        const Radius.circular(0.14),
      );
      canvas.drawRRect(shape, Paint()..color = tone.withValues(alpha: 0.14 * strength));
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6 * px
          ..color = tone.withValues(alpha: 0.9 * strength),
      );
    }
    canvas.restore();
  }

  // ------------------------------------------------------------------ blocks

  void _drawSettled(Canvas canvas, FieldGeometry g, GameState state) {
    final board = state.board;
    final origin = -g.grid / 2;
    final matched = state.activeMatch?.cells ?? const <CellPosition>{};
    final moving = {for (final move in state.moves) move.to};

    // Cells still reacting to a landing are drawn in their own pass.
    final landing = <CellPosition, Landing>{};
    for (final effect in fx.landings) {
      for (final cell in effect.placement.cells) {
        if (board.colorAt(cell.position) == cell.color &&
            !matched.contains(cell.position) &&
            !moving.contains(cell.position)) {
          landing[cell.position] = effect;
        }
      }
    }

    for (final block in board.blocks) {
      final at = block.position;
      if (matched.contains(at) || moving.contains(at) || landing.containsKey(at)) {
        continue;
      }
      _block(canvas, block.color, origin + at.col + 0.5, origin + at.row + 0.5, 0);
    }

    // Falling: each block accelerates over its own distance, so short falls
    // land first, and wobbles once when it arrives.
    if (state.moves.isNotEmpty) {
      final side = state.activeSide;
      final bounce = engine.config.fallBounceSeconds / engine.config.animationSpeed;
      canvas.save();
      canvas.rotate(side.index * _quarter);
      for (final move in state.moves) {
        final from = RotationTransform.worldToView(move.from, side, board.size);
        final to = RotationTransform.worldToView(move.to, side, board.size);
        final flight = engine.config.fallSeconds(move.distance);
        final t = math.min(1.0, state.phaseElapsed / flight);
        final row = from.row + (to.row - from.row) * t * t;
        var scaleX = 1.0;
        var scaleY = 1 + 0.12 * math.sin(t * math.pi);
        if (t >= 1) {
          final b = math.min(1.0, (state.phaseElapsed - flight) / bounce);
          final wave = math.sin(b * math.pi) * (1 - b);
          scaleY = 1 - 0.3 * wave;
          scaleX = 1 + 0.16 * wave;
        }
        _block(
          canvas,
          move.color,
          origin + to.col + 0.5,
          origin + row + 0.5 + 0.44 * (1 - math.min(scaleY, 1.0)),
          side.index,
          scaleX: scaleX,
          scaleY: scaleY,
        );
      }
      canvas.restore();
    }

    // Match: flash to white and swell, then collapse while shards fly off.
    if (matched.isNotEmpty) {
      final t = state.phaseProgress;
      final popping = state.phase == GamePhase.clearing;
      final scale = popping
          ? 1.22 * math.max(0.0, 1 - t * 1.7)
          : 1 + 0.22 * (1 - (1 - t) * (1 - t));
      final flash = popping ? 1.0 : 0.3 + 0.7 * t;
      if (scale > 0.01) {
        for (final cell in matched) {
          final color = board.colorAt(cell);
          if (color == null) continue;
          _block(
            canvas,
            color,
            origin + cell.col + 0.5,
            origin + cell.row + 0.5,
            0,
            scaleX: scale,
            scaleY: scale,
            flash: flash,
          );
        }
      }
    }

    // Landing: a white flash, and after a hard drop a squash along the fall.
    for (final effect in fx.landings) {
      final u = effect.age / effect.life;
      final wave = effect.dropped ? math.sin(u * math.pi * 2) * (1 - u) : 0.0;
      final scaleY = 1 - 0.26 * wave;
      final scaleX = 1 + 0.15 * wave;
      final side = effect.placement.side;
      canvas.save();
      canvas.rotate(side.index * _quarter);
      for (final cell in effect.placement.cells) {
        if (!identical(landing[cell.position], effect)) continue;
        final local = RotationTransform.worldToView(cell.position, side, board.size);
        _block(
          canvas,
          cell.color,
          origin + local.col + 0.5,
          origin + local.row + 0.5 + 0.44 * (1 - math.min(scaleY, 1.0)),
          side.index,
          scaleX: scaleX,
          scaleY: scaleY,
          flash: 0.85 * (1 - u) * (1 - u),
        );
      }
      canvas.restore();
    }
  }

  /// Bars of light over popped lines, and the wash of a triple clear.
  void _drawFlashes(Canvas canvas, FieldGeometry g) {
    for (final flash in fx.flashes) {
      canvas.drawRect(
        Rect.fromLTRB(flash.x0, flash.y0, flash.x1, flash.y1),
        Paint()..color = flash.color.withValues(alpha: 0.85 * (1 - flash.age / flash.life)),
      );
    }
    final extent = g.grid.toDouble();
    for (final veil in fx.veils) {
      canvas.drawRect(
        Rect.fromLTWH(-extent, -extent, 2 * extent, 2 * extent),
        Paint()..color = _white.withValues(alpha: 0.22 * (1 - veil.age / veil.life)),
      );
    }
  }

  void _drawRings(Canvas canvas, double px) {
    for (final ring in fx.rings) {
      if (ring.age < 0) continue;
      final t = ring.age / ring.life;
      final eased = 1 - (1 - t) * (1 - t);
      canvas.drawCircle(
        Offset(ring.x, ring.y),
        0.3 + ring.reach * eased,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(px, 0.16 * (1 - t))
          ..color = ring.color.withValues(alpha: 0.75 * (1 - t)),
      );
    }
  }

  void _drawParticles(Canvas canvas) {
    final paint = Paint();
    for (final particle in fx.particles) {
      final strength = 1 - particle.age / particle.life;
      final size = particle.size * (0.4 + 0.6 * strength);
      paint.color = particle.color.withValues(alpha: strength.clamp(0.0, 1.0));
      canvas.drawRect(
        Rect.fromCenter(center: Offset(particle.x, particle.y), width: size, height: size),
        paint,
      );
    }
  }

  void _drawIncoming(Canvas canvas, FieldGeometry g, double px, IncomingPiece piece) {
    final side = piece.side;
    final lit = fx.activeness[side.index];
    final secondsLeft = engine.secondsToLock(side) ?? 0;
    final urgent = secondsLeft < 3;

    final top = -g.reach + piece.row - fx.slideLeft(piece);
    final left = -g.half + piece.column;

    canvas.save();
    canvas.rotate(side.index * _quarter);

    // Halo: white for the piece being steered, coloured when time runs out.
    final strength = math.max(lit, urgent ? 0.85 : 0.0);
    if (strength > 0.02) {
      final warn = urgent && lit < 0.5;
      final color = warn ? _urgencyColor(secondsLeft) : _ice;
      final pulse = warn ? 0.6 + 0.4 * math.sin(fx.clock * 10) : 1.0;
      final shape = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          left - 0.03,
          top - 0.03,
          piece.piece.width + 0.06,
          piece.piece.depth + 0.06,
        ),
        const Radius.circular(0.2),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * px
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * px)
          ..color = color.withValues(alpha: 0.7 * strength),
      );
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * px
          ..color = color.withValues(alpha: 0.95 * strength * pulse),
      );
    }

    final offsets = piece.piece.offsets;
    for (var i = 0; i < offsets.length; i++) {
      _block(
        canvas,
        piece.piece.colors[i],
        left + offsets[i].col + 0.5,
        top + offsets[i].row + 0.5,
        side.index,
      );
    }
    canvas.restore();
  }

  /// A hard-dropped piece streaking down to where it lands.
  void _drawDrop(Canvas canvas, FieldGeometry g, GameState state) {
    final drop = state.drop;
    if (drop == null) return;
    final t = state.phaseProgress;
    final row = drop.startRow + (drop.placement.row - drop.startRow) * t * t;
    final left = -g.half + drop.placement.column;
    final top = -g.reach + row;

    canvas.save();
    canvas.rotate(drop.placement.side.index * _quarter);
    final offsets = drop.placement.piece.offsets;
    for (var i = 0; i < offsets.length; i++) {
      _block(
        canvas,
        drop.placement.piece.colors[i],
        left + offsets[i].col + 0.5,
        top + offsets[i].row + 0.5,
        drop.placement.side.index,
        scaleY: 1 + 0.18 * t,
        flash: 0.25 * t,
      );
    }
    canvas.restore();
  }

  /// Seconds until a piece locks by itself, written upright beside it.
  void _drawCountdown(
    Canvas canvas,
    FieldGeometry g,
    Offset origin,
    double scale,
    IncomingPiece piece,
  ) {
    if (engine.isGameOver) return;
    final secondsLeft = engine.secondsToLock(piece.side) ?? 0;
    final lit = fx.activeness[piece.side.index];
    // The piece being steered only needs its timer when it is about to lock.
    if (lit > 0.5 && secondsLeft >= 3) return;

    // A point just beyond the left end of the piece, in its glass's frame…
    final localX = -g.half + piece.column - 0.85;
    final localY =
        -g.reach + piece.row - fx.slideLeft(piece) + piece.piece.depth / 2;
    // …turned with its glass and with the cross into screen pixels.
    final angle = fx.viewAngle + piece.side.index * _quarter;
    final centre = origin +
        Offset(
          (localX * math.cos(angle) - localY * math.sin(angle)) * scale,
          (localX * math.sin(angle) + localY * math.cos(angle)) * scale,
        );

    final urgent = secondsLeft < 3;
    final text = TextPainter(
      text: TextSpan(
        text: secondsLeft < 10
            ? secondsLeft.toStringAsFixed(1)
            : secondsLeft.round().toString(),
        style: Type.body(
          math.max(9.0, g.cell * 0.78),
          weight: urgent ? FontWeight.w800 : FontWeight.w600,
          color: urgent
              ? _urgencyColor(secondsLeft)
              : Palette.text.withValues(alpha: 0.42),
          height: 1,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, centre - Offset(text.width / 2, text.height / 2));
  }

  static Color _urgencyColor(double secondsLeft) =>
      secondsLeft < 1.5 ? Palette.danger : Palette.warning;
}
