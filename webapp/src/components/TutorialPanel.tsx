export const TUTORIAL_LESSONS = [
  [
    'Одна фигура — три клетки',
    'Фигура падает в активный стакан сверху. В центре стаканы делят общее поле. Сейчас попробуем всё без спешки: падение в обучении остановлено.',
  ],
  [
    'Сдвиньте фигуру',
    'Сдвиньте фигуру влево или вправо. Удержание повторяет движение. Светлый контур показывает место приземления.',
  ],
  [
    'Поверните фигуру',
    'Каждый поворот — четверть оборота; порядок цветов в фигуре сохраняется. Попробуйте повернуть её сейчас.',
  ],
  [
    'Соберите три в ряд',
    'Здесь всё подготовлено: клетка фигуры встанет рядом с двумя того же цвета. Нажмите сброс. Три одинаковых цвета по горизонтали или вертикали исчезнут, а блоки над ними упадут.',
  ],
  [
    'Переключите стакан',
    'Появился второй стакан. Переключите его наверх кнопкой или нажатием на рукав. Блоки в общем центре останутся на месте.',
  ],
  [
    'Следите за всеми стаканами',
    'В настоящей игре фигуры падают одновременно: в активном стакане быстрее, в остальных медленнее. Переключайтесь до переполнения рукава. Новые совпадения после оседания дают комбо. Пауза позволяет сохранить партию.',
  ],
] as const;

export function TutorialPanel({
  step,
  performed,
  controls,
  onNext,
  onSkip,
}: {
  step: number;
  performed: boolean;
  controls: string;
  onNext: () => void;
  onSkip: () => void;
}) {
  const [title, body] = TUTORIAL_LESSONS[step];
  return (
    <section className="tutorial" aria-label="Обучение">
      <div aria-live="polite">
        <span className="kicker">
          Обучение · {step + 1} / {TUTORIAL_LESSONS.length}
        </span>
        <h2>{title}</h2>
        <p>{body}</p>
        {controls && <p className="tutorial__controls">{controls}</p>}
      </div>
      <div className="tutorial__actions">
        <button type="button" className="button button--ghost" onClick={onSkip}>
          Пропустить
        </button>
        <button
          type="button"
          className="button button--primary"
          disabled={step !== 0 && step !== TUTORIAL_LESSONS.length - 1 && !performed}
          onClick={onNext}
        >
          {step === TUTORIAL_LESSONS.length - 1 ? 'Играть' : performed ? '✓ Дальше' : 'Дальше'}
        </button>
      </div>
    </section>
  );
}
