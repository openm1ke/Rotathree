import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../game/config/game_config.dart';
import '../../game/engine/game_engine.dart';
import '../../game/engine/rotation_transform.dart';
import '../../game/model/color.dart';
import '../../game/model/incoming_piece.dart';
import '../../game/model/piece.dart';
import '../../game/model/position.dart';
import '../../game/model/side.dart';
import '../../game/state/game_state.dart';
import '../style.dart';
import 'effects.dart';
import 'field_viewport.dart';

const _quarter = math.pi / 2;

/// Cosine and sine of 0, 1, 2 and 3 quarter turns, exactly: `cos` of a
/// quarter turn is 6e-17, not 0, which is enough to nudge a block off the
/// pixel grid.
const _quarterCos = [1.0, 0.0, -1.0, 0.0];
const _quarterSin = [0.0, 1.0, 0.0, -1.0];

const _accent = Color(0xFF78CDFF);
const _ice = Color(0xFFF0FAFF);
const _white = Color(0xFFFFFFFF);

/// Colours of the halo round a piece: being steered, running out of time,
/// about to lock.
const _haloColors = [_ice, Palette.warning, Palette.danger];

/// Where a touch landed, in the turned view.
enum FieldZone { center, top, right, bottom, left, outside }

/// Measurements of the cross on a square canvas. Everything inside is drawn
/// in cell units.
class FieldGeometry {
  FieldGeometry(
    this.size,
    GameConfig config, {
    this.devicePixelRatio = 1,
    this.angle = 0,
    List<Side>? sides,
    Side? building,
    double progress = 1,
    bool reduceMotion = false,
    bool focusSingleGlass = false,
  }) : n = config.boardSize,
       arm = config.armLength,
       grid = config.gridSize,
       sides = sides ?? config.sides,
       viewport = FieldViewport.fit(
         boardSize: config.boardSize,
         armLength: config.armLength,
         sides: sides ?? config.sides,
         angle: angle,
         building: building,
         progress: progress,
         reduceMotion: reduceMotion,
         focusSingleGlass: focusSingleGlass,
       );

  /// The cross is drawn a touch smaller than its canvas so that glows and
  /// the recoil of a hard drop are not clipped at the edges.
  static const fit = 0.965;

  /// Side of the square canvas, in logical pixels.
  final double size;
  final double devicePixelRatio;
  final int n;
  final int arm;
  final int grid;
  final double angle;
  final List<Side> sides;
  final FieldViewport viewport;

  double get half => n / 2;
  double get reach => n / 2 + arm;

  /// A cell of the grid the canvas is divided into.
  double get cell => size / grid;

  /// Physical pixels to a cell while the cross is at rest. A whole number, so
  /// that a block is copied to the screen pixel for pixel.
  int get unit => math.max(1, (size * devicePixelRatio * fit / viewport.span).floor());

  /// A cell as drawn at rest, in logical pixels.
  double get drawnCell => unit / devicePixelRatio;

  Offset get origin => Offset(
    ((size / 2 - viewport.center.dx * drawnCell) * devicePixelRatio).round() / devicePixelRatio,
    ((size / 2 - viewport.center.dy * drawnCell) * devicePixelRatio).round() / devicePixelRatio,
  );

  /// The corner squares the cross leaves free, as a fraction of the canvas.
  double get cornerFraction => arm / grid;

  /// Which part of the cross is under a point of the canvas.
  FieldZone zoneAt(Offset point) {
    final cx = (point.dx - origin.dx) / drawnCell;
    final cy = (point.dy - origin.dy) / drawnCell;
    final c = math.cos(angle), s = math.sin(angle);
    final x = c * cx + s * cy, y = -s * cx + c * cy;
    if (x.abs() <= half && y.abs() <= half) return FieldZone.center;
    for (final side in sides) {
      final turn = side.index * _quarter;
      final rx = math.cos(turn) * x + math.sin(turn) * y;
      final ry = -math.sin(turn) * x + math.cos(turn) * y;
      if (rx.abs() <= half && ry <= -half && ry >= -reach) {
        return [
          FieldZone.top,
          FieldZone.right,
          FieldZone.bottom,
          FieldZone.left,
        ][(side.index + (angle / _quarter).round()) % 4];
      }
    }
    return FieldZone.outside;
  }
}

/// A glow drawn once into an image: a blur costs far more than the copy of
/// its result does.
class _Glow {
  _Glow(this.image, this.pad, this.unit)
    : source = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());

  final ui.Image image;

  /// Physical pixels between the edge of the image and the origin of its shape.
  final int pad;
  final int unit;
  final Rect source;

  /// Where the image goes when its shape's origin is at ([x], [y]), in cells.
  Rect at(double x, double y) => Rect.fromLTWH(x - pad / unit, y - pad / unit, image.width / unit, image.height / unit);
}

/// The seconds written beside a piece, laid out once for each text.
class _Label {
  String text = '';
  int tone = -1;
  double size = 0;
  TextPainter? painter;
}

/// Sprites of one image drawn in a single call.
class _Batch {
  Float32List _transforms = Float32List(1024);
  Float32List _sources = Float32List(1024);
  Int32List _tints = Int32List(256);
  int _count = 0;

