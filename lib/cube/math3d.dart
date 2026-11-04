// The little 3D the picture of Cube needs, with three.js's own conventions
// (webapp/src/cube/view.ts is drawn with it): vectors, quaternions that turn
// them, and the camera's projection. Kept apart from vector_math on purpose:
// the order of products and the way turns are applied must be exactly those
// the web's view was written for.
import 'dart:math' as math;

import 'rules.dart';

class V3 {
  V3(this.x, this.y, this.z);
  V3.zero() : x = 0, y = 0, z = 0;
  V3.ofVec(Vec v) : x = v.x.toDouble(), y = v.y.toDouble(), z = v.z.toDouble();

  double x, y, z;

  V3 clone() => V3(x, y, z);
  V3 copy(V3 o) => this
    ..x = o.x
    ..y = o.y
    ..z = o.z;
  V3 set(double x, double y, double z) => this
    ..x = x
    ..y = y
    ..z = z;
  V3 add(V3 o) => this
    ..x += o.x
    ..y += o.y
    ..z += o.z;
  V3 addScaled(V3 o, double k) => this
    ..x += o.x * k
    ..y += o.y * k
    ..z += o.z * k;
  V3 scale(double k) => this
    ..x *= k
    ..y *= k
    ..z *= k;
  V3 lerp(V3 o, double t) => this
    ..x += (o.x - x) * t
    ..y += (o.y - y) * t
    ..z += (o.z - z) * t;
  V3 negate() => scale(-1);
  V3 round() => set(x.roundToDouble(), y.roundToDouble(), z.roundToDouble());
  double dot(V3 o) => x * o.x + y * o.y + z * o.z;
  double get lengthSq => x * x + y * y + z * z;
  double get length => math.sqrt(lengthSq);
  V3 normalize() {
    final l = length;
    return l > 0 ? scale(1 / l) : this;
  }

  double distanceToSq(V3 o) {
    final dx = x - o.x, dy = y - o.y, dz = z - o.z;
    return dx * dx + dy * dy + dz * dz;
  }

  double distanceTo(V3 o) => math.sqrt(distanceToSq(o));

  /// Turns this vector by [q] (three.js `applyQuaternion`).
  V3 applyQuaternion(Q q) {
    final vx = x, vy = y, vz = z;
    final qx = q.x, qy = q.y, qz = q.z, qw = q.w;
    final tx = 2 * (qy * vz - qz * vy);
    final ty = 2 * (qz * vx - qx * vz);
    final tz = 2 * (qx * vy - qy * vx);
    x = vx + qw * tx + qy * tz - qz * ty;
    y = vy + qw * ty + qz * tx - qx * tz;
    z = vz + qw * tz + qx * ty - qy * tx;
    return this;
  }

  /// The nearest data direction (three.js `round()` after a turn).
  Vec toVec() => Vec(x.round(), y.round(), z.round());
}

/// A turn, as three.js keeps it: x, y, z, w.
class Q {
  Q([this.x = 0, this.y = 0, this.z = 0, this.w = 1]);

  double x, y, z, w;

  Q clone() => Q(x, y, z, w);
  Q copy(Q o) => this
    ..x = o.x
    ..y = o.y
    ..z = o.z
    ..w = o.w;
  Q identity() => this
    ..x = 0
    ..y = 0
    ..z = 0
    ..w = 1;

  Q setFromAxisAngle(V3 axis, double angle) {
    final half = angle / 2, s = math.sin(half);
    x = axis.x * s;
    y = axis.y * s;
    z = axis.z * s;
    w = math.cos(half);
    return this;
  }

  /// this = this · b.
  Q multiply(Q b) => _multiply(this, b);

  /// this = a · this.
  Q premultiply(Q a) => _multiply(a, this);

