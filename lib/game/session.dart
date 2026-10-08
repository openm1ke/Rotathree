import 'config/campaign.dart';
import 'config/modes.dart';

/// A game being played: one campaign level, Insane, or a custom setup. The
/// setup is copied when the game starts, so changing it later does not touch
/// a game in progress.
sealed class Session {
  const Session();
}

final class CampaignSession extends Session {
  const CampaignSession(this.level);

  /// Index into [campaignLevels].
  final int level;
}

final class InsaneSession extends Session {
  const InsaneSession();
}

final class CustomSession extends Session {
  const CustomSession(this.setup);

  final CustomSetup setup;
}

/// The engine configuration and speed ramp of a session.
RunPlan planFor(Session session) => switch (session) {
      CampaignSession(:final level) =>
        RunPlan(config: levelConfig(campaignLevels[level])),
      InsaneSession() => insanePlan(),
      CustomSession(:final setup) => customPlan(setup),
    };
