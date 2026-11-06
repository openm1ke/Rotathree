// Paints what view.dart built: the camera of the web's view (an orthographic
// eye easing into perspective as the hub opens), the blocks as the web's tile
// shader shades them, far to near, and the thin lines of the cross and the
// hub. Everything that has depth goes into one list of triangles, drawn in
// one call.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../game/model/color.dart';
import '../ui/field/block_look.dart';
import '../ui/style.dart';
import 'math3d.dart';
import 'view.dart';

/// How round a block's edges are, in parts of its side (ROUND on the web).
const _round = 0.13;

/// Triangles with a colour at every corner, kept between frames.
class _Triangles {
  Float32List positions = Float32List(6 * 4096);
  Int32List colors = Int32List(3 * 4096);
  int vertices = 0;

  void reset() => vertices = 0;

  void _grow() {
    final p = Float32List(positions.length * 2)..setRange(0, positions.length, positions);
    final c = Int32List(colors.length * 2)..setRange(0, colors.length, colors);
    positions = p;
    colors = c;
  }

  void add(Offset a, int ca, Offset b, int cb, Offset c, int cc) {
    if (3 * (vertices + 3) > colors.length) _grow();
    final i = vertices * 2;
    positions[i] = a.dx;
    positions[i + 1] = a.dy;
    positions[i + 2] = b.dx;
    positions[i + 3] = b.dy;
    positions[i + 4] = c.dx;
    positions[i + 5] = c.dy;
    colors[vertices] = ca;
    colors[vertices + 1] = cb;
    colors[vertices + 2] = cc;
    vertices += 3;
  }

  void quad(Offset a, Offset b, Offset c, Offset d, int ca, int cb, int cc, int cd) {
    add(a, ca, b, cb, c, cc);
    add(a, ca, c, cc, d, cd);
  }

  /// A triangle between points [a], [b] and [c] of [xs] and [ys].
  void addAt(Float64List xs, Float64List ys, int a, int ca, int b, int cb, int c, int cc) {
    if (3 * (vertices + 3) > colors.length) _grow();
    final i = vertices * 2;
    positions[i] = xs[a];
    positions[i + 1] = ys[a];
    positions[i + 2] = xs[b];
    positions[i + 3] = ys[b];
    positions[i + 4] = xs[c];
    positions[i + 5] = ys[c];
    colors[vertices] = ca;
    colors[vertices + 1] = cb;
    colors[vertices + 2] = cc;
    vertices += 3;
  }

  /// A quad between points [a], [b], [c] and [d] of [xs] and [ys], as [quad].
  void quadAt(Float64List xs, Float64List ys, int a, int b, int c, int d, int ca, int cb, int cc, int cd) {
    addAt(xs, ys, a, ca, b, cb, c, cc);
    addAt(xs, ys, a, ca, c, cc, d, cd);
  }

  void draw(Canvas canvas) {
    if (vertices == 0) return;
    final vertexData = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(positions, 0, vertices * 2),
      colors: Int32List.sublistView(colors, 0, vertices),
    );
    canvas.drawVertices(vertexData, BlendMode.dst, Paint());
    vertexData.dispose();
  }
}

/// The colour as ARGB with an alpha.
int _argb(double r, double g, double b, double a) =>
    ((a.clamp(0.0, 1.0) * 255).round() << 24) |
    ((r.clamp(0.0, 1.0) * 255).round() << 16) |
    ((g.clamp(0.0, 1.0) * 255).round() << 8) |
    (b.clamp(0.0, 1.0) * 255).round();

/// One face of a cube: its normal and the two axes across it, (u × v = n).
const _faces = <(List<double>, List<double>, List<double>)>[
  ([1, 0, 0], [0, 1, 0], [0, 0, 1]),
  ([-1, 0, 0], [0, 0, 1], [0, 1, 0]),
  ([0, 1, 0], [0, 0, 1], [1, 0, 0]),
  ([0, -1, 0], [1, 0, 0], [0, 0, 1]),
  ([0, 0, 1], [1, 0, 0], [0, 1, 0]),
  ([0, 0, -1], [0, 1, 0], [1, 0, 0]),
];

