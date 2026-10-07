import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/ui/settings/pad_action.dart';
import 'package:rotathree/ui/settings/settings.dart';
import 'package:rotathree/ui/settings/settings_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('the default pads cover every action but pause', () {
    final assigned = {...defaultLeftPad.values, ...defaultRightPad.values};
    expect(
      assigned,
      containsAll(PadAction.values.where(
        (action) => action != PadAction.pause && action != PadAction.none,
      )),
    );
    expect(defaultLeftPad.keys, PadSlot.values);
    expect(defaultRightPad.keys, PadSlot.values);
  });

  test('settings survive a round trip through their text form', () {
    final settings = const Settings().copyWith(
      pads: const PadOptions().copyWith(
        left: {...defaultLeftPad, PadSlot.center: PadAction.pause},
        right: {...defaultRightPad, PadSlot.up: PadAction.hardDrop},
        scale: 1.15,
        opacity: 0.6,
        dasMs: 90,
        arrMs: 0,
        haptics: false,
        fieldGestures: true,
      ),
      game: const GameOptions(
        activeStepSeconds: 0.75,
        inactiveStepSeconds: 2,
        armLength: 8,
        glassCount: 2,
        numberOfColors: 6,
        gravityScope: GravityScope.aboveCleared,
        settleAfterBoardRotation: true,
      ),
      hud: const HudOptions(padLabels: false, score: true, stats: false, opacity: 0.35),
      turnMs: 420,
      screenShake: false,
    );
    final restored = Settings.decode(settings.encode());
    expect(restored.toJson(), settings.toJson());
    expect(restored.pads.left[PadSlot.center], PadAction.pause);
    expect(restored.game.key, settings.game.key);
  });

  test('anything missing or out of range falls back to its default', () {
    final cleaned = Settings.fromJson({
      'pads': {
        'left': {'up': 'teleport', 'center': 'pause'},
        'scale': 9,
        'dasMs': -5,
        'arrMs': 'fast',
      },
      'game': {'armLength': 99, 'numberOfColors': 7, 'glassCount': 1, 'gravityScope': 'sideways'},
      'hud': {'padLabels': 'no', 'opacity': 0},
      'turnMs': 5000,
    });
    expect(cleaned.pads.left[PadSlot.up], PadAction.hardDrop);
    expect(cleaned.pads.left[PadSlot.center], PadAction.pause);
    expect(cleaned.pads.right, defaultRightPad);
    expect(cleaned.pads.scale, 1.25);
    expect(cleaned.pads.dasMs, 0);
    expect(cleaned.pads.arrMs, 35);
    expect(cleaned.game.armLength, 12);
    expect(cleaned.game.numberOfColors, 6);
    expect(cleaned.game.glassCount, 2);
    expect(cleaned.game.gravityScope, GravityScope.wholeGlass);
    expect(cleaned.hud.padLabels, isTrue);
    expect(cleaned.hud.opacity, 0.1);
    expect(cleaned.turnMs, 800);
    expect(cleaned.screenShake, isTrue);

    expect(Settings.decode('{broken').toJson(), const Settings().toJson());
    expect(Settings.decode(null).toJson(), const Settings().toJson());
    expect(Settings.decode(jsonEncode([1, 2])).toJson(), const Settings().toJson());
  });

  test('the options become an engine configuration', () {
    final config = const GameOptions(
      glassCount: 3,
      numberOfColors: 5,
      armLength: 6,
      inactiveStepSeconds: 2,
    ).toConfig(seed: 11);
    expect(config.sides, [Side.top, Side.right, Side.left]);
    expect(config.numberOfColors, 5);
    expect(config.armLength, 6);
    expect(config.inactiveStepSeconds, 2);
    expect(config.seed, 11);
    // A different rule set is a different game.
    expect(const GameOptions(glassCount: 3).key, isNot(const GameOptions().key));
    expect(const GameOptions().key, const GameOptions().key);
  });

  test('the device store keeps what was saved', () async {
    SharedPreferences.setMockInitialValues({});
    final store = DeviceSettingsStore();
    expect((await store.load()).toJson(), const Settings().toJson());
    final changed = const Settings().copyWith(
      turnMs: 100,
      game: const GameOptions(numberOfColors: 5),
    );
    expect(await store.save(changed), isTrue);
    expect((await DeviceSettingsStore().load()).toJson(), changed.toJson());
  });
}
