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

/** A single list: each level carries its rules and completion state. */
export function CampaignScreen({ progress, colours, onStart, onInsane, onBack, active }: Props) {
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, onBack);
  return (
    <Screen rootRef={rootRef} kicker="Режим" title="Кампания" onBack={onBack}
      footer={<span>Уровни открываются по очереди · пройденные можно повторить</span>}>
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
  return (
    <button
      type="button"
      data-nav
      autoFocus={autoFocus}
      disabled={status === 'locked'}
      className={`level-card is-${status}`}
      onClick={onStart}
      aria-label={`Уровень ${index + 1}, цель ${level.target}`}
    >
      <span className="level-card__head">
        <strong>Уровень {index + 1}</strong>
        <span className="level-card__target">Цель {formatScore(level.target)}</span>
      </span>
      <span className="level-card__badges">
        <span className="level-badge"><i style={{ background: colours[0] }} />Цвета: {level.colours}</span>
        <span className="level-badge">Стаканы: {level.glasses}</span>
        <span className="level-badge">Скорость: {String(level.activeStep).replace('.', ',')} с/шаг</span>
      </span>
      <span className="level-card__meta">
        {status === 'locked' ? 'Закрыто' : status === 'open' ? 'Играть →'
          : best > 0 ? `✓ Лучший: ${formatScore(best)}` : '✓ Пройден'}
      </span>
    </button>
  );
}
