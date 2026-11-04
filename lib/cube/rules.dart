// The rules of Cube, the 3D mode of RotaThree: webapp/src/cube/rules.ts,
// carried over line by line. Six glasses (arms) along ±x, ±y, ±z share a cube
// of a centre, a stick of three falls down each glass one whole cell per step,
// the steered glass steps fast and the others slowly, a stick that cannot step
// locks, cascades repeat, and a glass whose far end is full when a new stick
// is due ends the game.
//
// The game is played on what the screen shows: the hub seen along the line
// of sight, each cell of the screen showing the nearest block behind it.
// Lines of three or more of a colour pop in that picture, and the cells of
// the glass on top fall down it, each with everything behind it — as in the
// 2D game. The sticks of the four glasses around the screen live in the
// middle layer of the cube and stop on whatever the screen shows. The glasses
// in front of and behind the screen drop their sticks along the line of
// sight, into any layer, and are steered in place; unless `depthFalls`, their
// sticks wait until they are steered. Tipping the hub over shows it from
// another side: what was depth becomes up or across, and the new picture
// settles and pops.
//
// Everything here is in the fixed data frame: cells are integer (x, y, z) in
// an N³ grid, N = centre + 2·arm. Turning the hub only changes which glass is
// on top and which way the eye looks; the view turns the picture. The web is
// the reference: test/cube/cube_parity_test.dart replays its trace.
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import 'random.dart';

const empty = -1;

/// A cell or a direction of the hub, in its fixed data frame.
@immutable
class Vec {
  const Vec(this.x, this.y, this.z);

  /// Each coordinate from [f]; doubles are whole by the time they get here.
  factory Vec.of(num Function(int axis) f) => Vec(f(0).round(), f(1).round(), f(2).round());

  final int x, y, z;

  int operator [](int axis) => axis == 0 ? x : axis == 1 ? y : z;
  Vec operator +(Vec o) => Vec(x + o.x, y + o.y, z + o.z);
  Vec operator -(Vec o) => Vec(x - o.x, y - o.y, z - o.z);
  Vec operator -() => Vec(-x, -y, -z);
  Vec operator *(int k) => Vec(x * k, y * k, z * k);

  Vec cross(Vec o) => Vec(y * o.z - z * o.y, z * o.x - x * o.z, x * o.y - y * o.x);
  int dot(Vec o) => x * o.x + y * o.y + z * o.z;
  bool get isZero => x == 0 && y == 0 && z == 0;

  /// The same with one coordinate changed.
  Vec withAxis(int axis, int value) => Vec(axis == 0 ? value : x, axis == 1 ? value : y, axis == 2 ? value : z);

  /// The axis of a unit axis vector.
  int get axis => x != 0 ? 0 : y != 0 ? 1 : 2;

  List<int> toJson() => [x, y, z];

  @override
  bool operator ==(Object other) => other is Vec && other.x == x && other.y == y && other.z == z;

  @override
  int get hashCode => Object.hash(x, y, z);

  @override
  String toString() => '$x,$y,$z';
}

/// One of the six glasses.
class SideInfo {
  const SideInfo(this.id, this.axis, this.sign, this.label);

  final int id;

  /// 0, 1, 2 for x, y, z.
  final int axis;

  /// Which end of the axis.
  final int sign;

  /// The number of a die: opposite glasses add up to seven.
  final String label;
}

const sides = <SideInfo>[
  SideInfo(0, 1, 1, '1'),
  SideInfo(1, 0, 1, '2'),
  SideInfo(2, 2, -1, '3'),
  SideInfo(3, 2, 1, '4'),
  SideInfo(4, 0, -1, '5'),
  SideInfo(5, 1, -1, '6'),
];

Vec normalOf(int side) => const Vec(0, 0, 0).withAxis(sides[side].axis, sides[side].sign);

int sideOfNormal(Vec n) =>
    sides.indexWhere((s) => n[s.axis] == s.sign && n[(s.axis + 1) % 3] == 0 && n[(s.axis + 2) % 3] == 0);

Vec fallOf(int side) => -normalOf(side);

/// The dot product of a cell's offset from the middle with a direction.
double _dotFrom(Vec p, double middle, Vec dir) =>
    (p.x - middle) * dir.x + (p.y - middle) * dir.y + (p.z - middle) * dir.z;

/// How the falling speeds up with the score: every `everyPoints` the steps
/// get `factor` times as long, down to the floors.
@immutable
class CubeRamp {
  const CubeRamp({required this.everyPoints, required this.factor, required this.minActive, required this.minInactive});

  final double everyPoints, factor, minActive, minInactive;

  Map<String, Object?> toJson() =>
      {'everyPoints': everyPoints, 'factor': factor, 'minActive': minActive, 'minInactive': minInactive};
}

@immutable
class CubeConfig {
  const CubeConfig({
    this.centre = 7,
    this.arm = 8,
    this.pieceLength = 3,
    this.numberOfColors = 4,
    this.minMatchLength = 3,
    this.activeStepSeconds = 1,
    this.inactiveStepSeconds = 3,
    this.softDropStepSeconds = 0.05,
    this.inactiveFalls = true,
    this.depthFalls = false,
    this.depthStepSeconds = 6,
    this.monoPieceKeepChance = 0.4,
    this.pauseIncomingDuringCascade = true,
    this.dropBaseSeconds = 0.06,
    this.dropSecondsPerCell = 0.012,
    this.matchSeconds = 0.22,
    this.clearSeconds = 0.2,
    this.fallBaseSeconds = 0.09,
    this.fallSecondsPerRootCell = 0.1,
    this.fallBounceSeconds = 0.08,
    this.basePoints = 100,
    this.maxQueuedInputs = 8,
    this.ramp,
    this.seed,
  });

  /// Side of the shared centre cube, and the cross-section of every arm.
  /// Odd or even: an even cube has two layers in the middle, and the sticks
  /// across the screen fall in the nearer of them (`layer`).
  final int centre;

