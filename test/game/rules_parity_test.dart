import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/engine/game_engine.dart';
import 'package:rotathree/game/engine/game_event.dart';
import 'package:rotathree/game/engine/speed_ramp.dart';
import 'package:rotathree/game/model/board.dart';
import 'package:rotathree/game/model/side.dart';

/// Rules parity with the web engine (webapp/src/tests/parity.test.ts).
///
/// Both engines are fed the same scripts: a seed for the piece colours and an
/// action seed. Every action is drawn from mulberry32, the generator the web
/// uses, so the same numbers come out on both platforms. After each action the
/// whole visible state is written as one line and hashed. The stored trace is
/// the list of those hashes; the web test must reproduce it step by step.
///
/// This file is the reference. Regenerate the stored trace with
///   ROTATHREE_WRITE_PARITY=1 flutter test test/game/rules_parity_test.dart
/// and debug a mismatch by dumping every state line with
///   ROTATHREE_PARITY_DUMP=/path/to/dump.txt flutter test test/game/rules_parity_test.dart

const _fixturePath = 'parity/rules-trace.json';
const _checkpointEvery = 250;

/// The scripted games. The web test reads these from the stored fixture.
const _scenarios = <Map<String, Object?>>[
  {
    'name': 'classic',
    'seed': 1,
    'actionSeed': 101,
    'steps': 2500,
    'config': <String, Object?>{},
    'ramp': null,
  },
  {
    'name': 'speed ramp',
    'seed': 2,
    'actionSeed': 202,
    'steps': 2500,
    'config': <String, Object?>{},
    'ramp': {'everyPoints': 300, 'factor': 0.9, 'minActive': 0.4, 'minInactive': 1.2},
  },
  {
    'name': 'three glasses, four colours',
    'seed': 3,
    'actionSeed': 303,
    'steps': 2500,
    'config': {'glassCount': 3, 'numberOfColors': 4},
    'ramp': null,
  },
  {
    'name': 'fast active glass, five colours',
    'seed': 4,
    'actionSeed': 404,
    'steps': 2500,
    'config': {'activeStepSeconds': 0.5, 'numberOfColors': 5},
    'ramp': null,
  },
];

void main() {
  test('the Dart engine reproduces the stored rules trace', () {
    final fixture = buildRulesFixture(dumpPath: Platform.environment['ROTATHREE_PARITY_DUMP']);
    final file = File(_fixturePath);
    if (Platform.environment['ROTATHREE_WRITE_PARITY'] == '1') {
      file.writeAsStringSync('${const JsonEncoder.withIndent('  ').convert(fixture)}\n');
      return;
    }
    final stored = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
    expect(fixture['config'], stored['config'], reason: 'default configuration changed');
    final actual = fixture['scenarios'] as List;
    final expected = stored['scenarios'] as List;
    expect(actual.length, expected.length, reason: 'scenario count changed');
    for (var i = 0; i < actual.length; i++) {
      final mine = actual[i] as Map<String, Object?>;
      final theirs = expected[i] as Map<String, Object?>;
      expect(mine['name'], theirs['name']);
      expect(mine['trace'], theirs['trace'], reason: 'trace of "${mine['name']}" differs');
      expect(mine['checkpoints'], theirs['checkpoints'], reason: 'checkpoints of "${mine['name']}" differ');
    }
  });

  test('the default configuration has the values the web engine uses', () {
    expect(const GameConfig().animationSpeed, 1.0);
  });
}

/// The whole fixture: default configuration digest, then every scenario.
Map<String, Object?> buildRulesFixture({String? dumpPath}) {
  final dump = dumpPath == null ? null : StringBuffer();
  final scenarios = [for (final spec in _scenarios) _runScenario(spec, dump)];
  if (dumpPath != null) File(dumpPath).writeAsStringSync(dump.toString());
  return {
    'format': 'rotathree-rules-parity',
    'version': 1,
    'config': _configDigest(const GameConfig()),
    'scenarios': scenarios,
  };
}

