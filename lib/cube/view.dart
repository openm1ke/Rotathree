// The picture of Cube: webapp/src/cube/view.ts, carried over. The screen
// shows the cross as the flat game does, and the game is played on that
// picture: each cell shows the nearest block behind it, lines of what is seen
// pop, and what is seen falls (rules.dart). The third dimension shows in the
// sticks of the glasses in front of and behind the screen, which fly along
// the line of sight; as the hub leaning over like a tower of blocks when it
// is tipped; and in the open while the volume is looked into. A tip can be
// looked at before it is made, and while paused, or once the game is over,
// the hub can be turned any way.
//
// This class keeps the turns and works out, frame by frame, what is drawn
// where in the scene; painter.dart projects it on the canvas.
import 'dart:math' as math;
import 'dart:ui';

import 'math3d.dart';
import 'rules.dart';

/// What the picture shows besides the game itself (settings).
class CubeLook {
  const CubeLook({
    this.depthSticks = false,
    this.behind = true,
    this.edges = false,
    this.numbers = false,
    this.lane = true,
    this.nextPiece = true,
    this.depthHint = true,
    this.volumeEdges = true,
    this.xray = true,
    this.grid = true,
  });

  /// The sticks in front and behind that are not being steered.
  final bool depthSticks;

  /// A mark in a corner of a cell with the colour of the block behind it.
  final bool behind;

  /// The edges of the hub's glasses.
  final bool edges;

  /// The glasses' numbers.
  final bool numbers;

  /// The aiming lane under the stick on top.
  final bool lane;

  /// The stick each glass gets next, beyond the far end of its arm.
  final bool nextPiece;

  /// Faint lines round the cross where the hub's depth would show, were it
  /// drawn in perspective: a reminder that the cross is a cube.
  final bool depthHint;

  /// The glasses' edges while the hub is open.
  final bool volumeEdges;

  /// In the open, a stick hidden behind blocks shows through them.
  final bool xray;

  /// The faint lines between the cells of the cross.
  final bool grid;
}

/// Which way the hub is turned to be looked at, while paused.
enum LookAxis { upright, across, sight }

/// The glass the player steers, as the screen shows it.
enum Steering { top, front, back }

/// Tipping the hub over takes a little longer than turning the cross.
const tiltSecondsDefault = 0.65;

/// How far the hub turns to be looked into: from above or below, from the
/// right or the left.
const _peekPitch = 0.45;
const _peekYaw = 0.55;

/// Depth is squashed this flat when the picture is the game: the nearest
/// block of every cell still wins, but nothing looks deeper than another.
const flat = 0.02;

/// How much of a cell a block fills: the 2D sprite is a rounded tile with a
/// narrow gap round it.
const tile = 0.96;

/// How far beyond the far end of an arm the box of its next stick is.
const _nextGap = 1.6;

/// The eye's distance the depth hint is drawn from, in reaches of an arm:
/// farther than the camera, so that the hint stays short of the boxes.
const _hintDistance = 6.0;

/// The box of a next stick: three squares and a margin.
const _nextBox = (3.5, 1.5, 0.2);
const _nextEdge = Color(0xFFEEF6FF);

/// How bright the edges of the glasses are when the hub is looked at in the
/// open.
const _edgeOpacity = 0.24;

/// How much a stick hidden behind blocks shows through them while the hub
/// is open.
const _xrayStrength = 0.5;

/// The small marks in the corners of cells.
const _mark = 0.3;
V3 _corner(double x, double y) => V3(0.27 * x, 0.27 * y, 0.5);

const _white = Color(0xFFFFFFFF);

/// Accent of the active glass.
const accent = Color(0xFF78CDFF);

/// The mark of a square that would hide: a dark hole.
const _hole = Color(0xFF05050A);

/// A block drawn: where (in the scene), turned how, how big, and how it looks.
class CubeSolid {
  CubeSolid(this.at, this.turn, this.size, this.color, this.brightness, this.flash, this.alpha);
  final V3 at;
  final Q turn;
  final double size;
  final int color;
  final double brightness, flash, alpha;
  double depth = 0;
}

/// An outline or a see-through box: the landing spot, the aiming lane, the
/// sticks in front and behind, the boxes of the next sticks.
class CubeClear {
  CubeClear(this.at, this.turn, this.size, this.color, this.alpha, this.fill, this.edge);
  final V3 at;
  final Q turn;
  final (double, double, double) size;
  final Color color;
  final double alpha, fill, edge;
  double depth = 0;
}

/// Thin lines of one colour: pairs of points in the scene.
class CubeLines {
  CubeLines(this.points, this.color, this.opacity, this.width);
  final List<V3> points;
  final Color color;
  final double opacity, width;
}

/// A faint flat pane of the cross: four corners in the scene.
class CubePane {
  CubePane(this.corners, this.opacity);
  final List<V3> corners;
  final double opacity;
}

/// A glass's number beside a corner of its rim.
class CubeLabel {
  CubeLabel(this.at, this.text, this.opacity);
  final V3 at;
  final String text;
  final double opacity;
}

class _Item {
  _Item(this.at, this.lift, this.nudge, this.spin, this.frame);
  V3 at;
  final double lift;
  final V3? nudge;
  final Q? spin;
  final Q? frame;
}

class _TileItem extends _Item {
  _TileItem(super.at, super.lift, super.nudge, super.spin, super.frame, this.size, this.color, this.brightness, this.flash, this.alpha);
  final double size;
  final int color;
  final double brightness, flash, alpha;
}

class _ClearItem extends _Item {
  _ClearItem(super.at, super.lift, super.nudge, super.spin, super.frame, this.size, this.color, this.alpha, this.fill, this.edge);
  final (double, double, double) size;
  final Color color;
  final double alpha, fill, edge;
}

/// Where a falling stick is drawn, kept while its stick is the same one:
/// `base` is the way it lay when first seen, `aim` the turn that takes `base`
/// to the way it lies now, `spin` the turn drawn, easing towards `aim`. `from`
/// is where a tip found it, to carry it from there.
class _StickView {
  _StickView(this.colors, this.at, this.base, this.dir);
  final List<int> colors;
  final V3 at;
  final V3 base;
  final V3 dir;
  final Q aim = Q();
  final Q spin = Q();
  ({V3 at, Q turn, V3 dir})? from;
}

