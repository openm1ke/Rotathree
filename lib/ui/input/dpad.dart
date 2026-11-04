import 'dart:math' as math;

import '../i18n/strings.dart';
import 'package:flutter/material.dart';

import 'game_action.dart';
import 'pad_shape.dart';
import '../style.dart';

/// A cross of four buttons with a fifth in the middle. What each of them
/// does is set by [layout]; how they look and where they sit is set by
/// [shape] and [tweaks].
///
/// Touches are tracked one finger at a time, so both pads and several
/// buttons can be used at once. A finger that slides from one held action to
/// another (left to right, say) hands over without being lifted; one-shot
/// actions only fire on a fresh touch, so a slip never drops the piece.
class DPad extends StatefulWidget {
  const DPad({
    super.key,
    required this.layout,
    required this.size,
    required this.onDown,
    required this.onUp,
    this.showLabels = true,
    this.opacity = 1,
    this.shape = PadShape.square,
    this.tweaks = const {},
    this.highlight,
    this.hint = const [],
  });

  final PadLayout layout;
  final double size;
  final bool showLabels;
  final double opacity;
  final PadShape shape;
  final PadTweaks tweaks;

  /// The button to outline while the layout is being edited.
  final PadSlot? highlight;

  /// The actions a tutorial lesson asks for: their buttons glow and the
  /// others step back.
  final List<GameAction> hint;
  final ValueChanged<GameAction> onDown;
  final ValueChanged<GameAction> onUp;

  @override
  State<DPad> createState() => _DPadState();
}

class _DPadState extends State<DPad> with SingleTickerProviderStateMixin {
  /// The button each finger is on.
  final Map<int, PadSlot> _fingers = {};

  /// The glow of the buttons a lesson asks for, beating.
  late final AnimationController _call = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));

  void _beat() {
    if (widget.hint.isEmpty || MediaQuery.disableAnimationsOf(context)) {
      _call.stop();
      _call.value = 0.5;
    } else if (!_call.isAnimating) {
      _call.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _beat();
  }

  @override
  void didUpdateWidget(DPad oldWidget) {
    super.didUpdateWidget(oldWidget);
    _beat();
  }

  GameAction _actionOf(PadSlot slot) => widget.layout[slot] ?? GameAction.none;

  bool _isPressed(PadSlot slot) => _fingers.containsValue(slot);

  Map<PadSlot, Rect> get _rects => padButtonRects(widget.size, widget.tweaks);

  PadSlot _slotAt(Offset point) =>
      padSlotAt(point, _rects, widget.shape, slop: padTouchSlop(widget.size));

  void _down(PointerDownEvent event) {
    final slot = _slotAt(event.localPosition);
    setState(() => _fingers[event.pointer] = slot);
    widget.onDown(_actionOf(slot));
  }

  void _move(PointerMoveEvent event) {
    final from = _fingers[event.pointer];
    if (from == null) return;
    final to = _slotAt(event.localPosition);
    if (to == from) return;
    final leaving = _actionOf(from);
    final entering = _actionOf(to);
    if (!leaving.isHeld || !entering.isHeld) return;
    setState(() => _fingers[event.pointer] = to);
    widget.onUp(leaving);
    widget.onDown(entering);
  }

  void _up(PointerEvent event) {
    final slot = _fingers.remove(event.pointer);
    if (slot == null) return;
    setState(() {});
    widget.onUp(_actionOf(slot));
  }

  @override
  void dispose() {
    for (final slot in _fingers.values) {
      widget.onUp(_actionOf(slot));
    }
    _call.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rects = _rects;
    Widget button(PadSlot slot) {
      final rect = rects[slot]!;
      final action = _actionOf(slot);
      final hinted = action != GameAction.none && widget.hint.contains(action);
      return Positioned.fromRect(
        rect: rect,
        child: Semantics(
          button: true,
          enabled: action != GameAction.none,
          label: context.tr(action.hint),
          excludeSemantics: true,
          onTap: action == GameAction.none
              ? null
              : () {
                  widget.onDown(action);
                  widget.onUp(action);
                },
          child: Opacity(
            opacity: widget.hint.isNotEmpty && !hinted ? 0.35 : 1,
            child: hinted
                ? AnimatedBuilder(
                    animation: _call,
                    builder: (context, _) => _PadButton(
                      slot: slot,
                      action: action,
                      shape: widget.shape,
                      pressed: _isPressed(slot),
                      highlighted: false,
                      showLabel: widget.showLabels,
                      size: rect.width,
                      // Up and down once a beat, softly.
                      call: 0.5 - 0.5 * math.cos(2 * math.pi * _call.value),
                    ),
                  )
                : _PadButton(
                    slot: slot,
                    action: action,
                    shape: widget.shape,
                    pressed: _isPressed(slot),
                    highlighted: widget.highlight == slot,
                    showLabel: widget.showLabels,
                    size: rect.width,
                  ),
          ),
        ),
      );
    }

    return Opacity(
      opacity: widget.opacity,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: SizedBox.square(
          dimension: widget.size,
          child: Stack(
            children: [
              button(PadSlot.up),
              button(PadSlot.left),
              button(PadSlot.center),
              button(PadSlot.right),
              button(PadSlot.down),
            ],
          ),
        ),
      ),
    );
  }
}

