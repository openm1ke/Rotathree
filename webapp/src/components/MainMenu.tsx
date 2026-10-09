import { useRef } from 'react';
import { CAMPAIGN_LAST } from '../game/campaign';
import type { Progress } from '../services/storage';
import { useScreenKeys } from './nav';
import type { SavedRuns } from '../services/runSave';
import { useTouchControls } from '../input/touch';

export type MenuTarget = 'campaign' | 'custom' | 'statistics' | 'settings';

const ITEMS: readonly { id: MenuTarget; title: string; caption: string }[] = [
  { id: 'campaign', title: 'Кампания', caption: 'Пятнадцать уровней: от одного стакана до четырёх' },
  { id: 'custom', title: 'Кастом', caption: 'Своя игра: стаканы, цвета и скорость' },
  { id: 'statistics', title: 'Статистика', caption: 'Очки, фигуры и рекорды по режимам' },
  { id: 'settings', title: 'Настройки', caption: 'Клавиши, цвета, эффекты, интерфейс' },
];

/** Blocks drifting down behind the menu: left %, size in px, delay in s, and
 * the colour slot they take. */
const DRIFT = [
  [6, 26, 0, 0],
  [18, 16, 3.2, 1],
  [31, 22, 6.1, 2],
  [44, 14, 1.4, 3],
  [57, 30, 4.7, 4],
  [70, 18, 8.3, 5],
  [83, 24, 2.6, 6],
  [92, 14, 6.9, 7],
  [12, 20, 9.5, 8],
  [76, 34, 0.8, 0],
  [50, 18, 11.2, 2],
  [24, 28, 7.6, 4],
] as const;

const COLOURS = ['#ff3d5e', '#3b82ff', '#ffc531', '#2fd985', '#a65cff', '#e4eafa', '#ff8a2e', '#2ee6f0', '#ff5fb0'];

interface Props {
  progress: Progress;
  onOpen: (target: MenuTarget) => void;
  /** False while the settings are open over the menu. */
  active: boolean;
  savedRuns?: SavedRuns;
  tutorialDone?: boolean;
  onResume?: () => void;
  onTutorial?: () => void;
}

/** The first screen: a column of large entries, the progress on the side. */
export function MainMenu({ progress, onOpen, active, savedRuns, tutorialDone, onResume, onTutorial }: Props) {
  const touch = useTouchControls();
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, () => {});
  const opened = progress.unlocked + (progress.completed ? 1 : 0);
  return (
    <main className="home" ref={rootRef}>
      <div className="home__drift" aria-hidden="true">
        {DRIFT.map(([x, size, delay, colour], i) => (
          <i
            key={i}
            style={{
              left: `${x}%`,
              width: size,
              height: size,
              animationDelay: `${-delay}s`,
              background: COLOURS[colour],
            }}
          />
        ))}
      </div>

      <header className="home__brand">
        <h1 className="logo" aria-label="ROTATHREE">
          ROTA{'THREE'.split('').map((letter, index) => (
            <span className={`logo__letter logo__letter--${index}`} key={index}>{letter}</span>
          ))}
        </h1>
        <p className="home__tag">Четыре стакана. Один центр. Три в ряд.</p>
      </header>

      <nav className="home__nav" aria-label="Главное меню">
        {savedRuns && Object.keys(savedRuns).length > 0 && (
          <button type="button" data-nav className="navitem navitem--resume" onClick={onResume}>
            <span className="navitem__text">
              <span className="navitem__title">Продолжить</span>
              <span className="navitem__caption">Выберите сохранённую игру</span>
            </span>
          </button>
        )}
        {onTutorial && (
          <button type="button" data-nav className="navitem" onClick={onTutorial}>
            <span className="navitem__text">
              <span className="navitem__title">Обучение</span>
              <span className="navitem__caption">
                {tutorialDone ? 'Повторить основы и управление' : 'Первые шаги без спешки'}
              </span>
            </span>
          </button>
        )}
        {ITEMS.map((item, i) => (
          <button
            key={item.id}
            type="button"
            data-nav
            className="navitem"
            autoFocus={i === 0}
            onClick={() => onOpen(item.id)}
          >
            <span className="navitem__text">
              <span className="navitem__title">{item.title}</span>
              <span className="navitem__caption">
                {touch && item.id === 'settings' ? 'Крестовины, цвета, эффекты, интерфейс' : item.caption}
              </span>
            </span>
          </button>
        ))}
      </nav>

      <aside className="home__side">
        <div className="card">
          <span className="kicker">Кампания</span>
          <strong>
            {progress.completed ? 'пройдена' : `уровень ${progress.unlocked + 1} из ${CAMPAIGN_LAST + 1}`}
          </strong>
          <div className="progressbar">
            <i style={{ width: `${(100 * opened) / (CAMPAIGN_LAST + 1)}%` }} />
          </div>
        </div>
        <div className={`card ${progress.completed ? '' : 'is-locked'}`}>
          <span className="kicker">Кошмар</span>
          <strong>{progress.completed ? 'открыт' : 'откроется после кампании'}</strong>
        </div>
      </aside>

      {!touch && (
        <footer className="home__foot">
          <span>↑ ↓ выбрать</span>
          <span>Enter открыть</span>
          <span>Esc назад в меню</span>
        </footer>
      )}
    </main>
  );
}
