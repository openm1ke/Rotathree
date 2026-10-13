import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/widgets/backdrop.dart';

void main() {
  // Glows and grid are one layer; the menu's squares are a second one.
  int layers(WidgetTester tester) =>
      tester.widgetList(find.descendant(of: find.byType(Backdrop), matching: find.byType(CustomPaint))).length;

  testWidgets('the menu backdrop has a layer for the falling squares', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Backdrop(menu: true)));
    expect(layers(tester), 2);
  });

  testWidgets('the game backdrop has no squares layer', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Backdrop()));
    expect(layers(tester), 1);
  });

  testWidgets('the squares move frame by frame without errors', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Backdrop(menu: true)));
    for (var frame = 0; frame < 30; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('leaving the menu stops the squares and disposes cleanly', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Backdrop(menu: true)));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const MaterialApp(home: Backdrop()));
    await tester.pump(const Duration(milliseconds: 50));
    expect(layers(tester), 1);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