  void add(double scos, double ssin, double tx, double ty, Rect source, [int tint = 0]) {
    if (_count == _tints.length) {
      _transforms = Float32List(_count * 8)..setAll(0, _transforms);
      _sources = Float32List(_count * 8)..setAll(0, _sources);
      _tints = Int32List(_count * 2)..setAll(0, _tints);
    }
    final i = _count * 4;
    _transforms[i] = scos;
    _transforms[i + 1] = ssin;
    _transforms[i + 2] = tx;
    _transforms[i + 3] = ty;
    _sources[i] = source.left;
    _sources[i + 1] = source.top;
    _sources[i + 2] = source.right;
    _sources[i + 3] = source.bottom;
    _tints[_count] = tint;
    _count++;
  }

  /// Draws what was added and empties the batch. With [tinted], each sprite
  /// is multiplied by its own colour.
  void draw(Canvas canvas, ui.Image atlas, Paint paint, {bool tinted = false}) {
    if (_count == 0) return;
    canvas.drawRawAtlas(
      atlas,
      Float32List.sublistView(_transforms, 0, _count * 4),
      Float32List.sublistView(_sources, 0, _count * 4),
      tinted ? Int32List.sublistView(_tints, 0, _count) : null,
      tinted ? BlendMode.modulate : null,
      null,
      paint,
    );
    _count = 0;
  }
}

/// What the field is drawn from, made once and reused every frame: the
/// blocks as an image, the glows as images, the lines as paths. Owned by the
/// game screen, which disposes of it.
class FieldAssets {
  /// Transparent pixels round each block of the atlas, so that neighbours do
  /// not bleed into one another when a block is drawn turned.
  static const _gutter = 1;

  /// Side of the white square that particles are tinted copies of.
  static const _patch = 4;