  /// Length of each arm, in cells. A glass is one arm plus the centre.
  final int arm;
  final int pieceLength;
  final int numberOfColors;
  final int minMatchLength;
  final double activeStepSeconds;
  final double inactiveStepSeconds;

  /// While soft drop is held, the steered stick steps this often.
  final double softDropStepSeconds;

  /// Sticks in the five other glasses step too (slowly) — the 2D rule.
  final bool inactiveFalls;

  /// …including the glasses in front of and behind the screen, more slowly
  /// still. Off: those sticks wait until they are steered.
  final bool depthFalls;
  final double depthStepSeconds;
  final double monoPieceKeepChance;
  final bool pauseIncomingDuringCascade;
  final double dropBaseSeconds;
  final double dropSecondsPerCell;
  final double matchSeconds;
  final double clearSeconds;
  final double fallBaseSeconds;
  final double fallSecondsPerRootCell;
  final double fallBounceSeconds;
  final int basePoints;
  final int maxQueuedInputs;
  final CubeRamp? ramp;
  final int? seed;

  CubeConfig copyWith({
    int? centre,
    int? arm,
    int? numberOfColors,
    double? activeStepSeconds,
    double? inactiveStepSeconds,
    bool? inactiveFalls,
    bool? depthFalls,
    CubeRamp? ramp,
    bool noRamp = false,
    int? seed,
  }) =>
      CubeConfig(
        centre: centre ?? this.centre,
        arm: arm ?? this.arm,
        pieceLength: pieceLength,
        numberOfColors: numberOfColors ?? this.numberOfColors,
        minMatchLength: minMatchLength,
        activeStepSeconds: activeStepSeconds ?? this.activeStepSeconds,
        inactiveStepSeconds: inactiveStepSeconds ?? this.inactiveStepSeconds,
        softDropStepSeconds: softDropStepSeconds,
        inactiveFalls: inactiveFalls ?? this.inactiveFalls,
        depthFalls: depthFalls ?? this.depthFalls,
        depthStepSeconds: depthStepSeconds,
        monoPieceKeepChance: monoPieceKeepChance,
        pauseIncomingDuringCascade: pauseIncomingDuringCascade,
        dropBaseSeconds: dropBaseSeconds,
        dropSecondsPerCell: dropSecondsPerCell,
        matchSeconds: matchSeconds,
        clearSeconds: clearSeconds,
        fallBaseSeconds: fallBaseSeconds,
        fallSecondsPerRootCell: fallSecondsPerRootCell,
        fallBounceSeconds: fallBounceSeconds,
        basePoints: basePoints,
        maxQueuedInputs: maxQueuedInputs,
        ramp: noRamp ? null : ramp ?? this.ramp,
        seed: seed ?? this.seed,
      );
}

/// The settled blocks of the whole hub.
class Hub {
  Hub(this.centre, this.arm)
      : size = centre + 2 * arm,
        cells = _emptyCells(centre + 2 * arm);

  Hub._copy(Hub other)
      : centre = other.centre,
        arm = other.arm,
        size = other.size,
        cells = Int8List.fromList(other.cells);

  final int centre;
  final int arm;
  final int size;
  final Int8List cells;

  static Int8List _emptyCells(int size) {
    final count = size * size * size;
    return Int8List(count)..fillRange(0, count, empty);
  }

  /// Grows with every write, so that what is worked out from the hub can
  /// tell when it is out of date.
  int version = 0;

  int index(Vec p) => (p.x * size + p.y) * size + p.z;

  Vec cellOf(int index) => Vec(index ~/ (size * size), (index ~/ size) % size, index % size);

  bool inBand(int v) => v >= arm && v < arm + centre;

  /// Whether the cell is in the centre or in one of the six arms.
  bool isInside(Vec p) {
    var outside = 0;
    for (final v in [p.x, p.y, p.z]) {
      if (v < 0 || v >= size) return false;
      if (!inBand(v)) outside++;
    }
    return outside <= 1;
  }

  int at(Vec p) => cells[index(p)];

  void set(Vec p, int color) {
    cells[index(p)] = color;
    version++;
  }

  // --- One glass: its arm plus the centre. Row 0 is the far end of the arm,
  // the last row the floor (the far wall of the centre); lanes (a, b) run
  // across it along the other two axes, in increasing axis order.

  int depth() => arm + centre;

  (int, int) crossAxes(int side) {
    final k = sides[side].axis;
    final others = [0, 1, 2].where((i) => i != k).toList();
    return (others[0], others[1]);
  }

  Vec toWorld(int side, int row, int a, int b) {
    final SideInfo(:axis, :sign) = sides[side];
    final (k1, k2) = crossAxes(side);
    final coords = [0, 0, 0];
    coords[axis] = sign > 0 ? size - 1 - row : row;
    coords[k1] = arm + a;
    coords[k2] = arm + b;
    return Vec(coords[0], coords[1], coords[2]);
  }

  /// (row, a, b) of a cell in the glass of `side`, or null outside it.
  ({int row, int a, int b})? fromWorld(int side, Vec p) {
    final SideInfo(:axis, :sign) = sides[side];
    final (k1, k2) = crossAxes(side);
    if (!inBand(p[k1]) || !inBand(p[k2])) return null;
    final row = sign > 0 ? size - 1 - p[axis] : p[axis];
    if (row < 0 || row >= depth()) return null;
    return (row: row, a: p[k1] - arm, b: p[k2] - arm);
  }

  bool inGlass(int side, Vec p) {
    for (final v in [p.x, p.y, p.z]) {
      if (v < 0 || v >= size) return false;
    }
    return fromWorld(side, p) != null;
  }

  Hub clone() => Hub._copy(this);

  void forEachBlock(void Function(Vec p, int color, int index) visit) {
    for (var i = 0; i < cells.length; i++) {
      if (cells[i] != empty) visit(cellOf(i), cells[i], i);
    }
  }
}

