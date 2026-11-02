// Photographs the key art (promo-lab/index.html) in every format and with
// every caption into docs/marketing/keyart.
//
// usage, in webapp/: node promo-lab/render.mjs [format…]
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { createServer } from 'vite';

const root = fileURLToPath(new URL('..', import.meta.url));
const out = fileURLToPath(new URL('../../docs/marketing/keyart/', import.meta.url));

/** Format, size in CSS pixels, pixel ratio, captions. */
const SHOTS = [
  ['16x9', 1920, 1080, 2, ['en', 'ru', 'none']],
  ['9x16', 1080, 1920, 2, ['en', 'ru', 'none']],
  ['1x1', 1080, 1080, 2, ['en', 'ru', 'none']],
  // Google Play's feature graphic is exactly 1024 × 500.
  ['feature', 1024, 500, 1, ['en', 'ru']],
];
const only = process.argv.slice(2);

mkdirSync(out, { recursive: true });
const server = await createServer({ root, logLevel: 'error', server: { port: 0 } });
await server.listen();
const base = server.resolvedUrls.local[0];
const browser = await chromium.launch({ channel: 'chrome', args: ['--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
try {
  for (const [format, width, height, scale, texts] of SHOTS) {
    if (only.length && !only.includes(format)) continue;
    for (const text of texts) {
      const page = await browser.newPage({ viewport: { width, height }, deviceScaleFactor: scale });
      const errors = [];
      page.on('pageerror', (error) => errors.push(error.message));
      await page.goto(`${base}promo-lab/?format=${format}&text=${text}`);
      await page.waitForFunction(() => window.__keyartReady === true, null, { timeout: 60_000 });
      const file = `${out}rotathree-keyart-${format}-${text}.png`;
      await page.screenshot({ path: file });
      console.log(errors.length ? `${file} — ${errors.join('; ')}` : file);
      await page.close();
    }
  }
} finally {
  await browser.close();
  await server.close();
}
