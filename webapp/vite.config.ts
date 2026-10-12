import { configDefaults, defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { cpSync, mkdirSync, rmSync } from 'node:fs';

export default defineConfig({
  // Relative base so the built app works when published under a sub-path
  // without needing to know that path at build time.
  base: './',
  plugins: [react(), {
    name: 'release-credits',
    closeBundle() {
      mkdirSync('dist/licenses', { recursive: true });
      for (const [source, name] of [
        ['../assets/fonts/OFL.txt', 'Exo2-OFL.txt'],
        ['node_modules/react/LICENSE', 'React-MIT.txt'],
        ['node_modules/react-dom/LICENSE', 'ReactDOM-MIT.txt'],
      ]) cpSync(source, `dist/licenses/${name}`);
      for (const name of ['deep-focus.m4a', 'deep-focus-1.m4a']) rmSync(`dist/music/${name}`, { force: true });
    },
  }],
  server: { port: 5183, strictPort: true },
  test: {
    environment: 'jsdom',
    globals: true,
    exclude: [...configDefaults.exclude, 'e2e/**'],
  },
});
