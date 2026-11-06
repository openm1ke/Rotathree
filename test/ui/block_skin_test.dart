import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/game/model/color.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/field/block_look.dart';
import 'package:rotathree/ui/menu/settings_screen.dart';
import 'package:rotathree/ui/style.dart';

void main() {
  tearDown(() => BlockTones.setLook(classicColours, BlockSkin.classic));

  test('the skin is kept with the settings, and one no longer offered is the classic', () {
    final settings = Settings.defaults().copyWith(skin: BlockSkin.retro);
    expect(Settings.fromJson(settings.toJson()).skin, BlockSkin.retro);
    for (final gone in ['dice', 'neon', 'gems', 'symbols', 'marble']) {
      expect(Settings.fromJson({'look': {'skin': gone}}).skin, BlockSkin.classic);
    }
    expect(Settings.fromJson(const {}).skin, BlockSkin.classic);
  });

  test('an instant hard drop is kept with the settings', () {
    final settings = Settings.defaults().copyWith(handling: const Handling(instantDrop: true));
    expect(Settings.fromJson(settings.toJson()).handling.instantDrop, isTrue);
    expect(Settings.defaults().handling.instantDrop, isFalse);
  });

  test('every skin keeps the palette, and a change of skin redraws the blocks', () {
    final before = BlockTones.revision;
    BlockTones.setLook(classicColours, BlockSkin.retro);
    expect(BlockTones.revision, greaterThan(before));
    expect(BlockTones.skin, BlockSkin.retro);
    expect(BlockTones.of(BlockColor.values.first).base, classicColours.first);
  });

  test('a die shows its colour\'s number in pips, on its face', () {
    for (var slot = 0; slot < BlockColor.values.length; slot++) {
      expect(faceMarks(BlockSkin.colourDice, slot), hasLength(slot + 1));
      expect(faceMarks(BlockSkin.classic, slot), isEmpty);
      expect(faceMarks(BlockSkin.retro, slot), isEmpty);
      for (final mark in faceMarks(BlockSkin.colourDice, slot)) {
        for (final point in mark.points) {
          final at = mark.centre + point;
          expect(at.dx.abs(), lessThan(0.36));
          expect(at.dy.abs(), lessThan(0.36));
        }
      }
    }
    // White pips would not show on a white die.
    expect(markColour(BlockTones.fromBase(const Color(0xFFE4EAFA))), isNot(const Color(0xF7FFFFFF)));
    expect(markColour(BlockTones.fromBase(const Color(0xFF3B82FF))), const Color(0xF7FFFFFF));
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
    await tester.tap(find.byKey(const ValueKey('skin-retro')));
    await tester.pumpAndSettle();
    expect(settings.skin, BlockSkin.retro);
    await tester.tap(find.byKey(const ValueKey('skin-colourDice')));
    await tester.pumpAndSettle();
    expect(settings.skin, BlockSkin.colourDice);
    expect(find.byKey(const ValueKey('skin-dice')), findsNothing);
  });
}
