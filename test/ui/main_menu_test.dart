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
  Future<void> pumpMenu(WidgetTester tester, Size size, {bool saved = true}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MainMenu(
            progress: Progress.initial(),
            hasSavedGames: saved,
            onResume: () {},
            onTutorial: () {},
            onCampaign: () {},
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

  Rect tile(WidgetTester tester, String name) => tester.getRect(find.byKey(ValueKey('menu-$name')));
  double scrollRoom(WidgetTester tester) =>
      tester.state<ScrollableState>(find.byType(Scrollable)).position.maxScrollExtent;

  testWidgets('a tall phone shows the tiles as drawn, one to a row, every one as tall', (tester) async {
    await loadExo2(tester);
    await pumpMenu(tester, const Size(390, 900));
    expect(tile(tester, 'campaign').height, 76);
    expect(tile(tester, 'custom').top - tile(tester, 'campaign').top, 86);
    expect(tile(tester, 'resume').height, tile(tester, 'settings').height);
    // The records and the settings side by side.
    expect(tile(tester, 'statistics').top, tile(tester, 'settings').top);
    expect(scrollRoom(tester), 0);
  });

  testWidgets('a 360x640 phone fits all of the menu, Continue included', (tester) async {
    await loadExo2(tester);
    // 640 dp less the status bar and the gesture bar.
    await pumpMenu(tester, const Size(360, 600));
    expect(scrollRoom(tester), 0);
    for (final name in ['resume', 'campaign', 'custom', 'tutorial', 'statistics', 'settings']) {
      expect(find.byKey(ValueKey('menu-$name')).hitTestable(), findsOneWidget, reason: name);
    }
  });

  testWidgets('a lower screen still reaches every tile by scrolling', (tester) async {
    await loadExo2(tester);
    await pumpMenu(tester, const Size(320, 330));
    expect(tile(tester, 'campaign').height, 54);
    expect(scrollRoom(tester), greaterThan(0));
  });

  testWidgets('a wide window puts the ways to play two to a row', (tester) async {
    await loadExo2(tester);
    await pumpMenu(tester, const Size(900, 500), saved: false);
    expect(tile(tester, 'campaign').top, tile(tester, 'custom').top);
    expect(tile(tester, 'tutorial').width, greaterThan(tile(tester, 'campaign').width));
    expect(find.byKey(const ValueKey('menu-resume')), findsNothing);
  });
}
