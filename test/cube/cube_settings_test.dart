import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/input/game_action.dart';
import 'package:rotathree/ui/menu/settings_screen.dart';

void main() {
  Future<List<Settings>> open(WidgetTester tester, {required bool cube}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final changes = <Settings>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => SettingsScreen(
            settings: changes.isEmpty ? Settings.defaults() : changes.last,
            stored: true,
            overlay: cube,
            cube: cube,
            onChange: (next) => setState(() => changes.add(next)),
            onBack: () {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return changes;
  }

  testWidgets('over a game of Cube the settings open on its look, and the hidden pieces can be hidden', (tester) async {
    final changes = await open(tester, cube: true);
    // The Interface tab, with Cube's switches first.
    expect(find.text('КУБ'), findsOneWidget);
    expect(tester.getTopLeft(find.text('КУБ')).dy, lessThan(300));
    final row = find.ancestor(of: find.text('Спрятанные фигуры сквозь блоки в объёме'), matching: find.byType(Column)).first;
    await tester.tap(find.descendant(of: row, matching: find.text('выкл')));
    await tester.pumpAndSettle();
    expect(changes.last.cube.xray, isFalse);
    expect(changes.last.cube.width, const CubeOptions().width);
  });

  testWidgets('Cube\'s pads are laid out apart from the flat game\'s', (tester) async {
    final changes = await open(tester, cube: false);
    await tester.scrollUntilVisible(find.text('Крестовины для'), 300, scrollable: find.byType(Scrollable).last);
    await tester.tap(find.text('Куб').last);
    await tester.pumpAndSettle();
    final centre = find.text('Объём');
    await tester.scrollUntilVisible(centre, 200, scrollable: find.byType(Scrollable).last);
    await tester.tap(centre);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Передний стакан').last);
    await tester.pumpAndSettle();
    expect(changes.last.cubeRightPad[PadSlot.center], GameAction.frontGlass);
    expect(changes.last.rightPad, defaultRightPad);
  });
}
