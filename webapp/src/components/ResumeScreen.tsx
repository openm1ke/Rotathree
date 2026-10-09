import { useRef } from 'react';
import type { RunSave, SavedRuns } from '../services/runSave';
import { MODE_NAMES } from '../game/modes';
import { abandonedRun } from '../services/runSave';
import { Screen, Button } from './ui';
import { useScreenKeys } from './nav';
import { formatDuration, formatNumber } from './format';

export function ResumeScreen({
  runs,
  onResume,
  onBack,
}: {
  runs: SavedRuns;
  onResume: (save: RunSave) => void;
  onBack: () => void;
}) {
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, true, onBack);
  return (
    <Screen
      rootRef={rootRef}
      kicker="Сохранённые игры"
      title="Продолжить"
      onBack={onBack}
      footer={<span>Каждый режим сохраняется автоматически. Другие партии остаются на месте.</span>}
    >
      {(['campaign', 'custom', 'insane'] as const).map((mode) => {
        const save = runs[mode];
        if (!save) return null;
        const totals = abandonedRun(save);
        return (
          <section className="group" key={mode}>
            <h3>{MODE_NAMES[mode]}</h3>
            <p className="hint">
              {save.session.mode === 'campaign' ? `Уровень ${save.session.level + 1} · ` : ''}
              {formatNumber(totals.score)} очков · {formatDuration(totals.seconds)}
            </p>
            <Button primary onClick={() => onResume(save)}>
              Продолжить {MODE_NAMES[mode]}
            </Button>
          </section>
        );
      })}
    </Screen>
  );
}
