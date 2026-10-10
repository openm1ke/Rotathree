import { configDefaults, defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';
import { cpSync, rmSync, writeFileSync } from 'node:fs';
import { loadEnv } from 'vite';

export default defineConfig(({ mode }) => ({
  // Relative base so the built app works when published under a sub-path
  // without needing to know that path at build time.
  base: './',
  plugins: [react(), {
    name: 'vk-licensed-music',
    closeBundle() {
      if (mode !== 'vk') return;
      for (const name of ['deep-focus.m4a', 'deep-focus-1.m4a']) rmSync(`dist-vk/music/${name}`, { force: true });
      cpSync('vk-public', 'dist-vk', { recursive: true });
      for (const [source, name] of [
        ['../assets/fonts/OFL.txt', 'Exo2-OFL.txt'],
        ['node_modules/@vkontakte/vk-bridge/LICENSE', 'VK-Bridge-MIT.txt'],
        ['node_modules/react/LICENSE', 'React-MIT.txt'],
        ['node_modules/react-dom/LICENSE', 'ReactDOM-MIT.txt'],
      ]) cpSync(source, `dist-vk/licenses/${name}`);
      writeFileSync('dist-vk/vk-release.json', JSON.stringify({ platform: 'vk', appId: loadEnv(mode, process.cwd(), 'VITE_').VITE_VK_APP_ID, draft: true, ads: false, purchases: false, languages: ['ru', 'en'] }, null, 2));
    },
  }],
  build: { outDir: mode === 'vk' ? 'dist-vk' : 'dist' },
  server: { port: 5183, strictPort: true },
  test: {
    environment: 'jsdom',
    globals: true,
    exclude: [...configDefaults.exclude, 'e2e/**'],
  },
}));
