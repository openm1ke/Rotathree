import { useRef } from 'react';
import { CAMPAIGN, CAMPAIGN_LAST, type CampaignLevel } from '../game/campaign';
import type { Progress } from '../services/storage';
import { formatScore } from './hudState';
import { Button, Screen } from './ui';
import { useScreenKeys } from './nav';

interface Props {
  progress: Progress;
  colours: string[];
  onStart: (level: number) => void;
  onInsane: () => void;
  onBack: () => void;
  active: boolean;
}

/** Compact level tiles, using the player's palette to show the colours in play. */
export function CampaignScreen({ progress, colours, onStart, onInsane, onBack, active }: Props) {
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, onBack);
  return (
    <Screen rootRef={rootRef} className="screen--campaign" kicker="Режим" title="Кампания" onBack={onBack}
      footer={<span>Уровни открываются по очереди · пройденные можно повторить</span>}>
      <div className="campaign-picker">
        <div className="levels">
          {CAMPAIGN.map((level, index) => (
            <LevelCard key={index} index={index} level={level} colours={colours}
              status={index < progress.unlocked || (index === CAMPAIGN_LAST && progress.completed)
                ? 'done' : index === progress.unlocked ? 'open' : 'locked'}
              best={progress.best[index] ?? 0} autoFocus={index === progress.unlocked}
              onStart={() => onStart(index)} />
          ))}
        </div>
        <section className={`nightmare ${progress.completed ? '' : 'is-locked'}`}>
          <div><h2>Кошмар</h2><p>6 цветов · 4 стакана · скорость растёт каждую тысячу очков</p></div>
          <Button primary={progress.completed} disabled={!progress.completed} onClick={onInsane}>
            {progress.completed ? 'Играть' : 'После кампании'}
          </Button>
        </section>
      </div>
    </Screen>
  );
}

function LevelCard({
  index,
  level,
  colours,
  status,
  best,
  autoFocus,
  onStart,
}: {
  index: number;
  level: CampaignLevel;
  colours: string[];
  status: 'done' | 'open' | 'locked';
  best: number;
  autoFocus: boolean;
  onStart: () => void;
}) {
  const step = String(level.activeStep).replace('.', ',');
  const state = status === 'locked' ? 'Закрыто' : status === 'open' ? 'Доступен' : 'Пройден';
  const description = `Цветов: ${level.colours}. Стаканов: ${level.glasses}. Шаг: ${step} с. ${state}`
    + (best > 0 ? `. Лучший результат: ${formatScore(best)}` : '');
  return (
    <button
      type="button"
      data-nav
      autoFocus={autoFocus}
      disabled={status === 'locked'}
      className={`level-card is-${status}`}
      onClick={onStart}
      aria-label={`Уровень ${index + 1}, цель ${level.target}`}
      aria-description={description}
      title={description}
    >
      <span className="level-card__head">
        <strong>{String(index + 1).padStart(2, '0')}</strong>
        <span className="level-card__state" aria-hidden="true">
          {status === 'locked'
            ? <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5">
                <rect x="3.5" y="7" width="9" height="7" rx="1" />
                <path d="M5.5 7V4a2.5 2.5 0 0 1 5 0v3" />
              </svg>
            : status === 'done' ? '✓' : '→'}
        </span>
      </span>
      <span className="level-card__colours" aria-hidden="true">
        {colours.slice(0, level.colours).map((colour, slot) => <i key={slot} style={{ background: colour }} />)}
      </span>
      <span className="level-card__rules">{level.glasses} ст. · {step} с/шаг</span>
      <span className="level-card__target">Цель {formatScore(level.target)}</span>
    </button>
  );
}