/// A stick in flight: its middle square sits at `pivot`, square i at
/// pivot + (i − 1)·dir. `dir` is a unit axis vector; turning the stick turns
/// `dir`, so the colour order never changes.
class Stick {
  Stick({required this.side, required this.colors, required this.pivot, required this.dir, this.progress = 0});

  final int side;
  final List<int> colors;
  Vec pivot;
  Vec dir;

  /// How far the wait for its next step has got, 0..1.
  double progress;

  Stick copy({Vec? pivot}) => Stick(side: side, colors: colors, pivot: pivot ?? this.pivot, dir: dir, progress: progress);
}

@immutable
class StickCell {
  const StickCell(this.p, this.color);
  final Vec p;
  final int color;
}

List<StickCell> pieceCells(List<int> colors, Vec pivot, Vec dir) => [
      for (var i = 0; i < colors.length; i++) StickCell(pivot + dir * (i - colors.length ~/ 2), colors[i]),
    ];

List<StickCell> cellsOf(Stick piece) => pieceCells(piece.colors, piece.pivot, piece.dir);

/// Data directions of the screen's right and up.
@immutable
class ViewFrame {
  const ViewFrame(this.right, this.up);
  final Vec right;
  final Vec up;

  @override
  bool operator ==(Object other) => other is ViewFrame && other.right == right && other.up == up;

  @override
  int get hashCode => Object.hash(right, up);
}

class Run {
  Run(this.color, this.cells, this.across);
  final int color;

  /// Hub indices of the cells.
  final List<int> cells;
  final bool across;
}

class Match {
  Match(this.runs, this.cells);
  final List<Run> runs;
  final Set<int> cells;
}

class BlockMove {
  BlockMove(this.from, this.to, this.color, this.distance);
  final Vec from, to;
  final int color;
  final double distance;
}

enum CubePhase { playing, dropping, matching, clearing, settling, gameOver }

sealed class CubeEvent {
  const CubeEvent();
}

class Switched extends CubeEvent {
  const Switched(this.from, this.to);
  final int from, to;
}

class Moved extends CubeEvent {
  const Moved(this.blocked);
  final bool blocked;
}

class Rotated extends CubeEvent {
  const Rotated(this.blocked);
  final bool blocked;
}

class Stepped extends CubeEvent {
  const Stepped(this.side);
  final int side;
}

class Dropped extends CubeEvent {
  const Dropped(this.side, this.cells);
  final int side, cells;
}

class Landed extends CubeEvent {
  const Landed(this.side, this.cells, this.dropped);
  final int side;
  final List<StickCell> cells;
  final bool dropped;
}

class Matched extends CubeEvent {
  const Matched(this.combo, this.score, this.match);
  final int combo, score;
  final Match match;
}

class Popped extends CubeEvent {
  const Popped(this.cells);
  final List<StickCell> cells;
}

class Fell extends CubeEvent {
  const Fell(this.moves);
  final List<BlockMove> moves;
}

class SpeedUp extends CubeEvent {
  const SpeedUp(this.level);
  final int level;
}

class GameEnded extends CubeEvent {
  const GameEnded(this.side);
  final int side;
}

sealed class _Input {
  const _Input();
}

class _Turn extends _Input {
  const _Turn(this.down, this.plane, this.viewFrame, this.settle);
  final int down;
  final Vec plane;
  final ViewFrame viewFrame;
  final bool settle;
}

class _Control extends _Input {
  const _Control(this.side);
  final int side;
}

class _Move extends _Input {
  const _Move(this.vector);
  final Vec vector;
}

class _Rotate extends _Input {
  const _Rotate(this.axis);
  final Vec axis;
}

class _Drop extends _Input {
  const _Drop();
}

/// What tipping the hub over would give (`previewTurn`).
class TurnPreview {
  TurnPreview(this.view, this.match, this.rounds, this.popped);
  final CubeGame view;
  final Match match;
  final int rounds;
  final int popped;
}

/// A hard-dropped stick on its way down: where it will lie, where it was,
/// and how many cells it falls.
class DropInFlight {
  DropInFlight(this.piece, this.from, this.cells);
  final Stick piece;
  final Vec from;
  final int cells;
}

class CubeGame {
  CubeGame([CubeConfig config = const CubeConfig()])
      : config = config,
        seed = config.seed ?? math.Random().nextInt(0xffffffff),
        hub = Hub(config.centre, config.arm),
        _baseActive = config.activeStepSeconds,
        _baseInactive = config.inactiveStepSeconds {
    random = Mulberry32(seed);
    for (final s in sides) {
      next[s.id] = roll();
    }
    for (final s in sides) {
      spawn(s.id);
    }
  }

  /// The same hub seen from another side (`lookFrom`): no sticks of its own,
  /// nothing drawn from a random generator.
  CubeGame._view(this.config, this.hub, this.plane, this.viewFrame, this.active)
      : seed = 0,
        _baseActive = config.activeStepSeconds,
        _baseInactive = config.inactiveStepSeconds {
    random = Mulberry32(0);
  }

  CubeConfig config;
  final int seed;
  late math.Random random;
  Hub hub;

  /// The glass on top of the screen: its fall is "down".
  int down = 0;

  /// The glass whose stick the player steers and that steps fast: the one
  /// on top, or the one in front of or behind the screen.
  int active = 0;

  /// The data direction towards the eye.
  Vec plane = const Vec(0, 0, 1);
  ViewFrame viewFrame = const ViewFrame(Vec(1, 0, 0), Vec(0, 1, 0));
  Map<int, Stick> pieces = {};

  /// The stick each glass gets next, as each glass of the flat game has its
  /// own.
  final Map<int, List<int>> next = {};
  CubePhase phase = CubePhase.playing;
  double phaseElapsed = 0;
  double phaseDuration = 0;
  int score = 0;
  int combo = 0;
  int bestCombo = 0;
  int placed = 0;
  int matches = 0;
  int cleared = 0;