  Q _multiply(Q a, Q b) {
    final qax = a.x, qay = a.y, qaz = a.z, qaw = a.w;
    final qbx = b.x, qby = b.y, qbz = b.z, qbw = b.w;
    x = qax * qbw + qaw * qbx + qay * qbz - qaz * qby;
    y = qay * qbw + qaw * qby + qaz * qbx - qax * qbz;
    z = qaz * qbw + qaw * qbz + qax * qby - qay * qbx;
    w = qaw * qbw - qax * qbx - qay * qby - qaz * qbz;
    return this;
  }

  Q invert() => this
    ..x = -x
    ..y = -y
    ..z = -z;

  double dot(Q o) => x * o.x + y * o.y + z * o.z + w * o.w;

  Q normalize() {
    var l = math.sqrt(x * x + y * y + z * z + w * w);
    if (l == 0) return identity();
    l = 1 / l;
    return this
      ..x *= l
      ..y *= l
      ..z *= l
      ..w *= l;
  }

  /// three.js `slerp`: towards [qb] by [t].
  Q slerp(Q qb, double t) {
    if (t == 0) return this;
    if (t == 1) return copy(qb);
    final x0 = x, y0 = y, z0 = z, w0 = w;
    var cosHalf = w0 * qb.w + x0 * qb.x + y0 * qb.y + z0 * qb.z;
    if (cosHalf < 0) {
      w = -qb.w;
      x = -qb.x;
      y = -qb.y;
      z = -qb.z;
      cosHalf = -cosHalf;
    } else {
      copy(qb);
    }
    if (cosHalf >= 1) {
      w = w0;
      x = x0;
      y = y0;
      z = z0;
      return this;
    }
    final sqrSin = 1 - cosHalf * cosHalf;
    if (sqrSin <= 2.220446049250313e-16) {
      final s = 1 - t;
      w = s * w0 + t * w;
      x = s * x0 + t * x;
      y = s * y0 + t * y;
      z = s * z0 + t * z;
      return normalize();
    }
    final sinHalf = math.sqrt(sqrSin);
    final halfTheta = math.atan2(sinHalf, cosHalf);
    final ratioA = math.sin((1 - t) * halfTheta) / sinHalf, ratioB = math.sin(t * halfTheta) / sinHalf;
    w = w0 * ratioA + w * ratioB;
    x = x0 * ratioA + x * ratioB;
    y = y0 * ratioA + y * ratioB;
    z = z0 * ratioA + z * ratioB;
    return this;
  }

  Q slerpQuaternions(Q a, Q b, double t) => copy(a).slerp(b, t);

  /// The turn that takes unit [from] to unit [to] (three.js `setFromUnitVectors`).
  Q setFromUnitVectors(V3 from, V3 to) {
    var r = from.dot(to) + 1;
    if (r < 2.220446049250313e-16) {
      r = 0;
      if (from.x.abs() > from.z.abs()) {
        x = -from.y;
        y = from.x;
        z = 0;
        w = r;
      } else {
        x = 0;
        y = -from.z;
        z = from.y;
        w = r;
      }
    } else {
      x = from.y * to.z - from.z * to.y;
      y = from.z * to.x - from.x * to.z;
      z = from.x * to.y - from.y * to.x;
      w = r;
    }
    return normalize();
  }

  /// Turns about x then y then z, as three.js's Euler in its default order.
  Q setFromEuler(double ex, double ey, double ez) {
    final c1 = math.cos(ex / 2), c2 = math.cos(ey / 2), c3 = math.cos(ez / 2);
    final s1 = math.sin(ex / 2), s2 = math.sin(ey / 2), s3 = math.sin(ez / 2);
    x = s1 * c2 * c3 + c1 * s2 * s3;
    y = c1 * s2 * c3 - s1 * c2 * s3;
    z = c1 * c2 * s3 + s1 * s2 * c3;
    w = c1 * c2 * c3 - s1 * s2 * s3;
    return this;
  }

