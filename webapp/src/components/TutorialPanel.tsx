import { Fragment, useEffect, useLayoutEffect, useRef, useState } from 'react';
import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { Keycap } from './Keycap';

export interface TutorialControl {
  label: string;
  keys: readonly string[];
}

/** One short line per lesson, read at a glance above the glass; the keys or
 * the glowing pad buttons say the rest. A lesson with an action goes on by
 * itself once the action is done; the first and the last wait for a button. */
export const TUTORIAL_LESSONS = [
  ['Собирай 3 в ряд', 'Три клетки одного цвета исчезают'],
  ['Двигай фигуру', ''],
  ['Поверни фигуру', ''],
  ['Брось — собери 3', ''],
  ['Поверни крест', 'Наверху — активный стакан'],
  ['Следи за всеми стаканами', 'Активный падает быстрее — переключайся'],
] as const;

export function TutorialPanel({
  step,
  performed,
  controls,
  keyboard,
  active,
  hint,
  urging,
  onPractice,
  onNext,
  onSkip,
}: {
  step: number;
  performed: boolean;
  controls: readonly TutorialControl[];
  keyboard: boolean;
  active: boolean;
  /** What to press, said again after a wrong key or a pause. */
  hint: string | null;
  /** The player has waited: the keys pulse harder. */
  urging: boolean;
  onPractice?: () => void;
  onNext: () => void;
  onSkip: () => void;
}) {
  const { t } = useI18n();
  const next = useRef<HTMLButtonElement>(null);
  const root = useRef<HTMLElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  // The frame follows its content's height with a transition rather than
  // jumping, and the glass below gives way just as smoothly.
  const [height, setHeight] = useState<number | null>(null);
  useLayoutEffect(() => {
    const content = inner.current;
    if (!content) return;
    const follow = () => setHeight(content.offsetHeight);
    follow();
    const observer = new ResizeObserver(follow);
    observer.observe(content);
    return () => observer.disconnect();
  }, []);
  const [title, body] = TUTORIAL_LESSONS[step];
  const last = step === TUTORIAL_LESSONS.length - 1;
  const waitsForButton = step === 0 || last;
  // The button waits for Enter; a lesson with an action keeps the focus on
  // itself, so Enter cannot press some other button by surprise.
  useEffect(() => {
    if (!keyboard || !active) return;
    (waitsForButton ? next.current : root.current)?.focus({ preventScroll: true });
  }, [step, keyboard, active, waitsForButton]);
  return (
    <section
      ref={root}
      tabIndex={-1}
      className={`tutorial ${performed ? 'tutorial--done' : ''}`}
      style={height === null ? undefined : { height }}
      aria-label={t('Обучение')}
    >
      <div className="tutorial__inner" ref={inner}>
      <div className="tutorial__top">
        <span className="tutorial__count"><T>{step + 1} / {TUTORIAL_LESSONS.length}</T></span>
        <button type="button" className="tutorial__skip" aria-keyshortcuts="Backspace" onClick={onSkip}>
          <T>Пропустить</T>
          {keyboard && <span aria-hidden="true"><Keycap code="Backspace" /></span>}
        </button>
      </div>
      {/* A new lesson fades in; a done one keeps its size, its keys dimmed. */}
      <div className="tutorial__body" key={step} aria-live="polite">
        <h2>{performed && <span className="tutorial__tick" aria-hidden="true">✓ </span>}<T>{title}</T></h2>
        {body && <p className="tutorial__line"><T>{body}</T></p>}
        {controls.length > 0 && (keyboard ? (
          <div className={`tutorial__controls ${urging ? 'is-urging' : ''} ${performed ? 'is-done' : ''}`}>
            {controls.map(({ label, keys }) => (
              <div className="tutorial__control" key={label}>
                {keys.map((code, i) => (
                  <Fragment key={code}>
                    {i > 0 && <>{' '}<span className="tutorial__or"><T>или</T></span>{' '}</>}
                    <Keycap code={code} />
                  </Fragment>
                ))}
              </div>
            ))}
          </div>
        ) : (
          // On a touch screen the pad buttons themselves glow below.
          <p className={`tutorial__pads ${urging ? 'is-urging' : ''} ${performed ? 'is-done' : ''}`}><T>Жми светящиеся кнопки ↓</T></p>
        ))}
        {hint && <p className={`tutorial__hint ${performed ? 'is-done' : ''}`}><T>{hint}</T></p>}
        {onPractice && !performed && (
          <>
            <p className="tutorial__missing"><T>Нет кнопки. Нажмите «Попробовать» или назначьте в настройках.</T></p>
            <button type="button" className="chip" onClick={onPractice}><T>
              Попробовать
            </T></button>
          </>
        )}
      </div>
      {waitsForButton && (
        <div className="tutorial__action">
          <button
            type="button"
            ref={next}
            className="button button--primary tutorial__next is-ready"
            aria-keyshortcuts="Enter"
            onClick={() => { if (active) onNext(); }}
          ><T>
            {last ? 'Играть' : 'Начать'}
          </T></button>
          {keyboard && (
            <span className="tutorial__keys-hint" aria-hidden="true">
              <Keycap code="Enter" />
              {/* Space starts too; on the last screen it drops, as in the game. */}
              {!last && <>{' '}<span className="tutorial__or"><T>или</T></span>{' '}<Keycap code="Space" /></>}
            </span>
          )}
        </div>
      )}
      </div>
    </section>
  );
}
