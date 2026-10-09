import type { Bindings } from '../input/bindings';
import type { HudOptions } from '../services/storage';
import { CAMPAIGN_LAST } from '../game/campaign';
import { formatClock, formatScore, type Callout, type HudState } from './hudState';
import { Keys } from './Keycap';

interface Props {
  hud: HudState;
  callout: Callout | null;
  bindings: Bindings;
  /** Which of the panels are shown. */
  options: HudOptions;
  onPause: () => void;
  onOpenSettings: () => void;
}

/** Readouts above the canvas keep the fitted field clear at every glass count. */
export function Hud({ hud, callout, bindings, options, onPause, onOpenSettings }: Props) {
  return (
    <>
      {options.score && (
        <section className="hud hud--tl">
          <span className="hud__label">Счёт</span>
          {/* Re-keyed on change so the number pops every time it grows. */}
          <span className="hud__value hud__value--xl" key={hud.score}>
            {formatScore(hud.score)}
          </span>
          {hud.level > 0 && (
            <div className="level">
              <div className="level__head">
                <span className="level__name">
                  Уровень {hud.level}
                  <small> / {CAMPAIGN_LAST + 1}</small>
                </span>
                <span className="level__meta">
                  {hud.colours} цв · {hud.glasses} ст
                </span>
              </div>
              <div className="level__bar">
                <i style={{ width: `${Math.min(100, (100 * hud.into) / Math.max(1, hud.target))}%` }} />
              </div>
              <span className="level__numbers">
                {formatScore(hud.into)} / {formatScore(hud.target)}
              </span>
            </div>
          )}
          {hud.speed > 0 && <span className="speed">Скорость {hud.speed}</span>}
          {callout?.kind === 'score' && (
            <span className="hud__gain" key={`gain-${callout.id}`}>
              +{callout.score}
            </span>
          )}
          {callout?.kind === 'score' && (callout.combo ?? 0) > 1 && (
            <span className="hud__combo" key={`combo-${callout.id}`}>
              <b>{callout.combo}×</b> комбо
            </span>
          )}
          {callout?.kind === 'speed' && (
            <span className="hud__speedup" key={`speed-${callout.id}`}>
              Скорость {callout.speed}
            </span>
          )}
        </section>
      )}

      {options.stats && (
        <>
          <section className="hud hud--tr">
            <span className="hud__label">Время</span>
            <span className="hud__value">{formatClock(hud.seconds)}</span>
            <span className="hud__label">Фигуры</span>
            <span className="hud__value hud__value--sm">{hud.pieces}</span>
          </section>

          <section className="hud hud--bl">
            <span className="hud__label">Матчи</span>
            <span className="hud__value">{hud.matches}</span>
            <span className="hud__label">Лучшее комбо</span>
            <span className="hud__value hud__value--sm">×{hud.bestCombo}</span>
          </section>
        </>
      )}

      <section className="hud hud--br">
        {options.keyHints && (
          <div className="hud__hints">
            <span>
              <Keys codes={[...bindings.moveLeft.slice(0, 1), ...bindings.moveRight.slice(0, 1)]} /> движение
            </span>
            <span>
              <Keys codes={[...bindings.rotateCW.slice(0, 1), ...bindings.rotateCCW.slice(0, 1)]} /> поворот
            </span>
            <span>
              <Keys codes={bindings.hardDrop.slice(0, 1)} /> сброс
            </span>
            <span>
              <Keys codes={[...bindings.glassLeft.slice(0, 1), ...bindings.glassRight.slice(0, 1)]} /> стаканы
            </span>
          </div>
        )}
        <div className="hud__buttons">
          <button type="button" className="chip" onClick={onPause}>
            Пауза
          </button>
          <button type="button" className="chip" onClick={onOpenSettings}>
            Настройки
          </button>
        </div>
      </section>
    </>
  );
}
