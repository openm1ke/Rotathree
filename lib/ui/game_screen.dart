import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../game/engine/game_engine.dart';
import '../game/engine/game_event.dart';
import '../game/engine/rotation_transform.dart';
import '../game/model/side.dart';
import '../game/sim/bot_player.dart';
import 'board_widget.dart';
import 'control_pad.dart';
import 'game_over_overlay.dart';
import 'hud.dart';
import 'lab_panel.dart';
import 'start_overlay.dart';
import 'theme.dart';
import 'view_effects.dart';

enum _Overlay { none, start, lab, gameOver }

enum _PanMode { undecided, dragPiece, swipeSide, swipeDrop, done }

/// The playable screen: owns the engine, runs it from a frame ticker and
/// turns touches, buttons and keys into engine input.
class GameScreen extends StatefulWidget {
  const GameScreen({
    super.key,
    this.settings = const LabSettings(),
    this.showIntro = true,
  });

  final LabSettings settings;
  final bool showIntro;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with SingleTickerProviderStateMixin {
  /// Longest frame the game will simulate in one go (hitches, backgrounding).
  static const _maxFrameSeconds = 0.05;
  static const _swipeDistance = 30.0;
  static const _dragSlop = 14.0;

  late LabSettings _settings;
  late GameEngine _engine;
  late ViewEffects _fx;
  BotPlayer? _bot;

  late final Ticker _ticker;
  Duration _lastTick = Duration.zero;
  final ValueNotifier<int> _frame = ValueNotifier<int>(0);
  late final ValueNotifier<HudData> _hud;

  late _Overlay _overlay;

  /// Where the lab panel returns to when it is closed without applying.
  _Overlay _overlayBeforeLab = _Overlay.none;

  Offset _panOrigin = Offset.zero;
  CrossZone _panZone = CrossZone.outside;
  _PanMode _panMode = _PanMode.done;
  int _panColumn = 0;

  bool get _running => _overlay == _Overlay.none;

  @override
  void initState() {
    super.initState();
    _overlay = widget.showIntro ? _Overlay.start : _Overlay.none;
    _startGame(widget.settings);
    _hud = ValueNotifier<HudData>(_snapshot());
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _hud.dispose();
    super.dispose();
  }

  void _startGame(LabSettings settings) {
    _settings = settings;
    _engine = GameEngine(config: settings.config);
    _fx = ViewEffects(rotationSeconds: settings.config.rotationSeconds)
      ..reset(_engine.activeSide);
    final profile = settings.bot;
    _bot = profile == null ? null : BotPlayer(_engine, profile: profile);
  }

  /// Replaces the running game and shows the new one at once.
  void _showNewGame(LabSettings settings) {
    setState(() {
      _startGame(settings);
      _overlay = _Overlay.none;
    });
    _hud.value = _snapshot();
  }

  HudData _snapshot() {
    final state = _engine.state;
    return HudData(
      score: state.score,
      combo: state.combo,
      bestCombo: state.bestCombo,
      matches: state.matches,
      seconds: state.elapsedSeconds.floor(),
      activeSide: state.activeSide,
    );
  }

  void _onTick(Duration elapsed) {
    final frameSeconds =
        ((elapsed - _lastTick).inMicroseconds / Duration.microsecondsPerSecond)
            .clamp(0.0, _maxFrameSeconds);
    _lastTick = elapsed;
    // Behind an overlay nothing moves, so nothing is simulated or repainted.
    if (!_running) return;
    final seconds = frameSeconds * _settings.config.timeScale;
    _bot?.tick(seconds);
    _engine.update(seconds);
    _react(_fx.update(seconds, _engine));
    _hud.value = _snapshot();
    _frame.value++;
  }

  void _react(List<GameEvent> events) {
    for (final event in events) {
      switch (event) {
        case SideSwitched():
          HapticFeedback.selectionClick();
        case PieceLanded():
          HapticFeedback.lightImpact();
        case MatchScored():
          HapticFeedback.mediumImpact();
        case GameEnded():
          HapticFeedback.heavyImpact();
          setState(() => _overlay = _Overlay.gameOver);
        case PieceDropped():
        case CellsPopped():
          break;
      }
    }
  }

  // ------------------------------------------------------------------ input

  bool get _acceptsInput => _running && _bot == null;

  void _turn(int quarterTurns) {
    if (_acceptsInput) _engine.switchSide(quarterTurns);
  }

  void _move(int delta) {
    if (_acceptsInput) _engine.moveActive(delta);
  }

  void _rotate() {
    if (_acceptsInput) _engine.rotateActive();
  }

  void _drop() {
    if (_acceptsInput) _engine.dropActive();
  }

  void _onTapUp(TapUpDetails details, CrossGeometry geometry) {
    if (!_acceptsInput) return;
    Side sideAt(Side slot) =>
        RotationTransform.sideAtSlot(_engine.activeSide, slot);
    switch (geometry.zoneAt(details.localPosition)) {
      case CrossZone.center:
      case CrossZone.top:
        _engine.rotateActive();
      case CrossZone.right:
        _engine.activateSide(sideAt(Side.right));
      case CrossZone.bottom:
        _engine.activateSide(sideAt(Side.bottom));
      case CrossZone.left:
        _engine.activateSide(sideAt(Side.left));
      case CrossZone.outside:
        break;
    }
  }

  void _onPanStart(DragStartDetails details, CrossGeometry geometry) {
    _panOrigin = details.localPosition;
    _panZone = geometry.zoneAt(details.localPosition);
    _panMode = _acceptsInput ? _PanMode.undecided : _PanMode.done;
    _panColumn = _engine.activePiece?.column ?? 0;
  }

  void _onPanUpdate(DragUpdateDetails details, CrossGeometry geometry) {
    if (_panMode == _PanMode.done || !_acceptsInput) return;
    final delta = details.localPosition - _panOrigin;

    if (_panMode == _PanMode.undecided) {
      if (delta.distance < _dragSlop) return;
      if (delta.dx.abs() >= delta.dy.abs()) {
        // Sideways in the top glass grabs the stick; anywhere else it turns
        // the whole cross.
        _panMode = _panZone == CrossZone.top
            ? _PanMode.dragPiece
            : _PanMode.swipeSide;
      } else {
        _panMode = delta.dy > 0 ? _PanMode.swipeDrop : _PanMode.done;
      }
    }

    switch (_panMode) {
      case _PanMode.dragPiece:
        _engine.setActiveColumn(
          _panColumn + (delta.dx / geometry.cell).round(),
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
      case _PanMode.undecided:
      case _PanMode.done:
        break;
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft) {
      _move(-1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _move(1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _rotate();
    } else if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.space) {
      _drop();
    } else if (key == LogicalKeyboardKey.keyA ||
        key == LogicalKeyboardKey.keyQ) {
      _turn(-1);
    } else if (key == LogicalKeyboardKey.keyD ||
        key == LogicalKeyboardKey.keyE) {
      _turn(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // --------------------------------------------------------------- overlays

  void _openLab() {
    setState(() {
      _overlayBeforeLab = _overlay;
      _overlay = _Overlay.lab;
    });
  }

  void _applyLab(LabSettings settings) => _showNewGame(settings);

  void _restart() => _showNewGame(_settings);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NeonPalette.background,
      body: Focus(
        autofocus: true,
        onKeyEvent: _onKey,
        child: Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, -0.15),
                  radius: 0.95,
                  colors: [NeonPalette.backgroundGlow, NeonPalette.background],
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Hud(data: _hud, onOpenLab: _openLab),
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final geometry = CrossGeometry(
                              constraints.biggest,
                              _settings.config,
                            );
                            return GestureDetector(
                              key: const ValueKey('field'),
                              behavior: HitTestBehavior.opaque,
                              onTapUp: (d) => _onTapUp(d, geometry),
                              onPanStart: (d) => _onPanStart(d, geometry),
                              onPanUpdate: (d) => _onPanUpdate(d, geometry),
                              child: CrossBoard(
                                engine: _engine,
                                fx: _fx,
                                repaint: _frame,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  _StatusLine(hud: _hud, summary: _settings.summary),
                  ControlPad(
                    onTurn: _turn,
                    onMove: _move,
                    onRotate: _rotate,
                    onDrop: _drop,
                  ),
                ],
              ),
            ),
            switch (_overlay) {
              _Overlay.none => const SizedBox.shrink(),
              _Overlay.start => StartOverlay(
                  onPlay: () => setState(() => _overlay = _Overlay.none),
                  onOpenLab: _openLab,
                ),
              _Overlay.lab => LabPanel(
                  settings: _settings,
                  canResume: _overlayBeforeLab == _Overlay.none,
                  onResume: () => setState(() => _overlay = _Overlay.none),
                  onApply: _applyLab,
                ),
              _Overlay.gameOver => GameOverOverlay(
                  state: _engine.state,
                  onRestart: _restart,
                  onOpenLab: _openLab,
                ),
            },
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.hud, required this.summary});

  final ValueListenable<HudData> hud;
  final String summary;

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: NeonPalette.textDim,
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
      child: Row(
        children: [
          ValueListenableBuilder<HudData>(
            valueListenable: hud,
            builder: (context, data, _) => Text.rich(
              TextSpan(
                text: 'ACTIVE GLASS  ',
                children: [
                  TextSpan(
                    text: data.activeSide.name.toUpperCase(),
                    style: const TextStyle(color: NeonPalette.outline),
                  ),
                ],
              ),
              style: style,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              summary.toUpperCase(),
              style: style,
              maxLines: 1,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
