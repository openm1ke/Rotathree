import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/config/campaign.dart';
import 'package:rotathree/game/config/game_config.dart';
import 'package:rotathree/game/config/modes.dart';
import 'package:rotathree/game/engine/game_event.dart';
import 'package:rotathree/game/engine/speed_ramp.dart';
import 'package:rotathree/game/model/side.dart';
import 'package:rotathree/game/session.dart';
import 'package:rotathree/game/state/game_state.dart';

import 'helpers.dart';

void main() {
  group('the campaign', () {
    test('fifteen levels in stages of 3, 4, 5 and 6 colours, with more glasses', () {
      expect(campaignLevels.length, 15);
      expect(campaignLevels.map((level) => level.colours).toSet(), {3, 4, 5, 6});
      expect(campaignLast, 14);
      for (var i = 1; i < campaignLevels.length; i++) {
        expect(campaignLevels[i].target, greaterThan(campaignLevels[i - 1].target));
        expect(campaignLevels[i].colours, greaterThanOrEqualTo(campaignLevels[i - 1].colours));
      }
      expect(campaignLevels.last.colours, 6);
      expect(campaignLevels.last.glasses, 4);
    });

    test('each stage starts again with one glass', () {
      final starts = [
        for (var i = 0; i < campaignLevels.length; i++)
          if (startsStage(i)) i,
      ];
      expect(starts, [0, 3, 7, 11]);
      expect(campaignLevels[3].glasses, 1);
      expect(campaignLevels[7].glasses, 1);
    });

    test('the last three levels step the falling up', () {
      final faster = [
        for (var i = 0; i < campaignLevels.length; i++)
          if (campaignLevels[i].activeStep < 1) i,
      ];
      expect(faster, [12, 13, 14]);
    });

    test('a level asks for its own glasses, colours and speeds', () {
      final config = levelConfig(campaignLevels[13]);
      expect(config.glassCount, 3);
      expect(config.numberOfColors, 6);
      expect(config.activeStepSeconds, 0.92);
      expect(config.inactiveStepSeconds, 2.7);
    });
  });

  group('modes and sessions', () {
    test('Insane: six colours, four glasses, and a speed that rises', () {
      final plan = planFor(const InsaneSession());
      expect(plan.config.glassCount, 4);
      expect(plan.config.numberOfColors, 6);
      expect(plan.ramp!.everyPoints, 1000);
    });

    test('custom: the setup decides glasses, colours and the optional speed-up', () {
      final plain = planFor(const CustomSession(defaultCustom));
      expect(plain.config.glassCount, 4);
      expect(plain.config.numberOfColors, 3);
      expect(plain.ramp, isNull);

      final faster = planFor(
        CustomSession(
          defaultCustom.copyWith(extraGlasses: 0, colours: 9, speedUp: true, speedUpStep: 0.2, speedUpEvery: 2000),
        ),
      );
      expect(faster.config.glassCount, 1);
      expect(faster.config.numberOfColors, 9);
      expect(faster.ramp!.factor, closeTo(0.8, 1e-9));
      expect(faster.ramp!.everyPoints, 2000);
    });

    test('stored custom values are clamped into their limits', () {
      final setup = CustomSetup.fromJson({
        'extraGlasses': 9,
        'colours': 1,
        'armLength': 'long',
        'speedUp': 'yes',
        'gravityScope': 'aboveCleared',
        'speedUpStep': 0.5,
      });
      expect(setup.extraGlasses, 3);
      expect(setup.colours, 3);
      expect(setup.armLength, defaultCustom.armLength);
      expect(setup.speedUp, isFalse);
      expect(setup.gravityScope, GravityScope.aboveCleared);
      expect(setup.speedUpStep, 0.3);
    });

    test('custom arm lengths 4 through 12 survive saving and configure the board', () {
      for (var length = 4; length <= 12; length++) {
        final setup = CustomSetup.fromJson(defaultCustom.copyWith(armLength: length).toJson());
        expect(setup.armLength, length);
        expect(customPlan(setup).config.armLength, length);
      }
      expect(CustomSetup.fromJson({'armLength': 0}).armLength, 4);
      expect(CustomSetup.fromJson({'armLength': 100}).armLength, 12);
    });

    test('a custom setup survives a JSON round trip', () {
      final setup = defaultCustom.copyWith(extraGlasses: 2, colours: 7, speedUp: true);
      final again = CustomSetup.fromJson(setup.toJson());
      expect(again.extraGlasses, 2);
      expect(again.colours, 7);
      expect(again.speedUp, isTrue);
    });
  });

  group('the engine during a campaign', () {
    test('a glass added during play grows first, then gets its first piece', () {
      final engine = newEngine(config: testConfig.copyWith(glassCount: 1));
      expect(engine.sides, [Side.top]);
      expect(engine.addGlass(), Side.right);
      expect(engine.state.phase, GamePhase.building);
      expect(engine.state.buildingSide, Side.right);
      expect(engine.state.incoming[Side.right], isNull);

      engine.update(testConfig.buildSeconds + 0.01);
      expect(engine.state.phase, GamePhase.playing);
      expect(engine.state.incoming[Side.right], isNotNull);
      expect(engine.drainEvents().whereType<GlassAdded>().map((e) => e.side), [Side.right]);
    });

    test('the next glass is the one after the last in play', () {
      final engine = newEngine(config: testConfig.copyWith(glassCount: 2));
      expect(engine.sides, [Side.top, Side.right]);
      expect(engine.addGlass(), Side.left);
      engine.update(testConfig.buildSeconds + 0.01);
      expect(engine.addGlass(), Side.bottom);
    });

    test('changing the step times keeps the pieces where they are', () {
      final engine = newEngine(config: testConfig);
      engine.update(0.4);
      final before = engine.state.incoming[Side.top]!.row;
      engine.setSteps(0.92, 2.7);
      expect(engine.config.activeStepSeconds, 0.92);
      expect(engine.config.inactiveStepSeconds, 2.7);
      expect(engine.state.incoming[Side.top]!.row, before);
    });

    test('the speed steps up with the score and never past its minimum', () {
      final engine = newEngine(config: testConfig.copyWith(glassCount: 1));
      engine.setRamp(const SpeedRamp(everyPoints: 100, factor: 0.5, minActive: 0.2, minInactive: 0.6));
      // A line of three is worth 100 points: one step of the ramp.
      engine.incoming.put(Side.top, horizontal([r, r, r]));
      engine.dropActive();
      while (engine.phase == GamePhase.pieceDropping) {
        engine.update(0.002);
      }
      final ups = engine.drainEvents().whereType<SpeedUp>().toList();
      expect(ups.single.level, 1);
      expect(engine.config.activeStepSeconds, closeTo(testConfig.activeStepSeconds * 0.5, 1e-9));
      expect(engine.state.speedLevel, 1);
    });
  });
}
