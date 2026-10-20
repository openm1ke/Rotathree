// Renders the Playgama covers from playgama/covers/cover.html with the local
// Chrome: square 800x800, portrait 1080x1920 and landscape 1920x1080, the
// three slots of the developer console (start_cover_upload).
import { chromium } from 'playwright';
import { mkdirSync } from 'node:fs';
import { fileURLToPath, pathToFileURL } from 'node:url';

const root = fileURLToPath(new URL('..', import.meta.url));
const page = pathToFileURL(`${root}playgama/covers/cover.html`).href;
const out = `${root}../build/releases/playgama/covers`;
mkdirSync(out, { recursive: true });

const browser = await chromium.launch({ channel: process.env.CI ? undefined : 'chrome' });
for (const [layout, width, height] of [['square', 800, 800], ['portrait', 1080, 1920], ['landscape', 1920, 1080]]) {
  const tab = await browser.newPage({ viewport: { width, height } });
  await tab.goto(`${page}?layout=${layout}`);
  await tab.evaluate(() => document.fonts.ready);
  const file = `${out}/cover-${layout}-${width}x${height}.png`;
  await tab.screenshot({ path: file });
  console.log(file);
  await tab.close();
}
await browser.close();