class _DrawnStick {
  _DrawnStick(this.piece, this.at, this.spin, this.base);
  final Stick piece;
  final V3 at;
  final Q spin;
  final V3 base;
}

class _Preview {
  _Preview(this.up, this.q);
  final bool up;
  final Q q;
  int version = -1;
  TurnPreview? result;
}

/// Draws a game of Cube and turns the player's intentions into its moves:
/// which way is left on the screen, which glass is on top, what the hub looks
/// like as it tips. The screen owns the game loop and calls `frame` once per
/// animation frame, then paints what it built.
class CubeView {
  CubeView(this.game)
      : n = game.config.centre + 2 * game.config.arm,
        h = game.config.centre / 2,
        reach = game.config.centre / 2 + game.config.arm {
    halfHub = n / 2;
    // Far away and narrow, so that the cross looks flat.
    distance = 4.2 * reach;
    _buildCross();
    _buildHub();
    _alignToGame();
  }

  CubeGame game;
  CubeLook look = const CubeLook();

  /// How long the cross takes to turn in the screen; 0 turns it at once.
  double turnSeconds = 0.36;

  /// How long the hub takes to lean over; 0 tips it at once.
  double tiltSeconds = tiltSecondsDefault;

  /// Paused: the sticks in front and behind all show.
  bool paused = false;

  /// The volume is being looked into; from where: +1 above / right, −1
  /// below / left.
  bool peeking = false;
  int peekPitch = 1;
  int peekYaw = 1;

  final int n;
  late final double halfHub;
  final double h;
  final double reach;
  late final double distance;

  /// The camera: its vertical field of view (degrees) and aspect, set by
  /// `resize`; near and far as the web's.
  double fov = 30;
  double aspect = 1;
  double get near => 1;
  double get far => distance * 3;

  /// How far the projection has gone from flat (orthographic) to perspective.
  double opened = 0;

  /// How much of the depth is shown: FLAT while playing, 1 mid-tip and while
  /// the volume is looked into.
  double depthShown = flat;

  /// Where the hub is turned to; the picture eases towards it. Always a
  /// whole number of quarter turns, so data axes map onto scene axes.
  final Q _targetQ = Q();
  final Q _turnFrom = Q();
  final Q _turned = Q();

  /// The hub's frame as the tip began, with the look into the volume: what
  /// the sticks that stay put are drawn in meanwhile.
  final Q _tiltFrom = Q();

  /// The hub as drawn: the look into the volume, then the turn.
  final Q hubQ = Q();

  // The turn under way: `tilt` when it leans the hub over rather than
  // turning the cross in the screen.
  double _t = 1;
  bool _tilt = false;
  bool _carry = false;
  int _steeredFrom = 0;

  /// A turn in the screen, as an angle: the quarters pressed, plus what was
  /// left of a turn it cut short, in the way they were pressed. A turn of
  /// half the circle or more has no shortest way round, and must not pick
  /// one; null for a turn that is not only in the screen.
  double? _spin;

  /// How far round the cross was laid as the turn began.
  double _crossFrom = 0;

  /// The cross's turn in the screen (crossGroup.rotation.z).
  double crossTurn = 0;

  /// 0 when the picture is the game, 1 while the volume is looked into.
  double _peek = 0;

  /// 0 to 1: the edges of the glasses show while the volume is looked into,
  /// or the hub is turned to be looked at, whatever the setting says.
  double _edgesShown = 0;

  /// How much the cross shows: less while the hub is open.
  double crossShown = 1;

  /// The look into the volume alone, without the hub's own turn: what the
  /// boxes of the next sticks turn with.
  final Q _peekTurn = Q();
  final Q _peekFrom = Q();
  final Q _peekTo = Q();
  double _xrayOpacity = 0;

  /// Turned to be looked at, while paused or once the game is over.
  Q? _inspect;

  /// A tip looked at before it is made.
  _Preview? _preview;

  final Map<int, _StickView> _pieceViews = {};

  /// Cells that have just landed flash white for a moment.
  final Map<int, double> _flashes = {};
  double _clock = 0;

  /// Time of the picture, for the blinking of what would pop.
  double _wall = 0;
  String _behindKey = '';
  List<({V3 at, int color})> _behindMarks = [];
  String _linesKey = '';
  Set<int> _linesCells = {};
  int _linesRuns = 0;

  /// The canvas size, to fit the cross to it again when the boxes of the
  /// next sticks come or go.
  ({double width, double height, bool withNext, bool withHint}) _size =
      (width: 0, height: 0, withNext: false, withHint: false);

  // The pieces of the cross, in its own frame, turned by `crossTurn`.
  final List<List<V3>> _armOutlines = [];
  final List<List<V3>> _cellGrids = [];
  final List<V3> _centreGrid = [];
  final List<V3> _centreOutline = [];
  final List<CubePane> _crossPanes = [];

  // The hub's edges, in its frame, and the depth hint laid flat.
  final List<List<V3>> _hubEdges = [];
  final List<V3> _hint = [];
  final List<V3> _labelPoints = [];

  // What the frame draws.
  final List<_TileItem> _solid = [];
  final List<_TileItem> _xray = [];
  final List<_TileItem> _fading = [];
  final List<_ClearItem> _clear = [];

  /// Blocks drawn this frame, opaque, then those drawn see-through, far to
  /// near; sticks seen through what hides them; outlines, far to near.
  List<CubeSolid> solids = [];
  List<CubeSolid> fadingSolids = [];
  List<CubeSolid> xrays = [];
  double xrayOpacity = 0;
  List<CubeClear> clears = [];
  List<CubeLines> lines = [];
  List<CubeLines> hubLines = [];
  List<CubePane> panes = [];
  List<CubeLabel> labels = [];

  /// The hub turned as the game looks at it: a new game straight on, a kept
  /// one as it was left.
  void _alignToGame() {
    final ViewFrame(:right, :up) = game.viewFrame;
    _targetQ.setFromColumns(V3.ofVec(right), V3.ofVec(up), V3.ofVec(game.plane)).invert();
    for (final q in [_turnFrom, _turned, _tiltFrom]) {
      q.copy(_targetQ);
    }
  }

  // ------------------------------------------------------------ the scene

