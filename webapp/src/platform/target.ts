/**
 * Which shell the bundle is built for, decided at build time by the Vite mode:
 * `npm run build:playgama` builds in mode `playgama`.
 *
 * Vite substitutes the value for a literal, so every branch on it folds away
 * in the other builds: the site never carries Playgama Bridge, and the
 * Playgama archive never carries the site's links.
 */
export const PLAYGAMA_BUILD = import.meta.env.MODE === 'playgama';

/** Playgama keeps Esc for leaving full screen (Game Requirements 1.5.2): its
 * build neither binds the key nor answers it, in play or in the menus. */
export const USES_ESCAPE = !PLAYGAMA_BUILD;
