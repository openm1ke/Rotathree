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
import '../../game/session.dart';
import '../../game/state/game_state.dart';
import '../data/bindings.dart';
import '../data/progress.dart';
import '../data/settings.dart';
import '../data/stats.dart';
import '../field/effects.dart';
import '../field/field_painter.dart';
import '../format.dart';
import '../input/dpad.dart';
import '../input/game_action.dart';
import '../input/pad_controller.dart';
import '../style.dart';
import '../widgets/controls.dart';
import 'hud.dart';
import 'level_banner.dart';

enum _Status { playing, paused, over, done }

const _slotNames = ['Верхний', 'Правый', 'Нижний', 'Левый'];

/// Points, pieces and so on, summed over the engines of one run.
class _Totals {
  const _Totals({
    this.score = 0,
    this.pieces = 0,
    this.matches = 0,
    this.bestCombo = 0,
    this.seconds = 0,
  });

  static const none = _Totals();

  final int score;
  final int pieces;
  final int matches;
  final int bestCombo;
  final double seconds;
}

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
  _Totals _carry = _Totals.none;
  bool _completing = false;
  bool _finished = false;
  _BannerState? _banner;
  int _bannerId = 0;
  Callout? _callout;
  int _calloutId = 0;
  Duration _last = Duration.zero;

  /// Frames in a row whose picture could not have changed.
  int _still = 0;
  int _drawnPalette = -1;
  double _pixelRatio = 1;

  bool get _isCampaign => widget.session is CampaignSession;

  bool get _acceptsInput => _status == _Status.playing && !(_banner?.blocking ?? false);

  ModeId get _mode => switch (widget.session) {
        CampaignSession() => ModeId.campaign,
        InsaneSession() => ModeId.insane,
        CustomSession() => ModeId.custom,
      };

  _Totals get _totals => _Totals(
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
    _fx.reset(_engine.activeSide);
    _hud.value = _currentHud();
    _pads = PadController(
      sink: this,
      dasMs: () => widget.settings.handling.dasMs,
      arrMs: () => widget.settings.handling.arrMs,
    );
    WidgetsBinding.instance.addObserver(this);
    _ticker.start();
  }

  @override
  void didUpdateWidget(GameScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
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
        data: BannerData(
          id: _bannerId,
          kicker: kicker,
          title: title,
          sub: sub,
          colours: colours,
        ),
        left: seconds,
        blocking: blocking,
        then: then,
      );
    });
  }

  List<Color> _stageColours(int count) =>
      widget.settings.palettes.activeSet.colours.take(count).toList();

  void _recordRun({required bool completed}) {
    final t = _totals;
    final record = RunRecord(
      id: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
      mode: _mode,
      at: DateTime.now().millisecondsSinceEpoch,
      score: t.score,
      pieces: t.pieces,
      matches: t.matches,
      bestCombo: t.bestCombo,
      seconds: t.seconds,
      level: _isCampaign
          ? (completed ? campaignLast + 1 : _campaignLevel + 1)
          : _engine.state.speedLevel + 1,
      completed: completed,
    );
    widget.onRecord(record);
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
    } else if (_status == _Status.paused) {
      _setStatus(_Status.playing);
    }
  }

  void _retry() {
    _finished = true;
    widget.onRetry(_isCampaign ? CampaignSession(_campaignLevel) : widget.session);
  }

  // ------------------------------------------------------------------ input

  @override
  void move(int direction, {required bool toWall}) {
    if (!_acceptsInput) return;
    _engine.moveActive(toWall ? direction * _engine.config.boardSize : direction);
  }

  @override
  void softDrop({required bool held}) => _engine.setSoftDrop(held);

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
          if ((_status == _Status.over || _status == _Status.done) &&
              action == GameAction.hardDrop) {
            _retry();
          }
          return;
        }
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
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.blocked) return KeyEventResult.ignored;
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
    if (_status != _Status.playing) return;
    final zone = FieldGeometry(side, _engine.config, devicePixelRatio: _pixelRatio)
        .zoneAt(details.localPosition);
    final slot = switch (zone) {
      FieldZone.right => Side.right,
      FieldZone.bottom => Side.bottom,
      FieldZone.left => Side.left,
      _ => null,
    };
    if (slot != null) {
      _engine.activateSide(RotationTransform.sideAtSlot(_engine.activeSide, slot));
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
    _fx.screenShake = settings.effects.screenShake;
    _fx.turnSeconds = settings.effects.turnMs / 1000;
    _fx.explosion = settings.effects.explosion;

    if (_status == _Status.playing && !holding) {
      _pads.update(seconds);
      _engine.update(seconds);
    }

    // Banners count down on their own clock.
    final banner = _banner;
    if (banner != null) {
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
          setState(() => _callout = Callout.score(id: ++_calloutId, points: score, combo: combo));
        case SpeedUp(:final level):
          setState(() => _callout = Callout.speed(id: ++_calloutId, speed: level + 1));
        case GameEnded(:final side):
          if (!_finished) _gameOver(side);
        default:
          break;
      }
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

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    _pixelRatio = MediaQuery.devicePixelRatioOf(context);
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
                final padSize = math.min(constraints.maxWidth * 0.36, 150.0);
                return Column(
                  children: [
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
                    // The pads are a layer of their own: the field is drawn
                    // again every frame, and they need not be.
                    RepaintBoundary(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            DPad(
                              layout: settings.leftPad,
                              size: padSize,
                              onDown: _pads.down,
                              onUp: _pads.up,
                            ),
                            DPad(
                              layout: settings.rightPad,
                              size: padSize,
                              onDown: _pads.down,
                              onUp: _pads.up,
                            ),
                          ],
                        ),
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
        Positioned.fill(
          child: RepaintBoundary(
            child: ValueListenableBuilder<HudState>(
              valueListenable: _hud,
              builder: (context, hud, _) => Hud(
                hud: hud,
                callout: _callout,
                bindings: widget.settings.bindings,
                options: widget.settings.hud,
                corner: corner,
                base: base,
                onPause: _togglePause,
                onOpenSettings: widget.onSettings,
              ),
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
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: card,
                  ),
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
      kicker: '${modeTitle(_mode)}${campaign ? ' · уровень ${_campaignLevel + 1} из ${campaignLevels.length}' : ''}',
      title: 'Пауза',
      note: level == null
          ? null
          : 'Цель ${formatNumber(level.target)} очков · ${level.colours} цв. · ${level.glasses} ст.',
      children: [
        _buttons([
          GoButton(label: 'Продолжить', expand: true, onPressed: _togglePause),
          OutlineButton(label: campaign ? 'Повторить уровень' : 'Заново', onPressed: _retry),
          OutlineButton(label: 'Настройки', onPressed: widget.onSettings),
          if (custom) OutlineButton(label: 'Изменить режим', onPressed: widget.onCustomise),
          if (!custom) OutlineButton(label: 'К уровням', onPressed: widget.onLevels),
          OutlineButton(label: 'В меню', onPressed: widget.onExit),
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
      note: '${_slotNames[_overSlot]} стакан заполнился до конца рукава.'
          '${campaign ? ' Уровень не пройден: начнём его заново или выберем другой.' : ''}',
      children: [
        _RunStats(record: record, campaign: campaign),
        const SizedBox(height: 14),
        _buttons([
          GoButton(
            label: campaign ? 'Повторить уровень' : 'Заново',
            expand: true,
            onPressed: _retry,
          ),
          if (custom) OutlineButton(label: 'Изменить режим', onPressed: widget.onCustomise),
          if (campaign) OutlineButton(label: 'К уровням', onPressed: widget.onLevels),
          OutlineButton(label: 'В меню', onPressed: widget.onExit),
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
            OutlineButton(label: 'В меню', onPressed: widget.onExit),
          ]),
        ],
      );

  Widget _buttons(List<Widget> buttons) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final button in buttons)
            Padding(padding: const EdgeInsets.only(bottom: 8), child: button),
        ],
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
      if (campaign)
        ('Уровень', '${record.completed ? campaignLast + 1 : record.level}'),
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
