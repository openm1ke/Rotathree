import type { Bindings } from '../input/bindings';
import { formatClock, type Callout, type HudState } from './hudState';
import { Keys } from './Keycap';

interface Props {
  hud: HudState;
  callout: Callout | null;
  bindings: Bindings;
  onPause: () => void;
  onOpenSettings: () => void;
}

/** Four panels in the corners the cross leaves free. */
export function Hud({ hud, callout, bindings, onPause, onOpenSettings }: Props) {
  return (
    <>
      <section className="hud hud--tl">
        <span className="hud__label">Счёт</span>
        {/* Re-keyed on change so the number pops every time it grows. */}
        <span className="hud__value hud__value--xl" key={hud.score}>
          {hud.score.toLocaleString('ru-RU')}
        </span>
        {callout && (
          <span className="hud__gain" key={callout.id}>
            +{callout.score}
          </span>
        )}
      </section>

      <section className="hud hud--tr">
        <span className="hud__label">Время</span>
        <span className="hud__value">{formatClock(hud.seconds)}</span>
        <span className="hud__label">Фигуры</span>
        <span className="hud__value hud__value--sm">{hud.pieces}</span>
      </section>

      <section className="hud hud--bl">
        {callout && callout.combo > 1 && (
          <span className="hud__combo" key={callout.id}>
            <b>{callout.combo}×</b> комбо
          </span>
        )}
        <span className="hud__label">Матчи</span>
        <span className="hud__value">{hud.matches}</span>
        <span className="hud__label">Лучшее комбо</span>
        <span className="hud__value hud__value--sm">×{hud.bestCombo}</span>
      </section>

      <section className="hud hud--br">
        <div className="hud__hints">
          <span>
            <Keys codes={[...bindings.moveLeft.slice(0, 1), ...bindings.moveRight.slice(0, 1)]} /> движение
          </span>
          <span>
            <Keys codes={[...bindings.rotateCW.slice(0, 1), ...bindings.rotateCCW.slice(0, 1)]} /> поворот
          </span>
          <span>
            <Keys codes={bindings.softDrop.slice(0, 1)} /> быстрее
          </span>
          <span>
            <Keys codes={bindings.hardDrop.slice(0, 1)} /> сброс
          </span>
          <span>
            <Keys codes={[...bindings.glassLeft.slice(0, 1), ...bindings.glassRight.slice(0, 1)]} /> стаканы
          </span>
        </div>
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
