import 'package:flutter/material.dart';

import 'theme.dart';

/// Dimmed backdrop with a framed panel in the middle, used by every overlay.
class NeonPanel extends StatelessWidget {
  const NeonPanel({super.key, required this.children, this.maxWidth = 340});

  final List<Widget> children;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xD9020409),
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xF2070C15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: NeonPalette.outline, width: 1.4),
                  boxShadow: [
                    BoxShadow(
                      color: NeonPalette.outline.withValues(alpha: 0.28),
                      blurRadius: 28,
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class PanelTitle extends StatelessWidget {
  const PanelTitle(this.text, {super.key, this.color = NeonPalette.text});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      textAlign: TextAlign.center,
      style: TextStyle(
        color: color,
        fontSize: 30,
        fontWeight: FontWeight.w900,
        letterSpacing: 4,
        shadows: [Shadow(color: color.withValues(alpha: 0.7), blurRadius: 18)],
      ),
    );
  }
}

class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.primary = true,
  });

  final String label;
  final VoidCallback onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final color = primary ? NeonPalette.outline : NeonPalette.textDim;
    return SizedBox(
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: color,
          backgroundColor:
              primary ? NeonPalette.outline.withValues(alpha: 0.12) : null,
          side: BorderSide(color: color, width: primary ? 1.6 : 1.1),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.5,
          ),
        ),
      ),
    );
  }
}