  /// Seconds of play, not counting a pause.
  double seconds = 0;
  int speedLevel = 0;
  bool softDrop = false;

  /// The tutorial's sticks hold still: they move only when moved.
  bool stepsHeld = false;
  DropInFlight? drop;
  Match? activeMatch;
  List<BlockMove> moves = [];
  List<int> awaiting = [];
  final List<_Input> _inputs = [];
  final List<CubeEvent> events = [];
  int? gameOverSide;
  final double _baseActive;
  final double _baseInactive;

  Stick? get activePiece => pieces[active];

  bool get isGameOver => phase == CubePhase.gameOver;

  /// Inputs waiting for the board to come to rest.
  int get queuedInputs => _inputs.length;

  /// The events since the last call, oldest first.
  List<CubeEvent> drainEvents() {
    final drained = List<CubeEvent>.of(events);
    events.clear();
    return drained;
  }

  /// Index of the middle of the hub along any axis: a half for an even
  /// hub, whose screen cells then sit at halves from the middle (±0.5,
  /// ±1.5, …).
  double get middle => (hub.size - 1) / 2;

  /// From the middle of the centre to the middle of its outer cells: 3 for
  /// a centre of 7, 4.5 for one of 10.
  double get half => (config.centre - 1) / 2;

  /// The depth of the layer the sticks across the screen fall in: the
  /// middle one, or of an even cube's two middle ones the nearer.
  double get layer => hub.size % 2 == 1 ? 0 : 0.5;

  /// The index of the sticks' layer along the axis looked along.
  ({int axis, int index}) _layerIndex() {
    final axis = plane.axis;
    return (axis: axis, index: (middle + layer * plane[axis]).round());
  }

  /// Whether the glass lies across the screen (top, left, right, bottom)
  /// rather than along the line of sight.
  bool inPlane(int side) => normalOf(side).dot(plane) == 0;

  // ------------------------------------------------------- what is seen

  /// The cell of the screen a data cell is seen in: across and up from the
  /// middle of the hub.
  (double, double) screenOf(Vec p) => (_dotFrom(p, middle, viewFrame.right), _dotFrom(p, middle, viewFrame.up));

  /// The depth of a cell, in layers from the middle one: + towards the eye.
  double depthOf(Vec p) => _dotFrom(p, middle, plane);

  /// The data cell seen at screen cell (`sx`, `sy`) at depth `d`.
  Vec cellAt(double sx, double sy, double d) {
    final ViewFrame(:right, :up) = viewFrame;
    return Vec.of((i) => middle + sx * right[i] + sy * up[i] + d * plane[i]);
  }

  /// The blocks seen at a screen cell, nearest first.
  List<Vec> stackAt(double sx, double sy) {
    final stack = <Vec>[];
    for (var d = middle; d >= -middle; d--) {
      final p = cellAt(sx, sy, d);
      if (hub.isInside(p) && hub.at(p) != empty) stack.add(p);
    }
    return stack;
  }

  /// The block the screen shows at a screen cell, or null.
  Vec? seenAt(double sx, double sy) {
    for (var d = middle; d >= -middle; d--) {
      final p = cellAt(sx, sy, d);
      if (hub.isInside(p) && hub.at(p) != empty) return p;
    }
    return null;
  }

  /// Whether nothing at all is seen where `p` is, at any depth.
  bool clearOnScreen(Vec p) {
    final (sx, sy) = screenOf(p);
    return seenAt(sx, sy) == null;
  }

  /// Whether a stick of `side` may cover `p`: inside its glass and, for a
  /// glass across the screen, where the screen shows nothing — sticks there
  /// stop on what is seen, whatever its depth.
  bool isFree(int side, Vec p) {
    if (!hub.inGlass(side, p)) return false;
    return inPlane(side) ? clearOnScreen(p) : hub.at(p) == empty;
  }

  /// Lines of `minMatchLength`+ of one colour in the picture on the screen,
  /// across or up it — the 2D rule on what is seen. A line pops the blocks
  /// that are seen, and shows what was behind them.
  Match findMatches() {
    final reach = middle;
    final min = config.minMatchLength;
    final seen = <(double, double), ({int index, int color})?>{};
    ({int index, int color})? at(double sx, double sy) => seen.putIfAbsent((sx, sy), () {
          final p = seenAt(sx, sy);
          return p == null ? null : (index: hub.index(p), color: hub.at(p));
        });
    final runs = <Run>[];
    for (final across in [true, false]) {
      for (var line = -reach; line <= reach; line++) {
        ({int index, int color})? cell(double k) => across ? at(k, line) : at(line, k);
        var start = -reach;
        while (start <= reach) {
          final first = cell(start);
          var end = start + 1;
          if (first != null) {
            while (end <= reach && cell(end)?.color == first.color) {
              end++;
            }
            if (end - start >= min) {
              final cells = <int>[for (var k = start; k < end; k++) cell(k)!.index];
              runs.add(Run(first.color, cells, across));
            }
          }
          start = end;
        }
      }
    }
    return Match(runs, {for (final run in runs) ...run.cells});
  }

  /// Gravity of the 2D game on the picture: in the glass on top, every cell
  /// of the screen that shows something falls down it to the next one that
  /// does, taking everything behind it along. Blocks in the other glasses
  /// never move. Mutates the hub and returns what moved.
  List<BlockMove> settle() {
    final half = this.half;
    final moves = <BlockMove>[];
    for (var sx = -half; sx <= half; sx++) {
      var target = -half;
      for (var sy = -half; sy <= middle; sy++) {
        final stack = stackAt(sx, sy);
        if (stack.isEmpty) continue;
        if (sy != target) {
          for (final from in stack) {
            final color = hub.at(from);
            final to = from + viewFrame.up * (target - sy).round();
            hub.set(from, empty);
            hub.set(to, color);
            moves.add(BlockMove(from, to, color, sy - target));
          }
        }
        target++;
      }
    }
    return moves;
  }

