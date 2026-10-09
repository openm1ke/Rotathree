import '../i18n/strings.dart';
import 'package:flutter/material.dart';

import '../data/settings.dart' show colourToHex;
import '../style.dart';
import '../widgets/controls.dart';

/// Asks for a colour with hue, saturation and brightness. Null when cancelled.
Future<Color?> showColourPicker(BuildContext context, Color initial, String name) {
  return showDialog<Color>(
    context: context,
    builder: (context) => _ColourDialog(initial: initial, name: name),
  );
}

class _ColourDialog extends StatefulWidget {
  const _ColourDialog({required this.initial, required this.name});

  final Color initial;
  final String name;

  @override
  State<_ColourDialog> createState() => _ColourDialogState();
}

class _ColourDialogState extends State<_ColourDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);

  @override
  Widget build(BuildContext context) {
    final colour = _hsv.toColor();
    return Dialog(
      backgroundColor: Palette.panelStrong,
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: Palette.lineStrong),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LText(widget.name.toUpperCase(), style: Type.label(11, color: Palette.accent)),
            const SizedBox(height: 10),
            Container(
              height: 56,
              decoration: BoxDecoration(
                color: colour,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Palette.lineStrong),
              ),
            ),
            const SizedBox(height: 6),
            LText(
              colourToHex(colour).toUpperCase(),
              style: Type.body(13, color: Palette.textDim),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            _slider('Оттенок', _hsv.hue, 0, 360, (v) => _hsv = _hsv.withHue(v)),
            _slider('Насыщенность', _hsv.saturation, 0, 1, (v) => _hsv = _hsv.withSaturation(v)),
            _slider('Яркость', _hsv.value, 0, 1, (v) => _hsv = _hsv.withValue(v)),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlineButton(label: 'Отмена', onPressed: () => Navigator.of(context).pop()),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GoButton(
                    label: 'Готово',
                    expand: true,
                    onPressed: () => Navigator.of(context).pop(colour),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _slider(String label, double value, double min, double max, void Function(double) change) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LText(label, style: Type.body(12, color: Palette.textDim, weight: FontWeight.w700)),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            activeColor: Palette.accent,
            onChanged: (next) => setState(() => change(next)),
          ),
        ],
      ),
    );
  }
}

/// The current colour of a slot, as a swatch with its name and code.
class ColourSwatch extends StatelessWidget {
  const ColourSwatch({super.key, required this.name, required this.colour, required this.onTap});

  final String name;
  final Color colour;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Palette.panel,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Palette.line),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Palette.lineStrong),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LText(name, style: Type.body(13, weight: FontWeight.w800)),
                  LText(colourToHex(colour).toUpperCase(), style: Type.body(11, color: Palette.textDim)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
