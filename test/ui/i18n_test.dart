import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/data/settings.dart';
import 'package:rotathree/ui/i18n/strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('auto follows preferred supported locales, with English fallback', () {
    expect(resolveLanguage(LanguageChoice.auto, [const Locale('ru', 'RU')]), const Locale('ru'));
    expect(resolveLanguage(LanguageChoice.auto, [const Locale('en', 'GB'), const Locale('ru')]), const Locale('en'));
    expect(resolveLanguage(LanguageChoice.auto, [const Locale('de'), const Locale('ru')]), const Locale('ru'));
    expect(resolveLanguage(LanguageChoice.auto, [const Locale('ja')]), const Locale('en'));
    expect(resolveLanguage(LanguageChoice.auto, []), const Locale('en'));
    expect(resolveLanguage(LanguageChoice.ru, [const Locale('en')]), const Locale('ru'));
    expect(resolveLanguage(LanguageChoice.en, [const Locale('ru')]), const Locale('en'));
  });

  test('language preferences persist and older settings use auto', () {
    final base = Settings.defaults().copyWith(handling: const Handling(dasMs: 210));
    for (final choice in LanguageChoice.values) {
      final saved = Settings.fromJson(base.copyWith(language: choice).toJson());
      expect(saved.language, choice);
      expect(saved.handling.dasMs, 210);
    }
    final legacy = base.toJson()..remove('language');
    expect(Settings.fromJson(legacy).language, LanguageChoice.auto);
    legacy['language'] = 'de';
    expect(Settings.fromJson(legacy).language, LanguageChoice.auto);
    expect(Settings.fromJson(legacy).handling.dasMs, 210);
  });

  test('the shared catalog preserves parameters and translates saved banners', () async {
    final catalog = await AppStrings.catalog();
    final english = AppStrings('en', catalog);
    final russian = AppStrings('ru', catalog);
    for (final entry in catalog.entries) {
      final sourceParams = RegExp(r'\{\w+\}').allMatches(entry.key).map((m) => m[0]).toSet();
      final targetParams = RegExp(r'\{\w+\}').allMatches(entry.value).map((m) => m[0]).toSet();
      expect(targetParams, sourceParams, reason: entry.key);
      if (!entry.key.contains('{')) {
        expect(english.tr(entry.key), entry.value, reason: entry.key);
      }
      final sourceExample = entry.key.replaceAll(RegExp(r'\{\w+\}'), '42');
      final targetExample = entry.value.replaceAll(RegExp(r'\{\w+\}'), '42');
      expect(english.tr(sourceExample), targetExample, reason: entry.key);
      expect(russian.tr(entry.key), entry.key);
    }
    expect(english.tr('Уровень 7 пройден'), 'Level 7 complete');
    expect(english.tr('УРОВЕНЬ 7 ПРОЙДЕН'), 'LEVEL 7 COMPLETE');
    expect(english.tr('Дальше: 6 цв. · 4 ст. · цель 12 000'), 'Next: colors 6 · glasses 4 · target 12,000');
    expect(english.tr('4 ст. · 1,2 с/шаг'), 'Glasses 4 · 1.2s/step');
    expect(english.tr('150 мс'), '150 ms');
    expect(english.tr('Левая: → · Правая: ↻'), 'Left: → · Right: ↻');
    expect(english.tr('Кампания · уровень 3'), 'Campaign · level 3');
    expect(
      english.tr('Правый стакан заполнился до конца рукава. Уровень не пройден: начнём его заново или выберем другой.'),
      'The Right glass is full. Level incomplete: retry it or choose another.',
    );
  });
}
