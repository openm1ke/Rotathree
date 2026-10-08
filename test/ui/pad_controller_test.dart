import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/input/pad_controller.dart';
import 'package:rotathree/ui/input/game_action.dart';

class _Log implements PadSink {
  final List<String> entries = [];

  @override
  void move(int direction, {required bool toWall}) =>
      entries.add('move $direction${toWall ? ' wall' : ''}');

  @override
  void press(GameAction action) => entries.add(action.name);

  @override
  void softDrop({required bool held}) => entries.add('soft $held');
}

void main() {
  (PadController, List<String>) setup({int das = 150, int arr = 50}) {
    final log = _Log();
    final pad = PadController(sink: log, dasMs: () => das, arrMs: () => arr);
    return (pad, log.entries);
  }

  test('one-shot actions fire once per press', () {
    final (pad, log) = setup();
    pad.down(GameAction.hardDrop);
    pad.up(GameAction.hardDrop);
    pad.down(GameAction.hardDrop);
    pad.down(GameAction.glassRight);
    pad.down(GameAction.rotateCCW);
    pad.down(GameAction.none);
    pad.update(1);
    expect(log, ['hardDrop', 'hardDrop', 'glassRight', 'rotateCCW']);
  });

  test('a held direction moves at once, waits, then repeats', () {
    final (pad, log) = setup(das: 150, arr: 50);
    pad.down(GameAction.moveLeft);
    expect(log, ['move -1']);
    pad.update(0.1);
    expect(log, hasLength(1)); // still inside the delay
    pad.update(0.05);
    expect(log, hasLength(2)); // the delay has just run out
    pad.update(0.1);
    expect(log, hasLength(4)); // two more repeats, 50 ms apart
    pad.up(GameAction.moveLeft);
    pad.update(0.5);
    expect(log, hasLength(4));
  });

  test('the most recently pressed direction wins; releasing it returns to the other', () {
    final (pad, log) = setup(das: 100, arr: 50);
    pad.down(GameAction.moveLeft);
    pad.down(GameAction.moveRight);
    pad.update(0.1);
    expect(log, ['move -1', 'move 1', 'move 1']);
    pad.up(GameAction.moveRight);
    pad.update(0.1);
    expect(log.last, 'move -1');
  });

  test('with zero repeat interval the piece slides straight to the wall, once', () {
    final (pad, log) = setup(das: 100, arr: 0);
    pad.down(GameAction.moveRight);
    pad.update(0.2);
    pad.update(0.2);
    expect(log, ['move 1', 'move 1 wall']);
  });

  test('soft drop is held, not pressed', () {
    final (pad, log) = setup();
    pad.down(GameAction.softDrop);
    pad.update(0.3);
    pad.up(GameAction.softDrop);
    expect(log, ['soft true', 'soft false']);
  });

  test('two buttons with the same held action count as one hold', () {
    final (pad, log) = setup();
    pad.down(GameAction.softDrop);
    pad.down(GameAction.softDrop);
    pad.up(GameAction.softDrop);
    expect(log, ['soft true']); // the other finger is still on it
    pad.up(GameAction.softDrop);
    expect(log, ['soft true', 'soft false']);

    pad.down(GameAction.moveLeft);
    pad.down(GameAction.moveLeft);
    expect(log.where((entry) => entry == 'move -1'), hasLength(1));
  });

  test('releasing everything forgets held keys', () {
    final (pad, log) = setup();
    pad.down(GameAction.softDrop);
    pad.down(GameAction.moveLeft);
    pad.releaseAll();
    pad.update(1);
    expect(log, ['soft true', 'move -1', 'soft false']);
    // A release that arrives late for a forgotten press does nothing.
    pad.up(GameAction.moveLeft);
    pad.up(GameAction.softDrop);
    expect(log, hasLength(3));
  });
}
