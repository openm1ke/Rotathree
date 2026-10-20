import { configDefaults, defineConfig, type Plugin } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { cpSync, mkdirSync, readFileSync, rmSync } from 'node:fs';

const BRIDGE = 'https://bridge.playgama.com/v2/stable/playgama-bridge.js';

/** The version and build of pubspec.yaml, the same as the archive's name:
 * telemetry tells builds apart by it. */
const BUILD_VERSION =
  /^version:\s*(\S+)/m.exec(readFileSync(new URL('../pubspec.yaml', import.meta.url), 'utf8'))?.[1] ?? 'dev';

/** The Playgama archive is played inside catalogue frames that forbid links
 * out of the game and anything that belongs to the site. */
function playgamaBuild(): Plugin {
  return {
    name: 'playgama-build',
    enforce: 'pre',
    // The credits keep their source pages for the site; the archive must not
    // carry the addresses even as unused data.
    transform(code, id) {
      if (!id.endsWith('/assets/credits/music.json')) return null;
      const tracks = (JSON.parse(code) as Record<string, unknown>[]).map(({ source: _source, ...track }) => track);
      return { code: JSON.stringify(tracks), map: null };
    },
    transformIndexHtml: {
      order: 'pre',
      handler: (html) => html
        .replace('<html lang="ru">', '<html lang="en">')
        // A plain, blocking tag: Bridge is on `window` before the game starts.
        .replace('<meta charset="UTF-8" />', `<meta charset="UTF-8" />\n    <script src="${BRIDGE}"></script>`)
        .replace(/\s*<link rel="(?:manifest|apple-touch-icon)"[^>]*>/g, '')
        .replace(/\s*<meta\s+name="description"[\s\S]*?\/>/, '')
        .replace(/\s*<!--[\s\S]*?-->/g, ''),
    },
  };
}

export default defineConfig(({ mode }) => {
  const playgama = mode === 'playgama';
  const outDir = playgama ? 'dist-playgama' : 'dist';
  return {
    // Relative base so the built app works when published under a sub-path
    // without needing to know that path at build time.
    base: './',
    plugins: [react(), ...(playgama ? [playgamaBuild()] : []), {
      name: 'release-credits',
      closeBundle() {
        mkdirSync(`${outDir}/licenses`, { recursive: true });
        for (const [source, name] of [
          ['../assets/fonts/OFL.txt', 'Exo2-OFL.txt'],
          ['node_modules/react/LICENSE', 'React-MIT.txt'],
          ['node_modules/react-dom/LICENSE', 'ReactDOM-MIT.txt'],
        ]) cpSync(source, `${outDir}/licenses/${name}`);
        for (const name of ['deep-focus.m4a', 'deep-focus-1.m4a']) rmSync(`${outDir}/music/${name}`, { force: true });
        if (!playgama) return;
        // The site's privacy page and install files have no place in a game
        // that runs inside somebody else's frame.
        for (const path of ['privacy', 'icons', 'site.webmanifest', 'apple-touch-icon.png']) {
          rmSync(`${outDir}/${path}`, { recursive: true, force: true });
        }
        cpSync('playgama/playgama-bridge-config.json', `${outDir}/playgama-bridge-config.json`);
      },
    }],
    build: { outDir },
    define: { __BUILD_VERSION__: JSON.stringify(BUILD_VERSION) },
    server: { port: 5183, strictPort: true },
    test: {
      environment: 'jsdom',
      globals: true,
      exclude: [...configDefaults.exclude, 'e2e/**'],
    },
  };
});
