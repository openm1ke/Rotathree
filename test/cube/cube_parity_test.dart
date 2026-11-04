import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/cube/random.dart';
import 'package:rotathree/cube/rules.dart';

/// Rules parity of Cube with the web (webapp/src/tests/cubeParity.test.ts).
///
/// Cube was made on the web, so the web test is the reference: it plays
/// scripted games and stores the hash of the whole state after every action
/// in parity/cube-trace.json. This test replays the same scripts with the Dart
/// rules and must reproduce every hash. The script, the line format and the
/// hash are defined in both files; keep them in step. A mismatch is easiest
/// to find through the stored checkpoints, full state lines every 200 steps.

const _fixturePath = 'parity/cube-trace.json';
const _checkpointEvery = 200;

/// Every this many actions the script starts a new game.
const _gameLength = 500;

void main() {
  final fixture = jsonDecode(File(_fixturePath).readAsStringSync()) as Map<String, Object?>;

  test('the default configuration is the web one', () {
    expect(_configDigest(const CubeConfig()), fixture['config']);
  });

  for (final scenario in (fixture['scenarios'] as List).cast<Map<String, Object?>>()) {
    test('the Dart rules replay "${scenario['name']}" step by step', () {
      final run = _run(scenario);
      final checkpoints = (scenario['checkpoints'] as Map).cast<String, String>();
      for (final MapEntry(:key, :value) in checkpoints.entries) {
        expect(run.checkpoints[key], value, reason: 'checkpoint at step $key');
      }
      final expected = scenario['trace'] as String;
      for (var i = 0; i < expected.length; i += 8) {
        if (run.trace.substring(i, i + 8) != expected.substring(i, i + 8)) {
          fail('the state after step ${i ~/ 8} differs from the web');
        }
      }
      expect(run.trace.length, expected.length);
    });
  }
}

CubeConfig _configOf(Map<String, Object?> o, int seed) {
  final ramp = o['ramp'] as Map<String, Object?>?;
  return CubeConfig(
    centre: o['centre'] as int? ?? 7,
    arm: o['arm'] as int? ?? 8,
    numberOfColors: o['numberOfColors'] as int? ?? 4,
    depthFalls: o['depthFalls'] as bool? ?? false,
    inactiveFalls: o['inactiveFalls'] as bool? ?? true,
    ramp: ramp == null
        ? null
        : CubeRamp(
            everyPoints: (ramp['everyPoints'] as num).toDouble(),
            factor: (ramp['factor'] as num).toDouble(),
            minActive: (ramp['minActive'] as num).toDouble(),
            minInactive: (ramp['minInactive'] as num).toDouble(),
          ),
    seed: seed,
  );
}

({String trace, Map<String, String> checkpoints}) _run(Map<String, Object?> spec) {
  final config = (spec['config'] as Map).cast<String, Object?>();
  final seed = spec['seed'] as int;
  var restarts = 0;
  CubeGame fresh() => CubeGame(_configOf(config, seed + restarts));
  var game = fresh();
  final steps = spec['steps'] as int;
  final actions = _script(spec['actionSeed'] as int, steps);
  final trace = StringBuffer();
  final checkpoints = <String, String>{};
  void record(int step) {
    final line = _canonical(game, game.drainEvents());
    trace.write(_hash(line).toRadixString(16).padLeft(8, '0'));
    if (step % _checkpointEvery == 0) checkpoints['$step'] = line;
  }

  record(0);
  for (var step = 1; step <= steps; step++) {
    final action = actions[step - 1];
    if (action.op == 'restart') {
      restarts++;
      game = fresh();
    } else {
      _apply(game, action);
    }
    record(step);
  }
  return (trace: trace.toString(), checkpoints: checkpoints);
}

typedef _Action = ({String op, String arg, int q});

_Action _draw(Mulberry32 rnd) {
  final r = rnd.nextDouble();
  if (r < 0.22) return (op: 'move', arg: const ['right', 'left', 'up', 'down'][(rnd.nextDouble() * 4).floor()], q: 0);
  if (r < 0.32) return (op: 'rotate', arg: const ['toward', 'away', 'up'][(rnd.nextDouble() * 3).floor()], q: 0);
  if (r < 0.38) return (op: 'cross', arg: '', q: rnd.nextDouble() < 0.5 ? 1 : -1);
  if (r < 0.43) return (op: 'tip', arg: '', q: rnd.nextDouble() < 0.5 ? 1 : -1);
  if (r < 0.47) return (op: 'control', arg: const ['front', 'back', 'top'][(rnd.nextDouble() * 3).floor()], q: 0);
  if (r < 0.5) return (op: 'drop', arg: '', q: 0);
  if (r < 0.54) return (op: 'soft', arg: '', q: rnd.nextDouble() < 0.5 ? 1 : 0);
  if (r < 0.545) return (op: 'restart', arg: '', q: 0);
  return (op: 'update', arg: '', q: 1 + (rnd.nextDouble() * 420).floor());
}

List<_Action> _script(int seed, int count) {
  final rnd = Mulberry32(seed);
  return [
    for (var i = 0; i < count; i++)
      () {
        final action = _draw(rnd);
        return (i + 1) % _gameLength == 0 ? (op: 'restart', arg: '', q: 0) : action;
      }(),
  ];
}

/// The hub turned a quarter in the screen, counterclockwise for +1.
void _crossTurn(CubeGame game, int q) {
  final ViewFrame(:right, :up) = game.viewFrame;
  final frame = q == 1 ? ViewFrame(-up, right) : ViewFrame(up, -right);
  game.turn(sideOfNormal(frame.up), game.plane, frame, false);
}

