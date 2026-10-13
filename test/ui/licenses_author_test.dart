import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/menu/licenses.dart';

void main() {
  testWidgets('the licences name the author and give a contact e-mail', (tester) async {
    // Tall enough that the whole list is built, the author section included.
    tester.view.physicalSize = const Size(400, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ListView(children: licenseSections(context)),
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Mikhail Shmyrev'), findsOneWidget);
    expect(find.byWidgetPredicate((w) => w is SelectableText && w.data == 'muxaujish@yandex.ru'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
