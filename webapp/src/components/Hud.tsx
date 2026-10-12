import { T } from '../i18n/Text';
import type { HudOptions } from '../services/storage';
import { CAMPAIGN_LAST } from '../game/campaign';
import { formatClock, formatScore, type Callout, type HudState } from './hudState';
import { GameIconButton } from './ui';

interface Props {
  hud: HudState;
  callout: Callout | null;
  options: HudOptions;
  onPause: () => void;
  onOpenSettings: () => void;
}

/** One compact row shares the canvas width and keeps the playfield clear. */
export function Hud({ hud, callout, options, onPause, onOpenSettings }: Props) {
  return <>
    {options.score && <section className="hud hud--score">
      <span className="hud__label"><T>Счёт</T></span>
      <div className="hud__score-line">
        <strong className="hud__value hud__value--score"><T>{formatScore(hud.score)}</T></strong>
        {callout?.kind === 'score' && <span className="hud__gain" key={callout.id}><T>+{callout.score}</T></span>}
      </div>
      {hud.level > 0 && <span className="hud__level"><T>Уровень {hud.level} / {CAMPAIGN_LAST + 1}</T></span>}
      {hud.speed > 0 && <span className="hud__level"><T>Скорость {hud.speed}</T></span>}
    </section>}
    {options.stats && <section className="hud__stats">
      <div className="hud">
        <span className="hud__label"><T>Время</T></span>
        <strong className="hud__value"><T>{formatClock(hud.seconds)}</T></strong>
      </div>
      <div className="hud">
        <span className="hud__label"><T>Фигуры</T></span>
        <strong className="hud__value"><T>{hud.pieces}</T></strong>
      </div>
    </section>}
    <div className="hud__buttons">
      <GameIconButton icon="pause" label="Пауза" onClick={onPause} />
      <GameIconButton icon="settings" label="Настройки" onClick={onOpenSettings} />
    </div>
  </>;
}
