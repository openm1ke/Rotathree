import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/game/hud.dart';

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets('score bonus stays outside the level label at width $width', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: const GameReadout(
          hud: HudState(score: 1500, combo: 3, bestCombo: 3, matches: 12, pieces: 16, seconds: 41,
            level: 2, into: 300, target: 1800, colours: 3, glasses: 2, speed: 0),
          options: HudOptions(),
          callout: Callout.score(id: 1, points: 400, combo: 3),
        )),
      ))));
      await tester.pump(const Duration(milliseconds: 220));
      final bonus = tester.getRect(find.text('+400  3× комбо'));
      final level = tester.getRect(find.text('Уровень 2 / 15'));
      expect(bonus.overlaps(level), isFalse);
      expect(find.text('1 500 очков'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
