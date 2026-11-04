import { defineConfig } from '@playwright/test';
import process from 'node:process';

export default defineConfig({
  testDir: './e2e',
  workers: 2,
  fullyParallel: true,
  // GitHub's runners draw Cube's WebGL in software, a few frames a second,
  // and the game's clock moves at most 0.05 s a frame: its animations take
  // several times longer there than on a real screen.
  timeout: process.env.CI ? 60_000 : 30_000,
  expect: { timeout: process.env.CI ? 15_000 : 5_000 },
  use: {
    locale: 'ru-RU',
    baseURL: 'http://127.0.0.1:5183',
    // Local Chrome is already installed; CI installs Playwright Chromium.
    channel: process.env.CI ? undefined : 'chrome',
    viewport: { width: 1280, height: 800 },
    trace: 'retain-on-failure',
  },
  webServer: {
    command: 'npm run dev -- --host 127.0.0.1',
    url: 'http://127.0.0.1:5183',
    reuseExistingServer: !process.env.CI,
  },
});
