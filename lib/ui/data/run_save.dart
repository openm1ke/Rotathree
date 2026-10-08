import '../../game/config/campaign.dart';
import '../../game/config/modes.dart';
import '../../game/engine/game_engine.dart';
import '../../game/engine/snapshot_reader.dart';
import '../../game/session.dart';
import 'stats.dart';

class RunTotals {
  const RunTotals({this.score = 0, this.pieces = 0, this.matches = 0, this.bestCombo = 0, this.seconds = 0});
  static const none = RunTotals();
  final int score, pieces, matches, bestCombo;
  final double seconds;
  Map<String, Object> toJson() => {
    'score': score,
    'pieces': pieces,
    'matches': matches,
    'bestCombo': bestCombo,
    'seconds': seconds,
  };
  factory RunTotals.fromJson(Object? raw) {
    final r = SnapshotReader(raw);
    return RunTotals(
      score: r.integer('score'),
      pieces: r.integer('pieces'),
      matches: r.integer('matches'),
      bestCombo: r.integer('bestCombo'),
      seconds: r.number('seconds'),
    );
  }
}

class SavedBanner {
  const SavedBanner({
    required this.kicker,
    required this.title,
    this.sub,
    required this.left,
    required this.blocking,
    this.pendingLevel,
    this.colours = 0,
  });
  final String kicker, title;
  final String? sub;
  final double left;
  final bool blocking;
  final int? pendingLevel;
  final int colours;
  Map<String, Object?> toJson() => {
    'kicker': kicker,
    'title': title,
    'sub': sub,
    'left': left,
    'blocking': blocking,
    'pendingLevel': pendingLevel,
    'colours': colours,
  };
  factory SavedBanner.fromJson(Object? raw) {
    final r = SnapshotReader(raw);
    if (r.data['kicker'] is! String || r.data['title'] is! String || r.data['blocking'] is! bool) {
      throw const FormatException('Invalid banner');
    }
    return SavedBanner(
      kicker: r.data['kicker'] as String,
      title: r.data['title'] as String,
      sub: r.data['sub'] as String?,
      left: r.number('left', max: 10),
      blocking: r.data['blocking'] as bool,
      pendingLevel: r.data['pendingLevel'] == null ? null : r.integer('pendingLevel', max: campaignLast),
      colours: r.integer('colours', max: 9),
    );
  }
}

/// One resumable run. The two platforms keep their own save format and RNG.
class RunSave {
  const RunSave({
    required this.id,
    required this.session,
    required this.engine,
    required this.carry,
    required this.levelBase,
    required this.savedAt,
    this.banner,
  });
  final String id;
  final Session session;
  final Map<String, Object?> engine;
  final RunTotals carry;
  final int levelBase, savedAt;
  final SavedBanner? banner;

  static RunSave? read(Object? raw) {
    if (raw == null) return null;
    try {
      final r = SnapshotReader(raw);
      if (r.integer('version', max: 1) != 1 ||
          r.data['id'] is! String ||
          (r.data['id'] as String).isEmpty ||
          (r.data['id'] as String).length > 80) {
        return null;
      }
      final s = SnapshotReader(r.data['session']);
      final session = switch (s.data['mode']) {
        'campaign' => CampaignSession(s.integer('level', max: campaignLast)),
        'insane' => const InsaneSession(),
        'custom' => CustomSession(CustomSetup.fromJson(s.data['setup'])),
        _ => throw const FormatException('Invalid session'),
      };
      final engine = SnapshotReader(r.data['engine']).data;
      final plan = planFor(session);
      (GameEngine(config: plan.config)..setRamp(plan.ramp)).restoreSnapshot(engine);
      final base = r.integer('levelBase');
      if (base > (engine['score'] as num)) return null;
      final banner = r.data['banner'] == null ? null : SavedBanner.fromJson(r.data['banner']);
      if (banner?.pendingLevel != null && (session is! CampaignSession || banner!.pendingLevel != session.level + 1)) {
        return null;
      }
      return RunSave(
        id: r.data['id'] as String,
        session: session,
        engine: engine,
        carry: RunTotals.fromJson(r.data['carry']),
        levelBase: base,
        savedAt: r.integer('savedAt', max: 1 << 53),
        banner: banner,
      );
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
    'version': 1,
    'id': id,
    'session': switch (session) {
      CampaignSession(:final level) => {'mode': 'campaign', 'level': level},
      InsaneSession() => {'mode': 'insane'},
      CustomSession(:final setup) => {'mode': 'custom', 'setup': setup.toJson()},
    },
    'engine': engine,
    'carry': carry.toJson(),
    'levelBase': levelBase,
    'savedAt': savedAt,
    'banner': banner?.toJson(),
  };

  RunRecord abandoned() => RunRecord(
    id: id,
    mode: switch (session) {
      CampaignSession() => ModeId.campaign,
      InsaneSession() => ModeId.insane,
      CustomSession() => ModeId.custom,
    },
    at: DateTime.now().millisecondsSinceEpoch,
    score: carry.score + (engine['score'] as int),
    pieces: carry.pieces + (engine['piecesPlaced'] as int),
    matches: carry.matches + (engine['matches'] as int),
    bestCombo: carry.bestCombo > (engine['bestCombo'] as int) ? carry.bestCombo : engine['bestCombo'] as int,
    seconds: carry.seconds + (engine['elapsedSeconds'] as num).toDouble(),
    level: switch (session) {
      CampaignSession(:final level) => level + 1,
      _ => (engine['speedLevel'] as int) + 1,
    },
    completed: false,
    interrupted: true,
  );
}
