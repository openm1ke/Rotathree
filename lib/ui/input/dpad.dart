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
  });

  final PadLayout layout;
  final double size;
  final bool showLabels;
  final double opacity;
  final PadShape shape;
  final PadTweaks tweaks;

  /// The button to outline while the layout is being edited.
  final PadSlot? highlight;
  final ValueChanged<GameAction> onDown;
  final ValueChanged<GameAction> onUp;

  @override
  State<DPad> createState() => _DPadState();
}

class _DPadState extends State<DPad> {
  /// The button each finger is on.
  final Map<int, PadSlot> _fingers = {};

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final rects = _rects;
    Widget button(PadSlot slot) {
      final rect = rects[slot]!;
      final action = _actionOf(slot);
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
          child: _PadButton(
            slot: slot,
            action: action,
            shape: widget.shape,
            pressed: _isPressed(slot),
            highlighted: widget.highlight == slot,
            showLabel: widget.showLabels,
            size: rect.width,
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
  });

  final PadSlot slot;
  final GameAction action;
  final PadShape shape;
  final bool pressed;
  final bool highlighted;
  final bool showLabel;

  /// The width of the button, which is also its height.
  final double size;

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
          stroke: highlighted
              ? Palette.accent
              : pressed
              ? tint
              : empty
              ? Palette.line
              : Palette.lineStrong,
          strokeWidth: highlighted ? 2.2 : 1.2,
          glow: pressed ? tint : null,
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
                        color: pressed ? Colors.white : Palette.text,
                      ),
                      if (showLabel && slot != PadSlot.center)
                        Padding(
                          padding: EdgeInsets.only(top: size * 0.02),
                          // The caption shrinks to the button instead of being cut off.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: LText(
                              padActionCaption(action),
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: Type.label(
                                9,
                                color: pressed ? Colors.white : Palette.textDim,
                              ).copyWith(letterSpacing: 0.3),
                            ),
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
  });

  final Path path;
  final Color fill, stroke;
  final double strokeWidth;
  final Color? glow;

  @override
  void paint(Canvas canvas, Size size) {
    final glowing = glow;
    if (glowing != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = glowing.withValues(alpha: 0.5)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.1),
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
};

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
};

/// Buttons light up in the colour of what they do: the piece in blue, the
/// cross in violet, the drop in pink.
Color padActionTint(GameAction action) => switch (action) {
  GameAction.hardDrop => Palette.pink,
  GameAction.glassLeft || GameAction.glassRight || GameAction.glassOpposite => Palette.violet,
  GameAction.pause => Palette.warning,
  _ => Palette.accent,
};
