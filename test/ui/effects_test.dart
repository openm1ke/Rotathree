import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/field/effects.dart';

import '../game/helpers.dart';

const quarter = math.pi / 2;

void main() {
  /// An engine and its effects, with the cross taking 0.3 s to a quarter turn.
  (Effects, void Function(int), List<double> Function(double)) setup({double turnSeconds = 0.3}) {
    final engine = newEngine();
    final fx = Effects(random: math.Random(1))
      ..turnSeconds = turnSeconds
      ..reset(engine.activeSide);
    void turn(int quarterTurns) {
      engine.switchSide(quarterTurns);
      fx.consume(engine.drainEvents(), engine);
    }

    /// Plays [seconds] of animation in small frames and returns every angle.
    List<double> play(double seconds) {
      final angles = <double>[];
      for (var t = 0.0; t < seconds - 1e-9; t += 0.01) {
        fx.update(0.01, engine);
        angles.add(fx.viewAngle);
      }
      return angles;
    }

    return (fx, turn, play);
  }

  test('the cross eases to the new glass and stops there without swinging past', () {
    final (fx, turn, play) = setup();
    turn(1);
    final angles = play(0.3);
    // Bringing the glass on the right to the top turns the view anticlockwise.
    expect(angles.last, closeTo(-quarter, 1e-9));
    for (var i = 1; i < angles.length; i++) {
      expect(angles[i], lessThanOrEqualTo(angles[i - 1] + 1e-12));
      expect(angles[i], greaterThanOrEqualTo(-quarter - 1e-12));
    }
    // Slow at both ends, fastest in the middle.
    final first = (angles[1] - angles[0]).abs();
    final middle = (angles[15] - angles[14]).abs();
    final end = (angles[29] - angles[28]).abs();
    expect(middle, greaterThan(first * 2));
    expect(middle, greaterThan(end * 2));
    expect(play(0.2).every((angle) => (angle + quarter).abs() < 1e-9), isTrue);
    expect(fx.turnMotion, 0);
  });

  test('a turn ordered mid-turn carries on without a jerk', () {
    final (fx, turn, play) = setup();
    turn(1);
    final before = play(0.15);
    final speedBefore = before.last - before[before.length - 2];
    turn(1);
    final after = play(0.6);
    final speedAfter = after.first - before.last;
    expect((speedAfter - speedBefore).abs(), lessThan(speedBefore.abs() * 0.35));
    expect(after.last, closeTo(-2 * quarter, 1e-9));
    expect(after.reduce(math.min), greaterThanOrEqualTo(-2 * quarter - 1e-12));
    expect(fx.targetTurns, -2);
  });

  test('a half turn takes longer than a quarter, but not twice as long', () {
    final (_, turn, play) = setup();
    turn(2);
    final angles = play(0.45);
    expect(angles[29], greaterThan(-2 * quarter + 0.05)); // not there yet at 0.3 s
    expect(angles.last, closeTo(-2 * quarter, 1e-9));
  });

  test('with a duration of zero the cross is simply there', () {
    final (fx, turn, play) = setup(turnSeconds: 0);
    turn(-1);
    expect(fx.viewAngle, closeTo(quarter, 1e-9));
    expect(play(0.05).every((angle) => (angle - quarter).abs() < 1e-9), isTrue);
    expect(fx.turnMotion, 0);
  });

  test('a level-up throws rings and confetti, then clears up after itself', () {
    final (fx, _, play) = setup();
    fx.celebrate(6);
    expect(fx.rings, hasLength(3));
    expect(fx.particles.length, greaterThan(100));
    play(2.4);
    expect(fx.rings, isEmpty);
    expect(fx.particles, isEmpty);
  });
}
