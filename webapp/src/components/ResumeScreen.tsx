import { T } from '../i18n/Text';
import { useRef } from 'react';
import type { RunSave, SavedRuns } from '../services/runSave';
import type { CubeSave } from '../cube/save';
import { MODE_NAMES } from '../game/modes';
import { abandonedRun } from '../services/runSave';
import { Screen, Button } from './ui';
import { useScreenKeys } from './nav';
import { formatDuration, formatPoints } from './format';

export function ResumeScreen({
  runs,
  onResume,
  cube,
  onResumeCube,
  onBack,
}: {
  runs: SavedRuns;
  onResume: (save: RunSave) => void;
  /** The game of Cube left unfinished, if any. */
  cube?: CubeSave | null;
  onResumeCube?: () => void;
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
      footer={<span><T>Каждый режим сохраняется автоматически. Другие партии остаются на месте.</T></span>}
    >
      {(['campaign', 'custom', 'insane'] as const).map((mode) => {
        const save = runs[mode];
        if (!save) return null;
        const totals = abandonedRun(save);
        return (
          <section className="group" key={mode}>
            <h3><T>{MODE_NAMES[mode]}</T></h3>
            <p className="hint"><T>
              {save.session.mode === 'campaign' ? `Уровень ${save.session.level + 1} · ` : ''}
              {formatPoints(totals.score)} · {formatDuration(totals.seconds)}
            </T></p>
            <Button primary onClick={() => onResume(save)}><T>
              Продолжить {MODE_NAMES[mode]}
            </T></Button>
          </section>
        );
      })}
      {cube && (
        <section className="group">
          <h3><T>{MODE_NAMES.cube}</T></h3>
          <p className="hint"><T>
            {formatPoints(cube.game.score)} · {formatDuration(cube.game.seconds)}
          </T></p>
          <Button primary onClick={() => onResumeCube?.()}><T>
            Продолжить {MODE_NAMES.cube}
          </T></Button>
        </section>
      )}
    </Screen>
  );
}
