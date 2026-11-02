// Plays the 3D prototype with real key presses and photographs it at the
// moments NOTES.md talks about, into proto3d/shots.
//
// usage, in webapp/: node proto3d/shots.mjs
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { createServer } from 'vite';

const root = fileURLToPath(new URL('..', import.meta.url));
const out = fileURLToPath(new URL('./shots/3d/', import.meta.url));
mkdirSync(out, { recursive: true });

const server = await createServer({ root, logLevel: 'error', server: { port: 0 } });
await server.listen();
const base = server.resolvedUrls.local[0];
const browser = await chromium.launch({ channel: 'chrome', args: ['--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });
const errors = [];

try {
  const page = await browser.newPage({ viewport: { width: 1440, height: 900 }, deviceScaleFactor: 1 });
  page.on('pageerror', (error) => errors.push(error.message));
  page.on('console', (message) => { if (message.type() === 'error') errors.push(message.text()); });
  await page.goto(`${base}proto3d/?seed=11`);
  await page.waitForFunction(() => window.__proto3d?.ready === true, null, { timeout: 30_000 });

  const key = (code, times = 1) => page.keyboard.press(code).then(() => (times > 1 ? key(code, times - 1) : undefined));
  const wait = (ms) => page.waitForTimeout(ms);
  const state = () => page.evaluate(() => ({ phase: window.__proto3d.game.phase, paused: window.__proto3d.options.paused }));
  /** Photographs the frozen game, then lets it run on. */
  const shot = async (name) => {
    if (!(await state()).paused) await key('KeyP');
    await wait(120);
    await page.screenshot({ path: `${out}${name}.jpg`, type: 'jpeg', quality: 86 });
    console.log(name);
    await key('KeyP');
  };

  // A busy centre to aim at, the stick still at the rim.
  await key('KeyF');
  await wait(300);
  await shot('01-start');
  await key('KeyH');

  // Slid to the far right corner of the glass: the ghost and the lane.
  await key('KeyD', 2);
  await key('KeyW', 2);
  await wait(250);
  await shot('02-aim-lying');

  // Spun flat to lie far–near, then stood up: from above the two look alike.
  await key('KeyR');
  await key('KeyA');
  await wait(250);
  await shot('03a-aim-far-near');
  await key('KeyE');
  await wait(250);
  await shot('03b-aim-standing');
  await key('Space');
  await wait(700);

  // Half-way through a turn of the hub, and once it is over.
  await key('ArrowLeft');
  await wait(140);
  await key('KeyP');
  await shot('04-turning');
  await wait(600);
  await shot('05-after-left-turn');
  await key('KeyT');
  await shot('05b-after-left-turn-others-solid');
  await key('KeyT');

  await key('KeyX');
  await shot('06-xray-shell');
  await key('KeyX');
  await shot('07-xray-slice');
  await key('KeyX');

  // Drop sticks here and there until something matches; freeze on the
  // flash.
  let matched = false;
  for (let i = 0; i < 40 && !matched; i++) {
    const moves = ['KeyA', 'KeyD', 'KeyW', 'KeyS', 'KeyQ', 'KeyE'];
    for (let m = 0; m < 2; m++) await key(moves[(i * 7 + m * 3) % moves.length]);
    await key('Space');
    matched = await page.evaluate(() => new Promise((resolve) => {
      const started = performance.now();
      const look = () => {
        const p = window.__proto3d;
        if (p.game.phase === 'matching') {
          p.press('KeyP');
          resolve(true);
        } else if (p.game.isGameOver || performance.now() - started > 900) resolve(false);
        else requestAnimationFrame(look);
      };
      look();
    }));
    if (!matched) await wait(150);
    if ((await page.evaluate(() => window.__proto3d.game.isGameOver))) break;
  }
  if (matched) await shot('08-match');

  // The same board from straight above and from 60°.
  await key('KeyP');
  await key('KeyV', 2);
  await wait(900);
  await shot('09-tilt-60');
  await key('KeyP');
  await key('KeyV');
  await wait(900);
  await shot('10-tilt-0');
  await key('KeyP');
  await key('KeyV');
  await key('KeyP');

  // Fill the glass up to its far end.
  for (let i = 0; i < 60; i++) {
    if (await page.evaluate(() => window.__proto3d.game.isGameOver)) break;
    await key('Space');
    await wait(260);
  }
  await shot('11-game-over');
} finally {
  await browser.close();
  await server.close();
}
if (errors.length) {
  console.error(errors.join('\n'));
  process.exitCode = 1;
}
