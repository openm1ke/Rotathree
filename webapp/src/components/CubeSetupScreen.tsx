import { T } from '../i18n/Text';
import { useRef } from 'react';
import type { Action } from '../input/bindings';
import { useTouchControls } from '../input/touch';
import type { CubeOptions, Settings, Stats } from '../services/storage';
import { formatNumber } from './format';
import { Keys } from './Keycap';
import { Button, Choice, Screen, Toggle } from './ui';
import { useScreenKeys } from './nav';

interface Props {
  settings: Settings;
  stats: Stats;
  colours: string[];
  onChange: (cube: CubeOptions) => void;
  onStart: () => void;
  /** Cube's lessons, again. */
  onTutorial: () => void;
  onBack: () => void;
  active: boolean;
}

/** What each key does in Cube, in the order a new player needs them. */
const KEYS: readonly { actions: readonly Action[]; label: string }[] = [
  { actions: ['moveLeft', 'moveRight'], label: 'Влево, вправо' },
  { actions: ['rotateCW', 'rotateCCW'], label: 'Повернуть фигуру' },
  { actions: ['hardDrop', 'softDrop'], label: 'Сбросить, ускорить' },
  { actions: ['glassLeft', 'glassRight'], label: 'Повернуть крест, как в 2D' },
  { actions: ['tipBack', 'tipFront'], label: 'Держать — показать, как ляжет куб; отпустить — опрокинуть' },
  { actions: ['frontGlass', 'backGlass', 'depthGlass'], label: 'Вести фигуру стакана спереди или сзади; ↑ ↓ двигают её' },
  { actions: ['peek'], label: 'Держать — заглянуть в объём; с A W S D — откуда смотреть' },
  { actions: ['pause'], label: 'Пауза; на паузе куб можно осмотреть со всех сторон' },
];

/** The same on the pads (CUBE_PADS). */
const PADS: readonly { where: string; label: string }[] = [
  { where: 'Левая: ← → ↑ ↓', label: 'Влево, вправо, повернуть, сбросить' },
  { where: 'Левая: центр', label: 'Стакан спереди, сзади, снова сверху' },
  { where: 'Правая: ← →', label: 'Повернуть крест' },
  { where: 'Правая: ↑ ↓', label: 'Держать — показать, отпустить — опрокинуть куб' },
  { where: 'Правая: центр', label: 'Держать — заглянуть в объём' },
];

const range = (from: number, to: number): number[] => Array.from({ length: to - from + 1 }, (_, i) => from + i);

/** Cube's own screen: what it is, how it is played, and its few options. */
export function CubeSetupScreen({ settings, stats, colours, onChange, onStart, onTutorial, onBack, active }: Props) {
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, onBack);
  const touch = useTouchControls();
  const cube = settings.cube;
  const set = (patch: Partial<CubeOptions>) => onChange({ ...cube, ...patch });
  const best = stats.modes.cube.bestScore;

  return (
    <Screen
      rootRef={rootRef}
      className="screen--cube"
      kicker="Режим"
      title="Куб"
      onBack={onBack}
      actions={<Button ghost onClick={onTutorial}><T>Обучение</T></Button>}
      footer={<span><T>Вид куба настраивается в настройках, во вкладке «Интерфейс»</T></span>}
    >
      <div className="form-layout">
        <div className="form">
          <p className="hint cube-about"><T>
            Крест на экране — вид на куб спереди. За ним и перед ним ещё два стакана: в каждой клетке видно ближайший
            блок, и линии собираются из того, что видно. Опрокиньте куб — и то, что лежало в глубине, станет новой
            картинкой: она осыплется и лопнет по своим линиям.
          </T></p>
          <Choice
            label="Цвета"
            note={
              <span className="dots">
                {colours.slice(0, cube.colours).map((colour, i) => (
                  <i key={i} style={{ background: colour }} />
                ))}
              </span>
            }
            value={cube.colours}
            options={range(3, 6).map((n) => [n, String(n)] as const)}
            onChange={(colours) => set({ colours })}
          />
          <Toggle
            label="Стаканы спереди и сзади падают сами"
            value={cube.depthFalls}
            on="медленно"
            off="ждут"
            onChange={(depthFalls) => set({ depthFalls })}
          />
          <dl className="cube-keys">
            {touch
              ? PADS.map(({ where, label }) => (
                  <div className="cube-keys__row" key={where}>
                    <dt><T>{where}</T></dt>
                    <dd><T>{label}</T></dd>
                  </div>
                ))
              : KEYS.map(({ actions, label }) => (
                  <div className="cube-keys__row" key={label}>
                    <dt><Keys codes={actions.flatMap((action) => settings.bindings[action])} /></dt>
                    <dd><T>{label}</T></dd>
                  </div>
                ))}
          </dl>
        </div>

        <div className="summary">
          <strong><T>{best > 0 ? `Рекорд: ${formatNumber(best)}` : 'Рекорда ещё нет'}</T></strong>
          <span><T>Бесконечная игра, скорость растёт с очками</T></span>
        </div>
        <div className="form__start">
          <Button primary onClick={onStart}><T>
            Играть
          </T></Button>
        </div>
      </div>
    </Screen>
  );
}
