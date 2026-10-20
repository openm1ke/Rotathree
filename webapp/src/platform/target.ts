/**
 * Which shell the bundle is built for, decided at build time by the Vite mode:
 * `npm run build:playgama` reads `VITE_PLATFORM=playgama` from `.env.playgama`.
 *
 * Vite substitutes the value for a literal, so every branch on it folds away
 * in the other builds: the site never carries Playgama Bridge, and the
 * Playgama archive never carries the site's links.
 */
export const PLAYGAMA_BUILD = import.meta.env.VITE_PLATFORM === 'playgama';
