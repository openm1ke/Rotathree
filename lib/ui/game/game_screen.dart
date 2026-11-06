import '../i18n/strings.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../game/config/campaign.dart';
import '../../game/config/modes.dart';
import '../../game/engine/game_engine.dart';
import '../../game/engine/game_event.dart';
import '../../game/engine/rotation_transform.dart';
import '../../game/model/side.dart';
import '../../game/model/color.dart';
import '../../game/model/piece.dart';
import '../../game/session.dart';
import '../../game/state/game_state.dart';
import '../audio/sound_effects.dart';
import '../data/bindings.dart';
import '../data/progress.dart';
import '../data/settings.dart';
import '../data/stats.dart';
import '../data/run_save.dart';
import '../field/effects.dart';
import '../field/field_painter.dart';
import '../format.dart';
import '../input/pad_surface.dart';
import '../input/game_action.dart';
import '../input/pad_controller.dart';
import '../layout.dart';
import '../style.dart';
import '../widgets/armed_layer.dart';
import '../widgets/controls.dart';
import 'hud.dart';
import 'campaign_progress.dart';
import 'level_banner.dart';
import 'play_layout.dart';
import 'tutorial.dart';

enum _Status { playing, paused, over, done }

const _slotNames = ['Верхний', 'Правый', 'Нижний', 'Левый'];

/// A tutorial lesson, once its action is done, moves on after this long.
const _tutorialNextDelay = Duration(milliseconds: 900);

/// A lesson still waiting after this long says again what to press.
const _tutorialIdle = Duration(seconds: 4);

/// On the first screen the piece can be moved, turned and dropped already:
/// a player who tries all three is taken straight to the cross.
const _introActions = [
  GameAction.moveLeft,
  GameAction.moveRight,
  GameAction.rotateCW,
  GameAction.rotateCCW,
  GameAction.hardDrop,
];

enum _Basic { move, rotate, drop }

/// The basic each early lesson teaches: a lesson already tried is skipped.
const _basicOfLesson = {1: _Basic.move, 2: _Basic.rotate, 3: _Basic.drop};

/// What each tutorial lesson asks for; the first and the last ask for none.
/// The cross is turned left or right: with two glasses there is none opposite
/// yet, so that button would do nothing here.
List<GameAction> _lessonActionsOf(int lesson) => switch (lesson) {
  1 => const [GameAction.moveLeft, GameAction.moveRight],
  2 => const [GameAction.rotateCW, GameAction.rotateCCW],
  3 => const [GameAction.hardDrop],
  4 => const [GameAction.glassLeft, GameAction.glassRight],
  _ => const [],
};

/// A banner on the field and how long it still shows.
class _BannerState {
  _BannerState({required this.data, required this.left, required this.blocking, this.then});

  final BannerData data;
  double left;

  /// Whether the game stands still while the banner shows.
  final bool blocking;

  /// What happens once the banner is gone.
  final VoidCallback? then;
}

/// Tells the field to draw again: the frame loop calls [touch] every frame.
class _Repaint extends ChangeNotifier {
  void touch() => notifyListeners();
}

/// The playable screen: owns the engine, runs it from the frame loop, drives
/// the campaign's levels and turns key presses and taps into engine input.
/// The parent re-keys it for every new game, so a session never changes under
/// it.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.session,
    required this.settings,
    required this.progress,
    required this.blocked,
    required this.onSettings,
    required this.onExit,
    required this.onLevels,
    required this.onRetry,
    required this.onInsane,
    required this.onCustomise,
    required this.onRecord,
    required this.onProgress,
    this.restore,
    this.resumeImmediately = false,
    this.onCheckpoint,
    this.tutorial = false,
    this.onTutorialDone,
    this.onPauseChanged,
    this.onToggleMusic,
  });

  final Session session;
  final Settings settings;
  final Progress progress;

  /// True while the settings are open over the game: nothing moves.
  final bool blocked;
  final VoidCallback onSettings;

  /// Back to the main menu.
  final VoidCallback onExit;

  /// Back to the campaign's levels.
  final VoidCallback onLevels;

  /// A new game of the given session: the campaign level, or the same run.
  final ValueChanged<Session> onRetry;

  /// Opens Insane once the campaign is finished.
  final VoidCallback onInsane;

  /// Back to the custom setup.
  final VoidCallback onCustomise;
  final ValueChanged<RunRecord> onRecord;
  final ValueChanged<Progress> onProgress;
  final RunSave? restore;
  /// A direct home-screen campaign shortcut resumes without another pause dialog.
  final bool resumeImmediately;
  final ValueChanged<RunSave?>? onCheckpoint;
  final bool tutorial;
  /// `true`: Play on the last lesson; `false` when the player skipped.
  final ValueChanged<bool>? onTutorialDone;
  final ValueChanged<bool>? onPauseChanged;

  /// The music switch beside the gear.
  final VoidCallback? onToggleMusic;

  @override
  State<GameScreen> createState() => GameScreenState();
}

class GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver
    implements PadSink {
  /// Longest frame the game will simulate in one go (hitches, tab switches).
  static const _maxFrameSeconds = 0.05;

  late final Ticker _ticker = createTicker(_onTick);
  late final RunPlan _plan = planFor(widget.session);
  late GameEngine _engine;

  /// The engine, for the tests of the game screen.
  @visibleForTesting
  GameEngine get engine => _engine;

  /// Opens a lesson of the tutorial at once, for the pictures of it.
  @visibleForTesting
  void debugEnterLesson(int step) => _enterLesson(step);
  late final PadController _pads;
  final Effects _fx = Effects();
  final FieldAssets _assets = FieldAssets();
  final _Repaint _repaint = _Repaint();
  final ValueNotifier<HudState> _hud = ValueNotifier(HudState.empty);
  late Progress _progressNow;
  final FocusNode _focus = FocusNode();

  _Status _status = _Status.playing;
  RunRecord? _result;
  int _overSlot = 0;

  /// The campaign level being played; -1 in the other modes.
  late int _campaignLevel;
  int _levelBase = 0;
  RunTotals _carry = RunTotals.none;
  bool _completing = false;
  bool _finished = false;
  late final String _runId = widget.restore?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  int? _pendingLevel;
  double _saveCharge = 0;
  int _tutorialStep = 0;
  bool _tutorialPerformed = false;
  bool _tutorialMatch = false;

  /// What to press, said again after a wrong button or a wait.
  String? _tutorialHint;

  /// The player has waited: the call to the pads beats faster.
  bool _urging = false;

  /// The basics the player tried on the first screen.
  Set<_Basic> _tried = {};

  /// The second glass comes once the field is still enough to build it.
  bool _glassPending = false;
  Timer? _autoNext;
  Timer? _idle;

  /// The combo of the match whose cells are bursting, for the pitch of the pop.
  int _poppingCombo = 1;
  _BannerState? _banner;
  int _bannerId = 0;
  Callout? _callout;
  int _calloutId = 0;
  Duration _last = Duration.zero;

  /// Frames in a row whose picture could not have changed.
  int _still = 0;
  int _drawnPalette = -1;
  double _pixelRatio = 1;
  bool _reduceMotion = false;

  bool get _isCampaign => widget.session is CampaignSession;

  bool _appActive = true;
  bool get _acceptsInput =>
      _appActive && _status == _Status.playing && !widget.blocked && !(_banner?.blocking ?? false);

  ModeId get _mode => switch (widget.session) {
    CampaignSession() => ModeId.campaign,
    InsaneSession() => ModeId.insane,
    CustomSession() => ModeId.custom,
  };

  RunTotals get _totals => RunTotals(
    score: _carry.score + _engine.state.score,
    pieces: _carry.pieces + _engine.state.piecesPlaced,
    matches: _carry.matches + _engine.state.matches,
    bestCombo: math.max(_carry.bestCombo, _engine.state.bestCombo),
    seconds: _carry.seconds + _engine.state.elapsedSeconds,
  );

  @override
  void initState() {
    super.initState();
    _engine = _newEngine(_plan);
    _campaignLevel = switch (widget.session) {
      CampaignSession(:final level) => level,
      _ => -1,
    };
    _progressNow = widget.progress;
    final save = widget.restore;
    if (save != null) {
      _engine.restoreSnapshot(save.engine);
      _carry = save.carry;
      _levelBase = save.levelBase;
      _status = widget.resumeImmediately ? _Status.playing : _Status.paused;
      final b = save.banner;
      if (b != null) {
        _pendingLevel = b.pendingLevel;
        _completing = b.pendingLevel != null;
        _banner = _BannerState(
          data: BannerData(
            id: ++_bannerId,
            kicker: b.kicker,
            title: b.title,
            sub: b.sub,
            colours: _stageColours(b.colours),
            kind: b.pendingLevel != null
                ? BannerKind.passed
                : b.colours > 0
                ? BannerKind.stage
                : BannerKind.level,
          ),
          left: b.left,
          blocking: b.blocking,
          then: b.pendingLevel == null ? null : () => _advanceTo(b.pendingLevel!),
        );
      }
    }
    _fx.reset(_engine.activeSide);
    _hud.value = _currentHud();
    _pads = PadController(
      sink: this,
      dasMs: () => widget.settings.handling.dasMs,
      arrMs: () => widget.settings.handling.arrMs,
    );
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
    _checkpoint();
  }

  @override
  void didUpdateWidget(GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.effects != widget.settings.effects) _still = 0;
    if (!oldWidget.blocked && widget.blocked) {
      _pads.releaseAll();
      _checkpoint();
    }
    // Keys go back to the game once the settings over it are closed, and a
    // lesson done just before they opened goes on.
    if (oldWidget.blocked && !widget.blocked) {
      if (_tutorialPerformed && _lessonActions.isNotEmpty) {
        _autoNext?.cancel();
        _autoNext = Timer(_tutorialNextDelay, () {
          if (mounted && _tutorialPerformed) _tutorialNext();
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoNext?.cancel();
    _idle?.cancel();
    _focus.dispose();
    _ticker.dispose();
    _hud.dispose();
    _repaint.dispose();
    _assets.dispose();
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
    _ticker.stop();
    _pads.releaseAll();
    if (!widget.tutorial && _status == _Status.playing) {
      _setStatus(_Status.paused);
    }
    _checkpoint();
  }

  void _setStatus(_Status status) {
    setState(() => _status = status);
    widget.onPauseChanged?.call(status == _Status.paused);
  }

  GameEngine _newEngine(RunPlan plan) => GameEngine(config: plan.config)
    ..setRamp(plan.ramp)
    ..instantDrop = widget.settings.handling.instantDrop;

  /// Replaces the engine, keeping the totals of the run so far.
  void _swapEngine(GameEngine next) {
    _carry = _totals;
    _engine = next;
    _fx.reset(_engine.activeSide);
  }

  HudState _currentHud() {
    final t = _totals;
    final level = _isCampaign ? campaignLevels[_campaignLevel] : null;
    return HudState(
      score: t.score,
      combo: _engine.state.combo,
      bestCombo: t.bestCombo,
      matches: t.matches,
      pieces: t.pieces,
      seconds: t.seconds.floor(),
      level: _isCampaign ? _campaignLevel + 1 : 0,
      into: _isCampaign ? _engine.state.score - _levelBase : 0,
      target: level?.target ?? 0,
      colours: level?.colours ?? _engine.config.numberOfColors,
      glasses: _engine.sides.length,
      speed: _plan.ramp != null ? _engine.state.speedLevel + 1 : 0,
    );
  }

  void _showBanner({
    required String kicker,
    required String title,
    String? sub,
    List<Color> colours = const [],
    BannerKind kind = BannerKind.level,
    required double seconds,
    required bool blocking,
    VoidCallback? then,
  }) {
    _bannerId++;
    setState(() {
      _banner = _BannerState(
        data: BannerData(id: _bannerId, kicker: kicker, title: title, sub: sub, colours: colours, kind: kind),
        left: seconds,
        blocking: blocking,
        then: then,
      );
    });
  }

  List<Color> _stageColours(int count) => widget.settings.palettes.activeSet.colours.take(count).toList();

  void _recordRun({required bool completed, bool interrupted = false}) {
    if (widget.tutorial) return;
    final t = _totals;
    final record = RunRecord(
      id: _runId,
      mode: _mode,
      at: DateTime.now().millisecondsSinceEpoch,
      score: t.score,
      pieces: t.pieces,
      matches: t.matches,
      bestCombo: t.bestCombo,
      seconds: t.seconds,
      level: _isCampaign ? (completed ? campaignLast + 1 : _campaignLevel + 1) : _engine.state.speedLevel + 1,
      completed: completed,
      interrupted: interrupted,
    );
    widget.onRecord(record);
    widget.onCheckpoint?.call(null);
    setState(() => _result = record);
  }

  void _gameOver(Side side) {
    _finished = true;
    _overSlot = RotationTransform.slotOfSide(_engine.activeSide, side).index;
    _recordRun(completed: false);
    _setStatus(_Status.over);
    SoundEffects.instance.play(SoundGroup.over);
  }

  void _campaignDone() {
    _finished = true;
    _recordRun(completed: true);
    _setStatus(_Status.done);
    SoundEffects.instance.play(SoundGroup.level);
  }

  /// A campaign level is finished: keep its best score, open the next one, and
  /// announce it. The game stands still while the banner shows.
  void _completeLevel() {
    _completing = true;
    final index = _campaignLevel;
    final levelScore = _engine.state.score - _levelBase;
    _progressNow = _progressNow.levelFinished(index, levelScore);
    widget.onProgress(_progressNow);
    if (index == campaignLast) {
      _campaignDone();
      return;
    }
    final next = index + 1;
    _pendingLevel = next;
    SoundEffects.instance.play(SoundGroup.level);
    final to = campaignLevels[next];
    _showBanner(
      kicker: 'Уровень ${index + 1} пройден',
      title: formatPoints(levelScore),
      sub: 'Дальше: ${to.colours} цв. · ${to.glasses} ст. · цель ${formatNumber(to.target)}',
      kind: BannerKind.passed,
      seconds: 2.2,
      blocking: true,
      then: () => _advanceTo(next),
    );
  }

  /// Moves to the next campaign level. A new number of colours starts a fresh
  /// board with one glass; a new glass grows out of the cross while the falling
  /// goes on.
  void _advanceTo(int next) {
    _completing = false;
    _pendingLevel = null;
    final from = campaignLevels[_campaignLevel];
    final to = campaignLevels[next];
    setState(() => _campaignLevel = next);
    if (startsStage(next)) {
      _swapEngine(_newEngine(RunPlan(config: levelConfig(to))));
      _levelBase = 0;
      _showBanner(
        kicker: 'Новый этап',
        title: formatColours(to.colours),
        sub: 'стаканы снова по одному',
        colours: _stageColours(to.colours),
        kind: BannerKind.stage,
        seconds: 2.2,
        blocking: true,
      );
    } else {
      _engine.setSteps(to.activeStep, to.inactiveStep);
      if (to.glasses > from.glasses) {
        _engine.addGlass();
        _showBanner(
          kicker: 'Новый стакан',
          title: '${to.glasses}-й стакан',
          sub: 'первая фигура уже в пути',
          kind: BannerKind.glass,
          seconds: 1.6,
          blocking: false,
        );
      } else {
        _showBanner(
          kicker: 'Уровень ${next + 1}',
          title: 'цель ${formatNumber(to.target)}',
          sub: '${to.glasses} ст. · ${to.colours} цв.',
          seconds: 1.6,
          blocking: false,
        );
      }
      _levelBase = _engine.state.score;
    }
  }

  void _togglePause() {
    if (widget.tutorial) {
      handleBack();
      return;
    }
    if (_status == _Status.playing) {
      _pads.releaseAll();
      _setStatus(_Status.paused);
      _checkpoint();
    } else if (_status == _Status.paused) {
      _setStatus(_Status.playing);
    }
  }

  void _retry() {
    if (widget.tutorial) {
      _pads.releaseAll();
      _engine = _newEngine(_plan);
      _fx.reset(_engine.activeSide);
      _autoNext?.cancel();
      _idle?.cancel();
      _tried = {};
      _glassPending = false;
      setState(() {
        _tutorialStep = 0;
        _tutorialPerformed = false;
        _tutorialMatch = false;
        _tutorialHint = null;
        _urging = false;
        _status = _Status.playing;
      });
      return;
    }
    if (!_finished) _recordRun(completed: false, interrupted: true);
    _finished = true;
    widget.onRetry(_isCampaign ? CampaignSession(_campaignLevel) : widget.session);
  }

  void _checkpoint() {
    if (widget.tutorial || _finished || _engine.isGameOver || widget.onCheckpoint == null) {
      return;
    }
    final b = _banner;
    widget.onCheckpoint!(
      RunSave(
        id: _runId,
        session: _isCampaign ? CampaignSession(_campaignLevel) : widget.session,
        engine: _engine.snapshot(),
        carry: _carry,
        levelBase: _levelBase,
        savedAt: DateTime.now().millisecondsSinceEpoch,
        banner: b == null
            ? null
            : SavedBanner(
                kicker: b.data.kicker,
                title: b.data.title,
                sub: b.data.sub,
                left: b.left,
                blocking: b.blocking,
                pendingLevel: _pendingLevel,
                colours: b.data.colours.length,
              ),
      ),
    );
    _saveCharge = 0;
  }

  void _leave(VoidCallback destination, {bool save = true}) {
    _pads.releaseAll();
    if (save) {
      _checkpoint();
    } else if (!_finished) {
      _recordRun(completed: false, interrupted: true);
      _finished = true;
    }
    destination();
  }

  /// Back captures the exact field before returning to the menu.
  void handleBack() => _leave(widget.onExit);

  /// The last screen is the game itself: pieces fall and every control
  /// works, until the player chooses to play for real.
  bool get _freePlay => widget.tutorial && _tutorialStep == tutorialLessons.length - 1;

  bool _tutorialAllows(GameAction action) =>
      !widget.tutorial ||
      _freePlay ||
      (_engine.phase == GamePhase.playing &&
          (_tutorialStep == 0 ? _introActions : _lessonActionsOf(_tutorialStep)).contains(action));

  void _tryBasic(_Basic basic) {
    if (widget.tutorial && _tutorialStep == 0) _tried.add(basic);
  }

  /// A button that this lesson does not take: say which one does.
  void _wrongInput(GameAction action) {
    final asked = _lessonActionsOf(_tutorialStep);
    if (!widget.tutorial || _tutorialPerformed || asked.isEmpty || asked.contains(action)) return;
    setState(() {
      _tutorialHint = 'Нажми подсвеченную кнопку';
      _urging = true;
    });
  }

  /// A lesson's action is done: the next lesson follows by itself after a moment.
  void _performed() {
    if (!widget.tutorial || _tutorialPerformed || _lessonActionsOf(_tutorialStep).isEmpty) return;
    _idle?.cancel();
    setState(() {
      _tutorialPerformed = true;
      _urging = false;
    });
    final at = _tutorialStep;
    _autoNext?.cancel();
    _autoNext = Timer(_tutorialNextDelay, () {
      if (mounted && _tutorialStep == at && _tutorialPerformed) _tutorialNext();
    });
  }

  /// A lesson still waiting says again what to press, and the call beats faster.
  void _armIdle() {
    _idle?.cancel();
    if (!widget.tutorial || _lessonActionsOf(_tutorialStep).isEmpty || _tutorialPerformed) return;
    _idle = Timer(_tutorialIdle, () {
      if (!mounted || _tutorialPerformed) return;
      if (widget.blocked || !_appActive) return _armIdle();
      setState(() {
        _urging = true;
        _tutorialHint ??= 'Нажми подсвеченную кнопку';
      });
    });
  }

  void _enterLesson(int next) {
    _pads.releaseAll();
    _autoNext?.cancel();
    setState(() {
      _tutorialStep = next;
      _tutorialPerformed = false;
      _tutorialHint = null;
      _urging = false;
    });
    if (next == 3) {
      _engine = _newEngine(_plan);
      _fx.reset(_engine.activeSide);
      _engine.board.paintCenter(['. Y . . . . . . . .', 'B . . . . . . . . .', 'R R . . . . . . . .']);
      _engine.incoming.put(Side.top, Piece([BlockColor.red, BlockColor.blue, BlockColor.yellow]), column: 2);
    } else if (next == 4) {
      _glassPending = true;
    }
    _armIdle();
  }

  void _tutorialNext() {
    final last = tutorialLessons.length - 1;
    if (widget.blocked || _status != _Status.playing || (_tutorialStep > 0 && _tutorialStep < last && !_tutorialPerformed)) {
      return;
    }
    if (_tutorialStep == last) {
      widget.onTutorialDone?.call(true);
      return;
    }
    var next = _tutorialStep + 1;
    // A lesson whose action was already tried on the first screen is skipped.
    while (_tried.contains(_basicOfLesson[next])) {
      next++;
    }
    _enterLesson(next);
  }

  /// The tutorial has no lost game: a glass filled in its free play empties,
  /// and the player goes on with both glasses.
  void _refillTutorial() {
    _pads.releaseAll();
    _engine = _newEngine(_plan);
    _fx.reset(_engine.activeSide);
    if (_tutorialStep >= 4) _glassPending = true;
  }

  /// A pad button or a key: in a lesson, a button it does not take says
  /// which one does.
  void _inputDown(GameAction action) {
    if (action != GameAction.none && _status == _Status.playing) _wrongInput(action);
    _pads.down(action);
  }

  // ------------------------------------------------------------------ input

  @override
  void move(int direction, {required bool toWall}) {
    if (!_acceptsInput || !_tutorialAllows(direction < 0 ? GameAction.moveLeft : GameAction.moveRight)) {
      return;
    }
    final before = _engine.activePiece?.column;
    _engine.moveActive(toWall ? direction * _engine.config.boardSize : direction);
    if (_engine.activePiece?.column != before) {
      _tryBasic(_Basic.move);
      _performed();
    }
  }

  @override
  void release(GameAction action) {}

  @override
  void softDrop({required bool held}) =>
      _engine.setSoftDrop(held && _acceptsInput && _tutorialAllows(GameAction.softDrop));

  @override
  void press(GameAction action) {
    switch (action) {
      case GameAction.pause:
        _togglePause();
      case GameAction.restart:
        _retry();
      default:
        if (!_acceptsInput) {
          // On the result screens the drop key starts the next game.
          if ((_status == _Status.over || _status == _Status.done) && action == GameAction.hardDrop) {
            _retry();
          }
          return;
        }
        if (!_tutorialAllows(action)) return;
        final beforePiece = _engine.activePiece?.piece;
        final beforeSide = _engine.activeSide;
        switch (action) {
          case GameAction.rotateCW:
            _engine.rotateActive();
          case GameAction.rotateCCW:
            _engine.rotateActive(clockwise: false);
          case GameAction.hardDrop:
            _engine.dropActive();
          case GameAction.glassLeft:
            _engine.switchSide(-1);
          case GameAction.glassRight:
            _engine.switchSide(1);
          case GameAction.glassOpposite:
            _engine.switchSide(2);
          default:
            break;
        }
        if (_engine.activePiece?.piece != beforePiece &&
            (action == GameAction.rotateCW || action == GameAction.rotateCCW)) {
          _tryBasic(_Basic.rotate);
          _performed();
        }
        if (action == GameAction.hardDrop) _tryBasic(_Basic.drop);
        if (_engine.activeSide != beforeSide) _performed();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.blocked) return KeyEventResult.ignored;
    if (usesDesktopKeyboard && widget.tutorial && event is KeyDownEvent) {
      switch (event.logicalKey) {
        case LogicalKeyboardKey.enter || LogicalKeyboardKey.numpadEnter when node.hasPrimaryFocus:
          _tutorialNext();
          return KeyEventResult.handled;
        case LogicalKeyboardKey.backspace:
          widget.onTutorialDone?.call(false);
          return KeyEventResult.handled;
        case LogicalKeyboardKey.escape:
          handleBack();
          return KeyEventResult.handled;
      }
    }
    if (_status != _Status.playing &&
        event.physicalKey != PhysicalKeyboardKey.escape &&
        event.physicalKey != PhysicalKeyboardKey.keyP) {
      return KeyEventResult.ignored;
    }
    final action = actionForKey(widget.settings.bindings, event.physicalKey);
    if (action == null) return KeyEventResult.ignored;
    // Held keys repeat through the pad controller, not through the system.
    if (event is KeyDownEvent) {
      _inputDown(action);
    } else if (event is KeyUpEvent) {
      _pads.up(action);
    }
    return KeyEventResult.handled;
  }

  /// Tapping a glass brings it to the top.
  void _onTapStage(TapUpDetails details, double side) {
    if (!_acceptsInput || !_tutorialAllows(GameAction.glassRight)) return;
    final before = _engine.activeSide;
    final zone = FieldGeometry(
      side,
      _engine.config,
      devicePixelRatio: _pixelRatio,
      angle: _fx.viewAngle,
      sides: _engine.sides,
      focusSingleGlass: true,
      showNextPiece: widget.settings.hud.nextPiece && !widget.tutorial,
    ).zoneAt(details.localPosition);
    final slot = switch (zone) {
      FieldZone.right => Side.right,
      FieldZone.bottom => Side.bottom,
      FieldZone.left => Side.left,
      _ => null,
    };
    if (slot != null) {
      _engine.activateSide(RotationTransform.sideAtSlot(_engine.activeSide, slot));
      if (_engine.activeSide != before) _performed();
    }
  }

  // ------------------------------------------------------------------- frame

  void _onTick(Duration elapsed) {
    final seconds = math.min(_maxFrameSeconds, math.max(0.0, (elapsed - _last).inMicroseconds / 1e6));
    _last = elapsed;
    final settings = widget.settings;
    final frozen = widget.blocked || !_appActive;
    final holding = frozen || (_banner?.blocking ?? false);
    if (frozen) _pads.releaseAll();
    _fx.screenShake = settings.effects.screenShake && !_reduceMotion;
    // Glass navigation follows the explicit game setting on every platform.
    _fx.turnSeconds = settings.effects.turnMs / 1000;
    _fx.explosion = settings.effects.explosion;
    _fx.fieldBackground = settings.effects.fieldBackground;

    if (_status == _Status.playing && !holding) {
      _pads.update(seconds);
      if (!widget.tutorial || _engine.phase != GamePhase.playing || _freePlay) {
        _engine.update(seconds);
      }
    }

    // Banners share the pause/settings gate with gameplay.
    final banner = _banner;
    if (banner != null && _status == _Status.playing && !frozen) {
      banner.left -= seconds;
      if (banner.left <= 0) {
        setState(() => _banner = null);
        banner.then?.call();
      }
    }

    final events = _engine.drainEvents();
    _fx.consume(events, _engine);
    // Effects keep playing out on the result screens, but not under a pause.
    _fx.update(_status == _Status.paused || frozen ? 0 : seconds, _engine);

    for (final event in events) {
      switch (event) {
        case MatchScored(:final score, :final combo):
          if (widget.tutorial && _tutorialStep == 3) _tutorialMatch = true;
          setState(() => _callout = Callout.score(id: ++_calloutId, points: score, combo: combo));
          _poppingCombo = combo;
        case CellsPopped():
          SoundEffects.instance.pop(_poppingCombo);
        case PieceMoved(:final blocked):
          if (!blocked) SoundEffects.instance.play(SoundGroup.move);
        case PieceRotated(:final blocked):
          if (!blocked) SoundEffects.instance.play(SoundGroup.rotate);
        case SideSwitched():
          SoundEffects.instance.play(SoundGroup.turn);
        case PieceLanded():
          SoundEffects.instance.play(SoundGroup.land);
        case SpeedUp(:final level):
          setState(() => _callout = Callout.speed(id: ++_calloutId, speed: level + 1));
          SoundEffects.instance.play(SoundGroup.level);
        case GameEnded(:final side):
          if (widget.tutorial) {
            _refillTutorial();
          } else if (!_finished) {
            _gameOver(side);
          }
        default:
          break;
      }
    }

    if (widget.tutorial && _tutorialMatch && _tutorialStep == 3 && _engine.phase == GamePhase.playing) {
      _performed();
    }
    // Moved, turned and dropped on the first screen already: on to the cross.
    if (widget.tutorial &&
        _tutorialStep == 0 &&
        _tried.length == 3 &&
        _status == _Status.playing &&
        _engine.phase == GamePhase.playing) {
      _enterLesson(4);
    }
    if (_glassPending && _engine.phase == GamePhase.playing && _engine.addGlass() != null) _glassPending = false;

    // The tutorial's free play scores, but completes no level of the campaign.
    if (_isCampaign &&
        !widget.tutorial &&
        !_finished &&
        !_completing &&
        _acceptsInput &&
        _engine.phase == GamePhase.playing &&
        _engine.state.score - _levelBase >= campaignLevels[_campaignLevel].target) {
      _completeLevel();
    }

    _hud.value = _currentHud();
    if (_status == _Status.playing && !frozen) _saveCharge += seconds;
    if (_saveCharge >= 2 ||
        events.any(
          (event) => event is PieceLanded || event is MatchScored || event is GlassAdded || event is SpeedUp,
        )) {
      _checkpoint();
    }

    // A picture that cannot have changed is not drawn again: under a pause,
    // or once a game that stands still has played out its effects. Nothing
    // is rastered then, and the device can rest.
    final engineRunning = _status == _Status.playing && !holding;
    final effectsRunning = _status != _Status.paused && !frozen;
    _still = !engineRunning && (!effectsRunning || _fx.settled) ? _still + 1 : 0;
    if (_still <= 2 || _drawnPalette != BlockTones.revision) {
      _drawnPalette = BlockTones.revision;
      _repaint.touch();
    }
  }

  List<GameAction> get _lessonActions => widget.tutorial ? _lessonActionsOf(_tutorialStep) : const [];

  /// Whether a pad has a button for what the lesson asks.
  bool get _lessonHasButton => [widget.settings.leftPad, widget.settings.rightPad]
      .any((layout) => PadSlot.values.any((slot) => _lessonActions.contains(layout[slot])));

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    // The settings may change in a game, from its own settings page.
    _engine.instantDrop = settings.handling.instantDrop;
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final desktop = usesDesktopKeyboard;
    final lessonHasControl = desktop
        ? _lessonActions.any((action) => settings.bindings[action]!.isNotEmpty)
        : _lessonHasButton;
    // Whatever made this build happen may have changed the picture too.
    _still = 0;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      skipTraversal: desktop,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          SafeArea(
            child: ExcludeFocus(
              excluding: desktop && !widget.tutorial && _status != _Status.playing,
              child: PlayLayout(
                heading: widget.tutorial
                    // The same heading as the menus: a small arrow, the mode, the title.
                    ? ScreenHeading(
                        kicker: 'Режим',
                        title: 'Обучение',
                        onBack: handleBack,
                        actions: [
                          ?_soundButton,
                          GameIconButton(icon: Icons.settings_rounded, label: 'Настройки', onPressed: widget.onSettings),
                        ],
                      )
                    : Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            GameIconButton(icon: Icons.pause_rounded, label: 'Пауза', onPressed: _togglePause),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 6),
                                child: ValueListenableBuilder<HudState>(
                                  valueListenable: _hud,
                                  builder: (context, hud, _) => GameReadout(hud: hud, options: settings.hud, callout: _callout),
                                ),
                              ),
                            ),
                            if (_soundButton case final sound?) ...[sound, const SizedBox(width: 6)],
                            GameIconButton(icon: Icons.settings_rounded, label: 'Настройки', onPressed: widget.onSettings),
                          ],
                        ),
                      ),
                lesson: widget.tutorial
                    ? TutorialPanel(
                        step: _tutorialStep,
                        performed: _tutorialPerformed,
                        bindings: desktop ? settings.bindings : null,
                        actions: _lessonActions,
                        hint: desktop ? null : _tutorialHint,
                        urging: _urging,
                        onPractice: _lessonActions.isNotEmpty && !lessonHasControl
                            ? () {
                                _pads.down(_lessonActions.first);
                                _pads.up(_lessonActions.first);
                              }
                            : null,
                        onNext: _tutorialNext,
                        onSkip: () => widget.onTutorialDone?.call(false),
                      )
                    : null,
                progress: _isCampaign && !widget.tutorial
                    ? ValueListenableBuilder<HudState>(
                        valueListenable: _hud,
                        builder: (context, hud, _) => CampaignProgress(
                          level: hud.level, into: hud.into, target: hud.target, compact: !desktop,
                          animated: _status == _Status.playing && !widget.blocked && _appActive &&
                              !_reduceMotion && settings.effects.fieldBackground,
                        ),
                      )
                    : null,
                // A whole number of physical pixels, set on a whole pixel:
                // the field is then drawn pixel for pixel.
                snap: (logical) => (logical * _pixelRatio).floorToDouble() / _pixelRatio,
                stage: _stage,
                pads: desktop
                    ? null
                    : RepaintBoundary(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                          child: PadSurface(
                            settings: settings,
                            onDown: _inputDown,
                            onUp: _pads.up,
                            hint: _tutorialPerformed ? const [] : _lessonActions,
                          ),
                        ),
                      ),
              ),
            ),
          ),
          if (!widget.tutorial && !widget.blocked && _status == _Status.paused) GameDialog(child: _pauseDialog()),
          // Result screens open by themselves, under fingers still playing.
          if (!widget.blocked && _status == _Status.over && _result != null)
            GameDialog(child: ArmedLayer(builder: (context, armed) => _overDialog(_result!, armed: armed))),
          if (!widget.blocked && _status == _Status.done && _result != null)
            GameDialog(child: ArmedLayer(builder: (context, armed) => _doneDialog(_result!, armed: armed))),
        ],
      ),
    );
  }

  Widget _stage(double side) {
    final banner = _banner;
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) => _onTapStage(details, side),
            // The field changes every frame and nothing round it does: with a
            // layer of its own, only the field is recorded again.
            child: RepaintBoundary(
              child: CustomPaint(
                painter: FieldPainter(
                  engine: _engine,
                  fx: _fx,
                  assets: _assets,
                  focusSingleGlass: true,
                  showNextPiece: widget.settings.hud.nextPiece && !widget.tutorial,
                  nextPieceOpacity: widget.settings.hud.nextPieceOpacity,
                  devicePixelRatio: _pixelRatio,
                  reduceMotion: _reduceMotion,
                  repaint: _repaint,
                ),
                size: Size.square(side),
              ),
            ),
          ),
        ),
        if (banner != null)
          Positioned(
            top: side * 0.24,
            left: 0,
            right: 0,
            child: Center(
              child: IgnorePointer(
                child: Scaled(
                  scale: desktopScale(MediaQuery.sizeOf(context)),
                  child: LevelBanner(banner: banner.data),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _pauseDialog() {
    final campaign = _isCampaign;
    final custom = widget.session is CustomSession;
    final level = campaign ? campaignLevels[_campaignLevel] : null;
    return PauseCard(
      kicker:
          '${widget.tutorial ? 'Обучение' : modeTitle(_mode)}${campaign ? ' · уровень ${_campaignLevel + 1} из ${campaignLevels.length}' : ''}',
      note: level == null
          ? null
          : 'Цель ${formatPoints(level.target)} · ${level.colours} цв. · ${level.glasses} ст.',
      onResume: _togglePause,
      tiles: [
        PauseAction(icon: Icons.replay_rounded, label: campaign ? 'Повторить уровень' : 'Заново', onPressed: _retry),
        PauseAction(icon: Icons.tune_rounded, label: 'Настройки', onPressed: widget.onSettings),
        if (custom && !widget.tutorial)
          PauseAction(icon: Icons.edit_rounded, label: 'Изменить режим', onPressed: () => _leave(widget.onCustomise)),
        if (!custom) PauseAction(icon: Icons.grid_view_rounded, label: 'К уровням', onPressed: () => _leave(widget.onLevels)),
      ],
      links: [
        if (!widget.tutorial) PauseAction(icon: Icons.home_rounded, label: 'В меню', onPressed: () => _leave(widget.onExit)),
        PauseAction(
          icon: widget.tutorial ? Icons.home_rounded : Icons.flag_rounded,
          label: widget.tutorial ? 'В меню' : 'Завершить партию',
          danger: !widget.tutorial,
          onPressed: () => _leave(widget.onExit, save: false),
        ),
      ],
    );
  }

  Widget? get _soundButton => switch (widget.onToggleMusic) {
    final toggle? => SoundButton(on: widget.settings.audio.music || widget.settings.audio.sounds, onToggle: toggle),
    null => null,
  };

  Widget _overDialog(RunRecord record, {bool armed = true}) {
    final campaign = _isCampaign;
    final custom = widget.session is CustomSession;
    return DialogCard(
      kicker: modeTitle(_mode),
      title: 'Игра окончена',
      danger: true,
      note:
          '${_slotNames[_overSlot]} стакан заполнился до конца рукава.'
          '${campaign ? ' Уровень не пройден: начнём его заново или выберем другой.' : ''}',
      children: [
        _RunStats(record: record, campaign: campaign),
        const SizedBox(height: 14),
        _buttons(armed: armed, [
          GoButton(label: campaign ? 'Повторить уровень' : 'Заново', expand: true, onPressed: _retry),
          if (custom && !widget.tutorial)
            OutlineButton(label: 'Изменить режим', onPressed: () => _leave(widget.onCustomise)),
          if (campaign) OutlineButton(label: 'К уровням', onPressed: widget.onLevels),
          OutlineButton(label: 'В меню', onPressed: () => _leave(widget.onExit)),
        ]),
      ],
    );
  }

  Widget _doneDialog(RunRecord record, {bool armed = true}) => DialogCard(
    kicker: 'Кампания',
    title: 'Кампания пройдена',
    note: 'Все ${campaignLevels.length} уровней позади. Кошмар открыт.',
    children: [
      _RunStats(record: record, campaign: true),
      const SizedBox(height: 14),
      _buttons(armed: armed, [
        GoButton(label: 'Кошмар', expand: true, onPressed: widget.onInsane),
        OutlineButton(label: 'К уровням', onPressed: widget.onLevels),
        OutlineButton(label: 'В меню', onPressed: () => _leave(widget.onExit)),
      ]),
    ],
  );

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

/// The summary of a finished run.
class _RunStats extends StatelessWidget {
  const _RunStats({required this.record, required this.campaign});

  final RunRecord record;
  final bool campaign;

  @override
  Widget build(BuildContext context) {
    final rows = [
      if (campaign) ('Уровень', '${record.completed ? campaignLast + 1 : record.level}'),
      ('Очки', formatNumber(record.score)),
      ('Фигуры', '${record.pieces}'),
      ('Матчи', '${record.matches}'),
      ('Лучшее комбо', '×${record.bestCombo}'),
      ('Время', formatDuration(record.seconds)),
    ];
    Widget row((String, String) entry) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: LText(entry.$1, style: const TextStyle(fontSize: 14))),
          LText(entry.$2, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
    // Below 760 dp of height the numbers go into two columns, so that the
    // dialog stays whole on a low phone, as on the web.
    if (MediaQuery.sizeOf(context).height >= 760) return Column(children: [for (final entry in rows) row(entry)]);
    return Column(
      children: [
        for (var i = 0; i < rows.length; i += 2)
          Row(
            children: [
              Expanded(child: row(rows[i])),
              const SizedBox(width: 18),
              Expanded(child: i + 1 < rows.length ? row(rows[i + 1]) : const SizedBox()),
            ],
          ),
      ],
    );
  }
}