/// The rounded rim of a face as an octagon, and the inner corner each of its
/// points belongs to (see [_cornerAt]).
const _inner = 0.5 - _round;
const _octagon = <(double, double, int)>[
  (-0.5, -_inner, 0), (-_inner, -0.5, 0), (_inner, -0.5, 1), (0.5, -_inner, 1),
  (0.5, _inner, 2), (_inner, 0.5, 2), (-_inner, 0.5, 3), (-0.5, _inner, 3),
];
const _grid = [-_inner, 0.0, _inner];

/// [_faces] as axes of the block: the normal's axis and its sign, then the
/// axes across the face.
const _faceAxes = <(int, double, int, int)>[
  (0, 1, 1, 2), (0, -1, 2, 1), (1, 1, 2, 0), (1, -1, 0, 2), (2, 1, 0, 1), (2, -1, 1, 0),
];

/// The points of a face, in its own (a, b): the three corners that tell
/// whether it faces the eye, the rim's eight, and the face's three-by-three
/// grid, row by row. The grid's corners are the rim's inner ones.
final _facePoints = <(double, double)>[
  (-0.5, -0.5), (0.5, -0.5), (0.5, 0.5),
  for (final (a, b, _) in _octagon) (a, b),
  for (final b in _grid)
    for (final a in _grid) (a, b),
];
const _rimAt = 3, _gridAt = 11;

/// Where each inner corner of the rim is among [_facePoints].
const _cornerAt = [_gridAt, _gridAt + 2, _gridAt + 8, _gridAt + 6];

class CubePainter extends CustomPainter {
  CubePainter(this.view, {super.repaint});

  final CubeView view;
  static final _triangles = _Triangles();

  // One face of a block at a time: its points on the canvas, how far up the
  // screen each is from the block's middle, and their colours.
  static final _xs = Float64List(_facePoints.length);
  static final _ys = Float64List(_facePoints.length);
  static final _ups = Float64List(_facePoints.length);
  static final _rims = Int32List(_facePoints.length);
  static final _fills = Int32List(_facePoints.length);

  /// The block's turn as columns: where each of its axes points.
  static final _axes = Float64List(9);

  /// The points of one mark on a face, its centre first.
  static final _markXs = Float64List(32);
  static final _markYs = Float64List(32);

  late List<double> _m;
  late Size _size;

  /// The camera's projection: orthographic and perspective, mixed as far as
  /// the hub is open (the web's `project`).
  void _camera(Size size) {
    _size = size;
    final fov = view.fov, aspect = view.aspect, near = view.near, far = view.far;
    final p = M4().perspective(fov, aspect, near, far).e;
    final high = view.distance * math.tan(fov * math.pi / 360);
    final wide = high * aspect;
    final o = M4().orthographic(-wide, wide, high, -high, near, far).e;
    final t = view.opened;
    _m = [for (var i = 0; i < 16; i++) o[i] + (p[i] - o[i]) * t];
  }

  /// A point of the scene on the canvas.
  Offset _project(double x, double y, double z) {
    final m = _m;
    final zv = z - view.distance;
    final cx = m[0] * x + m[4] * y + m[8] * zv + m[12];
    final cy = m[1] * x + m[5] * y + m[9] * zv + m[13];
    final cw = m[3] * x + m[7] * y + m[11] * zv + m[15];
    return Offset((cx / cw + 1) / 2 * _size.width, (1 - cy / cw) / 2 * _size.height);
  }

  Offset _p(V3 v) => _project(v.x, v.y, v.z);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    _camera(size);
    view.tone = (color, {light = false}) {
      final tones = BlockTones.of(BlockColor.values[color.clamp(0, BlockColor.values.length - 1)]);
      return light ? tones.light : tones.base;
    };

    // The cross's panes and lines, then the hub's edges: behind the blocks.
    for (final pane in view.panes) {
      if (pane.opacity < 0.002) continue;
      final path = Path()..addPolygon([for (final c in pane.corners) _p(c)], true);
      canvas.drawPath(path, Paint()..color = const Color(0xFFFFFFFF).withValues(alpha: pane.opacity));
    }
    for (final set in [...view.lines, ...view.hubLines]) {
      _lines(canvas, set);
    }

    // Every block and outline, far to near.
    final t = _triangles..reset();
    final items = <(double, Object)>[
      for (final s in view.solids) (s.depth, s),
      for (final s in view.fadingSolids) (s.depth, s),
      for (final c in view.clears) (c.depth, c),
    ]..sort((a, b) => b.$1.compareTo(a.$1));
    for (final (_, item) in items) {
      if (item is CubeSolid) {
        _solid(t, item, 1);
      } else if (item is CubeClear) {
        _clear(t, item);
      }
    }
    // A stick hidden behind blocks shows through them while the hub is open.
    if (view.xrayOpacity > 0.01 && view.xrays.isNotEmpty) {
      _placeCentres();
      for (final x in view.xrays) {
        if (_hidden(x)) _solid(t, x, view.xrayOpacity);
      }
    }
    t.draw(canvas);

