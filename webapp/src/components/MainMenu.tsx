import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { useRef, type ReactNode } from 'react';
import { CAMPAIGN_LAST } from '../game/campaign';
import { CUBE_CAMPAIGN_LAST } from '../cube/campaign';
import type { Progress } from '../services/storage';
import { useScreenKeys } from './nav';
import type { SavedRuns } from '../services/runSave';
import { useTouchControls } from '../input/touch';
import { USES_ESCAPE } from '../platform/target';

export type MenuTarget = 'campaign' | 'custom' | 'cube' | 'statistics' | 'settings';

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

/** The classic set's colours for the tiles' little pictures. */
const RED = 0;
const BLUE = 1;
const YELLOW = 2;
const GREEN = 3;
const VIOLET = 4;

/** A picture made of the game's own blocks: [column, row, colour] on a
 * three-by-three grid, `faint` ones drawn see-through. */
type Blocks = readonly (readonly [number, number, number, boolean?])[];

const PICTURES: Record<'campaign' | 'cube' | 'custom' | 'tutorial' | 'statistics', Blocks> = {
  // Three in a row, the game in one picture.
  campaign: [[0, 2, RED], [1, 2, RED], [2, 2, RED], [1, 1, BLUE]],
  // A cube: its front, and its back showing behind.
  cube: [[1, 0, BLUE, true], [2, 0, BLUE, true], [2, 1, BLUE, true], [0, 1, BLUE], [1, 1, BLUE], [0, 2, BLUE], [1, 2, BLUE]],
  // A stick of three colours, as the player sets them.
  custom: [[1, 0, YELLOW], [1, 1, GREEN], [1, 2, VIOLET]],
  // A stick coming down into the gap that makes the line.
  tutorial: [[1, 0, GREEN], [0, 2, GREEN], [2, 2, GREEN], [1, 2, GREEN, true]],
  // Columns growing: the records.
  statistics: [[0, 2, VIOLET], [1, 2, VIOLET], [1, 1, VIOLET], [2, 2, VIOLET], [2, 1, VIOLET], [2, 0, VIOLET]],
};

interface Props {
  progress: Progress;
  /** How far Cube's campaign has been played. */
  cubeProgress?: Progress;
  onOpen: (target: MenuTarget) => void;
  /** False while the settings are open over the menu. */
  active: boolean;
  savedRuns?: SavedRuns;
  /** A game of Cube left unfinished. */
  cubeSaved?: boolean;
  tutorialDone?: boolean;
  onResume?: () => void;
  onTutorial?: () => void;
}

/** The main menu: a tile for each way to play, with a picture made of the
 * game's blocks and a line that says where the player is; the records and
 * the settings in a row of smaller ones under them. */
