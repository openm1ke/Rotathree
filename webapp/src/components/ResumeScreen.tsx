import { T } from '../i18n/Text';
import { useRef } from 'react';
import type { RunSave, SavedRuns } from '../services/runSave';
import type { CubeKind, CubeRuns } from '../cube/save';
import { CUBE_CAMPAIGN_LAST } from '../cube/campaign';
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
  /** The games of Cube left unfinished. */
  cube?: CubeRuns;
  onResumeCube?: (kind: CubeKind) => void;
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
      {(['campaign', 'endless'] as const).map((kind) => {
        const save = cube?.[kind];
        if (!save) return null;
        const mode = kind === 'campaign' ? MODE_NAMES.cubeCampaign : MODE_NAMES.cube;
        return (
          <section className="group" key={kind}>
            <h3><T>{mode}</T></h3>
            <p className="hint"><T>
              {save.level !== undefined ? `Уровень ${save.level + 1} из ${CUBE_CAMPAIGN_LAST + 1} · ` : ''}
              {formatPoints(save.game.score)} · {formatDuration(save.game.seconds)}
            </T></p>
            <Button primary onClick={() => onResumeCube?.(kind)}><T>
              Продолжить {mode}
            </T></Button>
          </section>
        );
      })}
    </Screen>
  );
}
