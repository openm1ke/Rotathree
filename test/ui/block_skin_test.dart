import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/model/color.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/field/block_look.dart';
import 'package:rotathree/ui/menu/settings_screen.dart';
import 'package:rotathree/ui/style.dart';

void main() {
  tearDown(() => BlockTones.setLook(classicColours, BlockSkin.classic));

  test('the skin is kept with the settings, and an unknown one is the classic', () {
    final settings = Settings.defaults().copyWith(skin: BlockSkin.dice);
    expect(Settings.fromJson(settings.toJson()).skin, BlockSkin.dice);
    expect(Settings.fromJson({'look': {'skin': 'marble'}}).skin, BlockSkin.classic);
    expect(Settings.fromJson(const {}).skin, BlockSkin.classic);
  });

  test('an instant hard drop is kept with the settings', () {
    final settings = Settings.defaults().copyWith(handling: const Handling(instantDrop: true));
    expect(Settings.fromJson(settings.toJson()).handling.instantDrop, isTrue);
    expect(Settings.defaults().handling.instantDrop, isFalse);
  });

  test('dice have one ivory for every slot, coloured skins keep the palette', () {
    final before = BlockTones.revision;
    BlockTones.setLook(classicColours, BlockSkin.dice);
    expect(BlockTones.revision, greaterThan(before));
    expect(BlockTones.skin, BlockSkin.dice);
    expect({for (final color in BlockColor.values) BlockTones.of(color).base}, {BlockTones.ivory.base});
    BlockTones.setLook(classicColours, BlockSkin.colourDice);
    expect(BlockTones.of(BlockColor.values.first).base, classicColours.first);
  });

  test('a slot shows its number in pips, and each slot its own sign', () {
    for (var slot = 0; slot < BlockColor.values.length; slot++) {
      expect(faceMarks(BlockSkin.dice, slot), hasLength(slot + 1));
      expect(faceMarks(BlockSkin.colourDice, slot), hasLength(slot + 1));
    }
    final signs = {for (var slot = 0; slot < BlockColor.values.length; slot++) faceMarks(BlockSkin.symbols, slot)};
    expect(signs, hasLength(BlockColor.values.length));
    expect(faceMarks(BlockSkin.classic, 0), isEmpty);
    // Every mark stays on the face; a gem is the whole block, within it.
    for (final skin in BlockSkin.values) {
      final edge = skin.body == BlockBody.gem ? blockHalf : 0.36;
      for (var slot = 0; slot < BlockColor.values.length; slot++) {
        for (final mark in faceMarks(skin, slot)) {
          for (final point in mark.points) {
            final at = mark.centre + point;
            expect(at.dx.abs(), lessThan(edge));
            expect(at.dy.abs(), lessThan(edge));
          }
        }
      }
    }
    // Each gem has its own cut.
    final cuts = {for (var slot = 0; slot < BlockColor.values.length; slot++) faceMarks(BlockSkin.gems, slot).length};
    expect(cuts.length, greaterThan(4));
  });

  testWidgets('the look tab picks how the blocks are drawn', (tester) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var settings = Settings.defaults();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: StatefulBuilder(
            builder: (context, setState) => SettingsScreen(
              settings: settings,
              stored: true,
              onBack: () {},
              onChange: (next) => setState(() => settings = next),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Вид'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('skin-dice')));
    await tester.pumpAndSettle();
    expect(settings.skin, BlockSkin.dice);
    expect(find.textContaining('У костей нет цветов'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('skin-symbols')));
    await tester.pumpAndSettle();
    expect(settings.skin, BlockSkin.symbols);
    expect(find.textContaining('У костей нет цветов'), findsNothing);
  });
}
