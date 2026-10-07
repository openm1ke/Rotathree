import 'dart:async';

import 'package:flutter/material.dart';

import 'theme.dart';

/// On-screen buttons. Every action also has a gesture on the field itself;
/// the pad makes the controls explicit and reliable for a first prototype.
class ControlPad extends StatelessWidget {
  const ControlPad({
    super.key,
    required this.onTurn,
    required this.onMove,
    required this.onRotate,
    required this.onDrop,
  });

  /// -1 brings the glass on the left to the top, +1 the one on the right.
  final ValueChanged<int> onTurn;
  final ValueChanged<int> onMove;
  final VoidCallback onRotate;
  final VoidCallback onDrop;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 58,
            child: Row(
              children: [
                Expanded(
                  flex: 10,
                  child: PadButton(
                    key: const ValueKey('pad-turn-left'),
                    icon: Icons.rotate_right_rounded,
                    label: 'LEFT GLASS',
                    onPressed: () => onTurn(-1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 9,
                  child: PadButton(
                    key: const ValueKey('pad-move-left'),
                    icon: Icons.chevron_left_rounded,
                    label: 'MOVE',
                    repeat: true,
                    onPressed: () => onMove(-1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 10,
                  child: PadButton(
                    key: const ValueKey('pad-rotate'),
                    icon: Icons.sync_rounded,
                    label: 'ROTATE',
                    onPressed: onRotate,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 9,
                  child: PadButton(
                    key: const ValueKey('pad-move-right'),
                    icon: Icons.chevron_right_rounded,
                    label: 'MOVE',
                    repeat: true,
                    onPressed: () => onMove(1),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 10,
                  child: PadButton(
                    key: const ValueKey('pad-turn-right'),
                    icon: Icons.rotate_left_rounded,
                    label: 'RIGHT GLASS',
                    onPressed: () => onTurn(1),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 56,
            width: double.infinity,
            child: PadButton(
              key: const ValueKey('pad-drop'),
              icon: Icons.keyboard_double_arrow_down_rounded,
              label: 'DROP',
              accent: true,
              horizontal: true,
              onPressed: onDrop,
            ),
          ),
        ],
      ),
    );
  }
}

/// A neon button that fires on touch-down (not on release) and can repeat
/// while held.
class PadButton extends StatefulWidget {
  const PadButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.repeat = false,
    this.accent = false,
    this.horizontal = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool repeat;
  final bool accent;
  final bool horizontal;

  @override
  State<PadButton> createState() => _PadButtonState();
}

class _PadButtonState extends State<PadButton> {
  static const _repeatDelay = Duration(milliseconds: 260);
  static const _repeatInterval = Duration(milliseconds: 75);

  bool _down = false;
  Timer? _timer;

  void _press() {
    widget.onPressed();
    setState(() => _down = true);
    if (!widget.repeat) return;
    _timer?.cancel();
    _timer = Timer(_repeatDelay, () {
      _timer = Timer.periodic(_repeatInterval, (_) => widget.onPressed());
    });
  }

  void _release() {
    _timer?.cancel();
    _timer = null;
    if (mounted && _down) setState(() => _down = false);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.accent ? NeonPalette.outline : NeonPalette.text;
    final content = [
      Icon(widget.icon, color: color, size: widget.horizontal ? 28 : 24),
      SizedBox(width: widget.horizontal ? 8 : 0, height: widget.horizontal ? 0 : 1),
      Text(
        widget.label,
        maxLines: 1,
        style: TextStyle(
          color: widget.horizontal ? color : NeonPalette.textDim,
          fontSize: widget.horizontal ? 17 : 8.5,
          fontWeight: FontWeight.w800,
          letterSpacing: widget.horizontal ? 3 : 0.6,
        ),
      ),
    ];
    return Semantics(
      button: true,
      label: widget.label,
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _press(),
        onPointerUp: (_) => _release(),
        onPointerCancel: (_) => _release(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 70),
          decoration: BoxDecoration(
            color: _down
                ? NeonPalette.outline.withValues(alpha: 0.22)
                : const Color(0xFF0A111C),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _down || widget.accent
                  ? NeonPalette.outline
                  : NeonPalette.outlineDim,
              width: widget.accent ? 1.6 : 1.2,
            ),
            boxShadow: [
              if (_down || widget.accent)
                BoxShadow(
                  color: NeonPalette.outline.withValues(alpha: _down ? 0.45 : 0.18),
                  blurRadius: 14,
                ),
            ],
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: widget.horizontal
                ? Row(mainAxisSize: MainAxisSize.min, children: content)
                : Column(mainAxisSize: MainAxisSize.min, children: content),
          ),
        ),
      ),
    );
  }
}
