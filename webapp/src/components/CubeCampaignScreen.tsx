import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { useRef } from 'react';
import { CUBE_CAMPAIGN, CUBE_CAMPAIGN_LAST, type CubeLevel } from '../cube/campaign';
import type { Progress } from '../services/storage';
import { formatScore } from './hudState';
import { Button, Screen } from './ui';
import { formatDuration, formatPoints } from './format';
import type { CubeSave } from '../cube/save';
import { useScreenKeys } from './nav';

interface Props {
  progress: Progress;
  /** A level left unfinished, to go on with. */
  saved?: CubeSave;
  onResume?: () => void;
  colours: string[];
  onStart: (level: number) => void;
  onBack: () => void;
  active: boolean;
}

/** The levels of Cube's campaign, as the flat campaign shows its own: open
 * one by one, the passed ones to play again. */
export function CubeCampaignScreen({ progress, saved, onResume, colours, onStart, onBack, active }: Props) {
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, onBack);
  return (
    <Screen rootRef={rootRef} className="screen--campaign" kicker="Куб" title="Кампания" onBack={onBack}
      footer={<span><T>Уровни открываются по очереди · пройденные можно повторить</T></span>}>
      <div className="campaign-picker">
        {saved?.level !== undefined && (
          <section className="cube-campaign">
            <div className="cube-campaign__text">
              <strong><T>Уровень {saved.level + 1} не закончен</T></strong>
              <span><T>{formatPoints(saved.game.score)} · {formatDuration(saved.game.seconds)}</T></span>
            </div>
            <Button primary onClick={() => onResume?.()}><T>Продолжить</T></Button>
          </section>
        )}
        <div className="levels levels--cube">
          {CUBE_CAMPAIGN.map((level, index) => (
            <LevelCard key={index} index={index} level={level} colours={colours}
              status={index < progress.unlocked || (index === CUBE_CAMPAIGN_LAST && progress.completed)
                ? 'done' : index === progress.unlocked ? 'open' : 'locked'}
              best={progress.best[index] ?? 0} autoFocus={index === progress.unlocked}
              onStart={() => onStart(index)} />
          ))}
        </div>
      </div>
    </Screen>
  );
}

function LevelCard({ index, level, colours, status, best, autoFocus, onStart }: {
  index: number;
  level: CubeLevel;
  colours: string[];
  status: 'done' | 'open' | 'locked';
  best: number;
  autoFocus: boolean;
  onStart: () => void;
}) {
  const { t } = useI18n();
  const state = status === 'locked' ? 'Закрыто' : status === 'open' ? 'Доступен' : 'Пройден';
  // Said in parts, each its own message in the catalog.
  const description = [
    level.title,
    `Цветов: ${level.colours}`,
    `Куб ${level.width}, рукав ${level.arm}`,
    level.depthFalls ? 'Стаканы спереди и сзади падают сами' : '',
    state,
    best > 0 ? `Лучший результат: ${formatScore(best)}` : '',
  ].filter(Boolean).map((part) => t(part)).join('. ');
  return (
    <button
      type="button"
      data-nav
      autoFocus={autoFocus}
      disabled={status === 'locked'}
      className={`level-card is-${status}`}
      onClick={onStart}
      aria-label={t(`Уровень ${index + 1}, цель ${level.target}`)}
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
      <span className="level-card__title"><T>{level.title}</T></span>
      <span className="level-card__colours" aria-hidden="true">
        {colours.slice(0, level.colours).map((colour, slot) => <i key={slot} style={{ background: colour }} />)}
      </span>
      <span className="level-card__rules"><T>
        куб {level.width} · рукав {level.arm}{level.depthFalls ? ' · глубина' : ''}
      </T></span>
      <span className="level-card__target"><T>Цель {formatScore(level.target)}</T></span>
    </button>
  );
}
