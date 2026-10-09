import '../game/config/modes.dart';

/// Thousands separated by a no-break space, as the Russian locale does.
String formatNumber(int value) {
  final digits = value.abs().toString();
  final groups = <String>[];
  for (var end = digits.length; end > 0; end -= 3) {
    final start = end - 3 < 0 ? 0 : end - 3;
    groups.insert(0, digits.substring(start, end));
  }
  return '${value < 0 ? '−' : ''}${groups.join(' ')}';
}

/// Russian cardinal forms depend on both the last digit and the last two.
String counted(int value, String one, String few, String many) {
  final lastTwo = value.abs() % 100;
  final last = value.abs() % 10;
  final noun = lastTwo >= 11 && lastTwo <= 14
      ? many
      : switch (last) {
          1 => one,
          2 || 3 || 4 => few,
          _ => many,
        };
  return '${formatNumber(value)} $noun';
}

String formatPoints(int value) => counted(value, 'очко', 'очка', 'очков');
String formatColours(int value) => counted(value, 'цвет', 'цвета', 'цветов');
String formatGlasses(int value) =>
    counted(value, 'стакан', 'стакана', 'стаканов');
String formatCells(int value) => counted(value, 'клетка', 'клетки', 'клеток');
String formatTimes(int value) => counted(value, 'раз', 'раза', 'раз');

/// Durations as m:ss, or h:mm:ss from an hour on.
String formatDuration(double seconds) {
  final total = seconds.floor();
  final h = total ~/ 3600;
  final m = (total % 3600) ~/ 60;
  final s = total % 60;
  String pad(int n) => n.toString().padLeft(2, '0');
  return h > 0 ? '$h:${pad(m)}:${pad(s)}' : '$m:${pad(s)}';
}

/// The clock of the field: m:ss.
String formatClock(int seconds) => '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

String modeTitle(ModeId mode) => switch (mode) {
      ModeId.campaign => 'Кампания',
      ModeId.insane => 'Кошмар',
      ModeId.custom => 'Кастом',
    };
