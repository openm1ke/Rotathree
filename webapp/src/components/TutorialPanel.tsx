import { useEffect, useRef } from 'react';
import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { Keycap, Keys } from './Keycap';

export interface TutorialControl {
  label: string;
  keys: readonly string[];
}
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
  active,
  onPractice,
  onNext,
  onSkip,
}: {
  step: number;
  performed: boolean;
  controls: readonly TutorialControl[];
  keyboard: boolean;
  active: boolean;
  onPractice?: () => void;
  onNext: () => void;
  onSkip: () => void;
}) {
  const { t } = useI18n();
  const next = useRef<HTMLButtonElement>(null);
  const [title, body] = TUTORIAL_LESSONS[step];
  const nextEnabled = step === 0 || step === TUTORIAL_LESSONS.length - 1 || performed;
  // aria-disabled keeps Next focusable while the lesson's action is still pending.
  useEffect(() => {
    if (keyboard && active) next.current?.focus({ preventScroll: true });
  }, [step, keyboard, active, nextEnabled]);
  return (
    <section className="tutorial" aria-label={t("Обучение")}>
      <div aria-live="polite">
        <div className="tutorial__heading">
          <span className="kicker"><T>Обучение</T></span>
          <span className="kicker"><T>{step + 1} / {TUTORIAL_LESSONS.length}</T></span>
        </div>
        <h2><T>{title}</T></h2>
        <p><T>{body}</T></p>
        {controls.length > 0 && <div className="tutorial__controls">
          {controls.map(({ label, keys }) => <div className="tutorial__control" key={label}>
            <span><T>{label}</T></span>
            {keyboard ? <Keys codes={keys} /> : <span className="keys">
              {keys.map((symbol) => <kbd className="keycap" key={symbol}>{symbol}</kbd>)}
            </span>}
          </div>)}
        </div>}
        {onPractice && (
          <>
            <p className="tutorial__missing"><T>Нет кнопки. Нажмите «Попробовать» или назначьте в настройках.</T></p>
            <button type="button" className="chip" onClick={onPractice}><T>
              Попробовать
            </T></button>
          </>
        )}
      </div>
      <div className="tutorial__actions">
        <div className="tutorial__action">
          <button type="button" className="button button--ghost" aria-keyshortcuts="Backspace" onClick={onSkip}><T>
            Пропустить
          </T></button>
          {keyboard && <Keycap code="Backspace" />}
        </div>
        <div className="tutorial__action">
          <button
            type="button"
            ref={next}
            className={`button button--primary tutorial__next ${nextEnabled ? 'is-ready' : ''}`}
            aria-keyshortcuts="Enter"
            aria-disabled={!nextEnabled}
            onClick={() => { if (nextEnabled && active) onNext(); }}
          ><T>
            {step === TUTORIAL_LESSONS.length - 1 ? 'Играть' : performed ? '✓ Дальше' : 'Дальше'}
          </T></button>
          {keyboard && <Keycap code="Enter" />}
        </div>
      </div>
    </section>
  );
}
