import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../cube/campaign.dart';
import '../../cube/painter.dart';
import '../../cube/rules.dart';
import '../../cube/save.dart';
import '../../cube/tutorial.dart';
import '../../cube/view.dart';
import '../../game/config/modes.dart';
import '../audio/sound_effects.dart';
import '../data/bindings.dart';
import '../data/progress.dart';
import '../data/settings.dart';
import '../data/stats.dart';
import '../format.dart';
import '../game/campaign_progress.dart';
import '../game/hud.dart';
import '../game/tutorial.dart';
import '../i18n/strings.dart';
import '../input/game_action.dart';
import '../input/pad_controller.dart';
import '../input/pad_surface.dart';
import '../layout.dart';
import '../style.dart';
import '../widgets/armed_layer.dart';
import '../widgets/controls.dart';

enum _Status { playing, paused, over, done }

/// Longest frame the game will simulate in one go (hitches, app switches).
const _maxFrameSeconds = 0.05;

/// A turn of the cross takes this much longer than in the flat game: the
/// hub is a heavier thing to turn.
const _turnSlower = 1.4;

/// The flat game's own turn, by default: the hub leans over in
/// [tiltSecondsDefault] then, and as much quicker or slower as the player
/// sets the turns.
const _defaultTurnMs = 260;

/// Seconds of play between two keepings of the game, at least.
const _saveEverySeconds = 5.0;

/// Frames a still picture is drawn for (a turn or a fade finishing) before
/// the drawing stops: a paused game, the results, burn no battery.
const _stillFrames = 45;

/// While the hub is turned to be looked at, the play keys turn it as they do
/// in play: ← clockwise, → counterclockwise, ↑ ↓ the glass behind or in front
/// over the top. The stick's turn shows it from the side.
const _lookTurns = <GameAction, (LookAxis, int)>{
  GameAction.glassLeft: (LookAxis.sight, -1),
  GameAction.glassRight: (LookAxis.sight, 1),
  GameAction.tipBack: (LookAxis.across, 1),
  GameAction.tipFront: (LookAxis.across, -1),
  GameAction.rotateCW: (LookAxis.upright, -1),
  GameAction.rotateCCW: (LookAxis.upright, 1),
};

/// A lesson done moves on once the board has been at rest this long.
const _tutorialNextSeconds = 0.7;

/// A lesson still waiting after this long says again what to press.
const _tutorialIdle = Duration(seconds: 4);

/// How long the volume has to be held open in its lesson.
const _peekLessonSeconds = 1.2;

/// Longest frame a lesson counts of a key held: as long as it was, on a
/// device that draws few frames, but not a stall.
const _maxLessonFrameSeconds = 0.25;

/// The first lesson opens the cube and closes it again, from either side,
/// this many seconds at a time.
const _introBeatSeconds = 2.4;

/// What the lessons let the player do with the stick.
const _pieceActions = [
  GameAction.moveLeft,
  GameAction.moveRight,
  GameAction.rotateCW,
  GameAction.rotateCCW,
  GameAction.softDrop,
  GameAction.hardDrop,
];

/// The glass that filled up, by where the screen shows it.
const _placeNames = {
  'top': 'Верхний',
  'right': 'Правый',
  'bottom': 'Нижний',
  'left': 'Левый',
  'front': 'Передний',
  'back': 'Задний',
};

/// What the line under the cube says.
@immutable
class _Line {
  const _Line(this.steering, this.tip, this.look);
  final Steering steering;
  final ({bool up, int popped, int rounds})? tip;
  final ({int runs, int blocks})? look;

  @override
  bool operator ==(Object other) => other is _Line && other.steering == steering && other.tip == tip && other.look == look;

  @override
  int get hashCode => Object.hash(steering, tip, look);
}

class _Repaint extends ChangeNotifier {
  void touch() => notifyListeners();
}

/// The playable screen of Cube (webapp/src/components/CubeScreen.tsx): owns
/// the game and its picture, runs them from the frame loop and turns key
/// presses and pad buttons into moves. The parent re-keys it for every new
/// game.
class CubeScreen extends StatefulWidget {
  const CubeScreen({
    super.key,
    required this.settings,
    required this.blocked,
    required this.onSettings,
    required this.onExit,
    required this.onSetup,
    required this.onRetry,
    required this.onRecord,
    this.level,
    this.progress,
    this.onProgress,
    this.onLevels,
    this.onNextLevel,
    this.restore,
    this.onCheckpoint,
    this.onPauseChanged,
    this.onToggleMusic,
    this.tutorial = false,
    this.onTutorialDone,
  });

