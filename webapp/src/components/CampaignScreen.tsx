import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { useEffect, useRef } from 'react';
import { CAMPAIGN, CAMPAIGN_LAST } from '../game/campaign';
import { CUBE_CAMPAIGN, CUBE_CAMPAIGN_LAST } from '../cube/campaign';
import type { CubeSave } from '../cube/save';
import type { Progress } from '../services/storage';
import { formatScore } from './hudState';
import { formatDuration, formatPoints } from './format';
import { Button, Screen } from './ui';
import { useScreenKeys } from './nav';

type Status = 'done' | 'open' | 'locked';

interface Props {
  progress: Progress;
  /** How far Cube's levels have been played. */
  cubeProgress: Progress;
  /** A level of Cube left unfinished, to go on with. */
  cubeSaved?: CubeSave;
  colours: string[];
  onStart: (level: number) => void;
  onInsane: () => void;
  onCubeStart: (level: number) => void;
  onCubeResume: () => void;
  /** Opened from a level of Cube: its part is shown first. */
  cube?: boolean;
  onBack: () => void;
  active: boolean;
}

const statusOf = (progress: Progress, index: number, last: number): Status =>
  index < progress.unlocked || (index === last && progress.completed)
    ? 'done' : index === progress.unlocked ? 'open' : 'locked';

const passed = (progress: Progress, count: number): number => (progress.completed ? count : progress.unlocked);

/** The whole campaign on one screen: the flat levels and the Nightmare after
 * them, then Cube's levels. Compact tiles, in the player's palette. */
export function CampaignScreen({ progress, cubeProgress, cubeSaved, colours, onStart, onInsane, onCubeStart, onCubeResume, cube = false, onBack, active }: Props) {
  const { t } = useI18n();
  const rootRef = useRef<HTMLElement>(null);
  const cubeRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, onBack);
  // The flat part waits for the player until it is passed; then Cube's.
  const cubeFirst = cube || progress.completed;
  useEffect(() => {
    if (cube) cubeRef.current?.scrollIntoView({ block: 'start' });
  }, [cube]);
  return (
    <Screen rootRef={rootRef} className="screen--campaign" kicker="Режим" title="Кампания" onBack={onBack}
      footer={<span><T>Уровни открываются по очереди · пройденные можно повторить</T></span>}>
      <div className="campaign-picker">
        <section className="campaign-part">
          <PartHead title="Стаканы · 2D" passed={passed(progress, CAMPAIGN_LAST + 1)} count={CAMPAIGN_LAST + 1} />
          <div className="levels">
            {CAMPAIGN.map((level, index) => {
              const step = String(level.activeStep).replace('.', ',');
              const status = statusOf(progress, index, CAMPAIGN_LAST);
              const best = progress.best[index] ?? 0;
              const description = t(`Цветов: ${level.colours}. Стаканов: ${level.glasses}. Шаг: ${step} с. ${stateOf(status)}`
                + (best > 0 ? `. Лучший результат: ${formatScore(best)}` : ''));
              return (
                <LevelCard key={index} index={index} target={level.target} colours={colours.slice(0, level.colours)}
                  status={status} description={description} rules={`${level.glasses} ст. · ${step} с/шаг`}
                  autoFocus={!cubeFirst && status === 'open'} onStart={() => onStart(index)} />
              );
            })}
          </div>
          <section className={`nightmare ${progress.completed ? '' : 'is-locked'}`}>
            <div><h2><T>Кошмар</T></h2><p><T>6 цветов · 4 стакана · скорость растёт каждую тысячу очков</T></p></div>
            <Button primary={progress.completed} disabled={!progress.completed} onClick={onInsane}><T>
              {progress.completed ? 'Играть' : 'После кампании'}
            </T></Button>
          </section>
        </section>

        <section className="campaign-part campaign-part--cube" ref={cubeRef}>
          <PartHead title="Куб · 3D" passed={passed(cubeProgress, CUBE_CAMPAIGN_LAST + 1)} count={CUBE_CAMPAIGN_LAST + 1} />
          {cubeSaved?.level !== undefined && (
            <section className="cube-campaign">
              <div className="cube-campaign__text">
                <strong><T>Уровень {cubeSaved.level + 1} не закончен</T></strong>
                <span><T>{formatPoints(cubeSaved.game.score)} · {formatDuration(cubeSaved.game.seconds)}</T></span>
              </div>
              <Button primary onClick={onCubeResume}><T>Продолжить</T></Button>
            </section>
          )}
          <div className="levels levels--cube">
            {CUBE_CAMPAIGN.map((level, index) => {
              const status = statusOf(cubeProgress, index, CUBE_CAMPAIGN_LAST);
              const best = cubeProgress.best[index] ?? 0;
              // Said in parts, each its own message in the catalog.
              const description = [
                level.title,
                `Цветов: ${level.colours}`,
                `Куб ${level.width}, рукав ${level.arm}`,
                level.depthFalls ? 'Стаканы спереди и сзади падают сами' : '',
                stateOf(status),
                best > 0 ? `Лучший результат: ${formatScore(best)}` : '',
              ].filter(Boolean).map((part) => t(part)).join('. ');
              return (
                <LevelCard key={index} index={index} target={level.target} colours={colours.slice(0, level.colours)}
                  status={status} description={description} title={level.title}
                  rules={`куб ${level.width} · рукав ${level.arm}${level.depthFalls ? ' · глубина' : ''}`}
                  autoFocus={cubeFirst && status === 'open'} onStart={() => onCubeStart(index)} />
              );
            })}
          </div>
        </section>
      </div>
    </Screen>
  );
}

const stateOf = (status: Status): string => (status === 'locked' ? 'Закрыто' : status === 'open' ? 'Доступен' : 'Пройден');

/** A part's name, and how much of it is passed. */
function PartHead({ title, passed, count }: { title: string; passed: number; count: number }) {
  return (
    <header className="campaign-part__head">
      <h2><T>{title}</T></h2>
      <span><T>{`пройдено ${passed} из ${count}`}</T></span>
      <div className="progressbar" aria-hidden="true"><i style={{ width: `${(100 * passed) / count}%` }} /></div>
    </header>
  );
}

function LevelCard({ index, target, colours, status, description, title, rules, autoFocus, onStart }: {
  index: number;
  target: number;
  colours: string[];
  status: Status;
  /** Read out and shown on hover, translated. */
  description: string;
  title?: string;
  rules: string;
  autoFocus: boolean;
  onStart: () => void;
}) {
  const { t } = useI18n();
  return (
    <button
      type="button"
      data-nav
      autoFocus={autoFocus}
      disabled={status === 'locked'}
      className={`level-card is-${status}`}
      onClick={onStart}
      aria-label={t(`Уровень ${index + 1}, цель ${target}`)}
      aria-description={description}
      title={description}
    >
      <span className="level-card__head">
        <strong><T>{String(index + 1).padStart(2, '0')}</T></strong>
        <span className="level-card__state" aria-hidden="true">
          {status === 'locked'
            ? <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                <rect x="3.5" y="7" width="9" height="7" rx="1" />
                <path d="M5.5 7V4a2.5 2.5 0 0 1 5 0v3" />
              </svg>
            : status === 'done' ? '✓' : '→'}
        </span>
      </span>
      {title && <span className="level-card__title"><T>{title}</T></span>}
      <span className="level-card__colours" aria-hidden="true">
        {colours.map((colour, slot) => <i key={slot} style={{ background: colour }} />)}
      </span>
      <span className="level-card__rules"><T>{rules}</T></span>
      <span className="level-card__target"><T>Цель {formatScore(target)}</T></span>
    </button>
  );
}
