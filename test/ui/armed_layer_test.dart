import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/widgets/armed_layer.dart';

void main() {
  late int presses;
  late bool armedNow;

  Future<void> pumpLayer(WidgetTester tester) async {
    presses = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: ArmedLayer(
            builder: (context, armed) {
              armedNow = armed;
              return ElevatedButton(onPressed: () => presses++, child: const Text('Заново'));
            },
          ),
        ),
      ),
    );
  }

  testWidgets('a result layer presses nothing for its first moment', (tester) async {
    await pumpLayer(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Заново'), warnIfMissed: false);
    await tester.pump();
    expect(presses, 0);
    expect(armedNow, isFalse);

    // That tap was a press: past 0.7 s the layer still waits for 0.4 s of still hands.
    await tester.pump(const Duration(milliseconds: 300));
    expect(armedNow, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(armedNow, isTrue);
    await tester.tap(find.text('Заново'));
    await tester.pump();
    expect(presses, 1);
  });

  testWidgets('a finger that went down before arming never presses', (tester) async {
    await pumpLayer(tester);
    final finger = await tester.startGesture(tester.getCenter(find.text('Заново')));
    await tester.pump(const Duration(seconds: 1));
    expect(armedNow, isFalse, reason: 'a finger is still down');
    await finger.up();
    await tester.pump();
    expect(armedNow, isTrue);
    expect(presses, 0);
  });

  testWidgets('a held key cannot lock the layer for longer than 3 s', (tester) async {
    await pumpLayer(tester);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.pump(const Duration(milliseconds: 2900));
    expect(armedNow, isFalse);
    await tester.pump(const Duration(milliseconds: 200));
    expect(armedNow, isTrue);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
  });
}
