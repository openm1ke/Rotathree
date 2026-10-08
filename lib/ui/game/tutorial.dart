import 'package:flutter/material.dart';
import '../style.dart';
import '../widgets/controls.dart';

const tutorialLessons = [
  (
    'Одна фигура — три клетки',
    'Фигура падает в активный стакан сверху. В центре стаканы делят общее поле. Сейчас попробуем всё без спешки: падение в обучении остановлено.',
  ),
  (
    'Сдвиньте фигуру',
    'Нажмите «Влево» или «Вправо» на левой крестовине. Удержание кнопки повторяет движение. Светлый контур показывает место приземления.',
  ),
  (
    'Поверните фигуру',
    'Нажмите кнопку поворота на правой крестовине. Каждый поворот — четверть оборота; порядок цветов в фигуре сохраняется.',
  ),
  (
    'Соберите три в ряд',
    'Здесь всё подготовлено: клетка фигуры встанет рядом с двумя того же цвета. Нажмите «Сброс» на левой крестовине. Три одинаковых цвета по горизонтали или вертикали исчезнут, а блоки над ними упадут.',
  ),
  (
    'Переключите стакан',
    'Появился второй стакан. Нажмите «Стакан» слева или справа на правой крестовине — или коснитесь нового рукава. Активный стакан окажется сверху; блоки в общем центре останутся на месте.',
  ),
  (
    'Следите за всеми стаканами',
    'В настоящей игре фигуры падают одновременно: в активном стакане быстрее, в остальных медленнее. Переключайтесь до переполнения рукава. Новые совпадения после оседания дают комбо. Кнопка «Пауза» позволяет сохранить партию.',
  ),
];

class TutorialPanel extends StatelessWidget {
  const TutorialPanel({
    super.key,
    required this.step,
    required this.performed,
    required this.onNext,
    required this.onSkip,
  });
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Palette.panelStrong,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Palette.lineStrong),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Обучение · ${step + 1} / ${tutorialLessons.length}',
                      style: Type.label(11, color: Palette.accent),
                    ),
                    const SizedBox(height: 4),
                    Text(title, style: Type.body(16, weight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    Text(body, style: Type.body(13)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
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