  final Settings settings;

  /// The tutorial's lessons instead of a game.
  final bool tutorial;

  /// `played`: Play on the last lesson; false when the player skipped.
  final ValueChanged<bool>? onTutorialDone;

  /// True while the settings are open over the game: nothing moves.
  final bool blocked;
  final VoidCallback onSettings;

  /// Back to the main menu.
  final VoidCallback onExit;

  /// Back to Cube's own screen.
  final VoidCallback onSetup;

  /// A new game: the same level again, or the endless game again.
  final VoidCallback onRetry;
  final ValueChanged<RunRecord> onRecord;

  /// A level of the campaign, by index, rather than the endless game.
  final int? level;

  /// How far the campaign has been played, and its change once a level is
  /// passed.
  final Progress? progress;
  final ValueChanged<Progress>? onProgress;

  /// The campaign's levels; the next one.
  final VoidCallback? onLevels;
  final ValueChanged<int>? onNextLevel;

  /// A game kept from before, to go on with: it opens paused.
  final CubeSave? restore;

  /// Keeps the game as it is now, or forgets it (null) once it is over.
  final ValueChanged<CubeSave?>? onCheckpoint;
  final ValueChanged<bool>? onPauseChanged;
  final VoidCallback? onToggleMusic;

  @override
  State<CubeScreen> createState() => CubeScreenState();
}

class CubeScreenState extends State<CubeScreen> with SingleTickerProviderStateMixin, WidgetsBindingObserver implements PadSink {
  late final Ticker _ticker = createTicker(_onTick);
  late CubeGame _game;
  late final CubeView _view;
  late final PadController _pads;
  final _repaint = _Repaint();
  final _focus = FocusNode();
  final ValueNotifier<HudState> _hud = ValueNotifier(HudState.empty);
  final ValueNotifier<_Line> _line = ValueNotifier(const _Line(Steering.top, null, null));
  late String _runId;
  late final int? _level = widget.restore?.level ?? widget.level;
  CubeLevel? get _levelPlayed => _level == null ? null : cubeCampaign[_level];

  _Status _status = _Status.playing;

  /// Paused, or over, with the hub turned to be looked at: no dialog.
  bool _looking = false;

  /// The results were looked away from and back: they answer at once.
  bool _resultsSeen = false;
  RunRecord? _result;
  String _overGlass = '';
  bool _finished = false;
  bool _appActive = true;
  Duration _last = Duration.zero;
  int _still = 0;
  bool _wasFrozen = false;
  Callout? _callout;
  int _calloutId = 0;

  /// The combo of the match flashing now: it bursts that many steps up.
  int _poppingCombo = 1;

  /// Seconds of play since the game was last kept, and whether it has
  /// changed since.
  double _unsaved = 0;
  bool _changed = false;

  // The tutorial: the lesson shown (−1 in a game), whether it is done, what
  // it has seen happen, and what it says.
  int _lesson = -1;
  bool _lessonDone = false;
  bool _landed = false;
  bool _matched = false;
  double _peekSeconds = 0;
  double _restSince = -1;
  double _clock = 0;
  String? _hint;
  bool _urging = false;
  Timer? _idle;

  /// The game and its picture, for the tests of the screen.
  @visibleForTesting
  CubeGame get game => _game;
  @visibleForTesting
  CubeView get view => _view;

