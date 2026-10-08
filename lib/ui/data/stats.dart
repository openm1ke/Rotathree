import '../../game/config/modes.dart';

/// One finished run.
class RunRecord {
  const RunRecord({
    required this.id,
    required this.mode,
    required this.at,
    required this.score,
    required this.pieces,
    required this.matches,
    required this.bestCombo,
    required this.seconds,
    required this.level,
    required this.completed,
    this.interrupted = false,
  });

  factory RunRecord.fromJson(Map<Object?, Object?> raw) => RunRecord(
    id: '${raw['id'] ?? ''}',
    mode: ModeId.values.firstWhere((m) => m.name == raw['mode'], orElse: () => ModeId.custom),
    at: _count(raw['at']),
    score: _count(raw['score']),
    pieces: _count(raw['pieces']),
    matches: _count(raw['matches']),
    bestCombo: _count(raw['bestCombo']),
    seconds: raw['seconds'] is num ? (raw['seconds'] as num).toDouble() : 0,
    level: _count(raw['level']),
    completed: raw['completed'] == true,
    interrupted: raw['interrupted'] == true,
  );

  final String id;
  final ModeId mode;

  /// Milliseconds since the epoch, when the run ended.
  final int at;
  final int score;
  final int pieces;
  final int matches;
  final int bestCombo;
  final double seconds;

  /// The campaign level reached, or the speed level + 1 of Insane and Custom.
  final int level;

  /// Campaign only: whether the last level was finished.
  final bool completed;
  final bool interrupted;

  Map<String, Object> toJson() => {
    'id': id,
    'mode': mode.name,
    'at': at,
    'score': score,
    'pieces': pieces,
    'matches': matches,
    'bestCombo': bestCombo,
    'seconds': seconds,
    'level': level,
    'completed': completed,
    'interrupted': interrupted,
  };
}

/// The totals of one mode.
class ModeStats {
  const ModeStats({
    this.games = 0,
    this.completed = 0,
    this.totalScore = 0,
    this.bestScore = 0,
    this.totalPieces = 0,
    this.totalMatches = 0,
    this.bestCombo = 0,
    this.totalSeconds = 0,
    this.bestLevel = 0,
  });

  factory ModeStats.fromJson(Object? raw) {
    if (raw is! Map) return const ModeStats();
    return ModeStats(
      games: _count(raw['games']),
      completed: _count(raw['completed']),
      totalScore: _count(raw['totalScore']),
      bestScore: _count(raw['bestScore']),
      totalPieces: _count(raw['totalPieces']),
      totalMatches: _count(raw['totalMatches']),
      bestCombo: _count(raw['bestCombo']),
      totalSeconds: raw['totalSeconds'] is num ? (raw['totalSeconds'] as num).toDouble() : 0,
      bestLevel: _count(raw['bestLevel']),
    );
  }

  final int games;
  final int completed;
  final int totalScore;
  final int bestScore;
  final int totalPieces;
  final int totalMatches;
  final int bestCombo;
  final double totalSeconds;
  final int bestLevel;

  /// The totals with [run] added.
  ModeStats added(RunRecord run) => ModeStats(
    games: games + 1,
    completed: completed + (run.completed ? 1 : 0),
    totalScore: totalScore + run.score,
    bestScore: run.score > bestScore ? run.score : bestScore,
    totalPieces: totalPieces + run.pieces,
    totalMatches: totalMatches + run.matches,
    bestCombo: run.bestCombo > bestCombo ? run.bestCombo : bestCombo,
    totalSeconds: totalSeconds + run.seconds,
    bestLevel: run.level > bestLevel ? run.level : bestLevel,
  );

  Map<String, Object> toJson() => {
    'games': games,
    'completed': completed,
    'totalScore': totalScore,
    'bestScore': bestScore,
    'totalPieces': totalPieces,
    'totalMatches': totalMatches,
    'bestCombo': bestCombo,
    'totalSeconds': totalSeconds,
    'bestLevel': bestLevel,
  };
}

/// The statistics of every mode, and the last runs.
class Stats {
  const Stats({required this.modes, required this.recent});

  factory Stats.empty() => const Stats(
    modes: {ModeId.campaign: ModeStats(), ModeId.insane: ModeStats(), ModeId.custom: ModeStats()},
    recent: [],
  );

  factory Stats.fromJson(Object? raw) {
    if (raw is! Map) return Stats.empty();
    final modesRaw = raw['modes'] is Map ? raw['modes'] as Map : const {};
    final recentRaw = raw['recent'];
    return Stats(
      modes: {for (final mode in ModeId.values) mode: ModeStats.fromJson(modesRaw[mode.name])},
      recent: [
        if (recentRaw is List)
          for (final item in recentRaw)
            if (item is Map) RunRecord.fromJson(item),
      ].take(recentLimit).toList(),
    );
  }

  static const recentLimit = 20;

  final Map<ModeId, ModeStats> modes;

  /// The newest run first.
  final List<RunRecord> recent;

  /// The statistics with [run] added to its mode and to the recent runs.
  Stats withRun(RunRecord run) => recent.any((old) => old.id == run.id)
      ? this
      : Stats(
          modes: {...modes, run.mode: modes[run.mode]!.added(run)},
          recent: [run, ...recent].take(recentLimit).toList(),
        );

  Map<String, Object> toJson() => {
    'modes': {for (final mode in ModeId.values) mode.name: modes[mode]!.toJson()},
    'recent': [for (final run in recent) run.toJson()],
  };
}

int _count(Object? value) => value is num && value.isFinite ? value.round().clamp(0, 1 << 52) : 0;
