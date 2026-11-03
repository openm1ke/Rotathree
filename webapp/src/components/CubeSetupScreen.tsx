import { T } from '../i18n/Text';
import { useRef } from 'react';
import { ACTIONS, type Action } from '../input/bindings';
import { PAD_SLOTS, type PadSlot } from '../input/pads';
import { useTouchControls } from '../input/touch';
import { CUBE_LIMITS, type CubeOptions, type Progress, type Settings, type Stats } from '../services/storage';
import { CUBE_CAMPAIGN, CUBE_CAMPAIGN_LAST } from '../cube/campaign';
import { formatCells, formatDuration, formatNumber, formatPoints } from './format';
import type { CubeSave } from '../cube/save';
import { Keys } from './Keycap';
import { Button, Choice, Screen, Toggle } from './ui';
import { useScreenKeys } from './nav';

interface Props {
  settings: Settings;
  stats: Stats;
  colours: string[];
  onChange: (cube: CubeOptions) => void;
  onStart: () => void;
  /** The game left unfinished, to go on with instead of a new one. */
  saved?: CubeSave | null;
  onResume?: () => void;
  /** How far Cube's campaign has been played; opens its levels. */
  progress: Progress;
  onCampaign: () => void;
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
  { actions: ['glassLeft', 'glassRight'], label: 'Повернуть крест против часовой и по часовой' },
  { actions: ['tipBack', 'tipFront'], label: 'Скрытые стаканы наверх: задний или передний. Держать — показать, отпустить — повернуть' },
  { actions: ['frontGlass', 'backGlass', 'depthGlass'], label: 'Вести фигуру стакана спереди или сзади; ↑ ↓ двигают её' },
  { actions: ['peek'], label: 'Держать — заглянуть в объём; с A W S D — откуда смотреть' },
  { actions: ['pause'], label: 'Пауза; на паузе куб можно осмотреть со всех сторон' },
];

/** Where a pad button is, as the list of Cube's pads names it. */
const SLOT_SIGNS: Record<PadSlot, string> = { up: '↑', left: '←', right: '→', down: '↓', center: 'центр' };

const range = (from: number, to: number): number[] => Array.from({ length: to - from + 1 }, (_, i) => from + i);

/** Cube's own screen: what it is, how it is played, and its few options. */
export function CubeSetupScreen({ settings, stats, colours, onChange, onStart, saved, onResume, progress, onCampaign, onTutorial, onBack, active }: Props) {
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
          <section className="cube-campaign">
            <div className="cube-campaign__text">
              <strong><T>Кампания</T></strong>
              <span><T>
                {progress.completed
                  ? `пройдена · ${CUBE_CAMPAIGN_LAST + 1} уровней`
                  : `уровень ${progress.unlocked + 1} из ${CUBE_CAMPAIGN_LAST + 1} · ${CUBE_CAMPAIGN[progress.unlocked].title}`}
              </T></span>
              <div className="progressbar" aria-hidden="true">
                <i style={{ width: `${(100 * (progress.completed ? CUBE_CAMPAIGN_LAST + 1 : progress.unlocked)) / (CUBE_CAMPAIGN_LAST + 1)}%` }} />
              </div>
            </div>
            <Button primary={!saved} onClick={onCampaign}><T>Уровни</T></Button>
          </section>
          <h2 className="cube-free"><T>Свободная игра</T></h2>
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
          <Choice
            label="Ширина стакана"
            note="и сторона куба в середине"
            value={cube.width}
            options={range(...CUBE_LIMITS.width).map((n) => [n, String(n)] as const)}
            onChange={(width) => set({ width })}
          />
          <Choice
            label="Длина рукава"
            note="в клетках"
            value={cube.arm}
            options={range(...CUBE_LIMITS.arm).map((n) => [n, String(n)] as const)}
            onChange={(arm) => set({ arm })}
          />
          <Toggle
            label="Следующие фигуры над стаканами"
            value={cube.nextPiece}
            on="показывать"
            off="скрыть"
            onChange={(nextPiece) => set({ nextPiece })}
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
              ? (['left', 'right'] as const).flatMap((side) =>
                  PAD_SLOTS.flatMap((slot) => {
                    // The player's own layout of Cube's pads.
                    const action = ACTIONS.find(({ id }) => id === settings.cubePads[side][slot]);
                    if (!action) return [];
                    const where = `${side === 'left' ? 'Левая' : 'Правая'}: ${SLOT_SIGNS[slot]}`;
                    return [
                      <div className="cube-keys__row" key={where}>
                        <dt><T>{where}</T></dt>
                        <dd><T>{action.label}</T></dd>
                      </div>,
                    ];
                  }),
                )
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
          <span><T>
            куб {cube.width}×{cube.width}×{cube.width} · рукав: {formatCells(cube.arm)} · скорость растёт с очками
          </T></span>
        </div>
        {saved && (
          <p className="hint cube-saved"><T>
            Партия не закончена: {formatPoints(saved.game.score)} · {formatDuration(saved.game.seconds)}
          </T></p>
        )}
        <div className="form__start">
          {saved ? (
            <>
              <Button onClick={onStart}><T>Новая игра</T></Button>
              <Button primary onClick={() => onResume?.()}><T>Продолжить</T></Button>
            </>
          ) : (
            <Button primary onClick={onStart}><T>
              Играть
            </T></Button>
          )}
        </div>
      </div>
    </Screen>
  );
}