Map<String, Object?> _runScenario(Map<String, Object?> spec, StringBuffer? dump) {
  final name = spec['name'] as String;
  final steps = spec['steps'] as int;
  final engine = GameEngine(
    config: _configFrom(spec['config'] as Map<String, Object?>),
    random: _Mulberry32(spec['seed'] as int),
  );
  final ramp = spec['ramp'] as Map<String, Object?>?;
  if (ramp != null) {
    engine.setRamp(
      SpeedRamp(
        everyPoints: ramp['everyPoints'] as int,
        factor: (ramp['factor'] as num).toDouble(),
        minActive: (ramp['minActive'] as num).toDouble(),
        minInactive: (ramp['minInactive'] as num).toDouble(),
      ),
    );
  }
  final actions = _script(spec['actionSeed'] as int, steps);
  final trace = StringBuffer();
  final checkpoints = <String, String>{};

  void record(int step, List<GameEvent> events) {
    final line = _canonical(engine, events);
    trace.write(_hash(line).toRadixString(16).padLeft(8, '0'));
    if (step % _checkpointEvery == 0) checkpoints['$step'] = line;
    dump?.writeln('$name\t$step\t$line');
  }

  record(0, const []);
  for (var step = 1; step <= steps; step++) {
    _apply(engine, actions[step - 1]);
    record(step, engine.drainEvents());
  }
  return {
    'name': name,
    'seed': spec['seed'],
    'actionSeed': spec['actionSeed'],
    'steps': steps,
    'config': spec['config'],
    'ramp': ramp,
    'trace': trace.toString(),
    'checkpoints': checkpoints,
  };
}

/// Every this many actions the script starts a new game, so that a long
/// scenario keeps exercising play after an early game over.
const _gameLength = 600;

/// Draws the scripted actions. The web test has the same function.
List<Map<String, Object?>> _script(int seed, int count) {
  final rnd = _Mulberry32(seed);
  final actions = <Map<String, Object?>>[];
  for (var i = 0; i < count; i++) {
    final action = _draw(rnd);
    actions.add((i + 1) % _gameLength == 0 ? {'op': 'restart'} : action);
  }
  return actions;
}

Map<String, Object?> _draw(_Mulberry32 rnd) {
  final r = rnd.nextDouble();
  if (r < 0.28) return {'op': 'move', 'delta': rnd.nextDouble() < 0.5 ? -1 : 1};
  if (r < 0.40) return {'op': 'rotate', 'cw': rnd.nextDouble() < 0.5};
  if (r < 0.46) return {'op': 'turn', 'q': 1 + (rnd.nextDouble() * 3).floor()};
  if (r < 0.50) return {'op': 'activate', 'side': (rnd.nextDouble() * 4).floor()};
  if (r < 0.52) return {'op': 'drop'};
  if (r < 0.56) return {'op': 'soft', 'held': rnd.nextDouble() < 0.5};
  if (r < 0.565) return {'op': 'add'};
  if (r < 0.566) return {'op': 'restart'};
  return {'op': 'update', 'ms': 1 + (rnd.nextDouble() * 420).floor()};
}

void _apply(GameEngine e, Map<String, Object?> a) {
  switch (a['op']) {
    case 'move':
      e.moveActive(a['delta'] as int);
    case 'rotate':
      e.rotateActive(clockwise: a['cw'] as bool);
    case 'turn':
      e.switchSide(a['q'] as int);
    case 'activate':
      e.activateSide(Side.values[a['side'] as int]);
    case 'drop':
      e.dropActive();
    case 'soft':
      e.setSoftDrop(a['held'] as bool);
    case 'add':
      e.addGlass();
    case 'restart':
      e.restart();
    case 'update':
      e.update((a['ms'] as int) / 1000);
  }
}

GameConfig _configFrom(Map<String, Object?> o) => const GameConfig().copyWith(
      glassCount: o['glassCount'] as int?,
      numberOfColors: o['numberOfColors'] as int?,
      activeStepSeconds: (o['activeStepSeconds'] as num?)?.toDouble(),
    );