  /// The cross of the flat game: a faint fill and grid for each arm and for
  /// the centre, outlines a little brighter, the glass on top in the accent.
  /// It turns with the hub in the screen, as the flat game's field turns, and
  /// is laid back when the turn is over: a quarter turn leaves it as it was.
  /// It fades while the hub opens up.
  void _buildCross() {
    final centre = game.config.centre, arm = game.config.arm;
    const z = -0.5;
    for (var quarter = 0; quarter < 4; quarter++) {
      // Drawn for the arm on top, then turned a quarter at a time.
      final turn = Q().setFromAxisAngle(sceneToward, -quarter * math.pi / 2);
      V3 p(double x, double y) => V3(x, y, z).applyQuaternion(turn);
      _crossPanes.add(CubePane([p(-h, h), p(h, h), p(h, reach), p(-h, reach)], 0.022));
      final grid = <V3>[];
      for (var i = 1; i < centre; i++) {
        grid.addAll([p(-h + i, h), p(-h + i, reach)]);
      }
      for (var j = 1; j < arm; j++) {
        grid.addAll([p(-h, h + j), p(h, h + j)]);
      }
      _cellGrids.add(grid);
      _armOutlines.add([p(-h, h), p(-h, reach), p(-h, reach), p(h, reach), p(h, reach), p(h, h)]);
    }
    _crossPanes.add(CubePane([V3(-h, -h, z), V3(h, -h, z), V3(h, h, z), V3(-h, h, z)], 0.05));
    for (var i = 1; i < centre; i++) {
      _centreGrid.addAll([V3(-h + i, -h, z), V3(-h + i, h, z), V3(-h, -h + i, z), V3(h, -h + i, z)]);
    }
    _centreOutline.addAll([
      V3(-h, -h, z), V3(h, -h, z), V3(h, -h, z), V3(h, h, z), //
      V3(h, h, z), V3(-h, h, z), V3(-h, h, z), V3(-h, -h, z),
    ]);
  }

  /// The hub itself: the edges of all six glasses and of the centre cube,
  /// thin, and the glasses' numbers beside a corner of each rim. The same
  /// edges drawn once in perspective, from the eye's distance, and laid flat
  /// on the screen, are `look.depthHint`.
  void _buildHub() {
    final arm = game.config.arm;
    V3 armPoint(int side, double t, double a, double b) {
      final s = sides[side];
      final others = [0, 1, 2].where((i) => i != s.axis).toList();
      final p = [0.0, 0.0, 0.0];
      p[s.axis] = s.sign * (h + t);
      p[others[0]] = a;
      p[others[1]] = b;
      return V3(p[0], p[1], p[2]);
    }

    final corners = [(-h, -h), (h, -h), (h, h), (-h, h)];
    final all = <V3>[];
    for (final s in sides) {
      final p = <V3>[];
      for (var i = 0; i < 4; i++) {
        final (a, b) = corners[i];
        final (na, nb) = corners[(i + 1) % 4];
        p.addAll([armPoint(s.id, 0, a, b), armPoint(s.id, arm.toDouble(), a, b)]);
        p.addAll([armPoint(s.id, arm.toDouble(), a, b), armPoint(s.id, arm.toDouble(), na, nb)]);
      }
      all.addAll(p);
      _hubEdges.add(p);
    }
    final p = <V3>[];
    for (final a in [-h, h]) {
      for (final b in [-h, h]) {
        p.addAll([V3(-h, a, b), V3(h, a, b), V3(a, -h, b), V3(a, h, b), V3(a, b, -h), V3(a, b, h)]);
      }
    }
    all.addAll(p);
    _hubEdges.add(p);
    final eye = _hintDistance * reach;
    for (final v in all) {
      final s = eye / (eye - v.z);
      _hint.add(V3(v.x * s, v.y * s, -0.5));
    }
    for (final s in sides) {
      _labelPoints.add(armPoint(s.id, arm - 0.2, h + 0.75, h + 0.75));
    }
  }

  /// Centre of a data cell in the hub's own frame.
  V3 _local(Vec p) => V3(p.x + 0.5 - halfHub, p.y + 0.5 - halfHub, p.z + 0.5 - halfHub);

  /// `at` is in the hub's frame. `lift` moves a cube towards the eye (or
  /// away) while the picture is flat: the sticks in front of and behind the
  /// screen are drawn over and under it. `nudge` shifts it on the screen, for
  /// the small marks in the corners of cells.
  void _pushSolid(
    V3 at,
    int color, {
    double brightness = 1,
    double flash = 0,
    double size = tile,
    double lift = 0,
    V3? nudge,
    Q? spin,
    Q? frame,
    double alpha = 1,
    bool seeThrough = false,
  }) {
    if (alpha <= 0.01) return;
    final item = _TileItem(at.clone(), lift, nudge, spin, frame, size, color, brightness, flash, alpha);
    (alpha < 0.99 ? _fading : _solid).add(item);
    // A stick, seen through what hides it while the hub is open.
    if (seeThrough && alpha >= 0.99 && _xrayOpacity > 0.01) {
      _xray.add(_TileItem(at.clone(), lift, nudge, spin, frame, size, color, brightness, flash, alpha));
    }
  }

  void _pushClear(
    V3 at,
    Color color,
    double alpha,
    double fill,
    double edge, {
    (double, double, double) size = (0.91, 0.91, 0.91),
    double lift = 0,
    V3? nudge,
    Q? spin,
    Q? frame,
  }) {
    _clear.add(_ClearItem(at.clone(), lift, nudge, spin, frame, size, color, alpha, fill, edge));
  }

  /// Where a cube of the hub's frame is drawn in the scene.
  V3 _place(_Item item) {
    final at = item.at.applyQuaternion(item.frame ?? hubQ);
    at.z = at.z * depthShown + item.lift * (1 - depthShown);
    if (item.nudge != null) at.add(item.nudge!);
    return at;
  }

  /// How a cube is turned on the screen: with the hub (or the frame it is
  /// drawn in), and then by its own turn, if it is a stick turning.
  Q _turnOf(_Item item) {
    final frame = item.frame ?? hubQ;
    return item.spin != null ? frame.clone().multiply(item.spin!) : frame.clone();
  }

  V3 get _eye => V3(0, 0, distance);

