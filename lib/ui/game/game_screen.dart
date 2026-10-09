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
import '../style.dart';
import '../widgets/controls.dart';
import 'hud.dart';
import 'level_banner.dart';
import 'tutorial.dart';

enum _Status { playing, paused, over, done }

const _slotNames = ['Верхний', 'Правый', 'Нижний', 'Левый'];

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
    this.onCheckpoint,
    this.tutorial = false,
    this.onTutorialDone,
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
  final ValueChanged<RunSave?>? onCheckpoint;
  final bool tutorial;
  final VoidCallback? onTutorialDone;

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

  bool get _acceptsInput => _status == _Status.playing && !widget.blocked && !(_banner?.blocking ?? false);

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
      _status = _Status.paused;
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
    if (!oldWidget.blocked && widget.blocked) {
      _pads.releaseAll();
      _checkpoint();
    }
    // Keys go back to the game once the settings over it are closed.
    if (oldWidget.blocked && !widget.blocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
    if (state == AppLifecycleState.resumed) return;
    _pads.releaseAll();
    if (_status == _Status.playing) _setStatus(_Status.paused);
    _checkpoint();
  }

  void _setStatus(_Status status) => setState(() => _status = status);

  GameEngine _newEngine(RunPlan plan) => GameEngine(config: plan.config)..setRamp(plan.ramp);

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
    required double seconds,
    required bool blocking,
    VoidCallback? then,
  }) {
    _bannerId++;
    setState(() {
      _banner = _BannerState(
        data: BannerData(id: _bannerId, kicker: kicker, title: title, sub: sub, colours: colours),
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
  }

  void _campaignDone() {
    _finished = true;
    _recordRun(completed: true);
    _setStatus(_Status.done);
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
    final to = campaignLevels[next];
    _showBanner(
      kicker: 'Уровень ${index + 1} пройден',
      title: '${formatNumber(levelScore)} очков',
      sub: 'Дальше: ${to.colours} цв. · ${to.glasses} ст. · цель ${formatNumber(to.target)}',
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
        title: '${to.colours} цвета',
        sub: 'стаканы снова по одному',
        colours: _stageColours(to.colours),
        seconds: 2.2,
        blocking: true,
      );
    } else {
      _engine.setSteps(to.activeStep, to.inactiveStep);
      if (to.glasses > from.glasses) {
        _engine.addGlass();
        _showBanner(
          kicker: 'Новый стакан',
          title: '${to.glasses} стакана',
          sub: 'первая фигура уже в пути',
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
      setState(() {
        _tutorialStep = 0;
        _tutorialPerformed = false;
        _tutorialMatch = false;
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

  bool _tutorialAllows(GameAction action) =>
      !widget.tutorial ||
      (_engine.phase == GamePhase.playing &&
          switch (_tutorialStep) {
            1 => action == GameAction.moveLeft || action == GameAction.moveRight,
            2 => action == GameAction.rotateCW || action == GameAction.rotateCCW,
            3 => action == GameAction.hardDrop,
            4 =>
              action == GameAction.glassLeft || action == GameAction.glassRight || action == GameAction.glassOpposite,
            _ => false,
          });
  void _performed() {
    if (widget.tutorial && !_tutorialPerformed) {
      setState(() => _tutorialPerformed = true);
    }
  }

  void _tutorialNext() {
    if (_tutorialStep == tutorialLessons.length - 1) {
      widget.onTutorialDone?.call();
      return;
    }
    _pads.releaseAll();
    setState(() {
      _tutorialStep++;
      _tutorialPerformed = false;
    });
    if (_tutorialStep == 3) {
      _engine = _newEngine(_plan);
      _fx.reset(_engine.activeSide);
      _engine.board.paintCenter(['. Y . . . . . . . .', 'B . . . . . . . . .', 'R R . . . . . . . .']);
      _engine.incoming.put(Side.top, Piece([BlockColor.red, BlockColor.blue, BlockColor.yellow]), column: 2);
    } else if (_tutorialStep == 4) {
      _engine.addGlass();
    }
  }

  // ------------------------------------------------------------------ input

  @override
  void move(int direction, {required bool toWall}) {
    if (!_acceptsInput || !_tutorialAllows(direction < 0 ? GameAction.moveLeft : GameAction.moveRight)) {
      return;
    }
    final before = _engine.activePiece?.column;
    _engine.moveActive(toWall ? direction * _engine.config.boardSize : direction);
    if (_engine.activePiece?.column != before) _performed();
  }

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
          _performed();
        }
        if (_engine.activeSide != beforeSide) _performed();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.blocked) return KeyEventResult.ignored;
    if (_status != _Status.playing &&
        event.physicalKey != PhysicalKeyboardKey.escape &&
        event.physicalKey != PhysicalKeyboardKey.keyP) {
      return KeyEventResult.ignored;
    }
    final action = actionForKey(widget.settings.bindings, event.physicalKey);
    if (action == null) return KeyEventResult.ignored;
    // Held keys repeat through the pad controller, not through the system.
    if (event is KeyDownEvent) {
      _pads.down(action);
    } else if (event is KeyUpEvent) {
      _pads.up(action);
    }
    return KeyEventResult.handled;
  }

  /// Tapping a glass brings it to the top.
  void _onTapStage(TapUpDetails details, double side) {
    if (!_acceptsInput || (widget.tutorial && _tutorialStep != 4)) return;
    final before = _engine.activeSide;
    final zone = FieldGeometry(side, _engine.config, devicePixelRatio: _pixelRatio).zoneAt(details.localPosition);
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
    final frozen = widget.blocked;
    final holding = frozen || (_banner?.blocking ?? false);
    if (frozen) _pads.releaseAll();
    _fx.screenShake = settings.effects.screenShake && !_reduceMotion;
    _fx.turnSeconds = _reduceMotion ? 0 : settings.effects.turnMs / 1000;
    _fx.explosion = settings.effects.explosion;

    if (_status == _Status.playing && !holding) {
      _pads.update(seconds);
      if (!widget.tutorial || _engine.phase != GamePhase.playing) {
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
        case SpeedUp(:final level):
          setState(() => _callout = Callout.speed(id: ++_calloutId, speed: level + 1));
        case GameEnded(:final side):
          if (!_finished) _gameOver(side);
        default:
          break;
      }
    }

    if (widget.tutorial && _tutorialMatch && _tutorialStep == 3 && _engine.phase == GamePhase.playing) {
      _performed();
    }

    if (_isCampaign &&
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

  List<GameAction> get _lessonActions => switch (_tutorialStep) {
    1 => [GameAction.moveLeft, GameAction.moveRight],
    2 => [GameAction.rotateCW, GameAction.rotateCCW],
    3 => [GameAction.hardDrop],
    4 => [GameAction.glassLeft, GameAction.glassRight, GameAction.glassOpposite],
    _ => [],
  };
  List<String> get _tutorialControls => [
    for (final side in [false, true])
      for (final slot in PadSlot.values)
        if (_lessonActions.contains((side ? widget.settings.rightPad : widget.settings.leftPad)[slot]))
          '${side ? 'Правая' : 'Левая'} крестовина · ${slot.label.toLowerCase()}',
  ];

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    // Whatever made this build happen may have changed the picture too.
    _still = 0;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        children: [
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.tutorial ? 'Обучение' : modeTitle(_mode),
                              style: Type.body(14, weight: FontWeight.w800),
                            ),
                          ),
                          TextButton(onPressed: _togglePause, child: const Text('Пауза')),
                          TextButton(onPressed: widget.onSettings, child: const Text('Настройки')),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, box) {
                          // A whole number of physical pixels, set on a whole
                          // pixel: the field is then drawn pixel for pixel.
                          final ratio = _pixelRatio;
                          double snap(double logical) => (logical * ratio).floorToDouble() / ratio;
                          final side = snap(math.min(box.maxWidth, box.maxHeight));
                          return Padding(
                            padding: EdgeInsets.only(
                              left: snap((box.maxWidth - side) / 2),
                              top: snap((box.maxHeight - side) / 2),
                            ),
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: SizedBox.square(dimension: side, child: _stage(side)),
                            ),
                          );
                        },
                      ),
                    ),
                    if (widget.tutorial)
                      SizedBox(
                        height: math.min(constraints.maxHeight * 0.4, 250),
                        child: TutorialPanel(
                          step: _tutorialStep,
                          performed: _tutorialPerformed,
                          controls: _lessonActions.isNotEmpty && _tutorialControls.isEmpty
                              ? 'Действие не назначено. Попробуйте его кнопкой ниже или назначьте в настройках.'
                              : _tutorialControls.join(' / '),
                          onPractice: _lessonActions.isNotEmpty && _tutorialControls.isEmpty
                              ? () {
                                  _pads.down(_lessonActions.first);
                                  _pads.up(_lessonActions.first);
                                }
                              : null,
                          onNext: _tutorialNext,
                          onSkip: () => widget.onTutorialDone?.call(),
                        ),
                      ),
                    RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: PadSurface(settings: settings, onDown: _pads.down, onUp: _pads.up),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (!widget.blocked && _status == _Status.paused) _dialog(_pauseDialog()),
          if (!widget.blocked && _status == _Status.over && _result != null) _dialog(_overDialog(_result!)),
          if (!widget.blocked && _status == _Status.done && _result != null) _dialog(_doneDialog(_result!)),
        ],
      ),
    );
  }

  Widget _stage(double side) {
    final config = _engine.config;
    final corner = side * config.armLength / config.gridSize;
    final base = math.max(10.0, side / 40);
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
                  devicePixelRatio: _pixelRatio,
                  repaint: _repaint,
                ),
                size: Size.square(side),
              ),
            ),
          ),
        ),
        if (!widget.tutorial)
          Positioned.fill(
            child: RepaintBoundary(
              child: ValueListenableBuilder<HudState>(
                valueListenable: _hud,
                builder: (context, hud, _) =>
                    Hud(hud: hud, callout: _callout, options: widget.settings.hud, corner: corner, base: base),
              ),
            ),
          ),
        if (banner != null)
          Positioned(
            top: side * 0.3,
            left: side * 0.1,
            right: side * 0.1,
            child: LevelBanner(banner: banner.data),
          ),
      ],
    );
  }

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
              child: SingleChildScrollView(padding: const EdgeInsets.all(16), child: card),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _pauseDialog() {
    final campaign = _isCampaign;
    final custom = widget.session is CustomSession;
    final level = campaign ? campaignLevels[_campaignLevel] : null;
    return DialogCard(
      kicker:
          '${widget.tutorial ? 'Обучение' : modeTitle(_mode)}${campaign ? ' · уровень ${_campaignLevel + 1} из ${campaignLevels.length}' : ''}',
      title: 'Пауза',
      note: level == null
          ? null
          : 'Цель ${formatNumber(level.target)} очков · ${level.colours} цв. · ${level.glasses} ст.',
      children: [
        _buttons([
          GoButton(label: 'Продолжить', expand: true, onPressed: _togglePause),
          OutlineButton(label: campaign ? 'Повторить уровень' : 'Заново', onPressed: _retry),
          OutlineButton(label: 'Настройки', onPressed: widget.onSettings),
          if (custom && !widget.tutorial)
            OutlineButton(label: 'Изменить режим', onPressed: () => _leave(widget.onCustomise)),
          if (!custom) OutlineButton(label: 'К уровням', onPressed: () => _leave(widget.onLevels)),
          if (!widget.tutorial) OutlineButton(label: 'В меню', onPressed: () => _leave(widget.onExit)),
          OutlineButton(
            label: widget.tutorial ? 'В меню' : 'Завершить партию',
            onPressed: () => _leave(widget.onExit, save: false),
          ),
        ]),
      ],
    );
  }

  Widget _overDialog(RunRecord record) {
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
        _buttons([
          GoButton(label: campaign ? 'Повторить уровень' : 'Заново', expand: true, onPressed: _retry),
          if (custom && !widget.tutorial)
            OutlineButton(label: 'Изменить режим', onPressed: () => _leave(widget.onCustomise)),
          if (campaign) OutlineButton(label: 'К уровням', onPressed: widget.onLevels),
          OutlineButton(label: 'В меню', onPressed: () => _leave(widget.onExit)),
        ]),
      ],
    );
  }

  Widget _doneDialog(RunRecord record) => DialogCard(
    kicker: 'Кампания',
    title: 'Кампания пройдена',
    note: 'Все ${campaignLevels.length} уровней позади. Безумие открыто.',
    children: [
      _RunStats(record: record, campaign: true),
      const SizedBox(height: 14),
      _buttons([
        GoButton(label: 'Безумие', expand: true, onPressed: widget.onInsane),
        OutlineButton(label: 'К уровням', onPressed: widget.onLevels),
        OutlineButton(label: 'В меню', onPressed: () => _leave(widget.onExit)),
      ]),
    ],
  );

  Widget _buttons(List<Widget> buttons) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    mainAxisSize: MainAxisSize.min,
    children: [for (final button in buttons) Padding(padding: const EdgeInsets.only(bottom: 8), child: button)],
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
    return Column(
      children: [
        for (final (label, value) in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
                Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
              ],
            ),
          ),
      ],
    );
  }
}