  static String _newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  CubeGame _fresh() {
    final level = _levelPlayed;
    if (level != null) return CubeGame(cubeLevelConfig(level));
    final cube = widget.settings.cube;
    return CubeGame(CubeConfig(
      centre: cube.width,
      arm: cube.arm,
      numberOfColors: cube.colours,
      depthFalls: cube.depthFalls,
      inactiveFalls: cube.inactiveFalls,
      ramp: cubeRamp,
    ));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _runId = widget.restore?.id ?? _newId();
    var restored = false;
    final save = widget.restore;
    if (widget.tutorial) {
      _lesson = 0;
      _game = lessonGame(0);
    } else if (save != null) {
      try {
        _game = CubeGame.restore(save.game);
        restored = true;
      } catch (_) {
        // Not a game after all: a new one, under a run of its own.
        _game = _fresh();
        _runId = _newId();
      }
    } else {
      _game = _fresh();
    }
    _view = CubeView(_game);
    _pads = PadController(
      sink: this,
      dasMs: () => widget.settings.handling.dasMs,
      arrMs: () => widget.settings.handling.arrMs,
    );
    // A kept game opens paused: the player looks first, then goes on.
    _status = restored ? _Status.paused : _Status.playing;
    _view.paused = _status != _Status.playing;
    _armIdle();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onPauseChanged?.call(_status == _Status.paused);
    });
    _ticker.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idle?.cancel();
    _ticker.dispose();
    _focus.dispose();
    _hud.dispose();
    _line.dispose();
    _repaint.dispose();
    super.dispose();
  }

  /// Leaving the app pauses the game, as losing focus does in the browser.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appActive = state == AppLifecycleState.resumed;
    if (_appActive) {
      _last = Duration.zero;
      _still = 0;
      if (!_ticker.isActive) _ticker.start();
      return;
    }
    _letGo();
    _checkpoint();
    if (_status == _Status.playing && !widget.tutorial) _setStatus(_Status.paused);
  }

  void _setStatus(_Status status) {
    setState(() => _status = status);
    _view.paused = status != _Status.playing;
    _still = 0;
    widget.onPauseChanged?.call(status == _Status.paused);
  }

  void _setLook(bool on) {
    setState(() => _looking = on);
    if (!on) _view.endInspect();
    _still = 0;
  }

  /// Keeps the game as it is, when it is at rest; otherwise the last one
  /// kept stands, a moment older.
  void _checkpoint() {
    if (_finished || widget.tutorial) return;
    final snapshot = _game.snapshot();
    if (snapshot == null) return;
    widget.onCheckpoint?.call(
      CubeSave(id: _runId, savedAt: DateTime.now().millisecondsSinceEpoch, game: snapshot, level: _level),
    );
  }

  /// `passed`: the level's target reached. A level's run reports the level
  /// it reached: the next one once passed.
  void _recordRun({required bool interrupted, bool passed = false}) {
    final level = _level;
    final record = RunRecord(
      id: _runId,
      mode: level == null ? ModeId.cube : ModeId.cubeCampaign,
      at: DateTime.now().millisecondsSinceEpoch,
      score: _game.score,
      pieces: _game.placed,
      matches: _game.matches,
      bestCombo: _game.bestCombo,
      seconds: _game.seconds,
      level: level == null ? _game.speedLevel + 1 : level + (passed ? 2 : 1),
      completed: passed && level == cubeCampaignLast,
      interrupted: interrupted,
    );
    widget.onRecord(record);
    widget.onCheckpoint?.call(null);
    setState(() => _result = record);
  }

  /// Lets go of everything held: a tip being looked at, the volume.
  void _letGo() {
    _pads.releaseAll();
    _view
      ..cancelTip()
      ..peeking = false;
  }

  void _togglePause() {
    if (_status == _Status.over || _status == _Status.done || widget.tutorial) return;
    _letGo();
    if (_looking) _setLook(false);
    _setStatus(_status == _Status.playing ? _Status.paused : _Status.playing);
    _checkpoint();
  }

  void _retry() {
    if (widget.tutorial) return;
    if (!_finished) _recordRun(interrupted: true);
    _finished = true;
    widget.onRetry();
  }

  void _look(bool on) {
    _letGo();
    _setLook(on);
    if (_status == _Status.over) setState(() => _resultsSeen = true);
  }

  /// Kept to go on with later, or given up and recorded.
  void _leave(VoidCallback destination, {bool keep = true}) {
    _letGo();
    if (keep) {
      _checkpoint();
    } else if (!_finished && (_game.placed > 0 || _game.seconds > 5)) {
      _recordRun(interrupted: true);
    } else {
      widget.onCheckpoint?.call(null);
    }
    _finished = true;
    destination();
  }

  /// A lesson whose button the player's pads do not have: pressed for them,
  /// held a moment for the volume.
  VoidCallback? get _practice {
    if (!widget.tutorial || _lessonDone) return null;
    final missing = missingOnPads(_lesson, widget.settings.cubeLeftPad, widget.settings.cubeRightPad);
    if (missing == null) return null;
    return () {
      _pads.down(missing);
      Timer(Duration(milliseconds: missing == GameAction.peek ? 1500 : 60), () {
        if (mounted) _pads.up(missing);
      });
    };
  }

  /// The system's Back: kept, and to the main menu; out of the lessons.
  void handleBack() => widget.tutorial ? widget.onTutorialDone?.call(false) : _leave(widget.onExit);

  // ------------------------------------------------------------ the lessons

  void _enterLesson(int next) {
    _letGo();
    _lesson = next;
    _game = lessonGame(next);
    _view.reset(_game);
    _lessonDone = _landed = _matched = false;
    _peekSeconds = 0;
    _restSince = -1;
    setState(() {
      _hint = null;
      _urging = false;
    });
    _armIdle();
  }

  void _didLesson() {
    if (_lessonDone) return;
    _lessonDone = true;
    _idle?.cancel();
    setState(() {
      _hint = null;
      _urging = false;
    });
  }

  /// The first lesson and the last wait for their button.
  void _nextLesson() {
    if (!widget.tutorial || widget.blocked || (_lesson > 0 && _lesson < cubeLessonLast)) return;
    if (_lesson == cubeLessonLast) {
      widget.onTutorialDone?.call(true);
    } else {
      _enterLesson(_lesson + 1);
    }
  }

  /// A lesson still waiting says again what to press, and the call beats
  /// faster.
  void _armIdle() {
    _idle?.cancel();
    if (!widget.tutorial || cubeLessonActions[_lesson] == null || _lessonDone) return;
    _idle = Timer(_tutorialIdle, () {
      if (!mounted || _lessonDone) return;
      if (widget.blocked || !_appActive) return _armIdle();
      setState(() {
        _urging = true;
        _hint ??= 'Нажми подсвеченную кнопку';
      });
    });
  }

  /// Whether the lesson lets the player do this now.
  bool _allows(GameAction action) {
    if (_lesson < 0 || _lesson == cubeLessonLast) return true;
    if (_lessonDone || _lesson == 0) return false;
    return switch (_lesson) {
      1 => _pieceActions.contains(action),
      2 => action == GameAction.glassLeft || action == GameAction.glassRight,
      3 => action == GameAction.tipBack || action == GameAction.tipFront,
      _ => action == GameAction.peek || (_view.peeking && _pieceActions.contains(action)),
    };
  }

  /// False, and a word of what to press, when the lesson asks for something
  /// else.
  bool _lets(GameAction action) {
    if (!widget.tutorial) return true;
    if (!_allows(action)) {
      if (_lesson > 0 && !_lessonDone) setState(() => _hint = 'Нажми подсвеченную кнопку');
      return false;
    }
    // On the right track: the reminder goes, and waits again.
    if (_hint != null || _urging) {
      setState(() {
        _hint = null;
        _urging = false;
      });
    }
    _armIdle();
    return true;
  }

  /// The lesson with a piece to drop: a miss lays the board out again; the
  /// volume held long enough; the first lesson opening the cube and closing
  /// it again. A lesson done goes on once the board is at rest.
  void _checkLesson(double seconds) {
    if (_lesson == 1) {
      if (_matched) {
        _didLesson();
      } else if (_landed && _game.phase == CubePhase.playing) {
        _enterLesson(_lesson);
        setState(() => _hint = 'Мимо — попробуй ещё раз');
      }
    } else if (_lesson == 4 && _view.peeking) {
      _peekSeconds += seconds;
      if (_peekSeconds >= _peekLessonSeconds) _didLesson();
    } else if (_lesson == 0 && !widget.blocked) {
      final beat = (_clock / _introBeatSeconds).floor() % 3;
      _view.peeking = beat > 0;
      if (beat > 0) _view.peekYaw = beat == 1 ? 1 : -1;
    }
    final atRest = _game.phase == CubePhase.playing && !_view.tilting;
    _restSince = _lessonDone && atRest ? (_restSince < 0 ? _clock : _restSince) : -1;
    if (_restSince >= 0 && _clock - _restSince >= _tutorialNextSeconds && _lesson < cubeLessonLast) {
      _enterLesson(_lesson + 1);
    }
  }

  bool get _playing => _status == _Status.playing && !widget.blocked && _appActive;

  // ------------------------------------------------------------- the pads

  @override
  void move(int direction, {required bool toWall}) {
    if (!_lets(direction < 0 ? GameAction.moveLeft : GameAction.moveRight)) return;
    if (_view.peeking) {
      _view.peekYaw = direction;
      return;
    }
    if (!_playing) return;
    for (var i = toWall ? _game.hub.size : 1; i > 0; i--) {
      _view.move(direction);
    }
  }

  @override
  void softDrop({required bool held}) {
    if (held && !_lets(GameAction.softDrop)) return;
    if (held && _view.peeking) {
      _view.peekPitch = -1;
    } else {
      _view.softDrop(held && _playing);
    }
  }

  @override
  void press(GameAction action) {
    if (action == GameAction.pause) return _togglePause();
    if (action == GameAction.restart) return _retry();
    if (!_lets(action)) return;
    if (action == GameAction.peek) {
      _view.peeking = _playing || _looking;
      return;
    }
    if (_view.peeking && (action == GameAction.rotateCW || action == GameAction.hardDrop)) {
      _view.peekPitch = action == GameAction.rotateCW ? 1 : -1;
      return;
    }
    if (_looking) {
      final turn = _lookTurns[action];
      if (turn != null) _view.inspectTurn(turn.$1, turn.$2);
      _still = 0;
      return;
    }
    if (_status == _Status.over && action == GameAction.hardDrop) return _retry();
    if (!_playing) return;
    final top = _view.steering == Steering.top;
    switch (action) {
      case GameAction.rotateCW:
      case GameAction.rotateCCW:
        _view.rotate(action == GameAction.rotateCW);
      case GameAction.hardDrop:
        _view.drop();
      case GameAction.glassLeft:
      case GameAction.glassRight:
        // As in the flat game: ← clockwise, the glass on the left coming to
        // the top; → counterclockwise.
        _view.turnCross(action == GameAction.glassLeft ? -1 : 1);
        if (_lesson == 2) _didLesson();
      case GameAction.tipBack:
      case GameAction.tipFront:
        // A stick in front or behind moves up and down the screen; the one
        // on top tips the hub over.
        if (top) {
          _view.startTip(action == GameAction.tipBack);
        } else {
          _view.shift(action == GameAction.tipBack ? 1 : -1);
        }
      case GameAction.frontGlass:
        _view.steer('front');
      case GameAction.backGlass:
        _view.steer('back');
      case GameAction.depthGlass:
        _view.steer('cycle');
      default:
        break;
    }
  }

  @override
  void release(GameAction action) {
    if (action == GameAction.peek) {
      _view.peeking = false;
    } else if (action == GameAction.tipBack || action == GameAction.tipFront) {
      if (!_playing) {
        _view.cancelTip();
      } else if (_view.commitTip(action == GameAction.tipBack) && _lesson == 3) {
        _didLesson();
      }
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.blocked) return KeyEventResult.ignored;
    final action = actionForKey(widget.settings.bindings, event.physicalKey, ActionScope.cube);
    if (action == null) return KeyEventResult.ignored;
    if (_status == _Status.paused && !_looking) {
      if (event is KeyDownEvent && action == GameAction.pause) _togglePause();
      return KeyEventResult.handled;
    }
    // Looking around: the pause key brings the dialog back.
    if (_looking && action == GameAction.pause) {
      if (event is KeyDownEvent) {
        if (_status == _Status.paused) {
          _togglePause();
        } else {
          _setLook(false);
        }
      }
      return KeyEventResult.handled;
    }
    if ((_status == _Status.over || _status == _Status.done) && !_looking) return KeyEventResult.ignored;
    // Held keys repeat through the pad controller, not through the system.
    if (event is KeyDownEvent) {
      _pads.down(action);
    } else if (event is KeyUpEvent) {
      _pads.up(action);
    }
    return KeyEventResult.handled;
  }

  // ------------------------------------------------------------- the frame

  CubeLook _lookOf(CubeOptions c) => CubeLook(
        depthSticks: c.depthSticks,
        behind: c.behind,
        edges: c.edges,
        numbers: c.numbers,
        lane: c.lane,
        nextPiece: c.nextPiece,
        depthHint: c.depthHint,
        volumeEdges: c.volumeEdges,
        xray: c.xray,
        grid: c.grid,
      );

  void _onTick(Duration elapsed) {
    final frameMs = _last == Duration.zero ? 0.0 : (elapsed - _last).inMicroseconds / 1000;
    _last = elapsed;
    final seconds = math.min(_maxFrameSeconds, math.max(0.0, frameMs / 1000));
    final s = widget.settings;
    final frozen = widget.blocked || !_appActive;
    if (frozen && !_wasFrozen) _letGo();
    // Back from the settings, a still picture is drawn again as now set.
    if (frozen != _wasFrozen) _still = 0;
    _wasFrozen = frozen;
    _view
      ..look = _lookOf(s.cube)
      ..turnSeconds = s.effects.turnMs / 1000 * _turnSlower
      ..tiltSeconds = tiltSecondsDefault * s.effects.turnMs / _defaultTurnMs;
    // The endless game takes these as set; a level keeps its own.
    if (_level == null &&
        (_game.config.depthFalls != s.cube.depthFalls || _game.config.inactiveFalls != s.cube.inactiveFalls)) {
      _game.config = _game.config.copyWith(depthFalls: s.cube.depthFalls, inactiveFalls: s.cube.inactiveFalls);
    }
    final play = _status == _Status.playing && !frozen;
    if (play) _pads.update(seconds);
    // Under the settings the picture holds still; looking around, it turns.
    // Paused, or over, it is drawn until what moved has come to rest.
    _still = _status == _Status.playing || _looking || _view.peeking ? 0 : _still + 1;
    final events = frozen || _still > _stillFrames ? const <CubeEvent>[] : _view.frame(seconds, play);
    if (!(frozen || _still > _stillFrames)) _repaint.touch();

    final levelPlayed = _levelPlayed;
    for (final event in events) {
      if (event is Landed) _landed = true;
      if (event is Matched) _matched = true;
      switch (event) {
        case Matched(:final score, :final combo):
          setState(() => _callout = Callout.score(id: ++_calloutId, points: score, combo: combo));
          _poppingCombo = combo;
        case Popped():
          SoundEffects.instance.pop(_poppingCombo);
        case Moved(:final blocked):
          if (!blocked) SoundEffects.instance.play(SoundGroup.move);
        case Rotated(:final blocked):
          if (!blocked) SoundEffects.instance.play(SoundGroup.rotate);
        case Switched():
          SoundEffects.instance.play(SoundGroup.turn);
        case Landed():
          SoundEffects.instance.play(SoundGroup.land);
        case SpeedUp(:final level):
          setState(() => _callout = Callout.speed(id: ++_calloutId, speed: level + 1));
          SoundEffects.instance.play(SoundGroup.level);
        case GameEnded() when widget.tutorial:
          // The tutorial's free play has no lost game: the cube empties.
          _game = lessonGame(cubeLessonLast);
          _view.reset(_game);
        case GameEnded(:final side) when !_finished && !(levelPlayed != null && _game.score >= levelPlayed.target):
          _finished = true;
          _letGo();
          _overGlass = _placeNames[_view.placeOf(side)] ?? '';
          _recordRun(interrupted: false);
          _setStatus(_Status.over);
          SoundEffects.instance.play(SoundGroup.over);
        default:
          break;
      }
    }

    if (widget.tutorial && !frozen) {
      final lessonSeconds = math.min(_maxLessonFrameSeconds, math.max(0.0, frameMs / 1000));
      _clock += lessonSeconds;
      _checkLesson(lessonSeconds);
    }
    // A level is passed once its points are in and the board is at rest.
    final level = _level;
    if (levelPlayed != null &&
        level != null &&
        !_finished &&
        _game.score >= levelPlayed.target &&
        (_game.phase == CubePhase.playing || _game.isGameOver)) {
      _finished = true;
      _letGo();
      widget.onProgress?.call(passCubeLevel(widget.progress ?? defaultCubeProgress(), level, _game.score));
      _recordRun(interrupted: false, passed: true);
      _setStatus(_Status.done);
      SoundEffects.instance.play(SoundGroup.level);
    }
    // Kept once a move is over, at most every few seconds, and on a pause or
    // when the app goes, at once.
    if (play) _unsaved += seconds;
    if (events.any((event) => event is Landed || event is Switched || event is Matched)) _changed = true;
    if (((_changed && _unsaved >= _saveEverySeconds) || _unsaved >= 3 * _saveEverySeconds) &&
        _game.phase == CubePhase.playing &&
        !_view.tilting) {
      _checkpoint();
      _changed = false;
      _unsaved = 0;
    }

    _hud.value = HudState(
      score: _game.score,
      combo: _game.combo,
      bestCombo: _game.bestCombo,
      matches: _game.matches,
      pieces: _game.placed,
      seconds: _game.seconds.floor(),
      level: level == null ? 0 : level + 1,
      into: _game.score,
      target: levelPlayed?.target ?? 0,
      colours: 0,
      glasses: 0,
      speed: level == null ? _game.speedLevel + 1 : 0,
    );
    _line.value = _Line(_view.steering, _view.tipPreview, _view.inspecting);
  }

  // ------------------------------------------------------------- the build

  String get _mode => _level == null
      ? modeTitle(ModeId.cube)
      : '${modeTitle(ModeId.cubeCampaign)} · уровень ${_level + 1} из ${cubeCampaignLast + 1}';

  /// Back to where the game was chosen: the levels, or Cube's screen.
  VoidCallback get _back => _level == null ? widget.onSetup : widget.onLevels ?? widget.onSetup;
  String get _backLabel => _level == null ? 'К режиму' : 'К уровням';
  String get _retryLabel => _level == null ? 'Заново' : 'Повторить уровень';

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final level = _level, levelPlayed = _levelPlayed;
    final sound = widget.onToggleMusic == null
        ? null
        : SoundButton(on: settings.audio.music || settings.audio.sounds, onToggle: widget.onToggleMusic!);
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) => Column(
              children: [
                if (widget.tutorial) ...[
                  // The same heading as the menus: a small arrow, the mode, the title.
                  ScreenHeading(
                    kicker: 'Куб',
                    title: 'Обучение',
                    onBack: handleBack,
                    actions: [
                      ?sound,
                      GameIconButton(icon: Icons.settings_rounded, label: 'Настройки', onPressed: widget.onSettings),
                    ],
                  ),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: math.min(constraints.maxHeight * 0.4, 260 * tabletScale(MediaQuery.sizeOf(context))),
                    ),
                    child: TutorialPanel(
                      lessons: cubeLessons,
                      step: _lesson,
                      performed: _lessonDone,
                      hint: _hint,
                      urging: _urging,
                      onPractice: _practice,
                      onNext: _nextLesson,
                      onSkip: () => widget.onTutorialDone?.call(false),
                    ),
                  ),
                ] else
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    children: [
                      GameIconButton(icon: Icons.pause_rounded, label: 'Пауза', onPressed: _togglePause),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: ValueListenableBuilder<HudState>(
                            valueListenable: _hud,
                            builder: (context, hud, _) => GameReadout(
                              hud: hud,
                              options: settings.hud,
                              callout: _callout,
                              levelCount: cubeCampaignLast + 1,
                            ),
                          ),
                        ),
                      ),
                      if (sound != null) ...[sound, const SizedBox(width: 6)],
                      GameIconButton(icon: Icons.settings_rounded, label: 'Настройки', onPressed: widget.onSettings),
                    ],
                  ),
                ),
                if (levelPlayed != null && level != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                    child: ValueListenableBuilder<HudState>(
                      valueListenable: _hud,
                      builder: (context, hud, _) => CampaignProgress(
                        level: level + 1,
                        into: hud.into,
                        target: levelPlayed.target,
                        compact: true,
                        animated: _status == _Status.playing && !widget.blocked && settings.effects.fieldBackground,
                      ),
                    ),
                  ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final side = math.min(box.maxWidth, box.maxHeight);
                      _view.resize(side, side);
                      return Center(child: SizedBox.square(dimension: side, child: _stage(side)));
                    },
                  ),
                ),
                RepaintBoundary(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                    child: IgnorePointer(
                      ignoring: (_status != _Status.playing && !_looking) || widget.blocked,
                      child: PadSurface(
                        settings: settings,
                        layouts: (settings.cubeLeftPad, settings.cubeRightPad),
                        onDown: _pads.down,
                        onUp: _pads.up,
                        hint: widget.tutorial && !_lessonDone ? cubeLessonActions[_lesson] ?? const [] : const [],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            ),
          ),
          if (!widget.blocked && _status == _Status.paused && !_looking) _dialog(_pauseDialog()),
          if (!widget.blocked && _status == _Status.over && _result != null && !_looking)
            _dialog(_resultsSeen
                ? _overDialog(_result!)
                : ArmedLayer(builder: (context, armed) => _overDialog(_result!, armed: armed))),
          if (!widget.blocked && _status == _Status.done && _result != null && level != null)
            _dialog(ArmedLayer(builder: (context, armed) => _doneDialog(_result!, level, armed: armed))),
        ],
      ),
    );
  }

  Widget _stage(double side) => Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(painter: CubePainter(_view, repaint: _repaint), size: Size.square(side)),
            ),
          ),
          Positioned(
            left: 8,
            right: 8,
            bottom: 8,
            child: Row(
              children: [
                Expanded(
                  child: ValueListenableBuilder<_Line>(
                    valueListenable: _line,
                    builder: (context, line, _) => _CubeLine(line: line, looking: _looking),
                  ),
                ),
                if (_looking && !widget.blocked) ...[
                  const SizedBox(width: 8),
                  GoButton(
                    label: _status == _Status.paused ? 'Продолжить' : 'К итогам',
                    onPressed: () => _status == _Status.paused ? _togglePause() : _look(false),
                  ),
                ],
              ],
            ),
          ),
        ],
      );

  /// A dialog over the game: the game stands still behind it.
  Widget _dialog(Widget card) => Positioned.fill(
        child: Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: const ColoredBox(color: Color(0xC4050508)),
              ),
            ),
            Positioned.fill(
              child: SafeArea(
                child: Center(
                  child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: TabletScale(child: card)),
                ),
              ),
            ),
          ],
        ),
      );

  Widget _pauseDialog() => DialogCard(
        kicker: _mode,
        title: 'Пауза',
        children: [
          _buttons([
            GoButton(label: 'Продолжить', expand: true, onPressed: _togglePause),
            OutlineButton(label: 'Осмотреть куб', onPressed: () => _look(true)),
            OutlineButton(label: _retryLabel, onPressed: _retry),
            OutlineButton(label: 'Настройки', onPressed: widget.onSettings),
            OutlineButton(label: _backLabel, onPressed: () => _leave(_back)),
            OutlineButton(label: 'В меню', onPressed: () => _leave(widget.onExit)),
            OutlineButton(label: 'Завершить партию', onPressed: () => _leave(widget.onExit, keep: false)),
          ]),
        ],
      );

  Widget _overDialog(RunRecord record, {bool armed = true}) => DialogCard(
        kicker: _mode,
        title: 'Игра окончена',
        danger: true,
        note: '$_overGlass стакан заполнился до конца рукава.',
        children: [
          _RunStats(rows: [
            ('Очки', formatNumber(record.score)),
            ('Фигуры', '${record.pieces}'),
            ('Лучшее комбо', '×${record.bestCombo}'),
            if (_level == null) ('Скорость', '${record.level}'),
            ('Время', formatDuration(record.seconds)),
          ]),
          const SizedBox(height: 14),
          _buttons(armed: armed, [
            GoButton(label: _retryLabel, expand: true, onPressed: _retry),
            OutlineButton(label: 'Осмотреть куб', onPressed: () => _look(true)),
            OutlineButton(label: _backLabel, onPressed: _back),
            OutlineButton(label: 'В меню', onPressed: widget.onExit),
          ]),
        ],
      );

  Widget _doneDialog(RunRecord record, int level, {bool armed = true}) {
    final next = level < cubeCampaignLast ? level + 1 : null;
    return DialogCard(
      kicker: _mode,
      title: next == null ? 'Кампания пройдена' : 'Уровень ${level + 1} пройден',
      note: next == null
          ? 'Все ${cubeCampaignLast + 1} уровней куба позади.'
          : 'Дальше: ${cubeCampaign[next].title} · цель ${formatNumber(cubeCampaign[next].target)}',
      children: [
        _RunStats(rows: [
          ('Очки', formatNumber(record.score)),
          ('Фигуры', '${record.pieces}'),
          ('Время', formatDuration(record.seconds)),
        ]),
        const SizedBox(height: 14),
        _buttons(armed: armed, [
          if (next != null) GoButton(label: 'Следующий уровень', expand: true, onPressed: () => widget.onNextLevel?.call(next)),
          if (next == null)
            GoButton(label: 'К уровням', expand: true, onPressed: _back)
          else
            OutlineButton(label: 'К уровням', onPressed: _back),
          OutlineButton(label: 'В меню', onPressed: widget.onExit),
        ]),
      ],
    );
  }

  /// The buttons light up once they will answer.
  Widget _buttons(List<Widget> buttons, {bool armed = true}) => AnimatedOpacity(
        opacity: armed ? 1 : 0.5,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [for (final button in buttons) Padding(padding: const EdgeInsets.only(bottom: 8), child: button)],
        ),
      );
}