  void _flushLayers() {
    final eye = _eye;
    CubeSolid solid(_TileItem item, {bool placed = false}) {
      final at = placed ? item.at : _place(item);
      return CubeSolid(at, _turnOf(item), item.size, item.color, item.brightness, item.flash, item.alpha)
        ..depth = at.distanceToSq(eye);
    }

    solids = [for (final item in _solid) solid(item)];
    xrays = [for (final item in _xray) solid(item)];
    xrayOpacity = _xrayOpacity;
    fadingSolids = [for (final item in _fading) solid(item)]..sort((a, b) => b.depth.compareTo(a.depth));
    clears = [
      for (final item in _clear)
        () {
          final at = _place(item);
          return CubeClear(at, _turnOf(item), item.size, item.color, item.alpha, item.fill, item.edge)..depth = at.distanceToSq(eye);
        }(),
    ]..sort((a, b) => b.depth.compareTo(a.depth));
    _solid.clear();
    _xray.clear();
    _fading.clear();
    _clear.clear();
  }

  /// The canvas is `width` × `height` logical pixels. The whole cross fits,
  /// whichever side is short.
  void resize(double width, double height) {
    if (width <= 0 || height <= 0) return;
    _size = (width: width, height: height, withNext: look.nextPiece, withHint: look.depthHint);
    _fit();
  }

  /// The camera takes in the whole cross, and the boxes of the next sticks
  /// beyond its arms when they show.
  void _fit() {
    final (:width, :height, :withNext, :withHint) = _size;
    aspect = width / height;
    // The depth hint reaches a little past the arms' ends: their near faces.
    final eye = _hintDistance * reach;
    final hinted = withHint ? (reach * eye) / (eye - h) - reach + 0.2 : 0.0;
    final half = reach + math.max(withNext ? _nextGap + _nextBox.$2 / 2 + 0.4 : 0.6, hinted);
    final tan = half / (distance - h) / math.min(1, aspect);
    fov = 2 * math.atan(tan) * 180 / math.pi;
  }

  /// Shows another game of the same size from scratch, as a new game lies:
  /// the tutorial's lessons.
  void reset(CubeGame game) {
    this.game = game;
    _alignToGame();
    _t = 1;
    _tilt = false;
    _carry = false;
    _steeredFrom = game.active;
    _preview = null;
    _inspect = null;
    _pieceViews.clear();
    _flashes.clear();
    _behindKey = '';
    _linesKey = '';
  }

  // ------------------------------------------------------------ the turns

  /// A scene direction in the data frame, once the turn under way is over.
  Vec _toData(V3 v) => dataIn(_targetQ, v);

  /// A data direction in the scene, once the turn under way is over.
  V3 _toScene(Vec d) => V3.ofVec(d).applyQuaternion(_targetQ).round();

  /// The game's hub seen from the side a turn `q` faces the eye, on the
  /// same blocks (read only).
  CubeGame _viewAt(Q q) =>
      game.lookFrom(dataIn(q, sceneToward), ViewFrame(dataIn(q, sceneRight), dataIn(q, sceneUp)), game.hub);

  /// Where the turn under way ends.
  Q _goalQ() => _preview?.q ?? _inspect ?? _targetQ;

  /// A tip of the game (or its preview) under way: the rules lay the sticks
  /// on the new side, and those on its axis stay put on the screen.
  bool _carrying() => _t < 1 && _carry;

  /// The hub leans over: the game holds still meanwhile.
  bool get tilting => _t < 1 && _tilt;

  /// Shows the hub turning, as one body. Tipped over — or turned to be
  /// looked at about anything but the line of sight — it leans like a tower
  /// of blocks and opens up into depth on the way, flattening again as it
  /// lands. Turned in the screen it stays flat, as the 2D cross turns.
  /// `steered`: the glass steered on the side the turn starts from.
  void _transition(V3? axis, {bool carry = false, int? steered, int quarters = 0}) {
    // A turn in the screen goes on from where one cut short has got to, and
    // the rest of that one is added to it.
    final going = _t < 1;
    final left = going && _spin != null ? _spin! * (1 - ease(_t)) : 0.0;
    _crossFrom = crossTurn;
    _spin = identical(axis, sceneToward) && (!going || _spin != null) ? left + quarters * math.pi / 2 : null;
    _turnFrom.copy(_turned);
    _t = 0;
    _tilt = !identical(axis, sceneToward);
    _carry = carry && _tilt;
    _steeredFrom = steered ?? game.active;
    // Where each stick is and how it lies on the screen as a tip begins, to
    // carry it from there (`stickViews`).
    for (final view in _pieceViews.values) {
      if (!_carry) {
        view.from = null;
        continue;
      }
      final onScreen = _turnFrom.clone().multiply(view.spin);
      view.from = (at: view.at.clone(), turn: onScreen, dir: view.base.clone().applyQuaternion(onScreen));
    }
  }

  /// Whether the flat picture shows the stick of `side` with the hub turned
  /// by `q` and `steered` the glass steered: always for a glass across the
  /// screen; in front or behind only when steered, or asked for, or paused.
  bool _shownFlat(int side, Q q, int steered) {
    final across = V3.ofVec(normalOf(side)).applyQuaternion(q).z.abs() < 0.5;
    return across || side == steered || look.depthSticks || paused;
  }

  /// The glasses that lie across the screen both before and after a tip (on
  /// its axis): their sticks stay where the screen shows them rather than
  /// turn with the hub, and the rules lay them there on the new side too.
  bool _staysPut(int side, Q from, Q to) {
    final before = V3.ofVec(normalOf(side)).applyQuaternion(from);
    final after = V3.ofVec(normalOf(side)).applyQuaternion(to);
    return before.z.abs() < 0.5 && after.z.abs() < 0.5 && before.dot(after) > 0.5;
  }

  /// Once a tip that carried the sticks has landed, the views of those that
  /// stayed put are moved into the hub's new frame, where they show the
  /// same: the rules have laid them just there.
  void _landCarried() {
    final to = _goalQ();
    final shift = to.clone().invert().multiply(_turnFrom);
    for (final MapEntry(key: side, value: view) in _pieceViews.entries) {
      view.from = null;
      if (!_staysPut(side, _turnFrom, to)) {
        // Already where it lies; the same turn, as the views keep it.
        view.spin.copy(view.aim);
        continue;
      }
      view.at.applyQuaternion(shift);
      view.dir.applyQuaternion(shift).round();
      view.aim.premultiply(shift);
      view.spin.premultiply(shift);
    }
  }

