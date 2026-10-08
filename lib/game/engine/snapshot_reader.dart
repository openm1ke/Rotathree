/// Strict, bounded decoding of local game saves. Invalid saves are rejected,
/// rather than partially applied to a live engine.
class SnapshotReader {
  SnapshotReader(Object? raw) {
    if (raw is! Map) throw const FormatException('Invalid game save');
    data = Map<String, Object?>.from(raw);
  }

  late final Map<String, Object?> data;

  int integer(String key, {int min = 0, int max = 1 << 40}) {
    final value = data[key];
    if (value is! num || !value.isFinite || value != value.round() || value < min || value > max) {
      throw FormatException('Invalid $key');
    }
    return value.toInt();
  }

  double number(String key, {double min = 0, double max = 1e12}) {
    final value = data[key];
    if (value is! num || !value.isFinite || value < min || value > max) {
      throw FormatException('Invalid $key');
    }
    return value.toDouble();
  }

  List<Object?> list(String key, {int max = 1000}) {
    final value = data[key];
    if (value is! List || value.length > max) throw FormatException('Invalid $key');
    return List<Object?>.from(value);
  }
}
