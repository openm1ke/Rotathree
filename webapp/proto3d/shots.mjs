// Plays the prototype with real key presses and photographs it at the
// moments NOTES.md talks about, into proto3d/shots/2d. (shots/3d holds the
// photographs of the first, perspective version, made by this script as it
// was in that commit.)
//
// usage, in webapp/: node proto3d/shots.mjs
import { mkdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { createServer } from 'vite';

const root = fileURLToPath(new URL('..', import.meta.url));
const out = fileURLToPath(new URL('./shots/2d/', import.meta.url));
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

  const key = async (code, times = 1) => {
    for (let i = 0; i < times; i++) await page.keyboard.press(code);
  };
  const wait = (ms) => page.waitForTimeout(ms);
  const paused = () => page.evaluate(() => window.__proto3d.options.paused);
  const settled = () => page.waitForFunction(() => !window.__proto3d.turning, null, { timeout: 5_000 });
  /** Photographs the frozen game, then lets it run on. A turn of the hub is
   * let finish first, unless the picture is of the turn. */
  const shot = async (name, { midTurn = false } = {}) => {
    if (!midTurn) await settled();
    if (!(await paused())) await key('KeyP');
    await wait(120);
    await page.screenshot({ path: `${out}${name}.jpg`, type: 'jpeg', quality: 86 });
    console.log(name);
    await key('KeyP');
  };
  /** Drops the steered stick and waits until the board is at rest. */
  const drop = async () => {
    await key('Space');
    await page.waitForFunction(() => ['playing', 'gameOver'].includes(window.__proto3d.game.phase), null, { timeout: 5_000 });
    await wait(80);
  };

  // A busy bottom of the centre, every layer of it; the stick still on top.
  await key('KeyF');
  await wait(300);
  await shot('01-start');
  await key('KeyH');

  // The stick on top, aimed: the landing outline and the lane.
  await key('KeyD', 2);
  await key('KeyW');
  await wait(250);
  await shot('02-top-aimed');
  await drop();

  // The glass in front (4): its stick flies at the screen; the squares show
  // where it is and where it will land.
  await key('Digit4');
  await key('KeyA');
  await key('KeyS');
  await wait(250);
  await shot('03-front-steered');
  await drop();
  await key('Digit4');
  await wait(250);
  await shot('04-front-landed-behind');

  // And the glass behind (3).
  await key('Digit3');
  await key('KeyW', 2);
  await wait(250);
  await shot('05-back-steered');
  await drop();

  // Tumble the hub: the glass behind comes over the top. Half-way, and after.
  await key('Digit1');
  await key('ArrowUp');
  await wait(150);
  await key('KeyP');
  await shot('06-tumbling', { midTurn: true });
  await wait(600);
  await shot('07-after-tumble');

  // The same board with every layer shown, and with none.
  await key('KeyX');
  await shot('08a-all-layers');
  await key('KeyX', 2);
  await shot('08b-no-layers');
  await key('KeyX');

  // Drop here and there, with every glass taking turns, until something
  // matches; freeze on the flash.
  let matched = false;
  const glasses = ['Digit1', 'Digit3', 'Digit4'];
  for (let i = 0; i < 60 && !matched; i++) {
    await key(glasses[i % glasses.length]);
    await settled();
    for (const code of [['KeyA', 'KeyD', 'KeyW'][i % 3], ['KeyD', 'KeyQ', 'KeyA', 'KeyS'][i % 4]]) await key(code);
    await key('Space');
    matched = await page.evaluate(() => new Promise((resolve) => {
      const started = performance.now();
      const look = () => {
        const p = window.__proto3d;
        if (p.game.phase === 'matching') {
          p.press('KeyP');
          resolve(true);
        } else if (p.game.isGameOver || performance.now() - started > 700) resolve(false);
        else requestAnimationFrame(look);
      };
      look();
    }));
    if (await page.evaluate(() => window.__proto3d.game.isGameOver)) break;
    if (!matched) await page.waitForFunction(() => ['playing', 'gameOver'].includes(window.__proto3d.game.phase), null, { timeout: 5_000 });
  }
  if (matched) await shot('09-match');

  // Play on carelessly until a glass is full.
  for (let i = 0; i < 120; i++) {
    if (await page.evaluate(() => window.__proto3d.game.isGameOver)) break;
    await key(glasses[i % glasses.length]);
    await settled();
    await drop();
  }
  await shot('10-game-over');
} finally {
  await browser.close();
  await server.close();
}
if (errors.length) {
  console.error(errors.join('\n'));
  process.exitCode = 1;
}