  /// Turns the hub a quarter turn about a scene axis: about the line of
  /// sight as the 2D cross turns, or about the screen's horizontal, so that
  /// the glass behind or in front comes over the top and the new picture
  /// settles and pops. The glass on top is steered. `shown`: a preview has
  /// already shown it, settled.
  void _turnHub(V3 axis, int quarters, {bool shown = false}) {
    final to = quarterTurned(axis, quarters, _targetQ);
    if (!shown) _transition(axis, carry: true, quarters: quarters);
    _targetQ.copy(to);
    final tipped = !identical(axis, sceneToward);
    game.turn(
      sideOfNormal(_toData(sceneUp)),
      _toData(sceneToward),
      ViewFrame(_toData(sceneRight), _toData(sceneUp)),
      tipped,
    );
    // The preview showed the blocks where they come to rest: no fall again.
    if (shown && game.phase == CubePhase.settling) game.phaseElapsed = game.phaseDuration;
  }

  // ------------------------------------------------------------ the player

  /// The glass steered, as the screen shows it.
  Steering get steering {
    final z = _toScene(normalOf(game.active)).z;
    return z > 0 ? Steering.front : z < 0 ? Steering.back : Steering.top;
  }

  /// Where a glass is on the screen now.
  String placeOf(int side) {
    final at = _toScene(normalOf(side));
    return at.z > 0 ? 'front' : at.z < 0 ? 'back' : at.y > 0 ? 'top' : at.y < 0 ? 'bottom' : at.x > 0 ? 'right' : 'left';
  }

  /// What the tip held would give: how many blocks would pop in how many
  /// rounds. Null while none is held.
  ({bool up, int popped, int rounds})? get tipPreview {
    final result = _preview?.result;
    return result == null ? null : (up: _preview!.up, popped: result.popped, rounds: result.rounds);
  }

  /// Turned to be looked at: how many lines show from there.
  ({int runs, int blocks})? get inspecting {
    if (_inspect == null) return null;
    _inspectLines();
    return (runs: _linesRuns, blocks: _linesCells.length);
  }

  /// Left or right on the screen.
  void move(int direction) => game.move(_toData(sceneRight.clone().scale(direction.toDouble())));

  /// Up or down on the screen: for a stick in front or behind.
  void shift(int direction) {
    if (steering == Steering.top) return;
    game.move(_toData(sceneUp.clone().scale(direction.toDouble())));
  }

  /// A quarter turn of the stick in the screen.
  void rotate(bool clockwise) => game.rotate(_toData(clockwise ? sceneToward.clone().negate() : sceneToward));

  void drop() => game.dropActive();

  void softDrop(bool held) => game.softDrop = held;

  /// The cross turns in the screen like the hands of a clock: −1 clockwise,
  /// +1 counterclockwise. Nothing falls.
  void turnCross(int quarters) {
    if (_preview != null || _inspect != null) return;
    _turnHub(sceneToward, quarters);
  }

  /// Steers the stick in front or behind; the same again goes back to the
  /// glass on top. `cycle`: top, front, back, top.
  void steer(String which) {
    if (_preview != null || _inspect != null) return;
    final front = sideOfNormal(_toData(sceneToward));
    final back = sideOfNormal(_toData(sceneToward.clone().negate()));
    final top = sideOfNormal(_toData(sceneUp));
    final now = steering;
    final next = which == 'cycle'
        ? now == Steering.top ? front : now == Steering.front ? back : top
        : which == 'front'
            ? now == Steering.front ? top : front
            : now == Steering.back ? top : back;
    game.control(next);
  }

  /// Starts showing how the hub would lie with the glass behind (`up`) or in
  /// front tipped over the top; the other way while one is shown puts it
  /// back. Letting go (`commitTip`) tips it.
  void startTip(bool up) {
    if (_inspect != null || game.isGameOver) return;
    if (_preview != null) {
      if (_preview!.up != up) cancelTip();
      return;
    }
    _preview = _Preview(up, quarterTurned(sceneRight, up ? 1 : -1, _targetQ));
    _refreshPreview();
    _transition(sceneRight, carry: true);
  }

  /// True when the hub was tipped.
  bool commitTip(bool up) {
    if (_preview?.up != up) return false;
    _preview = null;
    _turnHub(sceneRight, up ? 1 : -1, shown: true);
    return true;
  }

  void cancelTip() {
    if (_preview == null) return;
    // From the preview's side, where its top glass was the one steered.
    _transition(sceneRight, carry: true, steered: _preview!.result?.view.active ?? game.active);
    _preview = null;
  }

  /// Works the preview out again when the board has changed under it.
  void _refreshPreview() {
    final preview = _preview;
    if (preview == null || preview.version == game.hub.version) return;
    preview.version = game.hub.version;
    final q = preview.q;
    preview.result = game.previewTurn(dataIn(q, sceneToward), ViewFrame(dataIn(q, sceneRight), dataIn(q, sceneUp)));
  }

  /// While paused, or once the game is over, the hub can be turned any way
  /// to be looked at: about the screen's upright, its horizontal or the line
  /// of sight. Nothing in the game changes; `endInspect` brings it back.
  void inspectTurn(LookAxis axis, int quarters) {
    cancelTip();
    final from = _inspect ?? _targetQ;
    final about = switch (axis) { LookAxis.upright => sceneUp, LookAxis.across => sceneRight, LookAxis.sight => sceneToward };
    final to = quarterTurned(about, quarters, from);
    _transition(about, quarters: quarters);
    _inspect = to;
  }

  void endInspect() {
    if (_inspect == null) return;
    _transition(null);
    _inspect = null;
  }

  // ------------------------------------------------------------ the frame