  // --------------------------------------------------------------- sticks

  List<int> roll() {
    final palette = config.numberOfColors;
    int pick(int count) => (random.nextDouble() * count).floor();
    final colors = <int>[for (var i = 0; i < config.pieceLength; i++) pick(palette)];
    if (colors.every((c) => c == colors[0]) && random.nextDouble() >= config.monoPieceKeepChance) {
      final others = <int>[for (var c = 0; c < palette; c++) if (c != colors[0]) c];
      colors[pick(colors.length)] = others[pick(others.length)];
    }
    return colors;
  }

  /// The stick the glass gets after the one in it now.
  List<int> nextOf(int side) => next[side] ?? const [];

  bool fits(int side, Vec pivot, Vec dir) =>
      pieceCells(const [0, 0, 0], pivot, dir).every((c) => isFree(side, c.p));

  /// Whether a stick of `side` may be at `pivot`/`dir`: free cells, and for
  /// a glass across the screen, flat in the middle layer.
  bool allowed(int side, Vec pivot, Vec dir) {
    if (inPlane(side) && (dir.dot(plane) != 0 || depthOf(pivot) != layer)) return false;
    return fits(side, pivot, dir);
  }

  /// A new stick lies across its glass along the screen's right, or along
  /// its up when right is the way the glass falls.
  Vec spawnDir(int side) {
    final n = normalOf(side);
    return viewFrame.right.dot(n) == 0 ? viewFrame.right : viewFrame.up;
  }

  /// Where a new stick of `side` appears: the far end of its glass, in the
  /// middle of it — so in the middle layer, for the glasses across the screen.
  Vec spawnPivot(int side) {
    final lane = config.centre ~/ 2;
    var pivot = hub.toWorld(side, 0, lane, lane);
    if (inPlane(side)) {
      final (:axis, :index) = _layerIndex();
      pivot = pivot.withAxis(axis, index);
    }
    return pivot;
  }

  /// Puts a new stick at the far end of the glass. False when it does not
  /// fit there — the game is over.
  bool spawn(int side) {
    final colors = next[side] ?? roll();
    next[side] = roll();
    final dir = spawnDir(side);
    final pivot = spawnPivot(side);
    if (!allowed(side, pivot, dir)) return false;
    pieces[side] = Stick(side: side, colors: colors, pivot: pivot, dir: dir);
    return true;
  }

  Vec restRow(Stick piece) {
    final fall = fallOf(piece.side);
    var pivot = piece.pivot;
    while (fits(piece.side, pivot + fall, piece.dir)) {
      pivot = pivot + fall;
    }
    return pivot;
  }

  /// Where the stick of `side` would land: its cells, or null.
  List<StickCell>? ghost([int? side]) {
    final piece = pieces[side ?? active];
    if (piece == null) return null;
    return pieceCells(piece.colors, restRow(piece), piece.dir);
  }

  /// For a stick in front or behind: the layer it would land in, and for
  /// each square whether it would be seen there or hidden behind blocks.
  ({double layer, List<bool> seen, int count})? landing([int? side]) {
    final cells = ghost(side);
    if (cells == null) return null;
    final seen = [
      for (final c in cells)
        () {
          final (sx, sy) = screenOf(c.p);
          final front = seenAt(sx, sy);
          return front == null || depthOf(front) < depthOf(c.p);
        }(),
    ];
    return (layer: depthOf(cells[0].p), seen: seen, count: seen.where((s) => s).length);
  }

  /// The same hub seen from another side: a view that can be settled and
  /// searched without touching the game. Works on a copy of the hub unless
  /// one is given.
  CubeGame lookFrom(Vec plane, ViewFrame viewFrame, [Hub? hub]) =>
      CubeGame._view(config, hub ?? this.hub.clone(), plane, viewFrame, active);

  /// What tipping the hub over to look along `plane` would give: the
  /// settled picture with the sticks in flight on it, what pops in it first,
  /// and how many blocks the whole cascade would pop in how many rounds.
  TurnPreview previewTurn(Vec plane, ViewFrame viewFrame) {
    final view = lookFrom(plane, viewFrame);
    view.settle();
    final settled = lookFrom(plane, viewFrame, view.hub.clone());
    // The sticks in flight, laid on the new side as the tip would lay them;
    // the glass on top is the one steered then.
    settled.pieces = {for (final MapEntry(:key, :value) in pieces.entries) key: value.copy()};
    settled.active = sideOfNormal(viewFrame.up);
    settled.reseat((plane: this.plane, viewFrame: this.viewFrame));
    final first = view.findMatches();
    var match = first;
    var rounds = 0;
    var popped = 0;
    while (match.runs.isNotEmpty) {
      rounds++;
      popped += match.cells.length;
      for (final i in match.cells) {
        view.hub.set(view.hub.cellOf(i), empty);
      }
      view.settle();
      match = view.findMatches();
    }
    return TurnPreview(settled, first, rounds, popped);
  }

  // --------------------------------------------------------------- input

  void _submit(_Input input) {
    if (isGameOver) return;
    if (phase == CubePhase.playing) {
      _apply(input);
      return;
    }
    // Hard drops are never buffered; everything else is replayed after. A
    // turn always is, or the picture and the rules would disagree.
    if (input is _Drop) return;
    if (input is _Turn || _inputs.length < config.maxQueuedInputs) _inputs.add(input);
  }

  void move(Vec vector) => _submit(_Move(vector));

  /// Quarter turn of the stick around its middle square, about `axis`.
  void rotate(Vec axis) => _submit(_Rotate(axis));

  void dropActive() => _submit(const _Drop());

  /// The hub has been turned: `down` is the glass now on top, and the one
  /// the player steers. After tipping it over (`settle`) the new picture
  /// settles and pops.
  void turn(int down, Vec plane, ViewFrame viewFrame, bool settle) => _submit(_Turn(down, plane, viewFrame, settle));

