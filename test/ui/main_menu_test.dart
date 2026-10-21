import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/data/progress.dart';
import 'package:rotathree/ui/menu/main_menu.dart';

/// The menu's heights depend on the real typeface, not on the test font.
Future<void> loadExo2(WidgetTester tester) => tester.runAsync(() async {
  for (final (family, script) in [('Exo2', 'Latin'), ('Exo2Cyrillic', 'Cyrillic')]) {
    final loader = FontLoader(family);
    for (final weight in ['400', '600', '800', '800Italic', '900Italic']) {
      final bytes = File('assets/fonts/Exo2-$script-$weight.ttf').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
});

void main() {
  Future<void> pumpMenu(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainMenu(
            progress: Progress.initial(),
            hasSavedGames: true,
            onResume: () {},
            onTutorial: () {},
            onCampaign: () {},
            onPlayCampaign: () {},
            onCustom: () {},
            onStatistics: () {},
            onSettings: () {},
            onToggleMusic: () {},
            onLanguage: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Rect item(WidgetTester tester, String title) =>
      tester.getRect(find.ancestor(of: find.text(title), matching: find.byType(Material)).first);
  double scrollRoom(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent;

  testWidgets('a tall phone shows the menu as drawn', (tester) async {
    await loadExo2(tester);
    await pumpMenu(tester, const Size(390, 900));
    expect(item(tester, 'Кампания').top - item(tester, 'Обучение').top, 76);
    expect(scrollRoom(tester), 0);
  });

  testWidgets('a 360x640 phone fits all of the menu, Continue and the campaign card included', (tester) async {
    await loadExo2(tester);
    // 640 dp less the status bar and the gesture bar.
    await pumpMenu(tester, const Size(360, 600));
    expect(item(tester, 'Кампания').top - item(tester, 'Обучение').top, lessThan(76));
    expect(scrollRoom(tester), 0);
    expect(find.byKey(const ValueKey('campaign-shortcut')).hitTestable(), findsOneWidget);
  });

  testWidgets('a lower screen still reaches every entry by scrolling', (tester) async {
    await loadExo2(tester);
    await pumpMenu(tester, const Size(360, 420));
    expect(item(tester, 'Кампания').top - item(tester, 'Обучение').top, 58);
    expect(scrollRoom(tester), greaterThan(0));
  });
}
