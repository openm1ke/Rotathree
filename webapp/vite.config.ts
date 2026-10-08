import { configDefaults, defineConfig } from 'vitest/config';
import react from '@vitejs/plugin-react';

export default defineConfig({
  // Relative base so the built app works when published under a sub-path
  // without needing to know that path at build time.
  base: './',
  plugins: [react()],
  server: { port: 5183, strictPort: true },
  test: {
    environment: 'jsdom',
    globals: true,
    exclude: [...configDefaults.exclude, 'e2e/**'],
  },
});
