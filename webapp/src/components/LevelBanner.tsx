import type { ReactNode } from 'react';
import { T } from '../i18n/Text';
import { currentSkin } from '../render/theme';
import { BlockRow } from './BlockRow';

/** What a banner says, which picks its badge. */
export type BannerKind = 'passed' | 'stage' | 'glass' | 'level' | 'start';

/** A message over the field: a level finished, a new stage, a new glass. */
export interface BannerData {
  id: number;
  kicker: string;
  title: string;
  sub?: string;
  /** Colours of the stage, shown as blocks. */
  colours?: string[];
  /** How long it stays, in seconds. */
  seconds: number;
  /** Comes in and stays until play goes on, rather than for `seconds`. */
  held?: boolean;
  kind?: BannerKind;
}

const BADGES: Record<BannerKind, ReactNode> = {
  // A cup.
  passed: <><path d="M8 4h8v5a4 4 0 0 1-8 0z" /><path d="M8 6H5a3 3 0 0 0 3 4M16 6h3a3 3 0 0 1-3 4M12 13v4M9 20h6" /></>,
  // Sparks.
  stage: <><path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6z" /><path d="M18 15l.7 1.8 1.8.7-1.8.7L18 20l-.7-1.8-1.8-.7 1.8-.7z" /></>,
  // A box with a plus.
  glass: <><rect x="4" y="4" width="16" height="16" rx="3" /><path d="M12 8v8M8 12h8" /></>,
  // A flag.
  level: <><path d="M6 21V4" /><path d="M6 4h11l-2.5 4L17 12H6" /></>,
  // A play sign.
  start: <path d="M9 6.5v11l9-5.5z" fill="currentColor" />,
};

/** A small card that pops up over the field: a badge for what happened, its
 * kicker and title, what comes next on a pill, and a new stage's colours as
 * blocks drawn as the field draws them. */
export function LevelBanner({ banner }: { banner: BannerData }) {
  const kind = banner.kind ?? 'level';
  return (
    <div className={`banner${banner.held ? ' banner--held' : ''}`} key={banner.id} role="status" style={{ ['--life' as string]: `${banner.seconds}s` }}>
      <div className="banner__card">
        <span className="banner__badge" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
            {BADGES[kind]}
          </svg>
        </span>
        <span className="banner__kicker"><T>{banner.kicker}</T></span>
        <span className="banner__title"><T>{banner.title}</T></span>
        {banner.colours && banner.colours.length > 0 && (
          <span className="banner__blocks">
            <BlockRow skin={currentSkin()} colours={banner.colours} unit={26} />
          </span>
        )}
        {banner.sub && <span className="banner__sub"><T>{banner.sub}</T></span>}
      </div>
    </div>
  );
}