/// Every default the rules depend on, as text, so that a drifting default on
/// either side fails the test before any trace does. Animation speed exists
/// only in Dart and is checked on its own.
String _configDigest(GameConfig c) => [
      'boardSize=${c.boardSize}',
      'armLength=${c.armLength}',
      'glassCount=${c.glassCount}',
      'pieceLength=${c.pieceLength}',
      'numberOfColors=${c.numberOfColors}',
      'minMatchLength=${c.minMatchLength}',
      'activeStepSeconds=${_micro(c.activeStepSeconds)}',
      'inactiveStepSeconds=${_micro(c.inactiveStepSeconds)}',
      'softDropStepSeconds=${_micro(c.softDropStepSeconds)}',
      'buildSeconds=${_micro(c.buildSeconds)}',
      'initialProgressStagger=${_micro(c.initialProgressStagger)}',
      'spawnColumn=${c.spawnColumn ?? -1}',
      'monoPieceKeepChance=${_micro(c.monoPieceKeepChance)}',
      'settleAfterBoardRotation=${c.settleAfterBoardRotation}',
      'pauseIncomingDuringCascade=${c.pauseIncomingDuringCascade}',
      'gravityScope=${c.gravityScope.name}',
      'crowdedHeadroom=${c.crowdedHeadroom}',
      'dropBaseSeconds=${_micro(c.dropBaseSeconds)}',
      'dropSecondsPerCell=${_micro(c.dropSecondsPerCell)}',
      'matchSeconds=${_micro(c.matchSeconds)}',
      'clearSeconds=${_micro(c.clearSeconds)}',
      'fallBaseSeconds=${_micro(c.fallBaseSeconds)}',
      'fallSecondsPerRootCell=${_micro(c.fallSecondsPerRootCell)}',
      'fallBounceSeconds=${_micro(c.fallBounceSeconds)}',
      'maxQueuedInputs=${c.maxQueuedInputs}',
      'basePoints=${c.scoring.basePoints}',
    ].join(';');

/// One line with everything a player can see or the score depends on.
String _canonical(GameEngine e, List<GameEvent> events) {
  final s = e.state;
  final parts = <String>[
    'ph=${s.phase.name}',
    'a=${s.activeSide.index}',
    'sc=${s.score}',
    'cb=${s.combo}',
    'bc=${s.bestCombo}',
    'mt=${s.matches}',
    'cc=${s.clearedCells}',
    'pp=${s.piecesPlaced}',
    'sl=${s.selfLocked}',
    'sp=${s.speedLevel}',
    'et=${_ms(s.elapsedSeconds)}',
    'pe=${_ms(s.phaseElapsed)}',
    'pd=${_ms(s.phaseDuration)}',
    'go=${s.gameOverSide?.index ?? -1}',
    'bs=${s.buildingSide?.index ?? -1}',
    'mv=${s.moves.length}',
    'am=${s.activeMatch?.cells.length ?? -1}',
    'dr=${s.drop?.startRow ?? -1}',
    'sides=${e.sides.map((side) => side.index).join(',')}',
    'cfg=${_micro(e.config.activeStepSeconds)},${_micro(e.config.inactiveStepSeconds)}',
  ];
  for (final side in Side.values) {
    final p = s.incoming[side];
    if (p == null) continue;
    final colours = p.piece.colors.map((c) => c.index).join();
    parts.add(
      'in${side.index}=$colours'
      'o${p.piece.orientation.index}@${p.column},${p.row},${_micro(p.stepProgress)}',
    );
  }
  parts.add('board=${_board(s.board)}');
  parts.add('ev=${events.map(_event).join(',')}');
  return parts.join('|');
}

String _board(Board b) => [
      for (var row = 0; row < b.size; row++)
        [
          for (var col = 0; col < b.size; col++)
            !b.isInside(row, col) ? '-' : (b.at(row, col)?.index.toString() ?? '.'),
        ].join(),
    ].join('/');

String _event(GameEvent ev) => switch (ev) {
      SideSwitched() => 'sideSwitched',
      PieceMoved(:final direction, :final blocked) => 'pieceMoved:$direction:${blocked ? 1 : 0}',
      PieceRotated(:final blocked) => 'pieceRotated:${blocked ? 1 : 0}',
      PieceStepped() => 'pieceStepped',
      PieceDropped(:final cells) => 'pieceDropped:$cells',
      PieceLanded(:final dropped) => 'pieceLanded:${dropped ? 1 : 0}',
      MatchScored(:final combo, :final score) => 'matchScored:$combo:$score',
      CellsPopped() => 'cellsPopped',
      BlocksFell() => 'blocksFell',
      GlassAdded(:final side) => 'glassAdded:${side.index}',
      SpeedUp(:final level) => 'speedUp:$level',
      GameEnded(:final side) => 'gameEnded:${side.index}',
    };

int _ms(double seconds) => (seconds * 1000).floor();

int _micro(double value) => (value * 1000000).round();

/// FNV-1a, 32 bit. The web test computes the same function.
int _hash(String text) {
  var h = 0x811c9dc5;
  for (final unit in text.codeUnits) {
    h ^= unit;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// mulberry32, as in webapp/src/game/random.ts, on unsigned 32-bit values.
class _Mulberry32 implements math.Random {
  _Mulberry32(this._state);

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