/// The hub tipped over about the screen's right: +1 brings the glass behind
/// to the top, −1 the one in front.
void _tip(CubeGame game, int q) {
  final ViewFrame(:right, :up) = game.viewFrame;
  final plane = game.plane;
  final frame = q == 1 ? ViewFrame(right, -plane) : ViewFrame(right, plane);
  game.turn(sideOfNormal(frame.up), q == 1 ? up : -up, frame, true);
}

void _apply(CubeGame game, _Action a) {
  final ViewFrame(:right, :up) = game.viewFrame;
  switch (a.op) {
    case 'move':
      game.move(switch (a.arg) { 'right' => right, 'left' => -right, 'up' => up, _ => -up });
    case 'rotate':
      game.rotate(switch (a.arg) { 'toward' => game.plane, 'away' => -game.plane, _ => up });
    case 'cross':
      _crossTurn(game, a.q);
    case 'tip':
      _tip(game, a.q);
    case 'control':
      game.control(switch (a.arg) {
        'front' => sideOfNormal(game.plane),
        'back' => sideOfNormal(-game.plane),
        _ => game.down,
      });
    case 'drop':
      game.dropActive();
    case 'soft':
      game.softDrop = a.q == 1;
    case 'update':
      game.update(a.q / 1000);
  }
}

int _micro(num value) => (value * 1000000).round();
int _ms(double seconds) => (seconds * 1000).floor();

String _event(CubeEvent e) => switch (e) {
      Switched(:final from, :final to) => 'switched:$from:$to',
      Moved(:final blocked) => 'moved:${blocked ? 1 : 0}',
      Rotated(:final blocked) => 'rotated:${blocked ? 1 : 0}',
      Stepped(:final side) => 'stepped:$side',
      Dropped(:final side, :final cells) => 'dropped:$side:$cells',
      Landed(:final side, :final dropped) => 'landed:$side:${dropped ? 1 : 0}',
      Matched(:final combo, :final score, :final match) => 'matched:$combo:$score:${match.cells.length}',
      Popped(:final cells) => 'popped:${cells.length}',
      Fell(:final moves) => 'fell:${moves.length}',
      SpeedUp(:final level) => 'speedUp:$level',
      GameEnded(:final side) => 'gameEnded:$side',
    };

/// One line with everything the rules decide, as the web test writes it.
String _canonical(CubeGame g, List<CubeEvent> events) {
  final parts = <String>[
    'ph=${g.phase.name}',
    'a=${g.active}',
    'd=${g.down}',
    'pl=${g.plane}',
    'vf=${g.viewFrame.right};${g.viewFrame.up}',
    'sc=${g.score}',
    'cb=${g.combo}',
    'bc=${g.bestCombo}',
    'pp=${g.placed}',
    'mt=${g.matches}',
    'cc=${g.cleared}',
    'sl=${g.speedLevel}',
    'et=${_ms(g.seconds)}',
    'pe=${_ms(g.phaseElapsed)}',
    'pd=${_ms(g.phaseDuration)}',
    'go=${g.gameOverSide ?? -1}',
    'iq=${g.queuedInputs}',
    'cfg=${_micro(g.config.activeStepSeconds)},${_micro(g.config.inactiveStepSeconds)}',
  ];
  for (final s in sides) {
    final p = g.pieces[s.id];
    if (p != null) parts.add('p${s.id}=${p.colors.join()}@${p.pivot}/${p.dir}/${_micro(p.progress)}');
    parts.add('n${s.id}=${g.nextOf(s.id).join()}');
  }
  final blocks = <String>[];
  g.hub.forEachBlock((_, color, index) => blocks.add('$index:$color'));
  parts
    ..add('hub=${blocks.join(',')}')
    ..add('ev=${events.map(_event).join(',')}');
  return parts.join('|');
}

/// Every default the rules depend on, in the order of the web's object.
String _configDigest(CubeConfig c) => [
      'centre=${_micro(c.centre)}',
      'arm=${_micro(c.arm)}',
      'pieceLength=${_micro(c.pieceLength)}',
      'numberOfColors=${_micro(c.numberOfColors)}',
      'minMatchLength=${_micro(c.minMatchLength)}',
      'activeStepSeconds=${_micro(c.activeStepSeconds)}',
      'inactiveStepSeconds=${_micro(c.inactiveStepSeconds)}',
      'softDropStepSeconds=${_micro(c.softDropStepSeconds)}',
      'inactiveFalls=${c.inactiveFalls}',
      'depthFalls=${c.depthFalls}',
      'depthStepSeconds=${_micro(c.depthStepSeconds)}',
      'monoPieceKeepChance=${_micro(c.monoPieceKeepChance)}',
      'pauseIncomingDuringCascade=${c.pauseIncomingDuringCascade}',
      'dropBaseSeconds=${_micro(c.dropBaseSeconds)}',
      'dropSecondsPerCell=${_micro(c.dropSecondsPerCell)}',
      'matchSeconds=${_micro(c.matchSeconds)}',
      'clearSeconds=${_micro(c.clearSeconds)}',
      'fallBaseSeconds=${_micro(c.fallBaseSeconds)}',
      'fallSecondsPerRootCell=${_micro(c.fallSecondsPerRootCell)}',
      'fallBounceSeconds=${_micro(c.fallBounceSeconds)}',
      'basePoints=${_micro(c.basePoints)}',
      'maxQueuedInputs=${_micro(c.maxQueuedInputs)}',
    ].join(';');

/// FNV-1a, 32 bit, as the web test computes it.
int _hash(String text) {
  var h = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}