export function MainMenu({ progress, cubeProgress, onOpen, active, savedRuns, cubeSaved, tutorialDone, onResume, onTutorial }: Props) {
  const { t } = useI18n();
  const touch = useTouchControls();
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, () => {});
  const saved = (savedRuns && Object.keys(savedRuns).length > 0) || cubeSaved;
  const levels = CAMPAIGN_LAST + 1;
  const cubeLevels = CUBE_CAMPAIGN_LAST + 1;
  return (
    <main className={`home ${touch ? 'home--touch' : ''}`} ref={rootRef}>
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

      <div className="home__content">
        <header className="home__brand">
          <h1 className="logo" aria-label="ROTATHREE">
            ROTA{'THREE'.split('').map((letter, index) => (
              <span className={`logo__letter logo__letter--${index}`} key={index}>{letter}</span>
            ))}
          </h1>
        </header>

        <nav className="home__nav" aria-label={t('Главное меню')}>
          {saved && (
            <Tile wide accent title="Продолжить" caption="Сохранённые игры" picture={<Play />} onClick={onResume} />
          )}
          <Tile
            title="Кампания"
            caption={progress.completed ? 'пройдена · Кошмар открыт' : `уровень ${progress.unlocked + 1} из ${levels}`}
            picture={PICTURES.campaign}
            done={progress.completed ? 1 : progress.unlocked / levels}
            autoFocus={!saved}
            onClick={() => onOpen('campaign')}
          />
          <Tile
            title="Куб"
            caption="Шесть стаканов в 3D"
            picture={PICTURES.cube}
            done={cubeProgress && (cubeProgress.completed ? 1 : cubeProgress.unlocked / cubeLevels)}
            onClick={() => onOpen('cube')}
          />
          <Tile title="Кастом" caption="Ваши правила" picture={PICTURES.custom} onClick={() => onOpen('custom')} />
          {onTutorial && (
            <Tile
              title="Обучение"
              caption={tutorialDone ? 'Повторить основы' : 'Правила на практике'}
              picture={PICTURES.tutorial}
              onClick={onTutorial}
            />
          )}
          <div className="home__more">
            <Tile small title="Статистика" picture={PICTURES.statistics} onClick={() => onOpen('statistics')} />
            <Tile small title="Настройки" picture={<Gear />} onClick={() => onOpen('settings')} />
          </div>
        </nav>

        {!touch && (
          <footer className="home__foot">
            <span><T>↑ ↓ выбрать</T></span>
            <span><T>Enter открыть</T></span>
            <span>{USES_ESCAPE ? <T>Esc назад в меню</T> : <T>Backspace назад в меню</T>}</span>
          </footer>
        )}
      </div>
    </main>
  );
}

/** One way into the game. `done`: how much of its campaign is played, as a
 * thin bar under the line. */
function Tile({ title, caption, picture, done, wide = false, small = false, accent = false, autoFocus = false, onClick }: {
  title: string;
  caption?: string;
  picture: Blocks | ReactNode;
  done?: number;
  wide?: boolean;
  small?: boolean;
  accent?: boolean;
  autoFocus?: boolean;
  onClick?: () => void;
}) {
  const kind = [wide && 'navitem--wide', small && 'navitem--small', accent && 'navitem--resume'].filter(Boolean).join(' ');
  return (
    <button type="button" data-nav className={`navitem navitem--tile ${kind}`} autoFocus={autoFocus} onClick={onClick}>
      <span className="navitem__picture" aria-hidden="true">
        {Array.isArray(picture) ? <BlockPicture blocks={picture as Blocks} /> : picture}
      </span>
      <span className="navitem__text">
        <span className="navitem__title"><T>{title}</T></span>
        {caption && <span className="navitem__caption"><T>{caption}</T></span>}
        {done !== undefined && (
          <span className="navitem__done"><i style={{ width: `${Math.round(done * 100)}%` }} /></span>
        )}
      </span>
    </button>
  );
}

function BlockPicture({ blocks }: { blocks: Blocks }) {
  return (
    <span className="blocks">
      {blocks.map(([x, y, colour, faint], i) => (
        <i
          key={i}
          className={faint ? 'blocks__faint' : undefined}
          style={{ left: `${x * 34}%`, top: `${y * 34}%`, ['--block' as string]: COLOURS[colour] }}
        />
      ))}
    </span>
  );
}

function Play() {
  return (
    <svg className="navitem__icon navitem__icon--play" viewBox="0 0 24 24" fill="currentColor">
      <path d="M8 5.5v13a1 1 0 0 0 1.5.86l10.4-6.5a1 1 0 0 0 0-1.72L9.5 4.64A1 1 0 0 0 8 5.5Z" />
    </svg>
  );
}

function Gear() {
  return (
    <svg className="navitem__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8">
      <path d="m9 3-.6 2.3-1.5.9-2.3-.6-3 5.2 1.7 1.7v1.8l-1.7 1.7 3 5.2 2.3-.6 1.5.9.6 2.3h6l.6-2.3 1.5-.9 2.3.6 3-5.2-1.7-1.7v-1.8l1.7-1.7-3-5.2-2.3.6-1.5-.9L15 3Z" transform="translate(1 0) scale(.9)" />
      <circle cx="12" cy="12" r="3" />
    </svg>
  );
}