  /// Advances the picture by `dt` seconds, and the game too unless `play`
  /// is false (paused, hidden) or the hub is leaning over. Returns what the
  /// game did, for the sounds and the readout.
  List<CubeEvent> frame(double dt, bool play) {
    _wall += dt;
    if (play && !tilting) {
      _clock += dt;
      game.update(dt);
    }
    final events = game.drainEvents();
    for (final event in events) {
      if (event is Landed) {
        for (final c in event.cells) {
          _flashes[game.hub.index(c.p)] = _clock;
        }
      }
    }
    if (_t < 1) {
      final seconds = _tilt ? tiltSeconds : turnSeconds;
      _t = seconds > 0 ? math.min(1, _t + dt / seconds) : 1;
      if (_t >= 1 && _carry) _landCarried();
    }
    _refreshPreview();
    final goal = _goalQ();
    // In the screen, round the way it was pressed; any other turn by the
    // shortest way.
    if (_t < 1 && _spin != null) {
      _turned.setFromAxisAngle(sceneToward, _spin! * ease(_t)).multiply(_turnFrom);
    } else if (_t < 1) {
      _turned.slerpQuaternions(_turnFrom, goal, ease(_t));
    } else {
      _turned.copy(goal);
    }
    _peek += ((peeking ? 1 : 0) - _peek) * (1 - math.exp(-dt * 10));
    _peekTo.setFromEuler(_peekPitch * peekPitch, -_peekYaw * peekYaw, 0);
    _peekFrom.slerp(_peekTo, 1 - math.exp(-dt * 8));
    final peeked = ease(_peek);
    _peekTurn.slerpQuaternions(Q(), _peekFrom, peeked);
    hubQ.copy(_peekTurn).multiply(_turned);
    _tiltFrom.slerpQuaternions(Q(), _peekFrom, peeked).multiply(_turnFrom);
    // Depth opens while the volume is looked into and half-way through a
    // tip: the cross of the screen fades meanwhile.
    opened = math.max(_peek, tilting ? math.sin(math.pi * _t) : 0);
    depthShown = flat + (1 - flat) * opened;
    crossShown = math.pow(1 - opened, 2).toDouble();
    // Turned in the screen, the cross goes round with the hub, by the same
    // angle; laid back once at rest, where a quarter turn leaves it as it was.
    // A tip that cut such a turn short lays the cross back on its way.
    crossTurn = _t >= 1
        ? 0
        : _spin != null
            ? _crossFrom + _spin! * ease(_t)
            : _crossFrom * (1 - ease(_t));
    if ((look.nextPiece != _size.withNext || look.depthHint != _size.withHint) && _size.width > 0) {
      _size = (width: _size.width, height: _size.height, withNext: look.nextPiece, withHint: look.depthHint);
      _fit();
    }
    _xrayOpacity = look.xray ? _xrayStrength * opened : 0;
    // The edges of the hub show the glasses' bounds whenever the hub is
    // looked at in the open; while playing on the flat picture, only when
    // asked for. They come and go slowly, and stay while the hub turns.
    final volumeEdges = look.volumeEdges;
    _edgesShown += ((volumeEdges && (peeking || _inspect != null) ? 1 : 0) - _edgesShown) * (1 - math.exp(-dt * 4));
    final open = _edgeOpacity * math.max(ease(_edgesShown), volumeEdges ? opened : 0);
    final edges = math.max(look.edges ? 0.08 + 0.16 * opened : 0.0, open);
    _buildLines(edges);
    _buildBlocks(dt);
    return events;
  }

  /// The cross, the hub's edges, the depth hint and the numbers, for this
  /// frame.
  void _buildLines(double edges) {
    final shown = crossShown;
    final crossQ = Q().setFromAxisAngle(sceneToward, crossTurn);
    List<V3> turned(List<V3> points, Q q) => [for (final p in points) p.clone().applyQuaternion(q)];
    lines = [];
    panes = [for (final pane in _crossPanes) CubePane(turned(pane.corners, crossQ), pane.opacity * shown)];
    if (look.grid) {
      for (final grid in _cellGrids) {
        lines.add(CubeLines(turned(grid, crossQ), _white, 0.045 * shown, 1));
      }
      lines.add(CubeLines(turned(_centreGrid, crossQ), _white, 0.07 * shown, 1));
    }
    lines.add(CubeLines(turned(_centreOutline, crossQ), _white, 0.22 * shown, 1.5));
    // The glass on top has its outline in the accent; as the cross turns,
    // the outline going from the top loses it and the one coming gains it.
    for (var quarter = 0; quarter < 4; quarter++) {
      final up = math.pow(math.max(0, math.cos(crossTurn - quarter * math.pi / 2)), 6).toDouble();
      final color = Color.lerp(_white, accent, up)!;
      lines.add(CubeLines(turned(_armOutlines[quarter], crossQ), color, (0.16 + (0.6 - 0.16) * up) * shown, 1.5));
    }
    if (look.depthHint) lines.add(CubeLines(turned(_hint, crossQ), _white, 0.1 * shown, 0.8));
    hubLines = edges > 0.01
        ? [
            for (final edge in _hubEdges)
              CubeLines(turned(edge, hubQ), _white, edges, 0.7),
          ]
        : [];
    labels = look.numbers
        ? [
            for (final s in sides)
              CubeLabel(_labelPoints[s.id].clone().applyQuaternion(hubQ), s.label, s.id == game.active ? 0.95 : 0.4),
          ]
        : [];
  }

  /// The picture is flat enough for marks in the corners of cells.
  bool _flat() => depthShown < flat + 0.01;

  /// In a corner of every cell that hides another block, a small square of
  /// that block's colour: what a pop there would show. Worked out once per
  /// board and view.
  void _pushBehindMarks(CubeGame view, String key) {
    if (!look.behind || !_flat()) return;
    if (_behindKey != key) {
      _behindKey = key;
      _behindMarks = [];
      for (var sx = -view.middle; sx <= view.middle; sx++) {
        for (var sy = -view.middle; sy <= view.middle; sy++) {
          final stack = view.stackAt(sx, sy);
          if (stack.length > 1) _behindMarks.add((at: _local(stack[0]), color: view.hub.at(stack[1])));
        }
      }
    }
    for (final (:at, :color) in _behindMarks) {
      _pushSolid(at, color, size: _mark, nudge: _corner(1, -1));
    }
  }

