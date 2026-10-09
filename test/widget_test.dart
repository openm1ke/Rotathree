import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/app.dart';
import 'package:rotathree/ui/data/store.dart';
import 'package:rotathree/ui/i18n/strings.dart';
import 'package:rotathree/game/config/modes.dart';
import 'package:rotathree/ui/game/game_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The backdrop animates for ever, so the screens are pumped for a while
/// instead of until nothing is left to animate. Real time is let through so
/// that the stored settings can be read.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({'rotathree.tutorial.v1': 'true'});
  });

  testWidgets('the menu opens and leads to the campaign', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);

    expect(find.text('Кампания'), findsWidgets);
    expect(find.text('Настройки'), findsOneWidget);

    await tester.tap(find.text('Кампания'));
    await settle(tester);
    expect(find.text('Кампания'), findsWidgets);
    final swatches = find.descendant(
      of: find.byKey(const ValueKey('campaign-colours-0')),
      matching: find.byType(Container),
    );
    expect(swatches, findsNWidgets(3));
    expect(find.text('1 ст. · 1 с/шаг'), findsWidgets);
    expect(find.text('Цель 1\u00a0200'), findsOneWidget);
  });

  testWidgets('a custom game can be set up and started', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);

    await tester.tap(find.text('Кастом'));
    await settle(tester);
    expect(find.text('Кастом'), findsWidgets);

    // The screens are lists: the button at the bottom is built once it is scrolled to.
    await tester.scrollUntilVisible(find.text('Начать'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Начать'));
    await settle(tester);
    expect(find.text('Пауза'), findsOneWidget);
  });

  testWidgets('new players see training and can skip into the chosen game', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);
    await tester.tap(find.text('Кастом'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Начать'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Начать'));
    await settle(tester);
    expect(find.text('Одна фигура — три клетки'), findsOneWidget);
    await tester.tap(find.text('Пропустить'));
    await settle(tester);
    expect(find.text('Одна фигура — три клетки'), findsNothing);
    expect(find.text('Пауза'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('rotathree.tutorial.v1'), 'true');
  });

  testWidgets('system Back keeps separate campaign and custom games for Continue', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);
    await tester.tap(find.text('Кампания'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('campaign-level-0')));
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);
    final first = (await AppStore.open()).loadRuns()[ModeId.campaign]!;
    expect(find.text('Кампания'), findsWidgets);
    await tester.tap(find.text('Кастом'));
    await settle(tester);
    await tester.scrollUntilVisible(find.text('Начать'), 300, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Начать'));
    await settle(tester);
    await tester.tap(find.text('Начать'));
    await settle(tester);
    expect(find.byType(GameScreen), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    final runs = (await AppStore.open()).loadRuns();
    expect(runs.keys, containsAll([ModeId.campaign, ModeId.custom]));
    expect(runs[ModeId.campaign]!.id, first.id);
    await tester.tap(find.text('Продолжить'));
    await settle(tester);
    expect(find.text('Продолжить Кампания'), findsOneWidget);
    expect(find.text('Продолжить Кастом'), findsOneWidget);
    await tester.tap(find.text('Продолжить Кампания'));
    await settle(tester);
    final state = tester.state<GameScreenState>(find.byType(GameScreen));
    expect(state.engine.snapshot(), first.engine);
  });

  testWidgets('mobile settings show pads without keyboard customization', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);
    await tester.ensureVisible(find.text('Настройки'));
    await tester.tap(find.text('Настройки'));
    await settle(tester);
    await tester.scrollUntilVisible(
      find.text('ЭКРАННЫЕ КНОПКИ'),
      200,
      scrollable: find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down).first,
    );
    expect(find.text('ЭКРАННЫЕ КНОПКИ'), findsOneWidget);
    expect(find.textContaining('новую клавишу'), findsNothing);
    expect(find.textContaining('Клавиши'), findsNothing);
  });
  testWidgets('auto detects English and manual language survives restart', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en', 'GB')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);
    expect(find.text('Campaign'), findsWidgets);
    await tester.ensureVisible(find.text('Settings'));
    await tester.tap(find.text('Settings'));
    await settle(tester);
    await tester.ensureVisible(find.text('Interface'));
    await tester.tap(find.text('Interface'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('language-ru')));
    await settle(tester);
    expect(find.text('Интерфейс'), findsOneWidget);
    expect((await AppStore.open()).loadSettings().language, LanguageChoice.ru);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);
    expect(find.text('Кампания'), findsWidgets);
    await tester.ensureVisible(find.text('Настройки'));
    await tester.tap(find.text('Настройки'));
    await settle(tester);
    await tester.ensureVisible(find.text('Интерфейс'));
    await tester.tap(find.text('Интерфейс'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('language-auto')));
    await settle(tester);
    expect(find.text('Interface'), findsOneWidget);
    expect((await AppStore.open()).loadSettings().language, LanguageChoice.auto);
  });

  testWidgets('switching the language in a game keeps its engine and snapshot', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    await tester.pumpWidget(const RotathreeApp());
    await settle(tester);
    await tester.tap(find.text('Кампания'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('campaign-level-0')));
    await settle(tester);
    final state = tester.state<GameScreenState>(find.byType(GameScreen));
    await tester.tap(find.text('Настройки'));
    await settle(tester);
    final snapshot = state.engine.snapshot();
    await tester.ensureVisible(find.text('Интерфейс'));
    await tester.tap(find.text('Интерфейс'));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('language-en')));
    await settle(tester);
    expect(find.text('Interface'), findsOneWidget);
    expect(tester.state<GameScreenState>(find.byType(GameScreen)), same(state));
    expect(state.engine.snapshot(), snapshot);
    expect(find.text('Pause'), findsWidgets);
    await tester.tap(find.byTooltip('Back'));
    await settle(tester);
    expect(find.text('Pause'), findsOneWidget);
    expect(tester.state<GameScreenState>(find.byType(GameScreen)), same(state));
    expect(tester.takeException(), isNull);
  });
}
