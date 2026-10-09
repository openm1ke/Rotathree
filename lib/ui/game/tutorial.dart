import 'package:flutter/material.dart';
import '../style.dart';
import '../widgets/controls.dart';

const tutorialLessons = [
  (
    'Одна фигура — три клетки',
    'Фигуры падают сверху. Собирайте три клетки одного цвета в ряд. Здесь падение остановлено.',
  ),
  ('Сдвиньте фигуру', 'Сдвигайте фигуру. Удерживайте кнопку для повтора. Контур — место приземления.'),
  ('Поверните фигуру', 'Поверните фигуру на четверть оборота. Цвета сохраняют свой порядок.'),
  ('Соберите три в ряд', 'Сбросьте фигуру. Три одинаковых цвета в ряд исчезнут, а блоки сверху опустятся.'),
  ('Переключите стакан', 'Выведите второй стакан наверх. У стаканов общий центр: блоки в нём остаются на месте.'),
  (
    'Следите за всеми стаканами',
    'Фигуры падают во всех стаканах. Активный быстрее: переключайтесь до переполнения. Игра сохраняется при выходе.',
  ),
];

class TutorialPanel extends StatelessWidget {
  const TutorialPanel({
    super.key,
    required this.step,
    required this.performed,
    required this.onNext,
    required this.onSkip,
    this.controls = '',
    this.onPractice,
  });
  final String controls;
  final VoidCallback? onPractice;
  final int step;
  final bool performed;
  final VoidCallback onNext, onSkip;
  @override
  Widget build(BuildContext context) {
    final (title, body) = tutorialLessons[step];
    return Semantics(
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        decoration: BoxDecoration(
          color: Palette.panelStrong,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.lineStrong),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(title, style: Type.body(14, weight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 8),
                        Text('${step + 1} / ${tutorialLessons.length}', style: Type.label(10, color: Palette.accent)),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(body, style: Type.body(12)),
                    if (controls.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(controls, style: Type.body(11, color: Palette.accent)),
                      ),
                    if (onPractice != null) TextButton(onPressed: onPractice, child: const Text('Попробовать')),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: TextButton(onPressed: onSkip, child: const Text('Пропустить')),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GoButton(
                    expand: true,
                    label: step == tutorialLessons.length - 1
                        ? 'Играть'
                        : performed
                        ? '✓ Дальше'
                        : 'Дальше',
                    onPressed: step == 0 || step == tutorialLessons.length - 1 || performed ? onNext : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
