import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/widgets/controls.dart';

void main() {
  testWidgets('the heading shows the mode in capitals above its title, with a back arrow', (tester) async {
    var backs = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ScreenHeading(kicker: 'Режим', title: 'Обучение', onBack: () => backs++),
      ),
    ));
    expect(find.text('РЕЖИМ'), findsOneWidget);
    expect(find.text('Обучение'), findsOneWidget);
    await tester.tap(find.byTooltip('Назад'));
    expect(backs, 1);
  });

  testWidgets('a heading without a way back shows no arrow', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: ScreenHeading(kicker: 'Режим', title: 'Кастом')),
    ));
    expect(find.byTooltip('Назад'), findsNothing);
    expect(find.text('Кастом'), findsOneWidget);
  });
}