    for (final label in view.labels) {
      _label(canvas, label);
    }
  }

  /// The middle of each of the view's blocks on the canvas, for [_hidden].
  static Float64List _centreXs = Float64List(256), _centreYs = Float64List(256);

  void _placeCentres() {
    final solids = view.solids;
    if (_centreXs.length < solids.length) {
      _centreXs = Float64List(solids.length * 2);
      _centreYs = Float64List(solids.length * 2);
    }
    for (var i = 0; i < solids.length; i++) {
      final at = _p(solids[i].at);
      _centreXs[i] = at.dx;
      _centreYs[i] = at.dy;
    }
  }

  /// Whether something nearer covers the middle of [x] on the canvas.
  bool _hidden(CubeSolid x) {
    final at = _p(x.at);
    final cell = (_p(V3(x.at.x + 0.5, x.at.y, x.at.z)) - at).distance;
    final solids = view.solids;
    for (var i = 0; i < solids.length; i++) {
      final s = solids[i];
      if (s.depth >= x.depth - 0.64 || s.size < 0.5) continue;
      final dx = _centreXs[i] - at.dx, dy = _centreYs[i] - at.dy;
      if (math.sqrt(dx * dx + dy * dy) < cell) return true;
    }
    return false;
  }

  void _lines(Canvas canvas, CubeLines set) {
    if (set.opacity < 0.002 || set.points.length < 2) return;
    final points = Float32List(set.points.length * 2);
    for (var i = 0; i < set.points.length; i++) {
      final p = _p(set.points[i]);
      points[2 * i] = p.dx;
      points[2 * i + 1] = p.dy;
    }
    canvas.drawRawPoints(
      ui.PointMode.lines,
      points,
      Paint()
        ..color = set.color.withValues(alpha: set.opacity.clamp(0.0, 1.0))
        ..strokeWidth = set.width
        ..strokeCap = StrokeCap.butt,
    );
  }

  /// A block as the web's tile shader draws it: a rim graded light at the top
  /// of the screen through its colour to dark at the bottom, round a face of
  /// the plain colour with a soft shine across its top; faces turned from the
  /// eye a little darker.
  void _solid(_Triangles t, CubeSolid s, double opacity) {
    final tones = BlockTones.of(BlockColor.values[s.color.clamp(0, BlockColor.values.length - 1)]);
    final skin = BlockTones.skin;
    final base = tones.base, light = tones.light, dark = tones.dark;
    final q = s.turn;
    final half = s.size;
    final at = s.at;
    final m = _m;
    final width = _size.width, height = _size.height, distance = view.distance;
    final axes = _axes;
    final qx = q.x, qy = q.y, qz = q.z, qw = q.w;
    // Each axis turned by q, as V3.applyQuaternion turns it.
    for (var axis = 0; axis < 3; axis++) {
      final vx = axis == 0 ? 1.0 : 0.0, vy = axis == 1 ? 1.0 : 0.0, vz = axis == 2 ? 1.0 : 0.0;
      final tx = 2 * (qy * vz - qz * vy);
      final ty = 2 * (qz * vx - qx * vz);
      final tz = 2 * (qx * vy - qy * vx);
      axes[axis * 3] = vx + qw * tx + qy * tz - qz * ty;
      axes[axis * 3 + 1] = vy + qw * ty + qz * tx - qx * tz;
      axes[axis * 3 + 2] = vz + qw * tz + qx * ty - qy * tx;
    }
    final xs = _xs, ys = _ys, ups = _ups, rims = _rims, fills = _fills;
    final marks = faceMarks(skin, s.color.clamp(0, BlockColor.values.length - 1));
    for (final (normalAxis, sign, uAxis, vAxis) in _faceAxes) {
      final nx = sign * axes[normalAxis * 3], ny = sign * axes[normalAxis * 3 + 1], nz = sign * axes[normalAxis * 3 + 2];
      final ux = axes[uAxis * 3], uy = axes[uAxis * 3 + 1], uz = axes[uAxis * 3 + 2];
      final vx = axes[vAxis * 3], vy = axes[vAxis * 3 + 1], vz = axes[vAxis * 3 + 2];
      // A point of the face in the scene, on the canvas (the camera's
      // projection, as _project), and how far up it is (vUp).
      void place(int i) {
        final (a, b) = _facePoints[i];
        final x = nx * 0.5 + ux * a + vx * b;
        final y = ny * 0.5 + uy * a + vy * b;
        final z = nz * 0.5 + uz * a + vz * b;
        final sx = at.x + x * half, sy = at.y + y * half, sz = at.z + z * half - distance;
        final cx = m[0] * sx + m[4] * sy + m[8] * sz + m[12];
        final cy = m[1] * sx + m[5] * sy + m[9] * sz + m[13];
        final cw = m[3] * sx + m[7] * sy + m[11] * sz + m[15];
        xs[i] = (cx / cw + 1) / 2 * width;
        ys[i] = (1 - cy / cw) / 2 * height;
        ups[i] = y;
      }

      // Facing the eye? The winding of its corners on the canvas says.
      place(0);
      place(1);
      place(2);
      final area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (ys[1] - ys[0]) * (xs[2] - xs[0]);
      if (area > -0.05) continue;
      for (var i = _rimAt; i < _facePoints.length; i++) {
        place(i);
      }
      final toEye = math.max(nz, 0.0);
      final shade = (0.72 + 0.28 * toEye + 0.12 * ny).clamp(0.0, 1.0) * s.brightness;
      final alpha = s.alpha * opacity;
      final flash = s.flash;
      int finish(double r, double g, double b) {
        r *= shade;
        g *= shade;
        b *= shade;
        r += (1 - r) * flash;
        g += (1 - g) * flash;
        b += (1 - b) * flash;
        return _argb(r, g, b, alpha);
      }

      // The rim: graded light at the top of the screen through its colour
      // to dark at the bottom; the face: its colour with a shine at the top.
      int rim(double up) {
        final y = (0.5 - up).clamp(0.0, 1.0);
        final (from, to, k) = y < 0.3 ? (light, base, y / 0.3) : (base, dark, (y - 0.3) / 0.7);
        return finish(from.r + (to.r - from.r) * k, from.g + (to.g - from.g) * k, from.b + (to.b - from.b) * k);
      }

      for (var i = _rimAt; i < _gridAt; i++) {
        rims[i] = rim(ups[i]);
      }
      for (final i in _cornerAt) {
        rims[i] = rim(ups[i]);
      }
      for (var i = _gridAt; i < _facePoints.length; i++) {
        final fy = ((0.37 - ups[i]) / 0.74).clamp(0.0, 1.0);
        final shine = 0.34 * math.max(0.0, 1 - fy * 2) * toEye;
        fills[i] = finish(base.r + (1 - base.r) * shine, base.g + (1 - base.g) * shine, base.b + (1 - base.b) * shine);
      }

      // The rim: an octagon round the inner square.
      for (var i = 0; i < 8; i++) {
        final j = (i + 1) % 8;
        final oi = _rimAt + i, oj = _rimAt + j;
        final ci = _octagon[i].$3, cj = _octagon[j].$3;
        final pi = _cornerAt[ci], pj = _cornerAt[cj];
        if (ci == cj) {
          t.addAt(xs, ys, oi, rims[oi], oj, rims[oj], pi, rims[pi]);
        } else {
          t.quadAt(xs, ys, oi, oj, pj, pi, rims[oi], rims[oj], rims[pj], rims[pi]);
        }
      }
      // The face: a three-by-three grid, for the shine to fade by the middle.
      for (var r = 0; r < 2; r++) {
        for (var c = 0; c < 2; c++) {
          final p00 = _gridAt + r * 3 + c, p01 = p00 + 1, p10 = p00 + 3, p11 = p00 + 4;
          t.quadAt(xs, ys, p00, p01, p11, p10, fills[p00], fills[p01], fills[p11], fills[p10]);
        }
      }

      // The skin's pips or sign on the face, as fans over it; not on a face
      // too small to read them on.
      if (marks.isEmpty || -area < 81) continue;
      final mx = _markXs, my = _markYs;
      // A point of the face at (a, b), y down as the marks are drawn, and
      // just off it towards the eye so that it lies over the face.
      void put(int i, double a, double b) {
        final x = nx * 0.502 + ux * a - vx * b;
        final y = ny * 0.502 + uy * a - vy * b;
        final z = nz * 0.502 + uz * a - vz * b;
        final sx = at.x + x * half, sy = at.y + y * half, sz = at.z + z * half - distance;
        final cx = m[0] * sx + m[4] * sy + m[8] * sz + m[12];
        final cy = m[1] * sx + m[5] * sy + m[9] * sz + m[13];
        final cw = m[3] * sx + m[7] * sy + m[11] * sz + m[15];
        mx[i] = (cx / cw + 1) / 2 * width;
        my[i] = (1 - cy / cw) / 2 * height;
      }

      final colour = markColour(tones);
      final ink = finish(colour.r, colour.g, colour.b);
      for (final mark in marks) {
        final centre = mark.centre, points = mark.points;
        put(0, centre.dx, centre.dy);
        for (var k = 0; k < points.length; k++) {
          put(k + 1, centre.dx + points[k].dx, centre.dy + points[k].dy);
        }
        for (var k = 0; k < points.length; k++) {
          t.addAt(mx, my, 0, ink, k + 1, ink, (k + 1) % points.length + 1, ink);
        }
      }
    }
  }

  /// An outline or a see-through box: a faint fill on the faces that look
  /// at the eye, their edges brighter.
  void _clear(_Triangles t, CubeClear c) {
    final q = c.turn;
    final (sx, sy, sz) = c.size;
    final fill = _argb(c.color.r, c.color.g, c.color.b, c.alpha * c.fill);
    final edge = _argb(c.color.r, c.color.g, c.color.b, c.alpha * math.max(c.fill, c.edge));
    for (final (n, u, v) in _faces) {
      final normal = V3(n[0] * sx, n[1] * sy, n[2] * sz).applyQuaternion(q);
      final uu = V3(u[0] * sx, u[1] * sy, u[2] * sz).applyQuaternion(q);
      final vv = V3(v[0] * sx, v[1] * sy, v[2] * sz).applyQuaternion(q);
      Offset point(double a, double b) => _project(
            c.at.x + normal.x * 0.5 + uu.x * a + vv.x * b,
            c.at.y + normal.y * 0.5 + uu.y * a + vv.y * b,
            c.at.z + normal.z * 0.5 + uu.z * a + vv.z * b,
          );
      final p0 = point(-0.5, -0.5), p1 = point(0.5, -0.5), p2 = point(0.5, 0.5), p3 = point(-0.5, 0.5);
      final area = (p1.dx - p0.dx) * (p2.dy - p0.dy) - (p1.dy - p0.dy) * (p2.dx - p0.dx);
      if (area > -0.05) continue;
      if (c.fill > 0.001) t.quad(p0, p1, p2, p3, fill, fill, fill, fill);
      if (c.edge > c.fill) {
        for (final (a, b) in [(p0, p1), (p1, p2), (p2, p3), (p3, p0)]) {
          _edge(t, a, b, 1.2, edge);
        }
      }
    }
  }

  /// A line `width` pixels wide, as two triangles.
  void _edge(_Triangles t, Offset a, Offset b, double width, int color) {
    final d = b - a;
    final length = d.distance;
    if (length < 0.01) return;
    final side = Offset(-d.dy, d.dx) / length * (width / 2);
    t.quad(a + side, b + side, b - side, a - side, color, color, color, color);
  }

  /// The glasses' numbers, laid out once for each look they take: laying
  /// text out costs more than everything else in a frame.
  static final _labelTexts = <(String, int, int), TextPainter>{};

  void _label(Canvas canvas, CubeLabel label) {
    final at = _p(label.at);
    final unit = (_p(V3(label.at.x + 1, label.at.y, label.at.z)) - at).distance;
    // Half a pixel of size and a fiftieth of opacity are not seen.
    final key = (label.text, (unit * 1.15 * 0.69 * 2).round(), (label.opacity.clamp(0.0, 1.0) * 50).round());
    var painter = _labelTexts.remove(key);
    if (painter == null) {
      if (_labelTexts.length >= 48) _labelTexts.remove(_labelTexts.keys.first)!.dispose();
      painter = TextPainter(
        text: TextSpan(
          text: label.text,
          style: Type.display(key.$2 / 2, color: Palette.text.withValues(alpha: key.$3 / 50)),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    }
    _labelTexts[key] = painter;
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(CubePainter old) => true;
}
