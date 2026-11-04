// A game of Cube kept between visits, as the flat game keeps its runs
// (webapp/src/cube/save.ts): taken while the game is at rest, so that it
// comes back exactly as it was left. One endless game and one campaign
// level may be kept at a time.
import '../game/config/modes.dart';
import '../ui/data/stats.dart';
import 'campaign.dart';
import 'rules.dart';

/// Which of the two kept games: the endless one or a level of the campaign.
enum CubeKind { endless, campaign }

CubeKind kindOf(int? level) => level == null ? CubeKind.endless : CubeKind.campaign;

class CubeSave {
  const CubeSave({required this.id, required this.savedAt, required this.game, this.level});

  /// The run's id, kept for its record in the statistics.
  final String id;
  final int savedAt;
  final Map<String, Object?> game;

  /// The campaign level, by index; null for the endless game.
  final int? level;

  CubeKind get kind => kindOf(level);

  /// A save as stored, or null for anything that does not restore a game.
  static CubeSave? read(Object? raw) {
    if (raw is! Map) return null;
    try {
      final id = raw['id'];
      final savedAt = raw['savedAt'];
      final level = raw['level'];
      final game = raw['game'];
      if (raw['version'] != 1 || id is! String || id.isEmpty || id.length > 80) return null;
      if (savedAt is! num || game is! Map) return null;
      if (level != null && (level is! int || level < 0 || level > cubeCampaignLast)) return null;
      CubeGame.restore(game);
      return CubeSave(id: id, savedAt: savedAt.round(), game: Map<String, Object?>.from(game), level: level as int?);
    } catch (_) {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
        'version': 1,
        'id': id,
        'savedAt': savedAt,
        'game': game,
        if (level != null) 'level': level,
      };

  /// The record of this game given up: a new one was started instead.
  RunRecord abandoned() {
    final restored = CubeGame.restore(game);
    return RunRecord(
      id: id,
      mode: level == null ? ModeId.cube : ModeId.cubeCampaign,
      at: DateTime.now().millisecondsSinceEpoch,
      score: restored.score,
      pieces: restored.placed,
      matches: restored.matches,
      bestCombo: restored.bestCombo,
      seconds: restored.seconds,
      level: level == null ? restored.speedLevel + 1 : level! + 1,
      completed: false,
      interrupted: true,
    );
  }
}

/// Both slots; anything that is not one of them is dropped.
Map<CubeKind, CubeSave> readCubeRuns(Object? raw) {
  final single = CubeSave.read(raw);
  if (single != null) return {single.kind: single};
  if (raw is! Map || raw['version'] != 2 || raw['runs'] is! Map) return {};
  final runs = raw['runs'] as Map;
  return {
    for (final kind in CubeKind.values)
      if (CubeSave.read(runs[kind.name]) case final CubeSave save when save.kind == kind) kind: save,
  };
}

Map<String, Object?> cubeRunsToJson(Map<CubeKind, CubeSave> runs) => {
      'version': 2,
      'runs': {for (final MapEntry(:key, :value) in runs.entries) key.name: value.toJson()},
    };