class _PadButton extends StatelessWidget {
  const _PadButton({
    required this.slot,
    required this.action,
    required this.shape,
    required this.pressed,
    required this.highlighted,
    required this.showLabel,
    required this.size,
    this.call,
  });

  final PadSlot slot;
  final GameAction action;
  final PadShape shape;
  final bool pressed;
  final bool highlighted;
  final bool showLabel;

  /// The width of the button, which is also its height.
  final double size;

  /// How brightly a button the tutorial asks for glows, 0..1; null when it
  /// does not ask for this one.
  final double? call;

  @override
  Widget build(BuildContext context) {
    final empty = action == GameAction.none;
    final tint = padActionTint(action);
    final shift = padContentShift(shape, slot) * size;

    return AnimatedScale(
      scale: pressed ? 0.93 : 1,
      duration: const Duration(milliseconds: 70),
      curve: Motion.snap,
      child: CustomPaint(
        painter: _KeyPainter(
          path: padButtonPath(shape, slot, Offset.zero & Size.square(size)),
          fill: pressed ? tint.withValues(alpha: 0.34) : Colors.white.withValues(alpha: empty ? 0.025 : 0.075),
          stroke: highlighted || call != null
              ? Palette.accent
              : pressed
              ? tint
              : empty
              ? Palette.line
              : Palette.lineStrong,
          strokeWidth: call != null ? 2.4 : highlighted ? 2.2 : 1.2,
          glow: pressed ? tint : call != null ? Palette.accent : null,
          glowStrength: pressed || call == null ? 0.5 : 0.55 + 0.3 * call!,
          glowSpread: pressed || call == null ? 0.1 : 0.08 + 0.08 * call!,
        ),
        child: empty
            ? null
            : Center(
                child: Transform.translate(
                  offset: shift,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        padActionIcon(action),
                        size: size * (showLabel ? 0.42 : 0.5),
                        color: pressed || call != null ? Colors.white : Palette.text,
                      ),
                      if (showLabel && slot != PadSlot.center)
                        Padding(
                          padding: EdgeInsets.only(top: size * 0.02),
                          child: _PadCaption(
                            text: padActionCaption(action),
                            color: pressed || call != null ? Colors.white : Palette.textDim,
                            room: size - 4,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

/// Fills a button's outline and strokes it; a pressed button glows in the
/// colour of its action.
class _KeyPainter extends CustomPainter {
  const _KeyPainter({
    required this.path,
    required this.fill,
    required this.stroke,
    required this.strokeWidth,
    this.glow,
    this.glowStrength = 0.5,
    this.glowSpread = 0.1,
  });

  final Path path;
  final Color fill, stroke;
  final double strokeWidth;
  final Color? glow;

  /// The glow's opacity, and its blur as a share of the button's width.
  final double glowStrength, glowSpread;

  @override
  void paint(Canvas canvas, Size size) {
    final glowing = glow;
    if (glowing != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = glowing.withValues(alpha: glowStrength)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * glowSpread),
      );
    }
    canvas.drawPath(path, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..color = stroke,
    );
  }

  @override
  bool shouldRepaint(_KeyPainter oldDelegate) => true;
}

/// The picture of an action on its button.
IconData padActionIcon(GameAction action) => switch (action) {
  GameAction.none => Icons.remove,
  GameAction.moveLeft => Icons.arrow_back_rounded,
  GameAction.moveRight => Icons.arrow_forward_rounded,
  GameAction.rotateCW => Icons.rotate_right_rounded,
  GameAction.rotateCCW => Icons.rotate_left_rounded,
  GameAction.softDrop => Icons.keyboard_double_arrow_down_rounded,
  GameAction.hardDrop => Icons.vertical_align_bottom_rounded,
  GameAction.glassLeft => Icons.turn_left_rounded,
  GameAction.glassRight => Icons.turn_right_rounded,
  GameAction.glassOpposite => Icons.swap_vert_rounded,
  GameAction.pause => Icons.pause_rounded,
  GameAction.restart => Icons.refresh_rounded,
  GameAction.tipBack => Icons.vertical_align_top_rounded,
  GameAction.tipFront => Icons.vertical_align_bottom_rounded,
  GameAction.frontGlass || GameAction.depthGlass => Icons.radio_button_checked_rounded,
  GameAction.backGlass => Icons.cancel_outlined,
  GameAction.peek => Icons.view_in_ar_rounded,
};

/// Captions read at 11 px, as on the web. A word wider than its button is
/// condensed to fit, and only a word that would need more than that drops to
/// 10 px.
class _PadCaption extends StatelessWidget {
  const _PadCaption({required this.text, required this.color, required this.room});

  static const _size = 11.0;
  static const _smallSize = 10.0;
  static const _mostCondensed = 0.8;

  final String text;
  final Color color;
  final double room;

  @override
  Widget build(BuildContext context) {
    final caption = context.tr(text);
    final scaler = MediaQuery.textScalerOf(context);
    TextStyle style(double size) => Type.label(size, color: color).copyWith(letterSpacing: 0.3);
    Size measure(double size) {
      final painter = TextPainter(
        text: TextSpan(text: caption, style: style(size)),
        textDirection: TextDirection.ltr,
        textScaler: scaler,
        maxLines: 1,
      )..layout();
      final measured = painter.size;
      painter.dispose();
      return measured;
    }

    var size = _size;
    var measured = measure(size);
    if (measured.width > room && room / measured.width < _mostCondensed) {
      size = _smallSize;
      measured = measure(size);
    }
    final label = Text(caption, maxLines: 1, softWrap: false, style: style(size));
    if (measured.width <= room) return label;
    return SizedBox(
      width: room,
      height: measured.height,
      child: ClipRect(
        child: OverflowBox(
          maxWidth: double.infinity,
          child: Transform.scale(scaleX: math.max(_mostCondensed, room / measured.width), scaleY: 1, child: label),
        ),
      ),
    );
  }
}

/// A word for the action, small under its picture.
String padActionCaption(GameAction action) => switch (action) {
  GameAction.none => '',
  GameAction.moveLeft => 'ВЛЕВО',
  GameAction.moveRight => 'ВПРАВО',
  GameAction.rotateCW || GameAction.rotateCCW => 'ПОВОРОТ',
  GameAction.softDrop => 'БЫСТРЕЕ',
  GameAction.hardDrop => 'СБРОС',
  GameAction.glassLeft || GameAction.glassRight => 'СТАКАН',
  GameAction.glassOpposite => 'НАПРОТИВ',
  GameAction.pause => 'ПАУЗА',
  GameAction.restart => 'ЗАНОВО',
  GameAction.tipBack || GameAction.tipFront => 'ОПРОКИНУТЬ',
  GameAction.frontGlass => 'ПЕРЕДНИЙ',
  GameAction.backGlass => 'ЗАДНИЙ',
  GameAction.depthGlass => 'ГЛУБИНА',
  GameAction.peek => 'ОБЪЁМ',
};

/// Buttons light up in the colour of what they do: the piece in blue, the
/// cross in violet, the drop in pink.
Color padActionTint(GameAction action) => switch (action) {
  GameAction.hardDrop => Palette.pink,
  GameAction.glassLeft || GameAction.glassRight || GameAction.glassOpposite => Palette.violet,
  GameAction.tipBack || GameAction.tipFront => Palette.violet,
  GameAction.pause => Palette.warning,
  _ => Palette.accent,
};
