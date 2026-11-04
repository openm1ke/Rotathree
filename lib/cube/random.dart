import 'dart:math' as math;

/// mulberry32, as in webapp/src/cube/rules.ts, on unsigned 32-bit values:
/// the same seed draws the same sticks on both platforms.
class Mulberry32 implements math.Random {
  Mulberry32(int seed) : _state = seed & 0xffffffff;

  int _state;

  @override
  double nextDouble() {
    _state = (_state + 0x6d2b79f5) & 0xffffffff;
    var t = _state;
    t = _imul(t ^ (t >>> 15), t | 1);
    t ^= (t + _imul(t ^ (t >>> 7), t | 61)) & 0xffffffff;
    return ((t ^ (t >>> 14)) & 0xffffffff) / 4294967296;
  }

  @override
  int nextInt(int max) => (nextDouble() * max).floor();

  @override
  bool nextBool() => nextInt(2) == 0;
}

/// The low 32 bits of a * b, as Math.imul gives them.
int _imul(int a, int b) => ((a & 0xffffffff) * (b & 0xffffffff)) & 0xffffffff;
