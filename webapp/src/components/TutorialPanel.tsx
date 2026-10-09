import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
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
  keyboard,
  onPractice,
  onNext,
  onSkip,
}: {
  step: number;
  performed: boolean;
  controls: string;
  keyboard: boolean;
  onPractice?: () => void;
  onNext: () => void;
  onSkip: () => void;
}) {
  const { t } = useI18n();
  const [title, body] = TUTORIAL_LESSONS[step];
  const nextEnabled = step === 0 || step === TUTORIAL_LESSONS.length - 1 || performed;
  return (
    <section className="tutorial" aria-label={t("Обучение")}>
      <div aria-live="polite">
        <div className="tutorial__heading">
          <h2><T>{title}</T></h2>
          <span className="kicker"><T>{step + 1} / {TUTORIAL_LESSONS.length}</T></span>
        </div>
        <p><T>{body}</T></p>
        {controls && <p className="tutorial__controls"><T>{controls}</T></p>}
        {onPractice && (
          <button type="button" className="chip" onClick={onPractice}><T>
            Попробовать
          </T></button>
        )}
      </div>
      <div className="tutorial__actions">
        <div className="tutorial__action">
          <button type="button" className="button button--ghost" aria-keyshortcuts="Backspace" onClick={onSkip}><T>
            Пропустить
          </T></button>
          {keyboard && <kbd>Backspace</kbd>}
        </div>
        <div className="tutorial__action">
          <button
            type="button"
            className={`button button--primary tutorial__next ${nextEnabled ? 'is-ready' : ''}`}
            aria-keyshortcuts="Enter"
            disabled={!nextEnabled}
            onClick={onNext}
          ><T>
            {step === TUTORIAL_LESSONS.length - 1 ? 'Играть' : performed ? '✓ Дальше' : 'Дальше'}
          </T></button>
          {keyboard && <kbd>Enter</kbd>}
        </div>
      </div>
    </section>
  );
}
