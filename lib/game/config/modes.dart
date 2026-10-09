import '../engine/speed_ramp.dart';
import 'game_config.dart';

/// The modes a game can be played in.
enum ModeId { campaign, insane, custom }

/// What the custom mode is set up with; kept between launches.
class CustomSetup {
  const CustomSetup({
    required this.extraGlasses,
    required this.colours,
    required this.armLength,
    required this.activeStep,
    required this.inactiveStep,
    required this.speedUp,
    required this.speedUpStep,
    required this.speedUpEvery,
    required this.gravityScope,
  });

  /// Glasses besides the one the game starts in: 0 to 3.
  final int extraGlasses;

  /// Colours in the pieces: 3 to 9.
  final int colours;
  final int armLength;
  final double activeStep;
  final double inactiveStep;

  /// Whether the falling speeds up with the score.
  final bool speedUp;

  /// How much faster each speed-up makes it, as a fraction (0.1 = 10%).
  final double speedUpStep;

  /// Points between two speed-ups.
  final int speedUpEvery;
  final GravityScope gravityScope;

  CustomSetup copyWith({
    int? extraGlasses,
    int? colours,
    int? armLength,
    double? activeStep,
    double? inactiveStep,
    bool? speedUp,
    double? speedUpStep,
    int? speedUpEvery,
    GravityScope? gravityScope,
  }) =>
      CustomSetup(
        extraGlasses: extraGlasses ?? this.extraGlasses,
        colours: colours ?? this.colours,
        armLength: armLength ?? this.armLength,
        activeStep: activeStep ?? this.activeStep,
        inactiveStep: inactiveStep ?? this.inactiveStep,
        speedUp: speedUp ?? this.speedUp,
        speedUpStep: speedUpStep ?? this.speedUpStep,
        speedUpEvery: speedUpEvery ?? this.speedUpEvery,
        gravityScope: gravityScope ?? this.gravityScope,
      );

  Map<String, Object> toJson() => {
        'extraGlasses': extraGlasses,
        'colours': colours,
        'armLength': armLength,
        'activeStep': activeStep,
        'inactiveStep': inactiveStep,
        'speedUp': speedUp,
        'speedUpStep': speedUpStep,
        'speedUpEvery': speedUpEvery,
        'gravityScope': gravityScope.name,
      };

  /// Makes sense of stored or edited values: anything missing or out of range
  /// falls back to the default or is clamped into its limits.
  factory CustomSetup.fromJson(Object? raw) {
    final map = raw is Map ? raw : const <Object?, Object?>{};
    double number(String key, double fallback, double min, double max) {
      final value = map[key];
      if (value is! num || !value.isFinite) return fallback;
      return value.clamp(min, max).toDouble();
    }

    return CustomSetup(
      extraGlasses: number('extraGlasses', defaultCustom.extraGlasses.toDouble(), 0, 3).round(),
      colours: number('colours', defaultCustom.colours.toDouble(), 3, 9).round(),
      armLength: number('armLength', defaultCustom.armLength.toDouble(), 4, 12).round(),
      activeStep: number('activeStep', defaultCustom.activeStep, 0.3, 2),
      inactiveStep: number('inactiveStep', defaultCustom.inactiveStep, 0.6, 6),
      speedUp: map['speedUp'] == true,
      speedUpStep: number('speedUpStep', defaultCustom.speedUpStep, 0.02, 0.3),
      speedUpEvery: number('speedUpEvery', defaultCustom.speedUpEvery.toDouble(), 200, 5000).round(),
      gravityScope: map['gravityScope'] == 'aboveCleared'
          ? GravityScope.aboveCleared
          : GravityScope.wholeGlass,
    );
  }
}

const defaultCustom = CustomSetup(
  extraGlasses: 3,
  colours: 3,
  armLength: 9,
  activeStep: 1,
  inactiveStep: 3,
  speedUp: false,
  speedUpStep: 0.1,
  speedUpEvery: 1000,
  gravityScope: GravityScope.wholeGlass,
);

/// A run: the engine configuration and, for modes that speed up, the ramp.
class RunPlan {
  const RunPlan({required this.config, this.ramp});

  final GameConfig config;
  final SpeedRamp? ramp;
}

/// Insane: six colours, four glasses, and the falling speeds up with every
/// thousand points until a glass overflows. It starts at the speed of the last
/// campaign level.
RunPlan insanePlan() => RunPlan(
      config: const GameConfig(
        glassCount: 4,
        numberOfColors: 6,
        activeStepSeconds: 0.9,
        inactiveStepSeconds: 2.6,
      ),
      ramp: const SpeedRamp(
        everyPoints: 1000,
        factor: 0.93,
        minActive: 0.15,
        minInactive: 0.5,
      ),
    );

/// Custom: everything from the setup; the speed-up is optional.
RunPlan customPlan(CustomSetup setup) => RunPlan(
      config: GameConfig(
        glassCount: 1 + setup.extraGlasses,
        numberOfColors: setup.colours,
        armLength: setup.armLength,
        activeStepSeconds: setup.activeStep,
        inactiveStepSeconds: setup.inactiveStep,
        gravityScope: setup.gravityScope,
      ),
      ramp: setup.speedUp
          ? SpeedRamp(
              everyPoints: setup.speedUpEvery,
              factor: 1 - setup.speedUpStep,
              minActive: 0.2,
              minInactive: 0.6,
            )
          : null,
    );
