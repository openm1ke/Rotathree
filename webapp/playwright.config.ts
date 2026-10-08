import { defineConfig } from '@playwright/test';
import process from 'node:process';

export default defineConfig({
  testDir: './e2e',
  workers: 2,
  fullyParallel: true,
  use: {
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