  /// From the columns of a pure rotation (three.js `setFromRotationMatrix`).
  Q setFromColumns(V3 c0, V3 c1, V3 c2) {
    final m11 = c0.x, m12 = c1.x, m13 = c2.x;
    final m21 = c0.y, m22 = c1.y, m23 = c2.y;
    final m31 = c0.z, m32 = c1.z, m33 = c2.z;
    final trace = m11 + m22 + m33;
    if (trace > 0) {
      final s = 0.5 / math.sqrt(trace + 1);
      w = 0.25 / s;
      x = (m32 - m23) * s;
      y = (m13 - m31) * s;
      z = (m21 - m12) * s;
    } else if (m11 > m22 && m11 > m33) {
      final s = 2 * math.sqrt(1 + m11 - m22 - m33);
      w = (m32 - m23) / s;
      x = 0.25 * s;
      y = (m12 + m21) / s;
      z = (m13 + m31) / s;
    } else if (m22 > m33) {
      final s = 2 * math.sqrt(1 + m22 - m11 - m33);
      w = (m13 - m31) / s;
      x = (m12 + m21) / s;
      y = 0.25 * s;
      z = (m23 + m32) / s;
    } else {
      final s = 2 * math.sqrt(1 + m33 - m11 - m22);
      w = (m21 - m12) / s;
      x = (m13 + m31) / s;
      y = (m23 + m32) / s;
      z = 0.25 * s;
    }
    return this;
  }

  /// The columns of this turn: where it takes x, y and z.
  (V3, V3, V3) columns() => (
        V3(1, 0, 0).applyQuaternion(this),
        V3(0, 1, 0).applyQuaternion(this),
        V3(0, 0, 1).applyQuaternion(this),
      );

  bool equals(Q o) => x == o.x && y == o.y && z == o.z && w == o.w;

  String get key => '$x,$y,$z,$w';
}

final sceneRight = V3(1, 0, 0);
final sceneUp = V3(0, 1, 0);
final sceneToward = V3(0, 0, 1);

/// The flat game's easing of a turn.
double ease(double t) => t < 0.5 ? 4 * t * t * t : 1 - math.pow(-2 * t + 2, 3) / 2;

/// A scene direction in the data frame of a turn `q`.
Vec dataIn(Q q, V3 v) => v.clone().applyQuaternion(q.clone().invert()).toVec();

/// `base` after a quarter turn about a scene axis, snapped so that the
/// rounding drift of many turns never builds up.
Q quarterTurned(V3 axis, int quarters, Q base) {
  final q = Q().setFromAxisAngle(axis, quarters * math.pi / 2).multiply(base);
  final (c0, c1, c2) = q.columns();
  return q.setFromColumns(c0.round(), c1.round(), c2.round());
}

/// A 4×4 matrix in three.js's column-major order.
class M4 {
  M4() : e = List<double>.filled(16, 0);
  final List<double> e;

  /// three.js `makePerspective` for a camera with this vertical field of
  /// view (degrees), aspect, near and far.
  M4 perspective(double fov, double aspect, double near, double far) {
    final top = near * math.tan(fov * math.pi / 360);
    final height = 2 * top, width = aspect * height;
    final left = -0.5 * width, right = left + width, bottom = top - height;
    e.fillRange(0, 16, 0);
    e[0] = 2 * near / (right - left);
    e[5] = 2 * near / (top - bottom);
    e[8] = (right + left) / (right - left);
    e[9] = (top + bottom) / (top - bottom);
    e[10] = -(far + near) / (far - near);
    e[11] = -1;
    e[14] = -2 * far * near / (far - near);
    return this;
  }

  /// three.js `makeOrthographic`.
  M4 orthographic(double left, double right, double top, double bottom, double near, double far) {
    final w = 1 / (right - left), h = 1 / (top - bottom), p = 1 / (far - near);
    e.fillRange(0, 16, 0);
    e[0] = 2 * w;
    e[5] = 2 * h;
    e[10] = -2 * p;
    e[12] = -(right + left) * w;
    e[13] = -(top + bottom) * h;
    e[14] = -(far + near) * p;
    e[15] = 1;
    return this;
  }
}