  /// Falling sticks ease into their cells and turn towards their new way as
  /// one body about their middle square, so that a stick turned by the
  /// player or laid somewhere else by a tip turns and slides there instead of
  /// jumping. While the hub leans over they turn with it like the blocks.
  /// `plane` looks at the eye, in the hub's frame: a half turn spins about
  /// it, flat on the screen.
  List<_DrawnStick> _stickViews(Map<int, Stick> pieces, double dt, Vec plane) {
    final k = tilting ? 0.0 : 1 - math.exp(-dt * 18);
    // A stick turns quicker than it slides: a turn is a decision made in a
    // flash, and the picture must not lag behind it.
    final turnK = tilting ? 0.0 : 1 - math.exp(-dt * 38);
    _pieceViews.removeWhere((side, view) => !identical(pieces[side]?.colors, view.colors));
    return [
      for (final piece in pieces.values)
        () {
          final goal = _local(piece.pivot);
          final dir = V3.ofVec(piece.dir);
          final view = _pieceViews.putIfAbsent(piece.side, () => _StickView(piece.colors, goal.clone(), dir.clone(), dir.clone()));
          if (view.dir.distanceToSq(dir) > 1e-6) {
            final by = Q();
            if (view.dir.dot(dir) > -0.5) {
              by.setFromUnitVectors(view.dir, dir);
            } else {
              final axis = V3.ofVec(plane);
              if (axis.dot(dir).abs() > 0.5) axis.set(dir.y, dir.z, dir.x);
              by.setFromAxisAngle(axis, math.pi);
            }
            view.aim.premultiply(by);
            view.dir.copy(dir);
          }
          if (_carrying() && view.from != null && !_staysPut(piece.side, _turnFrom, _goalQ())) {
            // Carried by a tip to lie some other way: it moves round with the
            // hub and at the same time turns, on the screen, from the way it
            // lay to the way it will lie — flat to the eye all along.
            final e = ease(_t);
            final from = view.from!;
            view.at.copy(from.at).lerp(goal, e);
            final end = dir.clone().applyQuaternion(_goalQ());
            final swing = Q();
            if (from.dir.dot(end) > -0.99) {
              swing.setFromUnitVectors(from.dir, end);
            } else {
              swing.setFromAxisAngle(sceneToward, math.pi);
            }
            final onScreen = Q().slerp(swing, e).multiply(from.turn);
            view.spin.copy(_turned).invert().multiply(onScreen);
          } else {
            view.at.lerp(goal, k);
            view.spin.slerp(view.aim, turnK);
          }
          return _DrawnStick(piece, view.at, view.spin, view.base);
        }(),
    ];
  }

  /// Draws sticks of `source` (the game, or a view of it) seen from the
  /// side `q` turns to the eye. Those of the glasses across the screen are
  /// solid; so is every stick while the hub is open (`solid`). On the flat
  /// picture those of the glasses in front and behind fly along the line of
  /// sight: outlines over the picture (in front) or under it (behind), and
  /// only the steered one unless the setting asks for all, or the game is
  /// paused. The steered one says, square by square, how it will land
  /// (`marks`): filled and with a mark of its colour if it will be seen, an
  /// empty outline and a dark hole if it will hide.
  void _drawSticks(CubeGame source, Q q, List<_DrawnStick> sticks, Color Function(int color, {bool light}) tone,
      {bool marks = true, bool solid = false}) {
    final open = solid || !_flat();
    final carried = _carrying();
    final goal = _goalQ();
    final steeredTo = sideOfNormal(dataIn(goal, sceneUp));
    for (final drawn in sticks) {
      final piece = drawn.piece;
      final steered = piece.side == source.active;
      // While a tip carries the sticks, those on its axis stay on the screen
      // as they were, drawn in the hub's frame from before the tip; one that
      // the flat picture shows on one side of the tip and not on the other
      // fades out (going in front of the eye or behind) or in as it turns.
      final frame = carried && _staysPut(piece.side, _turnFrom, goal) ? _tiltFrom.clone() : null;
      var alpha = 1.0;
      if (carried) {
        final before = _shownFlat(piece.side, _turnFrom, _steeredFrom);
        final after = _shownFlat(piece.side, goal, steeredTo);
        final e = ease(_t);
        if (before && !after) {
          alpha = 1 - e;
        } else if (!before && after) {
          alpha = e;
        }
      }
      V3 cell(int i) => drawn.at.clone().addScaled(drawn.base.clone().applyQuaternion(drawn.spin), i - 1.0);
      final spin = drawn.spin.clone();
      if (open || source.inPlane(piece.side)) {
        for (final (i, color) in piece.colors.indexed) {
          _pushSolid(cell(i), color, spin: spin, frame: frame, alpha: alpha, seeThrough: true);
        }
        continue;
      }
      if (!steered && !look.depthSticks && !paused) continue;
      final lift = V3.ofVec(normalOf(piece.side)).applyQuaternion(q).z * 0.6;
      final landing = steered && marks ? source.landing(piece.side) : null;
      for (final (i, color) in piece.colors.indexed) {
        if (!steered) {
          _pushClear(cell(i), tone(color, light: false), 0.8, 0.06, 0.5, lift: lift, spin: spin);
          continue;
        }
        final seen = landing?.seen[i] ?? true;
        _pushClear(cell(i), tone(color, light: true), 1, seen ? 0.42 : 0, 1, lift: lift, spin: spin);
        if (landing == null || !_flat()) continue;
        if (seen) {
          _pushSolid(cell(i), color, size: _mark, lift: 0.6, nudge: _corner(-1, 1));
        } else {
          _pushClear(cell(i), _hole, 1, 0.8, 1, size: (_mark, _mark, _mark), lift: 0.6, nudge: _corner(-1, 1));
        }
      }
    }
  }

  /// The colour of a block's slot for the outlines, light or plain; set by
  /// the painter from the active set.
  Color Function(int color, {bool light}) tone = (color, {light = false}) => _white;

  /// While a tip is held and the hub has turned: the board as it would
  /// settle, what would pop first blinking, and the sticks in flight where
  /// the tip would lay them.
  void _buildPreview(double dt, _Preview preview, TurnPreview result) {
    final view = result.view;
    final blink = 0.2 + 0.25 * (0.5 + 0.5 * math.sin(_wall * 1000 / 110));
    view.hub.forEachBlock((p, color, index) => _pushSolid(_local(p), color, flash: result.match.cells.contains(index) ? blink : 0));
    _drawSticks(view, preview.q, _stickViews(view.pieces, dt, view.plane), tone);
    _pushBehindMarks(view, 'preview:${preview.up}:${preview.version}');
    _pushNext();
    _flushLayers();
  }

  /// Lines the hub would show from the side it is looked at from: worked
  /// out once per board and side.
  void _inspectLines() {
    final key = '${game.hub.version}:${_inspect!.key}';
    if (_linesKey != key) {
      final match = _viewAt(_inspect!).findMatches();
      _linesKey = key;
      _linesCells = match.cells;
      _linesRuns = match.runs.length;
    }
  }

  /// Turned to be looked at: the blocks as seen from there, those that make
  /// lines from there blinking.
  void _buildInspect(double dt, Q inspect) {
    _inspectLines();
    final cells = _linesCells;
    final blink = 0.2 + 0.3 * (0.5 + 0.5 * math.sin(_wall * 1000 / 110));
    game.hub.forEachBlock((p, color, index) => _pushSolid(_local(p), color, flash: cells.contains(index) ? blink : 0));
    // The sticks in flight turn with the hub, all of them solid: from here
    // the glasses in front and behind may well be across the screen.
    _drawSticks(game, inspect, _stickViews(game.pieces, dt, game.plane), tone, marks: false, solid: true);
    _pushBehindMarks(_viewAt(inspect), 'inspect:$_linesKey');
    _pushNext();
    _flushLayers();
  }