  /// Steers the stick of another glass without turning anything.
  void control(int side) => _submit(_Control(side));

  void _apply(_Input input) {
    final piece = activePiece;
    switch (input) {
      case _Turn(:final down, :final plane, :final viewFrame, :final settle):
        final from = active;
        this.down = down;
        active = down;
        final previous = (plane: this.plane, viewFrame: this.viewFrame);
        this.plane = plane;
        this.viewFrame = viewFrame;
        reseat(previous);
        events.add(Switched(from, down));
        if (settle) _resolve();
      case _Control(:final side):
        if (side != active) {
          final from = active;
          active = side;
          events.add(Switched(from, side));
        }
      case _Move(:final vector):
        if (piece == null) return;
        final to = piece.pivot + vector;
        final ok = vector.dot(normalOf(piece.side)) == 0 && allowed(piece.side, to, piece.dir);
        if (ok) piece.pivot = to;
        events.add(Moved(!ok));
      case _Rotate(:final axis):
        if (piece == null) return;
        final dir = axis.cross(piece.dir);
        if (dir.isZero) {
          events.add(const Rotated(true));
          return;
        }
        // Nudges tried when the turn does not fit, gentlest first: across the
        // glass, back towards its far end, down. A stick of a glass across the
        // screen is only nudged within the screen (`allowed`).
        final n = normalOf(piece.side);
        final (k1, k2) = hub.crossAxes(piece.side);
        final across = [for (final k in [k1, k2]) const Vec(0, 0, 0).withAxis(k, 1)];
        final kicks = <Vec>[const Vec(0, 0, 0)];
        for (final step in [1, 2]) {
          for (final e in across) {
            kicks
              ..add(e * -step)
              ..add(e * step);
          }
          kicks
            ..add(n * step)
            ..add(n * -step);
        }
        for (final kick in kicks) {
          final pivot = piece.pivot + kick;
          if (allowed(piece.side, pivot, dir)) {
            piece.pivot = pivot;
            piece.dir = dir;
            events.add(const Rotated(false));
            return;
          }
        }
        events.add(const Rotated(true));
      case _Drop():
        _beginDrop();
    }
  }

  /// After tipping the hub over some sticks in flight point at the eye or
  /// have left the middle layer. Each is laid flat again — in the middle
  /// layer for a glass across the screen, across the line of sight for the
  /// one in front or behind — and backs off towards its far end if it no
  /// longer fits; failing that it starts again from there.
  ///
  /// After a tip, a glass that lies across the screen both before and after
  /// it (on its axis) keeps its stick where the screen showed it, lying the
  /// same way on the screen, so that it need not turn at all. A turn in the
  /// screen moves no stick: each goes round with its glass, as in 2D.
  /// `previous` is the plane and frame looked along before.
  void reseat([({Vec plane, ViewFrame viewFrame})? previous]) {
    final k = plane.axis;
    final middle = this.middle;
    final tipped = previous != null && previous.plane.dot(plane) == 0;
    for (final piece in pieces.values) {
      final n = normalOf(piece.side);
      var dir = piece.dir;
      var pivot = piece.pivot;
      if (tipped && inPlane(piece.side) && n.dot(previous.plane) == 0) {
        final ViewFrame(:right, :up) = previous.viewFrame;
        final sx = _dotFrom(pivot, middle, right), sy = _dotFrom(pivot, middle, up);
        final dx = dir.dot(right), dy = dir.dot(up);
        final now = viewFrame;
        pivot = Vec.of((i) => middle + sx * now.right[i] + sy * now.up[i] + layer * plane[i]);
        dir = Vec.of((i) => dx * now.right[i] + dy * now.up[i]);
      } else if (inPlane(piece.side)) {
        if (dir.dot(plane) != 0) dir = n.cross(plane);
        pivot = pivot.withAxis(k, _layerIndex().index);
      } else if (dir.dot(n) != 0) {
        dir = viewFrame.up;
      }
      var at = pivot;
      while (hub.inGlass(piece.side, at) && !allowed(piece.side, at, dir)) {
        at = at + n;
      }
      if (allowed(piece.side, at, dir)) {
        piece.pivot = at;
        piece.dir = dir;
        continue;
      }
      final start = spawnPivot(piece.side);
      final flat = spawnDir(piece.side);
      if (allowed(piece.side, start, flat)) {
        piece.pivot = start;
        piece.dir = flat;
        piece.progress = 0;
      }
    }
  }

  void _flushInputs() {
    while (_inputs.isNotEmpty && phase == CubePhase.playing) {
      _apply(_inputs.removeAt(0));
    }
  }

  // ---------------------------------------------------------------- time

  double stepSeconds(Stick piece) {
    if (piece.side == active) {
      // Soft drop only speeds up actual falling: a stick that has landed
      // keeps its full step to be slid or turned before it locks.
      final falling = softDrop && fits(piece.side, piece.pivot + fallOf(piece.side), piece.dir);
      return falling ? math.min(config.softDropStepSeconds, config.activeStepSeconds) : config.activeStepSeconds;
    }
    return inPlane(piece.side) ? config.inactiveStepSeconds : config.depthStepSeconds;
  }

  /// Whether a stick nobody steers falls by itself.
  bool fallsAlone(Stick piece) {
    if (piece.side == active) return true;
    if (!config.inactiveFalls) return false;
    return inPlane(piece.side) || config.depthFalls;
  }

  void _advancePieces(double seconds) {
    if (stepsHeld) return;
    for (final piece in pieces.values) {
      if (!fallsAlone(piece)) continue;
      piece.progress = math.min(1, piece.progress + seconds / stepSeconds(piece));
    }
  }

  void update(double seconds) {
    if (isGameOver || seconds <= 0) return;
    this.seconds += seconds;
    if (phase == CubePhase.playing) {
      _advancePieces(seconds);
      _stepDuePieces();
      return;
    }
    if (!config.pauseIncomingDuringCascade) _advancePieces(seconds);
    phaseElapsed += seconds;
    if (phaseElapsed >= phaseDuration) _completePhase();
  }

