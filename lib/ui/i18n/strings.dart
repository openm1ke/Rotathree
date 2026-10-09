import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Auto follows the first supported language in the device's preferred list.
enum LanguageChoice {
  auto,
  ru,
  en;

  static LanguageChoice fromJson(Object? value) => switch (value) {
    'ru' => ru,
    'en' => en,
    _ => auto,
  };
}

Locale resolveLanguage(LanguageChoice choice, Iterable<Locale> preferred) {
  if (choice != LanguageChoice.auto) return Locale(choice.name);
  for (final locale in preferred) {
    if (locale.languageCode == 'ru' || locale.languageCode == 'en') {
      return Locale(locale.languageCode);
    }
  }
  return const Locale('en');
}

/// Russian source messages are the catalog keys, shared with the web app.
/// Templates also recognize messages stored in older game checkpoints.
class AppStrings {
  AppStrings(this.language, Map<String, String> english)
    : _english = english,
      _templates = [
        for (final entry in english.entries)
          if (entry.key.contains('{')) _MessageTemplate(entry.key, entry.value),
      ]..sort((a, b) => b.specificity.compareTo(a.specificity));

  final String language;
  final Map<String, String> _english;
  final List<_MessageTemplate> _templates;
  static Map<String, String>? _catalog;
  static final _fallback = AppStrings('ru', const {});
  static const delegate = _StringsDelegate();

  static Future<Map<String, String>> catalog() async {
    if (_catalog != null) return _catalog!;
    final value = await rootBundle.loadString('assets/i18n/en.json');
    return _catalog = Map<String, String>.from(jsonDecode(value) as Map);
  }

  static AppStrings of(BuildContext context) => Localizations.of<AppStrings>(context, AppStrings) ?? _fallback;

  String tr(String source, [int depth = 0]) {
    if (language == 'ru' || depth > 4 || source.isEmpty) return source;
    // Preserve whitespace at JSX/text fragment boundaries and number grouping.
    final normalized = source.trim().replaceAll(RegExp(r'[\t\r\n ]+'), ' ');
    final upper = normalized.contains(RegExp('[А-ЯЁ]')) && normalized == normalized.toUpperCase();
    final key = upper
        ? _english.keys.firstWhere((key) => key.toUpperCase() == normalized, orElse: () => normalized)
        : normalized;
    var translated = _english[key];
    if (translated == null) {
      for (final template in _templates) {
        final match = (upper ? template.upperPattern : template.pattern).firstMatch(normalized);
        if (match == null) continue;
        translated = template.english.replaceAllMapped(RegExp(r'\{(\w+)\}'), (parameter) {
          final index = template.parameters.indexOf(parameter[1]!);
          return tr(match[index + 1]!, depth + 1);
        });
        break;
      }
    }
    if (translated == null) return _numbers(source);
    if (upper) translated = translated.toUpperCase();
    final leading = RegExp(r'^\s*').firstMatch(source)![0]!;
    final trailing = RegExp(r'\s*$').firstMatch(source)![0]!;
    return '$leading${_quantities(_numbers(translated))}$trailing';
  }

  // Russian singular forms also occur at 21, 31, etc. English is singular only
  // at one, so choose its form after numeric template parameters are resolved.
  String _quantities(String value) => value.replaceAllMapped(
    RegExp(
      r'\b(\d[\d,]*(?:\.\d+)?) (points|colors|glasses|cells|times)\b',
      caseSensitive: false,
    ),
    (m) {
      if (double.tryParse(m[1]!.replaceAll(',', '')) != 1) return m[0]!;
      final noun = switch (m[2]!.toLowerCase()) {
        'points' => 'point',
        'colors' => 'color',
        'glasses' => 'glass',
        'cells' => 'cell',
        _ => 'time',
      };
      return '${m[1]} ${m[2] == m[2]!.toUpperCase() ? noun.toUpperCase() : noun}';
    },
  );

  String _numbers(String value) => value
      .replaceAllMapped(RegExp(r'(\d)[\u00a0\u202f](?=\d{3}(?:\D|$))'), (m) => '${m[1]},')
      .replaceAllMapped(RegExp(r'(\d),(\d{1,2})(?=\D|$)'), (m) => '${m[1]}.${m[2]}');
}

class _MessageTemplate {
  _MessageTemplate(String source, this.english) {
    final matches = RegExp(r'\{(\w+)\}').allMatches(source);
    var expression = '^';
    var end = 0;
    for (final match in matches) {
      expression += RegExp.escape(source.substring(end, match.start));
      expression += '(.+?)';
      parameters.add(match[1]!);
      end = match.end;
    }
    expression += '${RegExp.escape(source.substring(end))}\$';
    pattern = RegExp(expression);
    upperPattern = RegExp(expression, caseSensitive: false);
    specificity = source.replaceAll(RegExp(r'\{\w+\}'), '').length;
  }
  final String english;
  final parameters = <String>[];
  late final RegExp pattern;
  late final RegExp upperPattern;
  late final int specificity;
}

class _StringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _StringsDelegate();
  @override
  bool isSupported(Locale locale) => locale.languageCode == 'ru' || locale.languageCode == 'en';
  @override
  Future<AppStrings> load(Locale locale) async => AppStrings(locale.languageCode, await AppStrings.catalog());
  @override
  bool shouldReload(_StringsDelegate old) => false;
}

extension TranslateContext on BuildContext {
  String tr(String source) => AppStrings.of(this).tr(source);
}

/// Translates at render time so changing locale never changes a game snapshot.
class LText extends StatelessWidget {
  const LText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.softWrap,
    this.translate = true,
  });
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;
  final bool? softWrap;
  final bool translate;
  @override
  Widget build(BuildContext context) => Text(
    translate ? context.tr(data) : data,
    style: style,
    textAlign: textAlign,
    maxLines: maxLines,
    overflow: overflow,
    softWrap: softWrap,
  );
}
