import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/config/zen_levels.dart';
import '../game/engine/game_engine.dart';
import '../game/engine/game_event.dart';
import '../game/engine/rotation_transform.dart';
import '../game/model/side.dart';
import '../game/state/game_state.dart';
import 'field/effects.dart';
import 'field/field_painter.dart';
import 'hud.dart';
import 'input/dpad.dart';
import 'input/pad_controller.dart';
import 'level_up_banner.dart';
import 'settings/pad_action.dart';
import 'settings/settings.dart';
import 'style.dart';
import 'widgets/controls.dart';

enum GameStatus { playing, paused, levelUp, over }

/// What a finished game came to.
class _Result {
  const _Result(this.hud, this.slot);

  final HudData hud;

  /// Screen slot of the glass that overflowed.
  final Side slot;
}

enum _PanMode { undecided, dragPiece, swipeSide, swipeDrop, done }

/// The playable screen: owns the engine, runs it from a frame ticker and
/// turns the two pads, touches on the field and keys into engine input.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    required this.mode,
    required this.settings,
    required this.blocked,
    required this.onOpenSettings,
    required this.onExit,
    this.seed,
  });

  final GameMode mode;
  final Settings settings;

  /// True while the settings panel is on top: the game is frozen.
  final bool blocked;
  final VoidCallback onOpenSettings;
  final VoidCallback onExit;

  /// Fixes the order of the pieces (tests).
  final int? seed;

  @override
  State<GameScreen> createState() => GameScreenState();
}

class GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver
    implements PadSink {
  /// Longest frame the game will simulate in one go (hitches, backgrounding).
  static const _maxFrameSeconds = 0.05;

  /// How long the game stands still while a new Zen level is announced.
  static const levelUpSeconds = 2.4;

  static const _swipeDistance = 30.0;
  static const _dragSlop = 14.0;

  static const _slotNames = {
    Side.top: 'Верхний',
    Side.right: 'Правый',
    Side.bottom: 'Нижний',
    Side.left: 'Левый',
  };

  late final GameEngine _engine;
  late final Effects _fx;
  late final PadController _pad;
  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;

  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  final ValueNotifier<HudData> _hud = ValueNotifier<HudData>(const HudData());
  final ValueNotifier<Callout?> _callout = ValueNotifier<Callout?>(null);
  final FocusNode _focus = FocusNode(debugLabel: 'game');

  GameStatus _status = GameStatus.playing;
  _Result? _result;

  // Zen: the level being played, the seconds left of the pause that
  // announces a new one, and the announcement itself.
  int _level = 0;
  double _levelUpLeft = 0;
  int _levelUpId = 0;
  int? _announcedLevel;
  int _calloutId = 0;

  Offset _panOrigin = Offset.zero;
  FieldZone _panZone = FieldZone.outside;
  _PanMode _panMode = _PanMode.done;
  int _panColumn = 0;

  bool get _zen => widget.mode == GameMode.zen;
  Settings get _settings => widget.settings;

  /// The engine of the running game.
  @visibleForTesting
  GameEngine get engine => _engine;

  GameStatus get status => _status;

  bool get _acceptsInput =>
      _status == GameStatus.playing && !widget.blocked && _levelUpLeft <= 0;

  @override
  void initState() {
    super.initState();
    _engine = GameEngine(config: _settings.game.toConfig(seed: widget.seed));
    _fx = Effects()..reset(_engine.activeSide);
    _pad = PadController(
      sink: this,
      dasMs: () => _settings.pads.dasMs,
      arrMs: () => _settings.pads.arrMs,
    );
    _level = _zen ? 1 : 0;
    _hud.value = _snapshot();
    _ticker = createTicker(_onTick)..start();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker.dispose();
    _frame.dispose();
    _hud.dispose();
    _callout.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Leaving the app pauses the game.
    if (state != AppLifecycleState.resumed) pause();
  }

  HudData _snapshot() {
    final state = _engine.state;
    return HudData(
      score: state.score,
      bestCombo: state.bestCombo,
      matches: state.matches,
      pieces: state.piecesPlaced,
      seconds: state.elapsedSeconds.floor(),
      level: _level,
      levelInto: _level > 0 ? ZenLevels.into(state.score, _level) : 0,
      levelTarget: _level > 0 ? ZenLevels.target(_level) : 0,
    );
  }

  // ------------------------------------------------------------- frame loop

  void _onTick(Duration elapsed) {
    final seconds =
        ((elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond)
            .clamp(0.0, _maxFrameSeconds);
    _lastTick = elapsed;
    final frozen = widget.blocked;
    final running =
        _status == GameStatus.playing && !frozen && _levelUpLeft <= 0;
    if (frozen) _pad.releaseAll();
    _fx
      ..screenShake = _settings.screenShake
      ..turnSeconds = _settings.turnMs / 1000;

    if (running) {
      _pad.update(seconds);
      _engine.update(seconds);
    }
    final events = _engine.drainEvents();
    _fx.consume(events, _engine);
    // Effects keep playing out on the result screen, but not under a pause.
    _fx.update(_status == GameStatus.paused || frozen ? 0 : seconds, _engine);
    _react(events);

    if (_levelUpLeft > 0) {
      if (!frozen) _levelUpLeft -= seconds;
      if (_levelUpLeft <= 0) {
        _levelUpLeft = 0;
        setState(() {
          _announcedLevel = null;
          if (_status == GameStatus.levelUp) _status = GameStatus.playing;
        });
      }
    } else if (_zen && running && _engine.phase == GamePhase.playing) {
      // The board is at rest, so a cascade that carried the score over the
      // line has played out in full before the game stops to celebrate.
      final reached = ZenLevels.levelOf(_engine.state.score);
      if (reached > _level) {
        _level = reached;
        _levelUpLeft = levelUpSeconds;
        _levelUpId++;
        _pad.releaseAll();
        _fx.celebrate(_engine.config.numberOfColors);
        _buzz(HapticFeedback.heavyImpact);
        setState(() {
          _announcedLevel = reached;
          _status = GameStatus.levelUp;
        });
      }
    }

    _hud.value = _snapshot();
    _frame.value++;
  }

  void _react(List<GameEvent> events) {
    for (final event in events) {
      switch (event) {
        case SideSwitched():
          _buzz(HapticFeedback.selectionClick);
        case PieceLanded():
          if (event.dropped) _buzz(HapticFeedback.lightImpact);
        case MatchScored():
          _buzz(HapticFeedback.mediumImpact);
          _callout.value =
              Callout(++_calloutId, score: event.score, combo: event.combo);
        case GameEnded():
          _buzz(HapticFeedback.heavyImpact);
          setState(() {
            _result = _Result(
              _snapshot(),
              RotationTransform.slotOfSide(_engine.activeSide, event.info.side),
            );
            _status = GameStatus.over;
          });
        case PieceMoved():
        case PieceRotated():
        case PieceDropped():
        case CellsPopped():
          break;
      }
    }
  }

  void _buzz(Future<void> Function() feedback) {
    if (_settings.pads.haptics) feedback();
  }

  // ------------------------------------------------------------------ state

  void pause() {
    if (_status != GameStatus.playing) return;
    _pad.releaseAll();
    setState(() => _status = GameStatus.paused);
  }

  void resume() {
    if (_status == GameStatus.paused) setState(() => _status = GameStatus.playing);
  }

  void togglePause() => _status == GameStatus.paused ? resume() : pause();

  void restart() {
    _engine.restart();
    _fx.reset(_engine.activeSide);
    _pad.releaseAll();
    _level = _zen ? 1 : 0;
    _levelUpLeft = 0;
    _callout.value = null;
    _hud.value = _snapshot();
    setState(() {
      _result = null;
      _announcedLevel = null;
      _status = GameStatus.playing;
    });
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
  void press(PadAction action) {
    if (action == PadAction.pause) return togglePause();
    if (!_acceptsInput) return;
    switch (action) {
      case PadAction.rotateCW:
        _engine.rotateActive();
      case PadAction.rotateCCW:
        _engine.rotateActive(clockwise: false);
      case PadAction.hardDrop:
        _engine.dropActive();
      case PadAction.glassLeft:
        _engine.switchSide(-1);
      case PadAction.glassRight:
        _engine.switchSide(1);
      case PadAction.glassOpposite:
        _engine.switchSide(2);
      case PadAction.none ||
            PadAction.moveLeft ||
            PadAction.moveRight ||
            PadAction.softDrop ||
            PadAction.pause:
        break;
    }
  }

  void _padDown(PadAction action) {
    if (action != PadAction.none) _buzz(HapticFeedback.selectionClick);
    _pad.down(action);
  }

  static final _keys = <LogicalKeyboardKey, PadAction>{
    LogicalKeyboardKey.arrowLeft: PadAction.moveLeft,
    LogicalKeyboardKey.arrowRight: PadAction.moveRight,
    LogicalKeyboardKey.arrowUp: PadAction.rotateCW,
    LogicalKeyboardKey.keyX: PadAction.rotateCW,
    LogicalKeyboardKey.keyZ: PadAction.rotateCCW,
    LogicalKeyboardKey.arrowDown: PadAction.softDrop,
    LogicalKeyboardKey.space: PadAction.hardDrop,
    LogicalKeyboardKey.keyA: PadAction.glassLeft,
    LogicalKeyboardKey.keyD: PadAction.glassRight,
    LogicalKeyboardKey.keyS: PadAction.glassOpposite,
    LogicalKeyboardKey.escape: PadAction.pause,
    LogicalKeyboardKey.keyP: PadAction.pause,
  };

  /// A hardware keyboard works the way it does in the browser version.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (widget.blocked) return KeyEventResult.ignored;
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.keyR) {
      restart();
      return KeyEventResult.handled;
    }
    final action = _keys[event.logicalKey];
    if (action == null) return KeyEventResult.ignored;
    if (event is KeyDownEvent) {
      _pad.down(action);
    } else if (event is KeyUpEvent) {
      _pad.up(action);
    }
    return KeyEventResult.handled;
  }

  /// Tapping a glass brings it to the top; with field gestures on, a tap on
  /// the centre or the top glass turns the piece.
  void _onTapUp(TapUpDetails details, FieldGeometry geometry) {
    if (!_acceptsInput) return;
    Side at(Side slot) => RotationTransform.sideAtSlot(_engine.activeSide, slot);
    switch (geometry.zoneAt(details.localPosition)) {
      case FieldZone.right:
        _engine.activateSide(at(Side.right));
      case FieldZone.bottom:
        _engine.activateSide(at(Side.bottom));
      case FieldZone.left:
        _engine.activateSide(at(Side.left));
      case FieldZone.center || FieldZone.top:
        if (_settings.pads.fieldGestures) _engine.rotateActive();
      case FieldZone.outside:
        break;
    }
  }

  void _onPanStart(DragStartDetails details, FieldGeometry geometry) {
    _panOrigin = details.localPosition;
    _panZone = geometry.zoneAt(details.localPosition);
    _panMode = _acceptsInput ? _PanMode.undecided : _PanMode.done;
    _panColumn = _engine.activePiece?.column ?? 0;
  }

  void _onPanUpdate(DragUpdateDetails details, FieldGeometry geometry) {
    if (_panMode == _PanMode.done || !_acceptsInput) return;
    final delta = details.localPosition - _panOrigin;

    if (_panMode == _PanMode.undecided) {
      if (delta.distance < _dragSlop) return;
      if (delta.dx.abs() >= delta.dy.abs()) {
        // Sideways in the top glass grabs the stick; anywhere else it turns
        // the whole cross.
        _panMode = _panZone == FieldZone.top
            ? _PanMode.dragPiece
            : _PanMode.swipeSide;
      } else {
        _panMode = delta.dy > 0 ? _PanMode.swipeDrop : _PanMode.done;
      }
    }

    switch (_panMode) {
      case _PanMode.dragPiece:
        _engine.setActiveColumn(
          _panColumn + (delta.dx / geometry.drawnCell).round(),
        );
      case _PanMode.swipeSide:
        if (delta.dx.abs() >= _swipeDistance) {
          // Swiping left pulls the glass on the right up to the top.
          _engine.switchSide(delta.dx < 0 ? 1 : -1);
          _panMode = _PanMode.done;
        }
      case _PanMode.swipeDrop:
        if (delta.dy >= _swipeDistance) {
          _engine.dropActive();
          _panMode = _PanMode.done;
        }
      case _PanMode.undecided || _PanMode.done:
        break;
    }
  }

  // ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    final pads = _settings.pads;
    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_zen) _Aura(level: math.max(1, _level)),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                // Two pads side by side with a gap between and around them.
                final padSize = math.min(
                  168.0 * pads.scale,
                  math.min((box.maxWidth - 36) / 2, box.maxHeight * 0.3),
                );
                return Column(
                  children: [
                    Expanded(child: Center(child: _buildStage())),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          DPad(
                            key: const ValueKey('pad-left'),
                            layout: pads.left,
                            size: padSize,
                            showLabels: _settings.hud.padLabels,
                            opacity: pads.opacity,
                            onDown: _padDown,
                            onUp: _pad.up,
                          ),
                          DPad(
                            key: const ValueKey('pad-right'),
                            layout: pads.right,
                            size: padSize,
                            showLabels: _settings.hud.padLabels,
                            opacity: pads.opacity,
                            onDown: _padDown,
                            onUp: _pad.up,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          if (_status == GameStatus.paused && !widget.blocked) _buildPause(),
          if (_status == GameStatus.over && _result != null && !widget.blocked)
            _buildGameOver(_result!),
        ],
      ),
    );
  }

  /// The square field with the HUD in its corners.
  Widget _buildStage() {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final geometry = FieldGeometry(box.maxWidth, _engine.config);
          final gestures = _settings.pads.fieldGestures;
          return Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                key: const ValueKey('field'),
                behavior: HitTestBehavior.opaque,
                onTapUp: (details) => _onTapUp(details, geometry),
                onPanStart:
                    gestures ? (details) => _onPanStart(details, geometry) : null,
                onPanUpdate:
                    gestures ? (details) => _onPanUpdate(details, geometry) : null,
                child: RepaintBoundary(
                  child: CustomPaint(
                    painter: FieldPainter(engine: _engine, fx: _fx, repaint: _frame),
                  ),
                ),
              ),
              Hud(
                data: _hud,
                callout: _callout,
                options: _settings.hud,
                corner: box.maxWidth * geometry.cornerFraction,
                onPause: pause,
                onOpenSettings: widget.onOpenSettings,
              ),
              if (_announcedLevel != null)
                IgnorePointer(
                  child: LevelUpBanner(
                    key: ValueKey(_levelUpId),
                    level: _announcedLevel!,
                    seconds: levelUpSeconds,
                    em: box.maxWidth / 34,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildPause() {
    return Scrim(
      child: DialogCard(
        width: 300,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('ПАУЗА', style: Type.display(30)),
            if (_zen)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Дзен · уровень $_level',
                  style: Type.body(13, color: Palette.textDim),
                ),
              ),
            const SizedBox(height: 20),
            GameButton(
              label: 'Продолжить',
              kind: ButtonKind.primary,
              onPressed: resume,
            ),
            const SizedBox(height: 10),
            GameButton(
              label: _zen ? 'Начать заново' : 'Заново',
              onPressed: restart,
            ),
            const SizedBox(height: 10),
            GameButton(label: 'Настройки', onPressed: widget.onOpenSettings),
            const SizedBox(height: 4),
            GameButton(
              label: 'В меню',
              kind: ButtonKind.ghost,
              onPressed: widget.onExit,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGameOver(_Result result) {
    final hud = result.hud;
    return Scrim(
      child: DialogCard(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'ИГРА ОКОНЧЕНА',
              style: Type.display(
                28,
                color: Palette.danger,
                shadows: Type.glow(Palette.danger.withValues(alpha: 0.55), 22),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              '${_slotNames[result.slot]} стакан заполнился до конца рукава.'
              '${_zen ? ' Начнёте заново с первого уровня?' : ''}',
              style: Type.body(13, color: Palette.textDim),
            ),
            const SizedBox(height: 12),
            if (_zen) _StatRow('Уровень', '${hud.level}', main: true),
            _StatRow('Счёт', formatScore(hud.score), main: !_zen),
            _StatRow('Лучшее комбо', '×${hud.bestCombo}'),
            _StatRow('Матчи', '${hud.matches}'),
            _StatRow('Фигуры', '${hud.pieces}'),
            _StatRow('Время', formatClock(hud.seconds)),
            const SizedBox(height: 18),
            GameButton(
              label: _zen ? 'Начать заново' : 'Заново',
              kind: ButtonKind.primary,
              onPressed: restart,
            ),
            const SizedBox(height: 10),
            GameButton(label: 'Настройки', onPressed: widget.onOpenSettings),
            const SizedBox(height: 4),
            GameButton(
              label: 'В меню',
              kind: ButtonKind.ghost,
              onPressed: widget.onExit,
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow(this.label, this.value, {this.main = false});

  final String label;
  final String value;
  final bool main;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Palette.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: Text(label.toUpperCase(), style: Type.label(11))),
          Text(
            value,
            style: Type.display(main ? 32 : 20, color: main ? Palette.accent : Palette.text),
          ),
        ],
      ),
    );
  }
}

/// Zen: a wash of colour behind the field that moves on with every level.
class _Aura extends StatelessWidget {
  const _Aura({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final hue = (158 + (level - 1) * 47) % 360;
    return IgnorePointer(
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: hue.toDouble()),
        duration: const Duration(milliseconds: 1400),
        curve: Curves.easeInOut,
        builder: (context, value, _) => DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: const Alignment(0, -0.25),
              radius: 0.9,
              colors: [
                HSLColor.fromAHSL(0.2, value % 360, 0.82, 0.4).toColor(),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }
}
