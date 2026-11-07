import type { ReactNode } from 'react';
import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { USES_ESCAPE } from '../platform/target';

export type PauseIcon = 'replay' | 'settings' | 'levels' | 'edit' | 'look' | 'home' | 'flag';

/** One way out of a pause, drawn as a tile or as a link under them. */
export interface PauseAction {
  icon: PauseIcon;
  label: string;
  onClick: () => void;
  danger?: boolean;
}

const PATHS: Record<PauseIcon | 'pause' | 'play' | 'target' | 'sound-on' | 'sound-off', ReactNode> = {
  replay: <><path d="M4 12a8 8 0 1 0 2.4-5.7" /><path d="M4 4v4.5h4.5" /></>,
  settings: <><path d="M4 7h10M18 7h2M4 17h4M12 17h8" /><circle cx="16" cy="7" r="2" /><circle cx="10" cy="17" r="2" /></>,
  levels: <><rect x="4" y="4" width="7" height="7" rx="1.5" /><rect x="13" y="4" width="7" height="7" rx="1.5" /><rect x="4" y="13" width="7" height="7" rx="1.5" /><rect x="13" y="13" width="7" height="7" rx="1.5" /></>,
  edit: <><path d="M4 20h4L19 9l-4-4L4 16z" /><path d="m13 7 4 4" /></>,
  look: <><path d="M12 3 4 7.5v9L12 21l8-4.5v-9z" /><path d="M4 7.5 12 12l8-4.5M12 12v9" /></>,
  home: <><path d="M4 11 12 4l8 7" /><path d="M6 10v10h12V10" /></>,
  flag: <><path d="M5 21V4" /><path d="M5 4h12l-2.5 4L17 12H5" /></>,
  pause: <path d="M9 6v12M15 6v12" strokeWidth="3" />,
  play: <path d="M8 5.5v13l11-6.5z" fill="currentColor" />,
  target: <><circle cx="12" cy="12" r="8" /><circle cx="12" cy="12" r="4" /><circle cx="12" cy="12" r="0.8" fill="currentColor" /></>,
  'sound-on': <><path d="M3.5 9.5h3.5L11.5 6v12L7 14.5H3.5z" /><path d="M15 9.5a3.5 3.5 0 0 1 0 5M17.5 7a7 7 0 0 1 0 10" /></>,
  'sound-off': <><path d="M3.5 9.5h3.5L11.5 6v12L7 14.5H3.5z" /><path d="m15 9.5 5 5m0-5-5 5" /></>,
};

function Icon({ name }: { name: keyof typeof PATHS }) {
  return (
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      {PATHS[name]}
    </svg>
  );
}

/** The pause: the mode and level, the way back into the game, the things to
 * do as tiles under it, and the ways out last. The ring with the pause sign
 * also leads back into the game (a play sign when pointed at) — a second
 * door for the mouse, so it is hidden from the keyboard and screen readers;
 * the ring beside it turns the sound on and off, for the mouse and fingers
 * too: the keys walk the pause from Continue to the ways out, as before. */
export function PauseCard({
  kicker,
  note,
  onResume,
  tiles,
  links,
  sound,
}: {
  kicker: ReactNode;
  note?: ReactNode;
  onResume: () => void;
  tiles: PauseAction[];
  links: PauseAction[];
  sound?: { on: boolean; toggle: () => void };
}) {
  const { t } = useI18n();
  return (
    <div className="pause-card">
      <div className="pause-card__head">
        <div className="pause-card__heading">
          <span className="kicker">{kicker}</span>
          <h2 className="pause-card__title"><T>Пауза</T></h2>
        </div>
        {sound && (
          <button
            type="button"
            tabIndex={-1}
            className="ring ring--sound"
            aria-label={t(sound.on ? 'Выключить звук' : 'Включить звук')}
            title={t(sound.on ? 'Выключить звук' : 'Включить звук')}
            onClick={(event) => {
              sound.toggle();
              if (event.detail > 0) event.currentTarget.blur();
            }}
          >
            <span className="ring__face"><Icon name={sound.on ? 'sound-on' : 'sound-off'} /></span>
          </button>
        )}
        <button type="button" className="ring ring--go" tabIndex={-1} aria-hidden="true" title={t('Продолжить')} onClick={onResume}>
          <span className="ring__face">
            <span className="ring__idle"><Icon name="pause" /></span>
            <span className="ring__hover"><Icon name="play" /></span>
          </span>
        </button>
      </div>
      {note && (
        <p className="pause-card__note">
          <Icon name="target" />
          <span>{note}</span>
        </p>
      )}
      <button type="button" className="pause-card__resume" data-nav autoFocus onClick={onResume}>
        <Icon name="play" />
        <span className="pause-card__resume-label"><T>Продолжить</T></span>
        {USES_ESCAPE && <kbd aria-hidden="true">Esc</kbd>}
      </button>
      {tiles.length > 0 && (
        <div className={`pause-card__tiles ${tiles.length === 4 ? 'pause-card__tiles--pairs' : ''}`}>
          {tiles.map((tile) => (
            <button key={tile.label} type="button" data-nav className="pause-tile" onClick={tile.onClick}>
              <Icon name={tile.icon} />
              <span><T>{tile.label}</T></span>
            </button>
          ))}
        </div>
      )}
      {links.length > 0 && (
        <div className="pause-card__links">
          {links.map((link) => (
            <button
              key={link.label}
              type="button"
              data-nav
              className={`pause-link ${link.danger ? 'pause-link--danger' : ''}`}
              onClick={link.onClick}
            >
              <Icon name={link.icon} />
              <span><T>{link.label}</T></span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}
