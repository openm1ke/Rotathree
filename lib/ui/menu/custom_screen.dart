import 'package:flutter/material.dart';

import '../../game/config/modes.dart';
import '../../game/config/game_config.dart';
import '../style.dart';
import '../widgets/controls.dart';

/// Everything the custom mode is made of, set before a game starts. These
/// values are not used by the campaign or by Insane.
class CustomScreen extends StatelessWidget {
  const CustomScreen({
    super.key,
    required this.setup,
    required this.colours,
    required this.onChange,
    required this.onStart,
    required this.onBack,
  });

  final CustomSetup setup;
  final List<Color> colours;
  final ValueChanged<CustomSetup> onChange;
  final VoidCallback onStart;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    void set(CustomSetup next) => onChange(next);
    final glasses = 1 + setup.extraGlasses;
    return ScreenFrame(
      kicker: 'Режим',
      title: 'Кастом',
      onBack: onBack,
      actions: [OutlineButton(square: true, label: 'Сбросить', onPressed: () => onChange(defaultCustom))],
      footer: 'Настройки этого режима действуют только в нём',
      children: [
        Section(
          title: 'Стаканы и цвета',
          children: [
            OptionGroup<int>(
              square: true,
              label: 'Дополнительных стаканов',
              note: 'кроме стакана, с которого начинается игра',
              value: setup.extraGlasses,
              options: [for (var n = 0; n <= 3; n++) (value: n, label: '$n')],
              onChanged: (value) => set(setup.copyWith(extraGlasses: value)),
            ),
            OptionGroup<int>(
              square: true,
              label: 'Цветов',
              value: setup.colours,
              options: [for (var n = 3; n <= 9; n++) (value: n, label: '$n')],
              onChanged: (value) => set(setup.copyWith(colours: value)),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                children: [
                  for (final colour in colours.take(setup.colours))
                    Container(
                      width: 12,
                      height: 12,
                      margin: const EdgeInsets.only(right: 4),
                      decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(2)),
                    ),
                ],
              ),
            ),
            OptionGroup<int>(
              square: true,
              label: 'Длина рукава, клеток',
              value: setup.armLength,
              options: [for (var n = 4; n <= 12; n++) (value: n, label: '$n')],
              onChanged: (value) => set(setup.copyWith(armLength: value)),
            ),
          ],
        ),
        Section(
          title: 'Скорость',
          children: [
            OptionGroup<double>(
              square: true,
              label: 'Старт: активный стакан',
              note: 'секунд на шаг фигуры',
              value: setup.activeStep,
              options: [
                for (final v in [0.5, 0.75, 1.0, 1.5]) (value: v, label: '$v'),
              ],
              onChanged: (value) => set(setup.copyWith(activeStep: value)),
            ),
            OptionGroup<double>(
              square: true,
              label: 'Старт: остальные стаканы',
              note: 'секунд на шаг фигуры',
              value: setup.inactiveStep,
              options: [
                for (final v in [1.5, 2.0, 3.0, 4.0, 6.0]) (value: v, label: '$v'),
              ],
              onChanged: (value) => set(setup.copyWith(inactiveStep: value)),
            ),
            SwitchRow(
              square: true,
              label: 'Ускорять падение',
              value: setup.speedUp,
              onChanged: (value) => set(setup.copyWith(speedUp: value)),
            ),
            if (setup.speedUp) ...[
              OptionGroup<double>(
                square: true,
                label: 'Шаг ускорения',
                note: 'на сколько быстрее каждый раз',
                value: setup.speedUpStep,
                options: [
                  for (final v in [0.05, 0.1, 0.15, 0.2]) (value: v, label: '${(v * 100).round()}%'),
                ],
                onChanged: (value) => set(setup.copyWith(speedUpStep: value)),
              ),
              OptionGroup<int>(
                square: true,
                label: 'Ускорять каждые',
                note: 'очков',
                value: setup.speedUpEvery,
                options: [
                  for (final v in [1000, 2000, 3000]) (value: v, label: '$v'),
                ],
                onChanged: (value) => set(setup.copyWith(speedUpEvery: value)),
              ),
            ],
          ],
        ),
        Section(
          title: 'Правила',
          children: [
            OptionGroup<GravityScope>(
              square: true,
              label: 'После хлопка падает',
              value: setup.gravityScope,
              options: const [
                (value: GravityScope.wholeGlass, label: 'всё без опоры'),
                (value: GravityScope.aboveCleared, label: 'только над дырой'),
              ],
              onChanged: (value) => set(setup.copyWith(gravityScope: value)),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: Palette.panel,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Palette.line),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$glasses ${glasses == 1 ? 'стакан' : 'стакана'} · ${setup.colours} цв. · рукав ${setup.armLength}',
                style: Type.body(15, weight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                setup.speedUp
                    ? 'ускорение на ${(setup.speedUpStep * 100).round()}% каждые ${setup.speedUpEvery} очков'
                    : 'скорость не меняется',
                style: Type.body(13, color: Palette.textDim),
              ),
            ],
          ),
        ),
        GoButton(square: true, label: 'Начать', expand: true, onPressed: onStart),
      ],
    );
  }
}
