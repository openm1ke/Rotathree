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
/// points belongs to.
const _inner = 0.5 - _round;
const _octagon = <(double, double, int)>[
  (-0.5, -_inner, 0), (-_inner, -0.5, 0), (_inner, -0.5, 1), (0.5, -_inner, 1),
  (0.5, _inner, 2), (_inner, 0.5, 2), (-_inner, 0.5, 3), (-0.5, _inner, 3),
];
const _innerCorners = <(double, double)>[(-_inner, -_inner), (_inner, -_inner), (_inner, _inner), (-_inner, _inner)];
const _grid = [-_inner, 0.0, _inner];

class CubePainter extends CustomPainter {
  CubePainter(this.view, {super.repaint});

  final CubeView view;
  static final _triangles = _Triangles();

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
    if (view.xrayOpacity > 0.01) {
      for (final x in view.xrays) {
        if (_hidden(x)) _solid(t, x, view.xrayOpacity);
      }
    }
    t.draw(canvas);

    for (final label in view.labels) {
      _label(canvas, label);
    }
  }

  /// Whether something nearer covers the middle of [x] on the canvas.
  bool _hidden(CubeSolid x) {
    final at = _p(x.at);
    final cell = (_p(V3(x.at.x + 0.5, x.at.y, x.at.z)) - at).distance;
    for (final s in view.solids) {
      if (s.depth >= x.depth - 0.64 || s.size < 0.5) continue;
      if ((_p(s.at) - at).distance < cell) return true;
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
    final base = tones.base, light = tones.light, dark = tones.dark;
    final q = s.turn;
    final half = s.size;
    for (final (n, u, v) in _faces) {
      final normal = V3(n[0], n[1], n[2]).applyQuaternion(q);
      final uu = V3(u[0], u[1], u[2]).applyQuaternion(q);
      final vv = V3(v[0], v[1], v[2]).applyQuaternion(q);
      // A point of the face in its own (a, b), in the scene and on the canvas;
      // and how far up the screen it is from the cube's middle (vUp).
      (Offset, double) point(double a, double b) {
        final x = normal.x * 0.5 + uu.x * a + vv.x * b;
        final y = normal.y * 0.5 + uu.y * a + vv.y * b;
        final z = normal.z * 0.5 + uu.z * a + vv.z * b;
        return (_project(s.at.x + x * half, s.at.y + y * half, s.at.z + z * half), y);
      }

      // Facing the eye? The winding of its corners on the canvas says.
      final c0 = point(-0.5, -0.5).$1;
      final c1 = point(0.5, -0.5).$1;
      final c2 = point(0.5, 0.5).$1;
      final area = (c1.dx - c0.dx) * (c2.dy - c0.dy) - (c1.dy - c0.dy) * (c2.dx - c0.dx);
      if (area > -0.05) continue;
      final toEye = math.max(normal.z, 0.0);
      final shade = (0.72 + 0.28 * toEye + 0.12 * normal.y).clamp(0.0, 1.0) * s.brightness;
      final alpha = s.alpha * opacity;
      int finish(double r, double g, double b) {
        r *= shade;
        g *= shade;
        b *= shade;
        r += (1 - r) * s.flash;
        g += (1 - g) * s.flash;
        b += (1 - b) * s.flash;
        return _argb(r, g, b, alpha);
      }

      int rim(double up) {
        final y = (0.5 - up).clamp(0.0, 1.0);
        final (from, to, k) = y < 0.3 ? (light, base, y / 0.3) : (base, dark, (y - 0.3) / 0.7);
        return finish(from.r + (to.r - from.r) * k, from.g + (to.g - from.g) * k, from.b + (to.b - from.b) * k);
      }

      int face(double up) {
        final fy = ((0.37 - up) / 0.74).clamp(0.0, 1.0);
        final shine = 0.34 * math.max(0.0, 1 - fy * 2) * toEye;
        return finish(base.r + (1 - base.r) * shine, base.g + (1 - base.g) * shine, base.b + (1 - base.b) * shine);
      }

      // The rim: an octagon round the inner square.
      final outer = [for (final (a, b, _) in _octagon) point(a, b)];
      final corners = [for (final (a, b) in _innerCorners) point(a, b)];
      for (var i = 0; i < 8; i++) {
        final j = (i + 1) % 8;
        final (oi, ui) = outer[i];
        final (oj, uj) = outer[j];
        final ci = _octagon[i].$3, cj = _octagon[j].$3;
        final (pi, upi) = corners[ci];
        final (pj, upj) = corners[cj];
        if (ci == cj) {
          t.add(oi, rim(ui), oj, rim(uj), pi, rim(upi));
        } else {
          t.quad(oi, oj, pj, pi, rim(ui), rim(uj), rim(upj), rim(upi));
        }
      }
      // The face: a three-by-three grid, for the shine to fade by the middle.
      final grid = [
        for (final b in _grid) [for (final a in _grid) point(a, b)],
      ];
      for (var r = 0; r < 2; r++) {
        for (var c = 0; c < 2; c++) {
          final (p00, u00) = grid[r][c];
          final (p01, u01) = grid[r][c + 1];
          final (p11, u11) = grid[r + 1][c + 1];
          final (p10, u10) = grid[r + 1][c];
          t.quad(p00, p01, p11, p10, face(u00), face(u01), face(u11), face(u10));
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

  void _label(Canvas canvas, CubeLabel label) {
    final at = _p(label.at);
    final unit = (_p(V3(label.at.x + 1, label.at.y, label.at.z)) - at).distance;
    final painter = TextPainter(
      text: TextSpan(
        text: label.text,
        style: Type.display(unit * 1.15 * 0.69, color: Palette.text.withValues(alpha: label.opacity)),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, at - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(CubePainter old) => true;
}
