import { T } from '../i18n/Text';
import { useI18n } from '../i18n/context';
import type { HudOptions } from '../services/storage';
import { CAMPAIGN_LAST } from '../game/campaign';
import { formatClock, formatScore, type Callout, type HudState } from './hudState';
import { GameIconButton, SoundButton } from './ui';

interface Props {
  hud: HudState;
  callout: Callout | null;
  options: HudOptions;
  onPause: () => void;
  onOpenSettings: () => void;
  /** The music switch beside the gear (Playgama build). */
  sound?: { on: boolean; toggle: () => void };
  compact?: boolean;
}

/** One compact row shares the canvas width and keeps the playfield clear. */
export function Hud({ hud, callout, options, onPause, onOpenSettings, sound, compact = false }: Props) {
  const { t } = useI18n();
  const soundButton = sound && <SoundButton on={sound.on} onToggle={sound.toggle} />;
  if (compact) return <>
    <div className="hud__buttons"><GameIconButton icon="pause" label="Пауза" onClick={onPause} /></div>
    <div className="hud__mobile-readout" style={{ opacity: options.opacity }}>
      {options.score && <div className="hud__mobile-score" aria-label={`${t('Счёт')}: ${formatScore(hud.score)}`}>
        <strong>{formatScore(hud.score)}</strong>
        {callout?.kind === 'score' && <span className="hud__gain" key={callout.id}>+{callout.score}</span>}
      </div>}
      {options.score && hud.level > 0 && <CompactStat icon="level" value={`${hud.level}/${CAMPAIGN_LAST + 1}`}
        label={t(`Уровень ${hud.level} / ${CAMPAIGN_LAST + 1}`)} accent />}
      {options.score && hud.speed > 0 && <CompactStat icon="level" value={`${hud.speed}`} label={t(`Скорость ${hud.speed}`)} accent />}
      {options.stats && <>
        <CompactStat icon="time" value={formatClock(hud.seconds)} label={t('Время')} />
        <CompactStat icon="pieces" value={`${hud.pieces}`} label={t('Фигуры')} />
      </>}
    </div>
    <div className="hud__buttons">
      {soundButton}
      <GameIconButton icon="settings" label="Настройки" onClick={onOpenSettings} />
    </div>
  </>;
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
      {soundButton}
      <GameIconButton icon="settings" label="Настройки" onClick={onOpenSettings} />
    </div>
  </>;
}

function CompactStat({ icon, value, label, accent = false }: {
  icon: 'level' | 'time' | 'pieces'; value: string; label: string; accent?: boolean;
}) {
  return <span className={`hud__compact-stat ${accent ? 'hud__compact-stat--accent' : ''}`} title={label} aria-label={accent ? label : `${label}: ${value}`}>
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
      {icon === 'time' ? <><circle cx="12" cy="12" r="9" /><path d="M12 6v6l4 2" /></>
        : icon === 'level' ? <><path d="m12 3 10 6-10 6L2 9Z M2 14l10 6 10-6" /></>
        : <><rect x="3" y="4" width="7" height="7" rx="1" /><rect x="14" y="4" width="7" height="7" rx="1" /><rect x="3" y="15" width="7" height="7" rx="1" /></>}
    </svg>
    <span>{value}</span>
  </span>;
}
