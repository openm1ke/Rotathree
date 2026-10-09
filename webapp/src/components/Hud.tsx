import { T } from '../i18n/Text';
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
          <span className="hud__label"><T>Счёт</T></span>
          {/* Re-keyed on change so the number pops every time it grows. */}
          <span className="hud__value hud__value--xl" key={hud.score}><T>
            {formatScore(hud.score)}
          </T></span>
          {hud.level > 0 && (
            <div className="level">
              <div className="level__head">
                <span className="level__name"><T>
                  Уровень {hud.level}
                  <small><T> / {CAMPAIGN_LAST + 1}</T></small>
                </T></span>
                <span className="level__meta"><T>
                  {hud.colours} цв · {hud.glasses} ст
                </T></span>
              </div>
              <div className="level__bar">
                <i style={{ width: `${Math.min(100, (100 * hud.into) / Math.max(1, hud.target))}%` }} />
              </div>
              <span className="level__numbers"><T>
                {formatScore(hud.into)} / {formatScore(hud.target)}
              </T></span>
            </div>
          )}
          {hud.speed > 0 && <span className="speed"><T>Скорость {hud.speed}</T></span>}
          {callout?.kind === 'score' && (
            <span className="hud__gain" key={`gain-${callout.id}`}><T>
              +{callout.score}
            </T></span>
          )}
          {callout?.kind === 'score' && (callout.combo ?? 0) > 1 && (
            <span className="hud__combo" key={`combo-${callout.id}`}><T>
              <b><T>{callout.combo}×</T></b> комбо
            </T></span>
          )}
          {callout?.kind === 'speed' && (
            <span className="hud__speedup" key={`speed-${callout.id}`}><T>
              Скорость {callout.speed}
            </T></span>
          )}
        </section>
      )}

      {options.stats && (
        <>
          <section className="hud hud--tr">
            <span className="hud__label"><T>Время</T></span>
            <span className="hud__value"><T>{formatClock(hud.seconds)}</T></span>
            <span className="hud__label"><T>Фигуры</T></span>
            <span className="hud__value hud__value--sm"><T>{hud.pieces}</T></span>
          </section>

          <section className="hud hud--bl">
            <span className="hud__label"><T>Матчи</T></span>
            <span className="hud__value"><T>{hud.matches}</T></span>
            <span className="hud__label"><T>Лучшее комбо</T></span>
            <span className="hud__value hud__value--sm"><T>×{hud.bestCombo}</T></span>
          </section>
        </>
      )}

      <section className="hud hud--br">
        {options.keyHints && (
          <div className="hud__hints">
            <span><T>
              <Keys codes={[...bindings.moveLeft.slice(0, 1), ...bindings.moveRight.slice(0, 1)]} /> движение
            </T></span>
            <span><T>
              <Keys codes={[...bindings.rotateCW.slice(0, 1), ...bindings.rotateCCW.slice(0, 1)]} /> поворот
            </T></span>
            <span><T>
              <Keys codes={bindings.hardDrop.slice(0, 1)} /> сброс
            </T></span>
            <span><T>
              <Keys codes={[...bindings.glassLeft.slice(0, 1), ...bindings.glassRight.slice(0, 1)]} /> стаканы
            </T></span>
          </div>
        )}
        <div className="hud__buttons">
          <button type="button" className="chip" onClick={onPause}><T>
            Пауза
          </T></button>
          <button type="button" className="chip" onClick={onOpenSettings}><T>
            Настройки
          </T></button>
        </div>
      </section>
    </>
  );
}
