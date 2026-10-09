import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/format.dart';

void main() {
  test('Russian quantities handle the teens, endings and grouped numbers', () {
    const cases = {
      0: 'очков',
      1: 'очко',
      2: 'очка',
      4: 'очка',
      5: 'очков',
      11: 'очков',
      12: 'очков',
      14: 'очков',
      20: 'очков',
      21: 'очко',
      22: 'очка',
      25: 'очков',
      101: 'очко',
      111: 'очков',
      1001: 'очко',
      1012: 'очков',
    };
    for (final entry in cases.entries) {
      expect(
        formatPoints(entry.key),
        '${formatNumber(entry.key)} ${entry.value}',
      );
    }
    expect(formatPoints(-22), '−22 очка');
    expect(formatPoints(1001), '1 001 очко');
  });

  test('UI quantities use the noun appropriate to their number', () {
    expect(formatGlasses(1), '1 стакан');
    expect(formatGlasses(3), '3 стакана');
    expect(formatGlasses(5), '5 стаканов');
    expect(formatColours(3), '3 цвета');
    expect(formatColours(5), '5 цветов');
    expect(formatCells(4), '4 клетки');
    expect(formatCells(12), '12 клеток');
    expect(formatTimes(1), '1 раз');
    expect(formatTimes(2), '2 раза');
    expect(formatTimes(11), '11 раз');
    expect(formatTimes(22), '22 раза');
  });
}
