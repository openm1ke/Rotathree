import 'package:flutter/material.dart';

import 'game_action.dart';
import '../style.dart';

/// A cross of four buttons with a fifth in the middle. What each of them
/// does is set by [layout].
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
  });

  final PadLayout layout;
  final double size;
  final bool showLabels;
  final double opacity;
  final ValueChanged<GameAction> onDown;
  final ValueChanged<GameAction> onUp;

  /// The button under a point of a pad [size] wide.
  static PadSlot slotAt(Offset point, double size, PadLayout layout) {
    final dx = point.dx - size / 2;
    final dy = point.dy - size / 2;
    final hasCenter = layout[PadSlot.center] != GameAction.none;
    if (hasCenter && dx * dx + dy * dy < size * size * 0.028) {
      return PadSlot.center;
    }
    if (dx.abs() > dy.abs()) return dx > 0 ? PadSlot.right : PadSlot.left;
    return dy > 0 ? PadSlot.down : PadSlot.up;
  }

  @override
  State<DPad> createState() => _DPadState();
}

class _DPadState extends State<DPad> {
  /// The button each finger is on.
  final Map<int, PadSlot> _fingers = {};

  GameAction _actionOf(PadSlot slot) => widget.layout[slot] ?? GameAction.none;

  bool _isPressed(PadSlot slot) => _fingers.containsValue(slot);

  PadSlot _slotAt(Offset point) =>
      DPad.slotAt(point, widget.size, widget.layout);

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
    final size = widget.size;
    final cell = size / 3;
    Widget button(PadSlot slot, int column, int row) => Positioned(
          left: column * cell,
          top: row * cell,
          width: cell,
          height: cell,
          child: _PadButton(
            slot: slot,
            action: _actionOf(slot),
            pressed: _isPressed(slot),
            showLabel: widget.showLabels,
            size: cell,
          ),
        );

    return Opacity(
      opacity: widget.opacity,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: SizedBox.square(
          dimension: size,
          child: Stack(
            children: [
              button(PadSlot.up, 1, 0),
              button(PadSlot.left, 0, 1),
              button(PadSlot.center, 1, 1),
              button(PadSlot.right, 2, 1),
              button(PadSlot.down, 1, 2),
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
    required this.pressed,
    required this.showLabel,
    required this.size,
  });

  final PadSlot slot;
  final GameAction action;
  final bool pressed;
  final bool showLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    final empty = action == GameAction.none;
    final outer = Radius.circular(size * 0.3);
    final inner = Radius.circular(size * 0.1);
    // The arms are rounded at their outer ends, like one cross-shaped key.
    final radius = switch (slot) {
      PadSlot.up => BorderRadius.vertical(top: outer, bottom: inner),
      PadSlot.down => BorderRadius.vertical(top: inner, bottom: outer),
      PadSlot.left => BorderRadius.horizontal(left: outer, right: inner),
      PadSlot.right => BorderRadius.horizontal(left: inner, right: outer),
      PadSlot.center => BorderRadius.all(Radius.circular(size * 0.5)),
    };
    final tint = padActionTint(action);

    return Padding(
      padding: EdgeInsets.all(size * (slot == PadSlot.center ? 0.1 : 0.035)),
      child: AnimatedScale(
        scale: pressed ? 0.93 : 1,
        duration: const Duration(milliseconds: 70),
        curve: Motion.snap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          decoration: BoxDecoration(
            borderRadius: radius,
            color: pressed
                ? tint.withValues(alpha: 0.34)
                : Colors.white.withValues(alpha: empty ? 0.025 : 0.075),
            border: Border.all(
              color: pressed
                  ? tint
                  : empty
                      ? Palette.line
                      : Palette.lineStrong,
              width: 1.2,
            ),
            boxShadow: pressed
                ? [BoxShadow(color: tint.withValues(alpha: 0.5), blurRadius: 16)]
                : null,
          ),
          child: empty
              ? null
              : Column(
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
                        child: Text(
                          padActionCaption(action),
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          softWrap: false,
                          style: Type.label(
                            size * 0.125,
                            color: pressed ? Colors.white : Palette.textDim,
                          ).copyWith(letterSpacing: 0.3),
                        ),
                      ),
                  ],
                ),
        ),
      ),
    );
  }
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
      GameAction.glassLeft ||
      GameAction.glassRight ||
      GameAction.glassOpposite =>
        Palette.violet,
      GameAction.pause => Palette.warning,
      _ => Palette.accent,
    };