  /// Every due stick steps one cell; the first that cannot locks, and the
  /// others wait until the board is at rest again.
  void _stepDuePieces() {
    final order = [active, for (final s in sides) if (s.id != active) s.id];
    for (final side in order) {
      final piece = pieces[side];
      if (piece == null || piece.progress < 1) continue;
      final to = piece.pivot + fallOf(side);
      if (fits(side, to, piece.dir)) {
        piece.pivot = to;
        piece.progress = 0;
        events.add(Stepped(side));
        continue;
      }
      pieces.remove(side);
      _commit(piece, false);
      return;
    }
  }

  void _beginDrop() {
    final piece = activePiece;
    if (piece == null) return;
    final rest = restRow(piece);
    final cells = (rest - piece.pivot).dot(fallOf(piece.side)).abs();
    pieces.remove(piece.side);
    drop = DropInFlight(piece.copy(pivot: rest), piece.pivot, cells);
    events.add(Dropped(piece.side, cells));
    _enterPhase(CubePhase.dropping, config.dropBaseSeconds + config.dropSecondsPerCell * cells);
  }

  void _commit(Stick piece, bool dropped) {
    for (final c in cellsOf(piece)) {
      hub.set(c.p, c.color);
    }
    placed++;
    combo = 0;
    awaiting.add(piece.side);
    events.add(Landed(piece.side, cellsOf(piece), dropped));
    if (!_makeRoom()) return;
    _checkMatches();
  }

  /// Sticks pass through each other while falling, so a block that has
  /// just appeared may cover one; it backs off towards its own far end.
  /// False when one has nowhere to go: game over.
  bool _makeRoom() {
    for (final piece in pieces.values) {
      final back = normalOf(piece.side);
      var pivot = piece.pivot;
      while (!allowed(piece.side, pivot, piece.dir)) {
        pivot = pivot + back;
        if (!hub.inGlass(piece.side, pivot)) {
          _endGame(piece.side);
          return false;
        }
      }
      piece.pivot = pivot;
    }
    return true;
  }

  /// Lets the picture settle, then pops what lines up (a tipped hub).
  void _resolve() {
    final moves = settle();
    if (moves.isNotEmpty) {
      _startFalling(moves);
    } else {
      _checkMatches();
    }
  }

  void _startFalling(List<BlockMove> moves) {
    this.moves = moves;
    final far = moves.fold<double>(0, (m, move) => math.max(m, move.distance));
    events.add(Fell(moves));
    _enterPhase(CubePhase.settling, config.fallBaseSeconds + config.fallSecondsPerRootCell * math.sqrt(far) + config.fallBounceSeconds);
    _makeRoom();
  }

  void _checkMatches() {
    final match = findMatches();
    if (match.runs.isEmpty) {
      _finishResolution();
      return;
    }
    combo++;
    bestCombo = math.max(bestCombo, combo);
    final score = match.runs.fold<int>(
      0,
      (sum, run) => sum + config.basePoints * (run.cells.length - config.minMatchLength + 1) * combo,
    );
    this.score += score;
    matches += match.runs.length;
    cleared += match.cells.length;
    activeMatch = match;
    events.add(Matched(combo, score, match));
    _applyRamp();
    _enterPhase(CubePhase.matching, config.matchSeconds);
  }

  /// Steps the speed up when the score has passed another multiple of the
  /// ramp's interval.
  void _applyRamp() {
    final ramp = config.ramp;
    if (ramp == null) return;
    final level = (score / ramp.everyPoints).floor();
    if (level == speedLevel) return;
    speedLevel = level;
    final factor = math.pow(ramp.factor, level).toDouble();
    config = config.copyWith(
      activeStepSeconds: math.max(ramp.minActive, _baseActive * factor),
      inactiveStepSeconds: math.max(ramp.minInactive, _baseInactive * factor),
    );
    events.add(SpeedUp(level));
  }

  void _completePhase() {
    switch (phase) {
      case CubePhase.dropping:
        final piece = drop!.piece;
        drop = null;
        _commit(piece, true);
      case CubePhase.matching:
        _enterPhase(CubePhase.clearing, config.clearSeconds);
      case CubePhase.clearing:
        final match = activeMatch!;
        events.add(Popped([for (final i in match.cells) StickCell(hub.cellOf(i), hub.cells[i])]));
        for (final i in match.cells) {
          hub.set(hub.cellOf(i), empty);
        }
        activeMatch = null;
        // What was behind the popped blocks is seen now; the picture falls.
        final moves = settle();
        if (moves.isEmpty) {
          _checkMatches();
        } else {
          _startFalling(moves);
        }
      case CubePhase.settling:
        moves = [];
        if (!isGameOver) _checkMatches();
      case CubePhase.playing:
      case CubePhase.gameOver:
        break;
    }
  }

  void _finishResolution() {
    combo = 0;
    _enterPhase(CubePhase.playing, 0);
    final waiting = awaiting;
    awaiting = [];
    for (final side in waiting) {
      if (!spawn(side)) {
        _endGame(side);
        return;
      }
    }
    _flushInputs();
  }

  void _enterPhase(CubePhase phase, double duration) {
    this.phase = phase;
    phaseElapsed = 0;
    phaseDuration = duration;
  }

  // ---------------------------------------------------------- keeping

