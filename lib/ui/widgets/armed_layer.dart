import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// A layer that opens by itself, under fingers and keys still busy with the
/// game (a result screen): for [delay], and then until the player's hands
/// have been still for [still], it presses nothing. It arms by [latest]
/// whatever is held, so that a stuck key cannot lock it. A touch that began
/// before it armed never counts: its taps were routed when it went down.
///
/// The builder learns whether the layer is armed, to dim its buttons till then.
class ArmedLayer extends StatefulWidget {
  const ArmedLayer({
    super.key,
    required this.builder,
    this.delay = const Duration(milliseconds: 700),
    this.still = const Duration(milliseconds: 400),
    this.latest = const Duration(seconds: 3),
  });

  final Widget Function(BuildContext context, bool armed) builder;
  final Duration delay, still, latest;

  @override
  State<ArmedLayer> createState() => _ArmedLayerState();
}

class _ArmedLayerState extends State<ArmedLayer> {
  /// Pointers that went down since the layer opened and are still down.
  final _pointers = <int>{};
  bool _armed = false;
  bool _waited = false;
  bool _quiet = true;
  Timer? _delay, _still, _latest;

  @override
  void initState() {
    super.initState();
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    _delay = Timer(widget.delay, () {
      _waited = true;
      _tryArm();
    });
    _latest = Timer(widget.latest, _arm);
  }

  @override
  void dispose() {
    _stopWatching();
    super.dispose();
  }

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) {
      _pointers.add(event.pointer);
      _pressed();
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      _pointers.remove(event.pointer);
      _tryArm();
    }
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyUpEvent) {
      _tryArm();
    } else {
      _pressed();
    }
    return false;
  }

  void _pressed() {
    _quiet = false;
    _still?.cancel();
    _still = Timer(widget.still, () {
      _quiet = true;
      _tryArm();
    });
  }

  void _tryArm() {
    if (_waited && _quiet && _pointers.isEmpty && HardwareKeyboard.instance.physicalKeysPressed.isEmpty) _arm();
  }

  void _arm() {
    if (_armed || !mounted) return;
    _stopWatching();
    setState(() => _armed = true);
  }

  void _stopWatching() {
    if (_delay == null) return;
    for (final timer in [_delay, _still, _latest]) {
      timer?.cancel();
    }
    _delay = _still = _latest = null;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
    HardwareKeyboard.instance.removeHandler(_onKey);
  }

  @override
  Widget build(BuildContext context) =>
      IgnorePointer(ignoring: !_armed, child: widget.builder(context, _armed));
}
