import 'package:flutter/material.dart';

import '../style.dart';

/// One choice of an [OptionGroup].
typedef Option<T> = ({T value, String label});

/// A page of the app: a heading with a way back, the content and a footer.
class ScreenFrame extends StatelessWidget {
  const ScreenFrame({
    super.key,
    required this.kicker,
    required this.title,
    required this.children,
    this.onBack,
    this.actions = const [],
    this.footer,
  });

  final String kicker;
  final String title;
  final List<Widget> children;
  final VoidCallback? onBack;
  final List<Widget> actions;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: Row(
              children: [
                if (onBack != null)
                  IconButton(
                    tooltip: 'Назад',
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Palette.text),
                  ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(kicker.toUpperCase(), style: Type.label(11, color: Palette.accent)),
                      Text(title, style: Type.display(28)),
                    ],
                  ),
                ),
                ...actions,
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                ...children,
                // The footer scrolls with the page, so it never covers it.
                if (footer != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(footer!, style: Type.body(12, color: Palette.textDim), textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The main button of the app: the gradient of "go".
class GoButton extends StatelessWidget {
  const GoButton({super.key, required this.label, required this.onPressed, this.expand = false});

  final String label;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = Opacity(
      opacity: enabled ? 1 : 0.4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(colors: Palette.go),
          boxShadow: enabled
              ? [BoxShadow(color: Palette.pink.withValues(alpha: 0.3), blurRadius: 18)]
              : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
              child: Text(label, style: Type.display(17, spacing: 0.4), textAlign: TextAlign.center),
            ),
          ),
        ),
      ),
    );
    return expand ? SizedBox(width: double.infinity, child: button) : button;
  }
}

/// A quiet outlined button.
class OutlineButton extends StatelessWidget {
  const OutlineButton({super.key, required this.label, required this.onPressed, this.danger = false});

  final String label;
  final VoidCallback? onPressed;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: danger ? Palette.danger : Palette.text,
        side: BorderSide(color: danger ? Palette.danger.withValues(alpha: 0.6) : Palette.lineStrong),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Text(label, style: Type.body(14, weight: FontWeight.w800)),
    );
  }
}

/// A small pill that is either on or off.
class OptionChip extends StatelessWidget {
  const OptionChip({super.key, required this.label, required this.selected, required this.onPressed, this.leading});

  final String label;
  final bool selected;
  final VoidCallback? onPressed;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? Palette.accent.withValues(alpha: 0.16) : Palette.panel,
      shape: StadiumBorder(
        side: BorderSide(color: selected ? Palette.accent : Palette.line, width: selected ? 1.4 : 1),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (leading != null) ...[leading!, const SizedBox(width: 8)],
              Text(
                label,
                style: Type.body(13, weight: FontWeight.w800, color: selected ? Palette.accent : Palette.text),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled block of rows on a card.
class Section extends StatelessWidget {
  const Section({super.key, required this.title, required this.children, this.note});

  final String title;
  final String? note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
        decoration: BoxDecoration(
          color: Palette.panel,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Palette.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(), style: Type.label(11, color: Palette.textDim)),
            if (note != null) ...[
              const SizedBox(height: 4),
              Text(note!, style: Type.body(12, color: Palette.textDim, weight: FontWeight.w500)),
            ],
            const SizedBox(height: 10),
            ...children,
          ],
        ),
      ),
    );
  }
}

/// One setting with a few choices, shown as chips.
class OptionGroup<T> extends StatelessWidget {
  const OptionGroup({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.note,
  });

  final String label;
  final String? note;
  final T value;
  final List<Option<T>> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Type.body(14, weight: FontWeight.w800)),
          if (note != null) Text(note!, style: Type.body(12, color: Palette.textDim, weight: FontWeight.w500)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in options)
                OptionChip(
                  label: option.label,
                  selected: option.value == value,
                  onPressed: () => onChanged(option.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A setting that is a number between two ends.
class SliderRow extends StatelessWidget {
  const SliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
    this.unit = '',
    this.note,
    this.scale = 1,
  });

  final String label;
  final num value;
  final num min;
  final num max;
  final num step;
  final String unit;
  final String? note;

  /// Multiplies the value for showing (0.01 shows a fraction as a percentage).
  final double scale;
  final ValueChanged<num> onChanged;

  @override
  Widget build(BuildContext context) {
    final divisions = ((max - min) / step).round();
    final shown = (value * scale);
    final text = shown == shown.roundToDouble() ? shown.round().toString() : shown.toStringAsFixed(2);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: Type.body(14, weight: FontWeight.w800))),
              Text(
                '$text${unit.isEmpty ? '' : ' $unit'}${note == null ? '' : ' · $note'}',
                style: Type.body(13, color: Palette.accent, weight: FontWeight.w800),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              activeTrackColor: Palette.accent,
              inactiveTrackColor: Palette.line,
              thumbColor: Palette.text,
              overlayColor: Palette.accent.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
              min: min.toDouble(),
              max: max.toDouble(),
              divisions: divisions,
              onChanged: (next) {
                final snapped = (min + ((next - min) / step).round() * step);
                onChanged(snapped);
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// A setting that is on or off.
class SwitchRow extends StatelessWidget {
  const SwitchRow({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.on = 'вкл',
    this.off = 'выкл',
  });

  final String label;
  final bool value;
  final String on;
  final String off;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label, style: Type.body(14, weight: FontWeight.w800))),
          Text(value ? on : off, style: Type.body(12, color: Palette.textDim, weight: FontWeight.w700)),
          const SizedBox(width: 6),
          Switch(
            value: value,
            activeThumbColor: Palette.accent,
            activeTrackColor: Palette.accent.withValues(alpha: 0.35),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// A key drawn like a keycap.
class Keycap extends StatelessWidget {
  const Keycap({super.key, required this.label, this.waiting = false, this.empty = false, this.onPressed});

  final String label;
  final bool waiting;
  final bool empty;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final color = waiting ? Palette.warning : (empty ? Palette.textFaint : Palette.text);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onPressed,
      child: Container(
        constraints: const BoxConstraints(minWidth: 44, minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: waiting ? Palette.warning.withValues(alpha: 0.14) : Palette.panelStrong,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: waiting ? Palette.warning : Palette.lineStrong),
        ),
        child: Text(label, style: Type.body(13, weight: FontWeight.w800, color: color), textAlign: TextAlign.center),
      ),
    );
  }
}

/// A dialog card drawn over the game or a screen.
class DialogCard extends StatelessWidget {
  const DialogCard({
    super.key,
    required this.kicker,
    required this.title,
    required this.children,
    this.danger = false,
    this.note,
  });

  final String kicker;
  final String title;
  final String? note;
  final bool danger;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
      decoration: BoxDecoration(
        color: Palette.panelStrong,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Palette.lineStrong),
        boxShadow: const [BoxShadow(color: Color(0x88000000), blurRadius: 40)],
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(kicker.toUpperCase(), style: Type.label(11, color: Palette.accent)),
            const SizedBox(height: 4),
            Text(title, style: Type.display(30, color: danger ? Palette.danger : Palette.text)),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(note!, style: Type.body(14, color: Palette.textDim)),
            ],
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}