  void _buildBlocks(double dt) {
    final preview = _preview, inspect = _inspect;
    if (preview?.result != null && _t >= 1) {
      _buildPreview(dt, preview!, preview.result!);
      return;
    }
    if (inspect != null) {
      _buildInspect(dt, inspect);
      return;
    }
    final hub = game.hub;
    final phase = game.phase;
    final progress = game.phaseDuration > 0 ? math.min(1.0, game.phaseElapsed / game.phaseDuration) : 1.0;
    final matched = game.activeMatch?.cells;
    final falling = <int>{};
    if (phase == CubePhase.settling) {
      for (final move in game.moves) {
        falling.add(hub.index(move.to));
      }
    }

    // Every block, solid. While the picture is flat the nearest one of each
    // cell hides the others; mid-tip and while the volume is open all show.
    hub.forEachBlock((p, color, index) {
      if (falling.contains(index)) return;
      var flash = 0.0;
      var size = tile;
      if (matched?.contains(index) ?? false) {
        if (phase == CubePhase.matching) flash = 0.25 + 0.4 * math.sin(progress * math.pi);
        if (phase == CubePhase.clearing) {
          flash = 0.6;
          size = tile * (1 - progress);
        }
      }
      final landed = _flashes[index];
      if (landed != null) {
        final age = _clock - landed;
        if (age > 0.25) {
          _flashes.remove(index);
        } else {
          flash = math.max(flash, 0.45 * (1 - age / 0.25));
        }
      }
      if (size > 0.02) _pushSolid(_local(p), color, flash: flash, size: size);
    });
    if (phase == CubePhase.settling) {
      final t = math.min(1.0, game.phaseElapsed / math.max(0.01, game.phaseDuration - game.config.fallBounceSeconds));
      for (final move in game.moves) {
        _pushSolid(_local(move.from).lerp(_local(move.to), t * t), move.color);
      }
    }

    // While a tip carries them, the sticks head for where it lays them: the
    // preview's, or the game's once the tip is made.
    final heading = _carrying() ? (preview?.result?.view.pieces ?? game.pieces) : game.pieces;
    final sticks = _stickViews(heading, dt, game.plane);
    final drop = game.drop;
    if (phase == CubePhase.dropping && drop != null) {
      // Seen as it lies in its glass, not turned to a view: its view is gone.
      sticks.add(_DrawnStick(
        drop.piece,
        _local(drop.from).lerp(_local(drop.piece.pivot), progress * progress),
        Q(),
        V3.ofVec(drop.piece.dir),
      ));
    }
    _drawSticks(game, _targetQ, sticks, tone);

    // Where the stick on top will land, and the lane down to it. A stick in
    // front or behind lands in the cells it is over, and says so itself.
    final piece = game.activePiece;
    if (piece != null && game.inPlane(piece.side) && !game.isGameOver) {
      final ghost = game.ghost();
      final cells = cellsOf(piece);
      var same = ghost != null;
      if (ghost != null) {
        for (var i = 0; i < ghost.length; i++) {
          if (ghost[i].p != cells[i].p) same = false;
        }
      }
      if (ghost != null && !same) {
        for (final c in ghost) {
          _pushClear(_local(c.p), tone(c.color, light: true), 1, 0.16, 1);
        }
        if (look.lane) _pushLanes(piece, ghost);
      }
    }
    _pushBehindMarks(game, 'game:${hub.version}:${_targetQ.key}');
    _pushNext();
    _flushLayers();
  }

  /// The stick each glass across the screen gets next, in a box beyond the
  /// far end of its arm, as the flat game shows them: turning round with the
  /// cross, fading as a glass tips out of the screen or into it, dimmed while
  /// the hub is open.
  void _pushNext() {
    if (!look.nextPiece) return;
    final dim = 0.35 + 0.65 * crossShown;
    for (final s in sides) {
      final out = V3.ofVec(normalOf(s.id)).applyQuaternion(_turned);
      final flatness = 1 - out.z.abs();
      final along = V3(-out.y, out.x, 0);
      if (flatness < 0.05 || along.lengthSq < 1e-4) continue;
      along.normalize();
      final alpha = dim * flatness * flatness;
      final centre = out.clone().scale(reach + _nextGap);
      final spin = Q().setFromAxisAngle(sceneToward, math.atan2(along.y, along.x));
      _pushClear(centre, _nextEdge, alpha * 0.5, 0.06, 0.6, size: _nextBox, frame: _peekTurn.clone(), spin: spin);
      // Left to right as the glass's own frame reads, arm on top.
      final colors = game.nextOf(s.id);
      for (final (i, color) in colors.indexed) {
        final at = centre.clone().addScaled(along, (colors.length - 1) / 2 - i);
        _pushSolid(at, color, size: 0.86, frame: _peekTurn.clone(), alpha: alpha);
      }
    }
  }

  /// A faint column under each lane of the stick, down to the landing spot —
  /// the flat game's aiming lane.
  void _pushLanes(Stick piece, List<StickCell> ghost) {
    final n = normalOf(piece.side);
    final axis = sides[piece.side].axis;
    final lanes = <String, ({Vec p, int height, Vec ghost})>{};
    for (final (i, c) in cellsOf(piece).indexed) {
      final key = [for (var j = 0; j < 3; j++) if (j != axis) c.p[j]].join(',');
      final low = lanes[key];
      final height = c.p.dot(n);
      if (low == null || height < low.height) lanes[key] = (p: c.p, height: height, ghost: ghost[i].p);
    }
    final normal = V3.ofVec(n);
    for (final lane in lanes.values) {
      final top = _local(lane.p).addScaled(normal, -0.5);
      final bottom = _local(lane.ghost).addScaled(normal, 0.5);
      final length = top.distanceTo(bottom);
      if (length < 0.05) continue;
      final size = [0.91, 0.91, 0.91];
      size[axis] = length;
      _pushClear(top.add(bottom).scale(0.5), _white, 1, 0.07, 0, size: (size[0], size[1], size[2]));
    }
  }
}
