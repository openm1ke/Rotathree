import '../i18n/strings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../data/settings.dart';
import '../style.dart';
import 'dpad.dart';
import 'game_action.dart';
import 'pad_placement.dart';

/// Shared game/editor geometry, in the safe area below the field.
class PadSurface extends StatefulWidget {
  const PadSurface({super.key, required this.settings, required this.onDown, required this.onUp, this.onEdit});
  final Settings settings;
  final ValueChanged<GameAction> onDown, onUp;
  final ValueChanged<PadPositions>? onEdit;
  @override
  State<PadSurface> createState() => _PadSurfaceState();
}

class _PadSurfaceState extends State<PadSurface> {
  Offset _drag = Offset.zero;
  int? _pointer;
  PadPositions _start = const PadPositions();
  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final preview = widget.onEdit != null;
        final width = preview ? media.size.width - media.padding.horizontal - 16 : constraints.maxWidth;
        final height = padAreaHeight(media.size.height - media.padding.vertical, widget.settings.padPositions, width);
        final area = Size(width, height);
        final geometry = padGeometry(area, widget.settings.padPositions);
        final surface = SizedBox(
          width: width,
          height: height,
          child: Stack(
            children: [
              for (final side in PadSide.values)
                Positioned.fromRect(rect: geometry[side]!, child: _pad(side, geometry[side]!, area, preview)),
            ],
          ),
        );
        if (!preview) return surface;
        return Container(
          decoration: BoxDecoration(
            color: Palette.bg,
            border: Border.all(color: Palette.accent.withValues(alpha: .5)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SizedBox(
            height: height * constraints.maxWidth / width,
            child: FittedBox(fit: BoxFit.contain, child: surface),
          ),
        );
      },
    );
  }

  Widget _pad(PadSide side, Rect rect, Size area, bool preview) {
    final pad = DPad(
      layout: side == PadSide.left ? widget.settings.leftPad : widget.settings.rightPad,
      size: rect.width,
      showLabels: widget.settings.hud.keyHints || preview,
      onDown: widget.onDown,
      onUp: widget.onUp,
    );
    if (!preview) return pad;
    void move(Offset point) => widget.onEdit!(movePad(_start, side, point, area));
    return Semantics(
      label: context.tr('Переместить: ${side == PadSide.left ? 'Левая' : 'Правая'} крестовина'),
      onIncrease: () =>
          widget.onEdit!(movePad(widget.settings.padPositions, side, rect.topLeft + const Offset(8, 0), area)),
      onDecrease: () =>
          widget.onEdit!(movePad(widget.settings.padPositions, side, rect.topLeft - const Offset(8, 0), area)),
      // Claim a drag that starts on a pad before the surrounding ListView
      // can interpret it as scrolling. Local deltas include preview scaling.
      child: RawGestureDetector(
        gestures: {
          EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            () => EagerGestureRecognizer(),
            (_) {},
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) {
            if (_pointer != null) return;
            _pointer = event.pointer;
            _start = widget.settings.padPositions;
            _drag = rect.topLeft;
          },
          onPointerMove: (event) {
            if (_pointer != event.pointer) return;
            _drag += event.localDelta;
            move(_drag);
          },
          onPointerUp: (event) {
            if (_pointer == event.pointer) _pointer = null;
          },
          onPointerCancel: (event) {
            if (_pointer == event.pointer) _pointer = null;
          },
          child: ExcludeSemantics(child: IgnorePointer(child: pad)),
        ),
      ),
    );
  }
}