  /// The game as it can be kept, while it is at rest between moves; null
  /// in the middle of a drop or a cascade, or once it is over.
  Map<String, Object?>? snapshot() {
    if (phase != CubePhase.playing || _inputs.isNotEmpty) return null;
    final blocks = <int>[];
    hub.forEachBlock((_, color, index) => blocks
      ..add(index)
      ..add(color));
    return {
      'centre': config.centre,
      'arm': config.arm,
      'numberOfColors': config.numberOfColors,
      'depthFalls': config.depthFalls,
      'ramp': config.ramp?.toJson(),
      'blocks': blocks,
      'down': down,
      'active': active,
      'plane': plane.toJson(),
      'viewFrame': {'right': viewFrame.right.toJson(), 'up': viewFrame.up.toJson()},
      'pieces': [
        for (final p in pieces.values)
          {'side': p.side, 'colors': [...p.colors], 'pivot': p.pivot.toJson(), 'dir': p.dir.toJson(), 'progress': p.progress},
      ],
      'next': [
        for (final MapEntry(:key, :value) in next.entries) [key, [...value]],
      ],
      'score': score,
      'bestCombo': bestCombo,
      'placed': placed,
      'matches': matches,
      'cleared': cleared,
      'seconds': seconds,
    };
  }

  /// A game kept by `snapshot`, checked piece by piece: throws on anything
  /// that does not make a game.
  static CubeGame restore(Object? raw) {
    final r = _record(raw);
    final rampRaw = r['ramp'] == null ? null : _record(r['ramp']);
    final ramp = rampRaw == null
        ? null
        : CubeRamp(
            everyPoints: _number(rampRaw['everyPoints'], 1, 1e9),
            factor: _number(rampRaw['factor'], 0.1, 1),
            minActive: _number(rampRaw['minActive'], 0.01, 10),
            minInactive: _number(rampRaw['minInactive'], 0.01, 30),
          );
    final depthFalls = r['depthFalls'];
    if (depthFalls is! bool) throw const FormatException('Invalid game save');
    final game = CubeGame(CubeConfig(
      centre: _integer(r['centre'], 3, 15),
      arm: _integer(r['arm'], 2, 16),
      numberOfColors: _integer(r['numberOfColors'], 2, 9),
      depthFalls: depthFalls,
      ramp: ramp,
    ));
    final hub = game.hub;
    final colours = game.config.numberOfColors;
    Vec axis(Object? raw) {
      final v = _list(raw, 3).map((c) => _integer(c, -1, 1)).toList();
      if (v.length != 3 || v.fold<int>(0, (sum, c) => sum + c.abs()) != 1) throw const FormatException('Invalid saved axis');
      return Vec(v[0], v[1], v[2]);
    }

    List<int> stick(Object? raw) {
      final colors = _list(raw, game.config.pieceLength).map((c) => _integer(c, 0, colours - 1)).toList();
      if (colors.length != game.config.pieceLength) throw const FormatException('Invalid saved stick');
      return colors;
    }

    final blocks = _list(r['blocks'], 2 * hub.cells.length);
    hub.cells.fillRange(0, hub.cells.length, empty);
    for (var i = 0; i + 1 < blocks.length; i += 2) {
      final index = _integer(blocks[i], 0, hub.cells.length - 1);
      if (!hub.isInside(hub.cellOf(index))) throw const FormatException('Invalid saved block');
      hub.cells[index] = _integer(blocks[i + 1], 0, colours - 1);
    }
    hub.version++;
    final frame = _record(r['viewFrame']);
    game.plane = axis(r['plane']);
    game.viewFrame = ViewFrame(axis(frame['right']), axis(frame['up']));
    final ViewFrame(:right, :up) = game.viewFrame;
    if (game.plane.dot(right) != 0 || game.plane.dot(up) != 0 || right.dot(up) != 0) {
      throw const FormatException('Invalid saved view');
    }
    game.down = sideOfNormal(up);
    game.active = _integer(r['active'], 0, sides.length - 1);
    if (_integer(r['down'], 0, sides.length - 1) != game.down) throw const FormatException('Invalid saved view');
    game.pieces.clear();
    for (final raw in _list(r['pieces'], sides.length)) {
      final p = _record(raw);
      final side = _integer(p['side'], 0, sides.length - 1);
      final pivot = _list(p['pivot'], 3).map((c) => _integer(c, 0, hub.size - 1)).toList();
      if (pivot.length != 3) throw const FormatException('Invalid saved stick');
      final piece = Stick(
        side: side,
        colors: stick(p['colors']),
        pivot: Vec(pivot[0], pivot[1], pivot[2]),
        dir: axis(p['dir']),
        progress: _number(p['progress'], 0, 1),
      );
      if (game.pieces.containsKey(side) || !game.allowed(side, piece.pivot, piece.dir)) {
        throw const FormatException('Invalid saved stick');
      }
      game.pieces[side] = piece;
    }
    for (final raw in _list(r['next'], sides.length)) {
      final pair = _list(raw, 2);
      if (pair.length != 2) throw const FormatException('Invalid saved stick');
      game.next[_integer(pair[0], 0, sides.length - 1)] = stick(pair[1]);
    }
    game.score = _integer(r['score']);
    game.bestCombo = _integer(r['bestCombo']);
    game.placed = _integer(r['placed']);
    game.matches = _integer(r['matches']);
    game.cleared = _integer(r['cleared']);
    game.seconds = _number(r['seconds']);
    game._applyRamp();
    game.events.clear();
    return game;
  }

  void _endGame(int side) {
    gameOverSide = side;
    _inputs.clear();
    _enterPhase(CubePhase.gameOver, 0);
    events.add(GameEnded(side));
  }
}

Map<String, Object?> _record(Object? raw) {
  if (raw is! Map) throw const FormatException('Invalid game save');
  return Map<String, Object?>.from(raw);
}

double _number(Object? raw, [double min = 0, double max = 1e12]) {
  if (raw is! num || !raw.isFinite || raw < min || raw > max) throw const FormatException('Invalid saved number');
  return raw.toDouble();
}

int _integer(Object? raw, [num min = 0, num max = 1e12]) {
  final value = _number(raw, min.toDouble(), max.toDouble());
  if (value != value.roundToDouble()) throw const FormatException('Invalid saved integer');
  return value.toInt();
}

List<Object?> _list(Object? raw, [int max = 1000]) {
  if (raw is! List || raw.length > max) throw const FormatException('Invalid saved list');
  return List<Object?>.from(raw);
}
