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

/** The levels, grouped by the number of colours. A level is open when every
 * level before it is finished; finished levels can be played again. */
export function CampaignScreen({ progress, colours, onStart, onInsane, onBack, active }: Props) {
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, onBack);

  const groups: { colours: number; levels: number[] }[] = [];
  CAMPAIGN.forEach((level, index) => {
    const group = groups[groups.length - 1];
    if (group && group.colours === level.colours) group.levels.push(index);
    else groups.push({ colours: level.colours, levels: [index] });
  });

  return (
    <Screen
      rootRef={rootRef}
      kicker="Режим"
      title="Кампания"
      onBack={onBack}
      footer={
        <>
          <span>Уровни открываются по очереди</span>
          <span>Очки считаются за уровень</span>
          <span>Пройденный уровень можно сыграть снова</span>
        </>
      }
    >
      {groups.map((group) => (
        <section className="stage-group" key={group.colours}>
          <header className="stage-group__head">
            <span className="dots">
              {colours.slice(0, group.colours).map((colour, i) => (
                <i key={i} style={{ background: colour }} />
              ))}
            </span>
            <h2>{group.colours} цвета</h2>
          </header>
          <div className="levels">
            {group.levels.map((index) => {
              const status = index < progress.unlocked || (index === CAMPAIGN_LAST && progress.completed)
                ? 'done'
                : index === progress.unlocked
                  ? 'open'
                  : 'locked';
              return (
                <LevelCard
                  key={index}
                  index={index}
                  level={CAMPAIGN[index]}
                  status={status}
                  best={progress.best[index] ?? 0}
                  autoFocus={index === progress.unlocked}
                  onStart={() => onStart(index)}
                />
              );
            })}
          </div>
        </section>
      ))}

      <section className="stage-group">
        <header className="stage-group__head">
          <h2>Безумие</h2>
        </header>
        <div className={`insane ${progress.completed ? '' : 'is-locked'}`}>
          <div>
            <strong>INSANE</strong>
            <p>
              6 цветов, 4 стакана. Скорость растёт с каждой тысячей очков, пока стакан не заполнится до конца.
            </p>
          </div>
          <Button primary={progress.completed} disabled={!progress.completed} onClick={onInsane}>
            {progress.completed ? 'Играть' : 'Закрыто'}
          </Button>
        </div>
      </section>
    </Screen>
  );
}

function LevelCard({
  index,
  level,
  status,
  best,
  autoFocus,
  onStart,
}: {
  index: number;
  level: CampaignLevel;
  status: 'done' | 'open' | 'locked';
  best: number;
  autoFocus: boolean;
  onStart: () => void;
}) {
  const faster = level.activeStep < 1;
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
      <span className="level-card__no">{index + 1}</span>
      <span className="level-card__glasses" aria-label={`${level.glasses} стакана`}>
        {[0, 1, 2, 3].map((g) => (
          <i key={g} className={g < level.glasses ? 'on' : ''} />
        ))}
      </span>
      <span className="level-card__target">{formatScore(level.target)}</span>
      <span className="level-card__meta">
        {level.glasses} ст · {faster ? 'быстрее' : 'обычная скорость'}
      </span>
      {status === 'done' && best > 0 && <span className="level-card__best">лучший {formatScore(best)}</span>}
      {status === 'locked' && <span className="level-card__lock">закрыто</span>}
    </button>
  );
}
