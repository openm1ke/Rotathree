import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/modes.dart';
import 'package:rotathree/ui/data/bindings.dart';
import 'package:rotathree/ui/data/progress.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/data/stats.dart';
import 'package:rotathree/ui/format.dart';
import 'package:rotathree/ui/input/game_action.dart';

void main() {
  test('the defaults survive a round trip through JSON', () {
    final stored = jsonDecode(jsonEncode(Settings.defaults().toJson()));
    final again = Settings.fromJson(stored);
    expect(again.bindings[GameAction.hardDrop], [PhysicalKeyboardKey.keyS, PhysicalKeyboardKey.space]);
    expect(again.leftPad, defaultLeftPad);
    expect(again.rightPad, defaultRightPad);
    expect(again.handling.dasMs, 150);
    expect(again.palettes.active, 'classic');
  });

  test('a key bound twice keeps its first use', () {
    final bindings = sanitizeBindings({
      'moveLeft': [PhysicalKeyboardKey.keyA.usbHidUsage],
      'moveRight': [PhysicalKeyboardKey.keyA.usbHidUsage],
    });
    expect(bindings[GameAction.moveLeft], [PhysicalKeyboardKey.keyA]);
    expect(bindings[GameAction.moveRight], isEmpty);
  });

  test('binding a key takes it away from the action it was on', () {
    final bindings = bindKey(defaultBindings(), GameAction.moveLeft, 0, PhysicalKeyboardKey.keyD);
    expect(bindings[GameAction.moveLeft], [PhysicalKeyboardKey.keyD]);
    expect(bindings[GameAction.moveRight], isEmpty);
    expect(actionForKey(bindings, PhysicalKeyboardKey.keyD), GameAction.moveLeft);
  });

  test('a slot can be cleared, and the second one is kept', () {
    final cleared = unbindKey(defaultBindings(), GameAction.hardDrop, 0);
    expect(cleared[GameAction.hardDrop], [PhysicalKeyboardKey.space]);
  });

  test('a custom palette keeps its colours, and bad ones fall back', () {
    final palettes = Palettes.fromJson({
      'active': 'mine',
      'sets': [
        {
          'id': 'mine',
          'name': 'Мой',
          'colours': ['#ff0000', 'nope'],
        },
      ],
    });
    expect(palettes.sets.length, builtinPalettes.length + 1);
    expect(palettes.activeSet.id, 'mine');
    expect(palettes.activeSet.colours[0], const Color(0xFFFF0000));
    expect(palettes.activeSet.colours[1], builtinPalettes.first.colours[1]);
  });

  test('colours print as hex and read back', () {
    expect(colourToHex(const Color(0xFF3B82FF)), '#3b82ff');
    expect(colourFromHex('#3b82ff'), const Color(0xFF3B82FF));
    expect(colourFromHex('blue'), isNull);
  });

  test('a finished level keeps its best score and opens the next one', () {
    final progress = Progress.initial().levelFinished(0, 1500).levelFinished(0, 900);
    expect(progress.best[0], 1500);
    expect(progress.unlocked, 1);
    expect(progress.completed, isFalse);
  });

  test('a run is added to its mode and to the recent runs', () {
    final run = RunRecord(
      id: 'a',
      mode: ModeId.custom,
      at: 0,
      score: 700,
      pieces: 20,
      matches: 4,
      bestCombo: 2,
      seconds: 90,
      level: 1,
      completed: false,
    );
    final stats = Stats.empty().withRun(run);
    expect(stats.modes[ModeId.custom]!.games, 1);
    expect(stats.modes[ModeId.custom]!.bestScore, 700);
    expect(stats.recent.single.id, 'a');
  });

  test('unreadable stored values fall back to the defaults', () {
    expect(Settings.fromJson('garbage').handling.arrMs, 35);
    expect(Progress.fromJson(null).unlocked, 0);
    expect(Stats.fromJson(42).recent, isEmpty);
  });

  test('numbers are grouped as the Russian locale does', () {
    expect(formatNumber(1234567), '1 234 567');
    expect(formatNumber(-950), '−950');
    expect(formatDuration(3725), '1:02:05');
  });
}
