import 'game_action.dart';

/// What the pads ask of the game.
abstract class PadSink {
  /// One shift of the active piece; [toWall] slides it as far as it goes.
  void move(int direction, {required bool toWall});

  /// A one-shot action: rotate, drop, switch glass, pause.
  void press(GameAction action);

  void softDrop({required bool held});
}

/// Turns presses and releases of pad buttons into game actions. Held
/// movement repeats with DAS/ARR timing driven by [update], so it feels the
/// same on every device and is easy to test.
class PadController {
  PadController({
    required this.sink,
    required this.dasMs,
    required this.arrMs,
  });

  static const _epsilon = 1e-6;

  final PadSink sink;

  /// Delayed auto shift: milliseconds a direction is held before it repeats.
  final int Function() dasMs;

  /// Auto repeat rate: milliseconds between repeats; 0 slides to the wall.
  final int Function() arrMs;

  /// How many buttons are holding each held action down: two buttons, one on
  /// each pad, may do the same thing.
  final Map<GameAction, int> _holders = {};

  /// Held directions, the most recent last: the latest one pressed wins.
  final List<int> _directions = [];
  double _shiftCharge = 0;
  double _repeatCharge = 0;
  bool _atWall = false;

  static int? _directionOf(GameAction action) => switch (action) {
        GameAction.moveLeft => -1,
        GameAction.moveRight => 1,
        _ => null,
      };

  /// A button with [action] went down.
  void down(GameAction action) {
    if (action == GameAction.none) return;
    if (!action.isHeld) {
      sink.press(action);
      return;
    }
    final holders = (_holders[action] ?? 0) + 1;
    _holders[action] = holders;
    if (holders > 1) return;
    final direction = _directionOf(action);
    if (direction == null) {
      sink.softDrop(held: true);
      return;
    }
    _directions
      ..remove(direction)
      ..add(direction);
    _restartRepeat();
    sink.move(direction, toWall: false);
  }

  /// A button with [action] was let go.
  void up(GameAction action) {
    final holders = _holders[action] ?? 0;
    if (holders == 0) return;
    _holders[action] = holders - 1;
    if (holders > 1) return;
    final direction = _directionOf(action);
    if (direction == null) {
      sink.softDrop(held: false);
      return;
    }
    final wasCurrent = _directions.isNotEmpty && _directions.last == direction;
    _directions.remove(direction);
    // The direction still held takes over and waits out its own delay.
    if (wasCurrent) _restartRepeat();
  }

  /// Lets [seconds] pass: a held direction repeats once its delay is over.
  void update(double seconds) {
    if (_directions.isEmpty) return;
    final direction = _directions.last;
    final ms = seconds * 1000;
    final das = dasMs();
    final before = _shiftCharge;
    _shiftCharge += ms;
    if (_shiftCharge < das - _epsilon) return;

    final arr = arrMs();
    if (arr <= 0) {
      if (!_atWall) {
        _atWall = true;
        sink.move(direction, toWall: true);
      }
      return;
    }
    if (before < das - _epsilon) {
      sink.move(direction, toWall: false);
      _repeatCharge = _shiftCharge - das;
    } else {
      _repeatCharge += ms;
    }
    while (_repeatCharge >= arr - _epsilon) {
      _repeatCharge -= arr;
      sink.move(direction, toWall: false);
    }
  }

  /// Forgets everything that is held (a pause, a dialog, a lost touch).
  void releaseAll() {
    final softDrop = (_holders[GameAction.softDrop] ?? 0) > 0;
    _holders.clear();
    _directions.clear();
    _restartRepeat();
    if (softDrop) sink.softDrop(held: false);
  }

  void _restartRepeat() {
    _shiftCharge = 0;
    _repeatCharge = 0;
    _atWall = false;
  }
}
