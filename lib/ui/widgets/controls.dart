import 'package:flutter/material.dart';

import '../style.dart';

/// Something that reacts to a touch by sinking a little — the buttons of the
/// game do not use Material's ink.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.onPressed,
    required this.builder,
    this.pressedScale = 0.97,
  });

  final VoidCallback? onPressed;
  final Widget Function(BuildContext context, bool pressed) builder;
  final double pressedScale;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _pressed = false;

  void _set(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onPressed,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: const Duration(milliseconds: 110),
        curve: Motion.snap,
        child: widget.builder(context, _pressed),
      ),
    );
  }
}

enum ButtonKind { primary, plain, ghost }

/// A wide slanted-capitals button of a dialog.
class GameButton extends StatelessWidget {
  const GameButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = ButtonKind.plain,
  });

  final String label;
  final VoidCallback onPressed;
  final ButtonKind kind;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: onPressed,
      builder: (context, pressed) => Container(
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          gradient: kind == ButtonKind.primary
              ? const LinearGradient(colors: Palette.go)
              : null,
          color: switch (kind) {
            ButtonKind.primary => null,
            ButtonKind.plain =>
              Colors.white.withValues(alpha: pressed ? 0.12 : 0.06),
            ButtonKind.ghost => Colors.transparent,
          },
          border: kind == ButtonKind.plain
              ? Border.all(color: Palette.lineStrong)
              : null,
          boxShadow: kind == ButtonKind.primary
              ? [
                  BoxShadow(
                    color: Palette.go.first.withValues(alpha: 0.32),
                    blurRadius: 26,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Text(
          label.toUpperCase(),
          style: Type.display(
            15,
            spacing: 0.9,
            color: kind == ButtonKind.ghost ? Palette.textDim : Palette.text,
          ),
        ),
      ),
    );
  }
}

/// A small pill: one of several choices, or a compact action.
class ChipButton extends StatelessWidget {
  const ChipButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      onPressed: onPressed,
      pressedScale: 0.95,
      builder: (context, pressed) => AnimatedContainer(
        duration: const Duration(milliseconds: 110),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          color: selected ? Palette.accent.withValues(alpha: 0.16) : Palette.panel,
          border: Border.all(color: selected ? Palette.accent : Palette.line),
        ),
        child: Text(
          label,
          style: Type.body(
            13,
            weight: FontWeight.w800,
            color: selected ? Colors.white : Palette.textDim,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}

/// A round button with a picture, for the corner of the field.
class RoundButton extends StatelessWidget {
  const RoundButton({
    super.key,
    required this.icon,
    required this.onPressed,
    required this.semanticLabel,
    this.size = 38,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String semanticLabel;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      child: Pressable(
        onPressed: onPressed,
        pressedScale: 0.9,
        builder: (context, pressed) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: pressed ? 0.14 : 0.06),
            border: Border.all(color: Palette.line),
          ),
          child: Icon(icon, size: size * 0.52, color: Palette.textDim),
        ),
      ),
    );
  }
}

/// The dimmed, blurred-looking layer a dialog sits on.
class Scrim extends StatelessWidget {
  const Scrim({super.key, required this.child, this.onTapOutside, this.strength = 0.72});

  final Widget child;
  final VoidCallback? onTapOutside;
  final double strength;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 160),
      builder: (context, t, child) => Opacity(opacity: t, child: child),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTapOutside,
        child: ColoredBox(
          color: Palette.bg.withValues(alpha: strength),
          child: Center(
            // Touches on the dialog itself must not count as "outside".
            child: GestureDetector(onTap: () {}, child: child),
          ),
        ),
      ),
    );
  }
}

/// The card of a dialog, sliding up into place.
class DialogCard extends StatelessWidget {
  const DialogCard({
    super.key,
    required this.child,
    this.width = 320,
    this.padding,
    this.scrollable = true,
  });

  final Widget child;
  final double width;
  final EdgeInsets? padding;

  /// Lets the content scroll when the screen is too short for it. Off for a
  /// card that lays out its own scrolling part.
  final bool scrollable;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 240),
      curve: Motion.back,
      builder: (context, t, child) => Transform.translate(
        offset: Offset(0, 14 * (1 - t)),
        child: Transform.scale(scale: 0.95 + 0.05 * t, child: child),
      ),
      child: Container(
        width: width,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.92,
        ),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Palette.panelStrong,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Palette.lineStrong),
          boxShadow: const [
            BoxShadow(color: Color(0x99000000), blurRadius: 60, offset: Offset(0, 24)),
          ],
        ),
        child: scrollable
            ? SingleChildScrollView(
                padding: padding ?? const EdgeInsets.fromLTRB(22, 24, 22, 20),
                child: child,
              )
            : Padding(padding: padding ?? EdgeInsets.zero, child: child),
      ),
    );
  }
}