  static final _blockShape = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-0.455, -0.455, 0.455, 0.455),
    const Radius.circular(0.16),
  );
  static final _faceShape = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-0.34, -0.34, 0.34, 0.34),
    const Radius.circular(0.096),
  );
  static final _flashShape = RRect.fromRectAndRadius(
    const Rect.fromLTRB(-0.455, -0.455, 0.455, 0.455),
    const Radius.circular(0.15),
  );
  static const _unitRect = Rect.fromLTRB(-0.5, -0.5, 0.5, 0.5);

  /// White, fading in down a unit square: stretched over an aiming lane.
  static final ui.Shader _laneShader = ui.Gradient.linear(Offset.zero, const Offset(0, 1), const [
    Color(0x05FFFFFF),
    Color(0x16FFFFFF),
  ]);

  ui.Image? _atlas;
  int _unit = 0;
  int _revision = -1;
  final List<Rect> _blocks = [];
  Rect _whitePatch = Rect.zero;

  String _glowKey = '';
  _Glow? _well;
  _Glow? _warning;
  final Map<int, _Glow> _halos = {};

  int _pathN = -1;
  int _pathArm = -1;
  Path _armGrid = Path();
  Path _centreGrid = Path();
  Path _armOutline = Path();
  Path _wallOutline = Path();

  final Map<Side, _Label> _labels = {};
  final _Batch _batch = _Batch();
  final Paint _imagePaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _glowPaint = Paint()..filterQuality = FilterQuality.low;
  final Paint _flashPaint = Paint();
  final Float64List _matrix = Float64List(16)
    ..[10] = 1
    ..[15] = 1;

  // Reused by the pass that has to know which cells are in motion.
  final Set<CellPosition> _moving = {};
  final Map<CellPosition, Landing> _landing = {};

  void dispose() {
    _atlas?.dispose();
    _atlas = null;
    _disposeGlows();
    for (final label in _labels.values) {
      label.painter?.dispose();
    }
    _labels.clear();
  }

  void _disposeGlows() {
    _well?.image.dispose();
    _warning?.image.dispose();
    for (final halo in _halos.values) {
      halo.image.dispose();
    }
    _well = null;
    _warning = null;
    _halos.clear();
    _glowKey = '';
  }

  /// Makes sure everything fits the canvas, the board and the palette.
  void _prepare(FieldGeometry g) {
    final unit = g.unit;
    if (_atlas == null || unit != _unit || _revision != BlockTones.revision) {
      _unit = unit;
      _revision = BlockTones.revision;
      _makeAtlas(unit);
    }
    final glowKey = '$unit:${g.devicePixelRatio}:${g.n}:${g.arm}';
    if (glowKey != _glowKey) {
      _disposeGlows();
      _glowKey = glowKey;
      _makeGlows(g);
    }
    if (g.n != _pathN || g.arm != _pathArm) {
      _pathN = g.n;
      _pathArm = g.arm;
      _makePaths(g);
    }
  }

  /// One block per colour, exactly a cell big — flat, with a lit top edge and
  /// a shaded bottom one — and a white square for the particles.
  void _makeAtlas(int unit) {
    _atlas?.dispose();
    final pitch = unit + 2 * _gutter;
    final count = BlockColor.values.length;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    _blocks.clear();
    for (final color in BlockColor.values) {
      final left = (color.index * pitch + _gutter).toDouble();
      final top = _gutter.toDouble();
      _blocks.add(Rect.fromLTWH(left, top, unit.toDouble(), unit.toDouble()));
      canvas.save();
      canvas.translate(left + unit / 2, top + unit / 2);
      canvas.scale(unit.toDouble());
      _paintBlock(canvas, BlockTones.of(color));
      canvas.restore();
    }
    final patchLeft = (count * pitch).toDouble();
    canvas.drawRect(Rect.fromLTWH(patchLeft, 0, _patch.toDouble(), _patch.toDouble()), Paint()..color = _white);
    _whitePatch = Rect.fromLTWH(patchLeft + 1, 1, 2, 2);
    final picture = recorder.endRecording();
    _atlas = picture.toImageSync(count * pitch + _patch, math.max(pitch, _patch));
    picture.dispose();
  }

  /// A block a cell wide, centred on the origin.
  static void _paintBlock(Canvas canvas, BlockTones tones) {
    final body = _blockShape.outerRect;
    canvas.drawRRect(
      _blockShape,
      Paint()
        ..shader = ui.Gradient.linear(
          body.topCenter,
          body.bottomCenter,
          [tones.light, tones.base, tones.dark],
          const [0, 0.3, 1],
        ),
    );
    // A flat face set into the bevel, with a soft highlight across its top.
    canvas.drawRRect(_faceShape, Paint()..color = tones.base);
    canvas.drawRRect(
      _faceShape,
      Paint()
        ..shader = ui.Gradient.linear(_faceShape.outerRect.topCenter, _faceShape.outerRect.center, const [
          Color(0x61FFFFFF),
          Color(0x00FFFFFF),
        ]),
    );
  }

  void _makeGlows(FieldGeometry g) {
    final px = g.devicePixelRatio / g.unit;
    final n = g.n.toDouble();
    final depth = (g.arm + g.n).toDouble();

    // The active glass: one tall well — its arm and the central square —
    // open at the top, with bright walls and a heavy floor.
    _well = _makeGlow(n, depth, g, 20, (canvas) {
      final well = Rect.fromLTWH(0, 0, n, depth);
      canvas.drawRect(
        well,
        Paint()
          ..shader = ui.Gradient.linear(well.topCenter, well.bottomCenter, [
            _accent.withValues(alpha: 0.13),
            _accent.withValues(alpha: 0.035),
          ]),
      );
      final walls = Path()
        ..moveTo(0, 0)
        ..lineTo(0, depth)
        ..lineTo(n, depth)
        ..lineTo(n, 0);
      final floor = Path()
        ..moveTo(0, depth)
        ..lineTo(n, depth);
      // A soft halo first, then the crisp lines on top of it.
      canvas.drawPath(
        walls,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = 5 * px
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 5 * px)
          ..color = _accent.withValues(alpha: 0.6),
      );
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 2.2 * px
        ..color = _ice.withValues(alpha: 0.95);
      canvas.drawPath(walls, line);
      canvas.drawPath(floor, line..strokeWidth = 4.5 * px);
    });

    // The far end of a glass that is nearly full.
    _warning = _makeGlow(n, 0, g, 16, (canvas) {
      canvas.drawLine(
        Offset.zero,
        Offset(n, 0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 6 * px
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * px)
          ..color = Palette.danger.withValues(alpha: 0.8),
      );
    });
  }

  /// The soft halo round a piece [width] by [depth] cells; [tone] indexes
  /// [_haloColors].
  _Glow _halo(int width, int depth, int tone, FieldGeometry g) {
    return _halos[width * 100 + depth * 10 + tone] ??= _makeGlow(width.toDouble(), depth.toDouble(), g, 16, (canvas) {
      final px = g.devicePixelRatio / g.unit;
      canvas.drawRRect(
        _haloShape(0, 0, width, depth),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4 * px
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 * px)
          ..color = _haloColors[tone].withValues(alpha: 0.7),
      );
    });
  }

  static RRect _haloShape(double left, double top, int width, int depth) => RRect.fromRectAndRadius(
    Rect.fromLTWH(left - 0.03, top - 0.03, width + 0.06, depth + 0.06),
    const Radius.circular(0.2),
  );

  /// Draws a glowing shape once, into an image with room for its glow.
  /// [draw] works in cells with the origin of the shape at (0, 0); [reach]
  /// is how far the glow spreads, in logical pixels.
  static _Glow _makeGlow(
    double width,
    double height,
    FieldGeometry g,
    double reach,
    void Function(Canvas canvas) draw,
  ) {
    final unit = g.unit;
    final pad = (reach * g.devicePixelRatio).ceil() + 2;
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.translate(pad.toDouble(), pad.toDouble());
    canvas.scale(unit.toDouble());
    draw(canvas);
    final picture = recorder.endRecording();
    final image = picture.toImageSync((width * unit).ceil() + pad * 2, (height * unit).ceil() + pad * 2);
    picture.dispose();
    return _Glow(image, pad, unit);
  }

  /// The lines of the field never change while the board keeps its shape.
  void _makePaths(FieldGeometry g) {
    final half = g.half;
    final reach = g.reach;
    _armGrid = Path();
    for (var i = 1; i < g.n; i++) {
      _armGrid
        ..moveTo(-half + i, -reach)
        ..lineTo(-half + i, -half);
    }
    for (var j = 1; j < g.arm; j++) {
      _armGrid
        ..moveTo(-half, -reach + j)
        ..lineTo(half, -reach + j);
    }
    _centreGrid = Path();
    for (var i = 1; i < g.n; i++) {
      _centreGrid
        ..moveTo(-half + i, -half)
        ..lineTo(-half + i, half)
        ..moveTo(-half, -half + i)
        ..lineTo(half, -half + i);
    }
    _armOutline = Path()
      ..moveTo(-half, -half)
      ..lineTo(-half, -reach)
      ..lineTo(half, -reach)
      ..lineTo(half, -half);
    _wallOutline = Path()
      ..moveTo(-half, -half)
      ..lineTo(half, -half);
  }

  /// The text of a countdown, laid out again only when it changes.
  TextPainter _label(Side side, String text, int tone, double size) {
    final label = _labels[side] ??= _Label();
    if (label.painter == null || label.text != text || label.tone != tone || label.size != size) {
      label.painter?.dispose();
      label
        ..text = text
        ..tone = tone
        ..size = size
        ..painter = (TextPainter(
          text: TextSpan(
            text: text,
            style: Type.body(
              size,
              weight: tone == 0 ? FontWeight.w600 : FontWeight.w800,
              color: tone == 0 ? Palette.text.withValues(alpha: 0.42) : _haloColors[tone],
              height: 1,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout());
    }
    return label.painter!;
  }
}

/// Draws the whole playfield: the glasses sharing the central square, their
/// falling pieces, settled blocks and every effect.
///
/// Everything is laid out in cell units, in the world frame of the cross, and
/// turned as a whole by the view angle. The game model itself never rotates.
///
/// Two things keep a frame cheap without changing a pixel of it. The blocks
/// are one image — a cell is a whole number of physical pixels, so at rest
/// they are copied exactly — and all of them go to the GPU in one call. And
/// nothing is blurred while playing: the glows are images made once.
class FieldPainter extends CustomPainter {
  FieldPainter({
    required this.engine,
    required this.fx,
    required this.assets,
    required this.devicePixelRatio,
    this.reduceMotion = false,
    this.focusSingleGlass = false,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GameEngine engine;
  final Effects fx;
  final FieldAssets assets;
  final double devicePixelRatio;
  final bool reduceMotion;
  final bool focusSingleGlass;

  // ------------------------------------------------ the frame being drawn
  /// One logical pixel, in cells.
  double _px = 1;

  /// True once a turn is over: frames are then at whole quarter turns.
  bool _atRest = true;

  /// The quarter turn the cross is settling on, 0..3.
  int _turnsQ = 0;

  /// Cosine and sine of each glass's frame on the screen.
  final Float64List _cos = Float64List(4);
  final Float64List _sin = Float64List(4);

  /// What is left of the turn: blocks stay upright at the end of it.
  double _left = 0;
  double _leftCos = 1;
  double _leftSin = 0;

  @override
  bool shouldRepaint(FieldPainter oldDelegate) =>
      oldDelegate.engine != engine ||
      oldDelegate.fx != fx ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      oldDelegate.reduceMotion != reduceMotion ||
      oldDelegate.focusSingleGlass != focusSingleGlass;

  @override
  void paint(Canvas canvas, Size size) {
    final state = engine.state;
    final building = state.phase == GamePhase.building ? state.buildingSide : null;
    final g = FieldGeometry(
      size.width,
      engine.config,
      devicePixelRatio: devicePixelRatio,
      angle: fx.viewAngle,
      sides: engine.sides,
      building: building,
      progress: state.phaseProgress,
      reduceMotion: reduceMotion,
      focusSingleGlass: focusSingleGlass,
    );
    if (g.cell <= 0) return;
    assets._prepare(g);
    _px = devicePixelRatio / g.unit;

    // Where each glass's frame points on the screen. At rest that is a whole
    // number of quarter turns, and it is written down exactly.
    _left = fx.turnLeft;
    _atRest = _left.abs() < 1e-7;
    _turnsQ = fx.targetTurns.round() % 4;
    for (var frame = 0; frame < 4; frame++) {
      if (_atRest) {
        final q = (_turnsQ + frame) & 3;
        _cos[frame] = _quarterCos[q];
        _sin[frame] = _quarterSin[q];
      } else {
        final angle = fx.viewAngle + frame * _quarter;
        _cos[frame] = math.cos(angle);
        _sin[frame] = math.sin(angle);
      }
    }
    _leftCos = _atRest ? 1 : math.cos(_left);
    _leftSin = _atRest ? 0 : math.sin(_left);

    // Combo pulses stay inside the fitted camera and zoom about its center.
    final scale = math.min(g.drawnCell * (1 + fx.punch), size.width * 0.985 / g.viewport.span);
    double snap(double value) => (value * devicePixelRatio).round() / devicePixelRatio;
    final ox = snap(size.width / 2 - g.viewport.center.dx * scale) + (fx.kickX + fx.shakeX) * g.cell;
    final oy = snap(size.width / 2 - g.viewport.center.dy * scale) + (fx.kickY + fx.shakeY) * g.cell;

    canvas.save();
    canvas.translate(ox, oy);
    canvas.scale(scale);

    _drawField(canvas, g, engine.sides, 1 - 0.7 * fx.turnMotion, building, g.viewport.grow);
    _drawActiveGlass(canvas, g);
    for (final side in engine.sides) {
      _drawCrowdedWarning(canvas, g, side);
    }
    for (final beam in fx.beams) {
      _drawBeam(canvas, g, beam);
    }
    for (final piece in state.incoming.values) {
      _drawAim(canvas, g, piece);
    }
    _drawSettled(canvas, g, state);
    _enter(canvas, 0);
    _drawFlashes(canvas, g);
    _drawRings(canvas);
    canvas.restore();
    _drawParticles(canvas);
    for (final piece in state.incoming.values) {
      _drawIncoming(canvas, g, piece);
    }
    _drawDrop(canvas, g, state);
    canvas.restore();

    for (final piece in state.incoming.values) {
      _drawCountdown(canvas, g, ox, oy, scale, piece);
    }
  }

  // ----------------------------------------------------------- transforms

  /// Starts drawing in the frame of glass [frame]: its arm on top. Undone by
  /// `canvas.restore()`.
  void _enter(Canvas canvas, int frame) {
    final m = assets._matrix;
    m[0] = _cos[frame];
    m[1] = _sin[frame];
    m[4] = -_sin[frame];
    m[5] = _cos[frame];
    canvas.save();
    canvas.transform(m);
  }

  // ------------------------------------------------------------- blocks

  /// Adds a plain block centred at ([x], [y]) of the frame of glass [frame]
  /// to the batch. Its lit edge faces the top of the screen however the cross
  /// is turned.
  void _add(BlockColor color, double x, double y, int frame) {
    final c = _cos[frame];
    final s = _sin[frame];
    final unit = assets._unit;
    // The sprite is `unit` pixels wide and a cell big; mid-turn it is turned
    // by what is left of the turn, about its centre.
    assets._batch.add(
      _leftCos / unit,
      _leftSin / unit,
      c * x - s * y - (_leftCos - _leftSin) / 2,
      s * x + c * y - (_leftSin + _leftCos) / 2,
      assets._blocks[color.index],
    );
  }

  void _flush(Canvas canvas) => assets._batch.draw(canvas, assets._atlas!, assets._imagePaint);

  /// Draws one block stretched along the axes of its frame, and lit by
  /// [flash] of white.
  void _stretched(
    Canvas canvas,
    BlockColor color,
    double x,
    double y,
    int frame,
    double scaleX,
    double scaleY,
    double flash,
  ) {
    final c = _cos[frame];
    final s = _sin[frame];
    // On the screen the frame's axes are swapped when it ends up a quarter
    // turn from upright.
    final swapped = ((_turnsQ + frame) & 1) == 1;
    canvas.save();
    canvas.translate(c * x - s * y, s * x + c * y);
    if (!_atRest) canvas.rotate(_left);
    canvas.scale(swapped ? scaleY : scaleX, swapped ? scaleX : scaleY);
    canvas.drawImageRect(assets._atlas!, assets._blocks[color.index], FieldAssets._unitRect, assets._imagePaint);
    if (flash > 0) {
      canvas.drawRRect(
        FieldAssets._flashShape,
        assets._flashPaint..color = _white.withValues(alpha: math.min(1.0, flash)),
      );
    }
    canvas.restore();
  }

  /// The squares of a stick whose top left cell is at ([left], [top]) of the
  /// frame of glass [frame].
  void _stick(Canvas canvas, Piece piece, double left, double top, int frame, {double scaleY = 1, double flash = 0}) {
    final count = piece.length;
    final lying = piece.isHorizontal;
    final flipped = piece.orientation.isFlipped;
    final plain = scaleY == 1 && flash <= 0;
    for (var i = 0; i < count; i++) {
      final along = flipped ? count - 1 - i : i;
      final x = left + (lying ? along : 0) + 0.5;
      final y = top + (lying ? 0 : along) + 0.5;
      if (plain) {
        _add(piece.colors[i], x, y, frame);
      } else {
        _stretched(canvas, piece.colors[i], x, y, frame, 1, scaleY, flash);
      }
    }
    if (plain) _flush(canvas);
  }

  // -------------------------------------------------------------- playfield

  /// The cross: the central square and the arm of every glass in play. A
  /// glass being built grows out of the centre. [lines] fades the grid while
  /// the cross is turning.
  void _drawField(Canvas canvas, FieldGeometry g, List<Side> sides, double lines, Side? growing, double grow) {
    final a = assets;
    final half = g.half;
    final n = g.n.toDouble();
    final arm = g.arm.toDouble();
    final far = half + arm * grow;

    final armFill = Paint()..color = const Color(0x06FFFFFF);
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px
      ..color = _white.withValues(alpha: 0.045 * lines);
    for (final side in sides) {
      _enter(canvas, side.index);
      if (side != growing) {
        canvas.drawRect(Rect.fromLTWH(-half, -g.reach, n, arm), armFill);
        _drawAmbient(canvas, g, side, g.reach);
        canvas.drawPath(a._armGrid, grid);
      } else {
        final grown = Rect.fromLTRB(-half, -far, half, -half);
        canvas.drawRect(grown, armFill);
        canvas.save();
        canvas.clipRect(grown);
        _drawAmbient(canvas, g, side, far);
        canvas.drawPath(a._armGrid, grid);
        canvas.restore();
      }
      canvas.restore();
    }

    final centre = Rect.fromLTWH(-half, -half, n, n);
    canvas.drawRect(centre, armFill..color = const Color(0x0DFFFFFF));
    canvas.drawPath(a._centreGrid, grid..color = _white.withValues(alpha: 0.07 * lines));

    // Outline of the whole cross — an arm where a glass is in play, the wall
    // of the centre where there is none — and of the centre, brighter.
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5 * _px
      ..strokeJoin = StrokeJoin.round
      ..color = const Color(0x29FFFFFF);
    for (final side in Side.values) {
      _enter(canvas, side.index);
      if (!sides.contains(side)) {
        canvas.drawPath(a._wallOutline, outline);
      } else if (side != growing) {
        canvas.drawPath(a._armOutline, outline);
      } else {
        canvas.drawPath(
          Path()
            ..moveTo(-half, -half)
            ..lineTo(-half, -far)
            ..lineTo(half, -far)
            ..lineTo(half, -half),
          outline,
        );
        // The leading edge of the glass that is growing.
        canvas.drawLine(
          Offset(-half, -far),
          Offset(half, -far),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2 * _px
            ..color = _accent.withValues(alpha: 0.9 * (1 - grow)),
        );
      }
      canvas.restore();
    }
    canvas.drawRect(centre, outline..color = const Color(0x38FFFFFF));
  }

  /// Each world-side has its own quiet motif behind the grid and pieces.
  /// It follows the glass through turns and shares the effects' pause clock.
  void _drawAmbient(Canvas canvas, FieldGeometry g, Side side, double far) {
    if (reduceMotion) return;
    final half = g.half, n = g.n.toDouble(), arm = g.arm.toDouble();
    final t = fx.clock;
    const colours = [Palette.accentStrong, Palette.violet, Color(0xFF2EE6F0), Palette.orange];
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _px
      ..color = colours[side.index].withValues(alpha: .10);
    canvas.save();
    canvas.clipRect(Rect.fromLTRB(-half, -far, half, -half));
    switch (side.index) {
      case 0:
        for (var lane = 0; lane < 3; lane++) {
          final path = Path();
          for (var j = 0; j <= 16; j++) {
            final y = -g.reach + arm * j / 16;
            final x = -half + n * (lane + 1) / 4 + .35 * math.sin(t * .45 + j * .4 + lane);
            if (j == 0) {
              path.moveTo(x, y);
            } else {
              path.lineTo(x, y);
            }
          }
          canvas.drawPath(path, paint);
        }
      case 1:
        for (var i = 0; i < 4; i++) {
          final pulse = (t / 12 + i / 4) % 1;
          final radius = n * .15 + pulse * arm * .7;
          canvas.drawRect(
            Rect.fromCenter(center: Offset(0, -half - arm * .55), width: radius * 2, height: radius * 2),
            paint..color = colours[1].withValues(alpha: .13 * (1 - pulse)),
          );
        }
      case 2:
        for (var wave = 0; wave < 5; wave++) {
          final y = -g.reach + ((t / 18 + wave / 5) % 1) * arm;
          final path = Path();
          for (var j = 0; j <= 16; j++) {
            final x = -half + n * j / 16;
            final yy = y + .45 * math.sin(j * .35 + t * .35);
            if (j == 0) {
              path.moveTo(x, yy);
            } else {
              path.lineTo(x, yy);
            }
          }
          canvas.drawPath(path, paint);
        }
      case 3:
        for (var i = 0; i < 5; i++) {
          final fall = (t / 24 + i / 5) % 1;
          final edge = 1.1 + (i % 3) * .35;
          canvas.save();
          canvas.translate(math.sin(i * 2.4 + t * .15) * n * .28, -g.reach + fall * arm);
          canvas.rotate(t * .08 + i * .6);
          canvas.drawRect(Rect.fromLTWH(-edge / 2, -edge / 2, edge, edge), paint);
          canvas.restore();
        }
    }
    canvas.restore();
  }

  /// The glass being steered glows; the glow moves over as the cross turns.
  void _drawActiveGlass(Canvas canvas, FieldGeometry g) {
    final well = assets._well;
    if (well == null) return;
    for (final side in Side.values) {
      final lit = fx.activeness[side.index];
      if (lit < 0.01) continue;
      _enter(canvas, side.index);
      _glow(canvas, well, -g.half, -g.reach, lit);
      canvas.restore();
    }
  }

  /// Draws a glow with its shape's origin at ([x], [y]) of the current frame.
  void _glow(Canvas canvas, _Glow glow, double x, double y, double alpha) {
    canvas.drawImageRect(
      glow.image,
      glow.source,
      glow.at(x, y),
      assets._glowPaint..color = _white.withValues(alpha: alpha.clamp(0.0, 1.0)),
    );
  }

  /// A glass that is nearly full up to its far end pulses red there.
  void _drawCrowdedWarning(Canvas canvas, FieldGeometry g, Side side) {
    final over = engine.isGameOver;
    if (over ? engine.state.gameOverSide != side : !engine.isCrowded(side)) {
      return;
    }
    final half = g.half;
    final reach = g.reach;
    final pulse = over ? 1.0 : 0.5 + 0.5 * math.sin(fx.clock * 9);
    _enter(canvas, side.index);
    final wash = Rect.fromLTRB(-half, -reach, half, -half);
    canvas.drawRect(
      wash,
      Paint()
        ..shader = ui.Gradient.linear(wash.topCenter, wash.bottomCenter, [
          Palette.danger.withValues(alpha: 0.1 + 0.2 * pulse),
          Palette.danger.withValues(alpha: 0.02),
        ]),
    );
    final warning = assets._warning;
    if (warning != null) _glow(canvas, warning, -half, -reach, 1);
    canvas.drawLine(
      Offset(-half, -reach),
      Offset(half, -reach),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3 * _px
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
    _enter(canvas, beam.side.index);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [
          const Color(0x00FFFFFF),
          _white.withValues(alpha: 0.34 * fade),
        ]),
    );
    canvas.restore();
  }

  /// Where a piece will land: the lane of the active one, and an outline of
  /// its resting place. Pieces nobody is steering only show theirs faintly
  /// until they are about to lock.
  void _drawAim(Canvas canvas, FieldGeometry g, IncomingPiece piece) {
    final rest = engine.restRow(piece.side);
    if (rest == null || rest == piece.row || engine.isGameOver) return;
    final lit = fx.activeness[piece.side.index];
    final urgent = (engine.secondsToLock(piece.side) ?? 99) < 6;
    final strength = math.max(lit, urgent ? 0.4 : 0.16);

    final stick = piece.piece;
    final left = -g.half + piece.column;
    final top = -g.reach + piece.row - fx.slideLeft(piece) + stick.depth;
    final bottom = -g.reach + rest;

    _enter(canvas, piece.side.index);
    if (lit > 0.05 && bottom > top) {
      // One gradient, made for a unit square and stretched over the lane.
      canvas.save();
      canvas.translate(left, top);
      canvas.scale(stick.width.toDouble(), bottom - top);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1, 1),
        Paint()
          ..shader = FieldAssets._laneShader
          ..color = _white.withValues(alpha: lit),
      );
      canvas.restore();
    }
    final count = stick.length;
    final lying = stick.isHorizontal;
    final flipped = stick.orientation.isFlipped;
    final fill = Paint();
    final edge = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * _px;
    for (var i = 0; i < count; i++) {
      final along = flipped ? count - 1 - i : i;
      final tone = BlockTones.of(stick.colors[i]).base;
      final shape = RRect.fromRectAndRadius(
        Rect.fromLTWH(left + (lying ? along : 0) + 0.07, -g.reach + rest + (lying ? 0 : along) + 0.07, 0.86, 0.86),
        const Radius.circular(0.14),
      );
      canvas.drawRRect(shape, fill..color = tone.withValues(alpha: 0.14 * strength));
      canvas.drawRRect(shape, edge..color = tone.withValues(alpha: 0.9 * strength));
    }
    canvas.restore();
  }

  void _drawSettled(Canvas canvas, FieldGeometry g, GameState state) {
    final a = assets;
    final board = state.board;
    final size = board.size;
    // Centre of the cell in the top left corner of the grid.
    final origin = -g.grid / 2 + 0.5;
    final matched = state.activeMatch?.cells;

    if (state.moves.isEmpty && fx.landings.isEmpty) {
      // Nothing is falling or landing: every block is where the board says.
      for (var row = 0; row < size; row++) {
        for (var col = 0; col < size; col++) {
          final color = board.at(row, col);
          if (color == null) continue;
          if (matched != null && matched.contains(CellPosition(row, col))) {
            continue;
          }
          _add(color, origin + col, origin + row, 0);
        }
      }
      _flush(canvas);
    } else {
      final moving = a._moving..clear();
      for (final move in state.moves) {
        moving.add(move.to);
      }
      // Cells still reacting to a landing are drawn in their own pass.
      final landing = a._landing..clear();
      for (final effect in fx.landings) {
        for (final cell in effect.placement.cells) {
          final at = cell.position;
          if (board.colorAt(at) == cell.color && !(matched?.contains(at) ?? false) && !moving.contains(at)) {
            landing[at] = effect;
          }
        }
      }

      for (var row = 0; row < size; row++) {
        for (var col = 0; col < size; col++) {
          final color = board.at(row, col);
          if (color == null) continue;
          final at = CellPosition(row, col);
          if ((matched?.contains(at) ?? false) || moving.contains(at) || landing.containsKey(at)) {
            continue;
          }
          _add(color, origin + col, origin + row, 0);
        }
      }
      _flush(canvas);

      // Falling: each block accelerates over its own distance, so short
      // falls land first, and wobbles once when it arrives.
      final side = state.activeSide;
      final bounce = engine.config.fallBounceSeconds / engine.config.animationSpeed;
      for (final move in state.moves) {
        final from = RotationTransform.worldToView(move.from, side, size);
        final to = RotationTransform.worldToView(move.to, side, size);
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
        _stretched(
          canvas,
          move.color,
          origin + to.col,
          origin + row + 0.44 * (1 - math.min(scaleY, 1.0)),
          side.index,
          scaleX,
          scaleY,
          0,
        );
      }

      // Landing: a white flash, and after a hard drop a squash along the fall.
      for (final effect in fx.landings) {
        final u = effect.age / effect.life;
        final wave = effect.dropped ? math.sin(u * math.pi * 2) * (1 - u) : 0.0;
        final scaleY = 1 - 0.26 * wave;
        final scaleX = 1 + 0.15 * wave;
        final frame = effect.placement.side;
        for (final cell in effect.placement.cells) {
          if (!identical(landing[cell.position], effect)) continue;
          final local = RotationTransform.worldToView(cell.position, frame, size);
          _stretched(
            canvas,
            cell.color,
            origin + local.col,
            origin + local.row + 0.44 * (1 - math.min(scaleY, 1.0)),
            frame.index,
            scaleX,
            scaleY,
            0.85 * (1 - u) * (1 - u),
          );
        }
      }
    }

    // Match: flash to white and swell, then collapse while shards fly off.
    if (matched != null && matched.isNotEmpty) {
      final t = state.phaseProgress;
      final popping = state.phase == GamePhase.clearing;
      final scale = popping ? 1.22 * math.max(0.0, 1 - t * 1.7) : 1 + 0.22 * (1 - (1 - t) * (1 - t));
      final flash = popping ? 1.0 : 0.3 + 0.7 * t;
      if (scale > 0.01) {
        for (final cell in matched) {
          final color = board.colorAt(cell);
          if (color == null) continue;
          _stretched(canvas, color, origin + cell.col, origin + cell.row, 0, scale, scale, flash);
        }
      }
    }
  }

  /// Bars of light over popped lines, and the wash of a triple clear.
  void _drawFlashes(Canvas canvas, FieldGeometry g) {
    final paint = Paint();
    for (final flash in fx.flashes) {
      canvas.drawRect(
        Rect.fromLTRB(flash.x0, flash.y0, flash.x1, flash.y1),
        paint..color = flash.color.withValues(alpha: 0.85 * (1 - flash.age / flash.life)),
      );
    }
    final extent = g.grid.toDouble();
    for (final veil in fx.veils) {
      canvas.drawRect(
        Rect.fromLTWH(-extent, -extent, 2 * extent, 2 * extent),
        paint..color = _white.withValues(alpha: 0.22 * (1 - veil.age / veil.life)),
      );
    }
  }

  void _drawRings(Canvas canvas) {
    final paint = Paint()..style = PaintingStyle.stroke;
    for (final ring in fx.rings) {
      if (ring.age < 0) continue;
      final t = ring.age / ring.life;
      final eased = 1 - (1 - t) * (1 - t);
      canvas.drawCircle(
        Offset(ring.x, ring.y),
        0.3 + ring.reach * eased,
        paint
          ..strokeWidth = math.max(_px, 0.16 * (1 - t))
          ..color = ring.color.withValues(alpha: 0.75 * (1 - t)),
      );
    }
  }

  /// Every shard is a tinted copy of one white square: all of them are one
  /// call, however many a cascade throws up.
  void _drawParticles(Canvas canvas) {
    if (fx.particles.isEmpty) return;
    final a = assets;
    final c = _cos[0];
    final s = _sin[0];
    for (final particle in fx.particles) {
      final strength = (1 - particle.age / particle.life).clamp(0.0, 1.0);
      // The white square is two pixels wide; half its drawn size is its scale.
      final half = particle.size * (0.4 + 0.6 * strength) / 2;
      final scos = half * c;
      final ssin = half * s;
      a._batch.add(
        scos,
        ssin,
        c * particle.x - s * particle.y - (scos - ssin),
        s * particle.x + c * particle.y - (ssin + scos),
        a._whitePatch,
        ((strength * 255).round() << 24) | (particle.color.toARGB32() & 0xFFFFFF),
      );
    }
    a._batch.draw(canvas, a._atlas!, a._imagePaint, tinted: true);
  }

  void _drawIncoming(Canvas canvas, FieldGeometry g, IncomingPiece piece) {
    final side = piece.side;
    final stick = piece.piece;
    final lit = fx.activeness[side.index];
    final secondsLeft = engine.secondsToLock(side) ?? 0;
    final urgent = secondsLeft < 3;

    final top = -g.reach + piece.row - fx.slideLeft(piece);
    final left = -g.half + piece.column;

    // Halo: white for the piece being steered, coloured when time runs out.
    final strength = math.max(lit, urgent ? 0.85 : 0.0);
    if (strength > 0.02) {
      final warn = urgent && lit < 0.5;
      final tone = !warn ? 0 : (secondsLeft < 1.5 ? 2 : 1);
      final pulse = warn ? 0.6 + 0.4 * math.sin(fx.clock * 10) : 1.0;
      _enter(canvas, side.index);
      _glow(canvas, assets._halo(stick.width, stick.depth, tone, g), left, top, strength);
      canvas.drawRRect(
        FieldAssets._haloShape(left, top, stick.width, stick.depth),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8 * _px
          ..color = _haloColors[tone].withValues(alpha: 0.95 * strength * pulse),
      );
      canvas.restore();
    }

    _stick(canvas, stick, left, top, side.index);
  }

  /// A hard-dropped piece streaking down to where it lands.
  void _drawDrop(Canvas canvas, FieldGeometry g, GameState state) {
    final drop = state.drop;
    if (drop == null) return;
    final t = state.phaseProgress;
    final row = drop.startRow + (drop.placement.row - drop.startRow) * t * t;
    _stick(
      canvas,
      drop.placement.piece,
      -g.half + drop.placement.column,
      -g.reach + row,
      drop.placement.side.index,
      scaleY: 1 + 0.18 * t,
      flash: 0.25 * t,
    );
  }

  /// Seconds until a piece locks by itself, written upright beside it.
  void _drawCountdown(Canvas canvas, FieldGeometry g, double ox, double oy, double scale, IncomingPiece piece) {
    if (engine.isGameOver) return;
    final secondsLeft = engine.secondsToLock(piece.side) ?? 0;
    final lit = fx.activeness[piece.side.index];
    // The piece being steered only needs its timer when it is about to lock.
    if (lit > 0.5 && secondsLeft >= 3) return;

    // A point just beyond the left end of the piece, in its glass's frame,
    // turned with its glass and with the cross into screen pixels.
    final localX = -g.half + piece.column - 0.85;
    final localY = -g.reach + piece.row - fx.slideLeft(piece) + piece.piece.depth / 2;
    final c = _cos[piece.side.index];
    final s = _sin[piece.side.index];

    final text = assets._label(
      piece.side,
      secondsLeft < 10 ? secondsLeft.toStringAsFixed(1) : secondsLeft.round().toString(),
      secondsLeft >= 3 ? 0 : (secondsLeft < 1.5 ? 2 : 1),
      math.max(9.0, g.cell * 0.78),
    );
    text.paint(
      canvas,
      Offset(
        ox + (localX * c - localY * s) * scale - text.width / 2,
        oy + (localX * s + localY * c) * scale - text.height / 2,
      ),
    );
  }
}
