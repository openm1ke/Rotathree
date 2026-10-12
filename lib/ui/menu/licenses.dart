import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../i18n/strings.dart';
import '../style.dart';
import '../widgets/controls.dart';

void registerAssetLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(['Exo 2'], await rootBundle.loadString('assets/fonts/OFL.txt'));
  });
}

class MusicCredits extends StatefulWidget {
  const MusicCredits({super.key});

  @override
  State<MusicCredits> createState() => _MusicCreditsState();
}

class _MusicCreditsState extends State<MusicCredits> {
  late final Future<List<dynamic>> _credits = rootBundle.loadString('assets/credits/music.json')
      .then((source) => jsonDecode(source) as List<dynamic>);

  @override
  Widget build(BuildContext context) => FutureBuilder<List<dynamic>>(
    future: _credits,
    builder: (context, snapshot) {
      if (snapshot.hasError) return const LText('Не удалось загрузить лицензии.');
      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        LText('Спасибо авторам, чья музыка звучит в RotaThree.', style: Type.body(13, color: Palette.textDim)),
        const SizedBox(height: 16),
        for (final raw in snapshot.data!) ...[
          LText(raw['title'] as String, style: Type.body(14, weight: FontWeight.w800)),
          const SizedBox(height: 4),
          LText(raw['author'] as String? ?? 'Автор уточняется', style: Type.body(13, color: Palette.accent)),
          LText(raw['license'] as String? ?? 'Условия использования уточняются', style: Type.body(12, color: Palette.textDim)),
          if (raw['source'] != null)
            SelectableText(raw['source'] as String, style: Type.body(11, color: Palette.textDim)),
          const SizedBox(height: 16),
        ],
        LText('Громкость треков выровнена, добавлены затухания в начале и конце.', style: Type.body(12, color: Palette.textDim)),
        const SizedBox(height: 8),
        SelectableText('https://creativecommons.org/publicdomain/zero/1.0/', style: Type.body(11, color: Palette.accent)),
      ]);
    },
  );
}

List<Widget> licenseSections(BuildContext context) => [
  const Section(title: 'Музыка', children: [MusicCredits()]),
  Section(title: 'Библиотеки и шрифт', children: [
    for (final entry in const [
      ('Flutter', 'The Flutter Authors · BSD-3-Clause'),
      ('shared_preferences', 'The Flutter Authors · BSD-3-Clause'),
      ('audioplayers', 'Blue Fire · MIT'),
      ('Exo 2', 'The Exo 2 Project Authors · SIL OFL 1.1'),
    ]) ...[
      Text(entry.$1, style: Type.body(14, weight: FontWeight.w800)),
      Text(entry.$2, style: Type.body(12, color: Palette.textDim)),
      const SizedBox(height: 12),
    ],
    LText('Полные тексты включают лицензии зависимостей библиотек.', style: Type.body(12, color: Palette.textDim)),
    const SizedBox(height: 12),
    OutlineButton(label: 'Полные лицензии', onPressed: () => showLicensePage(context: context, applicationName: 'RotaThree')),
  ]),
];
