import '../../game/config/campaign.dart';

/// How far the campaign has been played.
class Progress {
  const Progress({required this.unlocked, required this.completed, required this.best});

  factory Progress.initial() => Progress(
        unlocked: 0,
        completed: false,
        best: List.filled(campaignLevels.length, 0),
      );

  factory Progress.fromJson(Object? raw) {
    final base = Progress.initial();
    if (raw is! Map) return base;
    final unlockedRaw = raw['unlocked'];
    final unlocked = unlockedRaw is num ? unlockedRaw.round().clamp(0, campaignLast) : 0;
    final stored = raw['best'];
    return Progress(
      unlocked: unlocked,
      completed: raw['completed'] == true,
      best: [
        for (var i = 0; i < campaignLevels.length; i++)
          stored is List && i < stored.length && stored[i] is num
              ? (stored[i] as num).round().clamp(0, 1 << 30)
              : 0,
      ],
    );
  }

  /// Index of the highest level that is open.
  final int unlocked;

  /// Whether the last level has been finished, which opens Insane.
  final bool completed;

  /// The best score of each level; 0 when never finished.
  final List<int> best;

  Map<String, Object> toJson() => {'unlocked': unlocked, 'completed': completed, 'best': best};

  /// The progress after level [index] was finished with [score].
  Progress levelFinished(int index, int score) => Progress(
        unlocked: unlocked > index + 1 ? unlocked : (index + 1).clamp(0, campaignLast),
        completed: completed || index == campaignLast,
        best: [
          for (var i = 0; i < best.length; i++) i == index && score > best[i] ? score : best[i],
        ],
      );
}