/// The summary of a finished run, in rows of a label and a value.
class _RunStats extends StatelessWidget {
  const _RunStats({required this.rows});

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) => Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: LText(label, style: const TextStyle(fontSize: 14))),
                  LText(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                ],
              ),
            ),
        ],
      );
}

/// The one line of words over the bottom of the field: which glass is
/// steered when it is not the one on top, what a tip held would pop, what
/// shows from where the hub is looked at. Nothing while plain play goes on.
class _CubeLine extends StatelessWidget {
  const _CubeLine({required this.line, required this.looking});

  final _Line line;
  final bool looking;

  @override
  Widget build(BuildContext context) {
    String? text;
    final look = line.look, tip = line.tip;
    if (looking) {
      text = look == null || look.runs == 0 ? 'Осмотр · линий отсюда нет' : 'Осмотр · линий отсюда: ${look.runs}, блоков ${look.blocks}';
    } else if (tip != null) {
      final pops = tip.popped == 0
          ? 'ничего не лопнет'
          : tip.rounds > 1
              ? 'лопнет ${tip.popped}, каскад ×${tip.rounds}'
              : 'лопнет ${tip.popped}';
      text = 'Отпустите — повернуть куб · $pops';
    } else if (line.steering != Steering.top) {
      text = line.steering == Steering.front ? 'Передний стакан' : 'Задний стакан';
    }
    if (text == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        key: const ValueKey('cube-line'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: Palette.panelStrong,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Palette.line),
        ),
        child: LText(text, style: Type.body(12.5, weight: FontWeight.w700)),
      ),
    );
  }
}
