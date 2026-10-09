export const TUTORIAL_LESSONS = [
  [
    'Одна фигура — три клетки',
    'Фигуры падают сверху. Собирайте три клетки одного цвета в ряд. Здесь падение остановлено.',
  ],
  [
    'Сдвиньте фигуру',
    'Сдвигайте фигуру. Удерживайте кнопку для повтора. Контур — место приземления.',
  ],
  [
    'Поверните фигуру',
    'Поверните фигуру на четверть оборота. Цвета сохраняют свой порядок.',
  ],
  [
    'Соберите три в ряд',
    'Сбросьте фигуру. Три одинаковых цвета в ряд исчезнут, а блоки сверху опустятся.',
  ],
  [
    'Переключите стакан',
    'Выведите второй стакан наверх. У стаканов общий центр: блоки в нём остаются на месте.',
  ],
  [
    'Следите за всеми стаканами',
    'Фигуры падают во всех стаканах. Активный быстрее: переключайтесь до переполнения. Игра сохраняется при выходе.',
  ],
] as const;

export function TutorialPanel({
  step,
  performed,
  controls,
  onPractice,
  onNext,
  onSkip,
}: {
  step: number;
  performed: boolean;
  controls: string;
  onPractice?: () => void;
  onNext: () => void;
  onSkip: () => void;
}) {
  const [title, body] = TUTORIAL_LESSONS[step];
  return (
    <section className="tutorial" aria-label="Обучение">
      <div aria-live="polite">
        <div className="tutorial__heading">
          <h2>{title}</h2>
          <span className="kicker">{step + 1} / {TUTORIAL_LESSONS.length}</span>
        </div>
        <p>{body}</p>
        {controls && <p className="tutorial__controls">{controls}</p>}
        {onPractice && (
          <button type="button" className="chip" onClick={onPractice}>
            Попробовать
          </button>
        )}
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
