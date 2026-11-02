// Plays the prototype with real key presses and photographs it at the
// moments NOTES.md talks about, into proto3d/shots/2d. (shots/3d holds the
// photographs of the first, perspective version, made by this script as it
// was in that commit.)
//
// usage, in webapp/: node proto3d/shots.mjs
import { mkdirSync, rmSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { chromium } from '@playwright/test';
import { createServer } from 'vite';

const root = fileURLToPath(new URL('..', import.meta.url));
const out = fileURLToPath(new URL('./shots/2d/', import.meta.url));
rmSync(out, { recursive: true, force: true });
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
  const atRest = () => page.waitForFunction(() => ['playing', 'gameOver'].includes(window.__proto3d.game.phase), null, { timeout: 5_000 });
  const settled = () => page.waitForFunction(() => !window.__proto3d.turning, null, { timeout: 5_000 });
  /** Photographs the frozen game, then lets it run on. A turn of the hub is
   * let finish first, unless the picture is of the turn. */
  const shot = async (name, { midTurn = false } = {}) => {
    if (!midTurn) await settled();
    if (!(await paused())) await key('KeyP');
    await wait(160);
    await page.screenshot({ path: `${out}${name}.jpg`, type: 'jpeg', quality: 86 });
    console.log(name);
    await key('KeyP');
  };
  /** Photographs the page as it is, paused or not. */
  const snap = async (name) => {
    await page.screenshot({ path: `${out}${name}.jpg`, type: 'jpeg', quality: 86 });
    console.log(name);
  };
  /** Turns and rolls go at this share of their speed, to be caught half-way. */
  const slow = (scale) => page.evaluate((s) => { window.__proto3d.options.transitionScale = s; }, scale);
  /** Drops the steered stick and waits until the board is at rest. */
  const drop = async () => {
    await key('Space');
    await atRest();
    await wait(80);
  };

  // A busy bottom, one to three blocks deep in every cell: only the nearest
  // of each is seen, and a mark in its corner gives the colour behind it.
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

  // The glass in front (4), steered in place: an outline over the picture,
  // a mark in each square saying whether it will be seen where it lands.
  await key('Digit4');
  await key('KeyA');
  await key('KeyS');
  await wait(250);
  await shot('03-front-steered');
  await drop();
  // The glass behind (3), over the stack: its squares would hide.
  await key('Digit3');
  await key('KeyS', 4);
  await wait(250);
  await shot('04-back-steered');

  // Holding V opens the depth up.
  await page.keyboard.down('KeyV');
  await wait(700);
  await shot('05-peek');
  await page.keyboard.up('KeyV');
  await wait(500);

  // Every stick in front and behind, not only the steered one.
  await key('KeyT');
  await wait(300);
  await shot('06-all-depth-sticks');
  await key('KeyT');

  // A clean board: columns built from the top, then the hub tipped over so
  // that the glass behind comes on top. The columns lie along the line of
  // sight now; the picture shows the top of each and settles to the bottom.
  await key('KeyN');
  await key('KeyI');
  await wait(200);
  const column = async (moves) => {
    for (const code of moves) await key(code);
    await key('KeyW');
    await drop();
  };
  await column(['KeyA', 'KeyA']);
  await column(['KeyA', 'KeyA']);
  await column(['KeyD', 'KeyD']);
  await column([]);
  await key('Digit1');
  await wait(200);
  await shot('07-columns-before-tip');
  // Holding ↑: the hub leans over like a tower of blocks, opening up into
  // depth half-way, then shows how it would lie, what would pop blinking;
  // letting go tips it.
  await slow(0.1);
  await page.keyboard.down('ArrowUp');
  await wait(3300);
  await snap('08-tip-tilt');
  await slow(1);
  await settled();
  await shot('09-tip-preview');
  await page.keyboard.up('ArrowUp');
  await atRest();
  await shot('10-after-tip');
  await key('KeyI');

  // A busy board looked at tipped over: what would pop blinks, and the panel
  // counts it. Esc puts it back.
  await key('KeyN');
  await key('KeyF');
  await wait(200);
  await page.keyboard.down('ArrowDown');
  await wait(700);
  await shot('11-tip-preview-pops');
  await key('Escape');
  await page.keyboard.up('ArrowDown');
  await settled();

  // Paused, the hub turns any way to be looked at: from the left (←), the
  // blocks that make lines from there blinking.
  await key('KeyP');
  await key('ArrowLeft');
  await settled();
  await wait(200);
  await snap('12-pause-look-from-left');
  // The same in the open, V held, then from below and the left (S, A).
  await page.keyboard.down('KeyV');
  await wait(800);
  await snap('13-pause-look-in-volume');
  await key('KeyS');
  await key('KeyA');
  await wait(900);
  await snap('14-volume-from-below-left');
  await key('KeyW');
  await key('KeyD');
  await page.keyboard.up('KeyV');
  await wait(500);
  // Going on rolls it back to where the game is.
  await key('KeyP');
  await settled();

  // The volume setting off: no edges of the hub, no numbers of the glasses
  // in front and behind — it looks like the 2D game.
  await key('KeyO');
  await wait(200);
  await shot('15-flat-2d');
  await key('KeyO');

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
    if (!matched) await atRest();
  }
  if (matched) await shot('16-match');

  // Play on carelessly until a glass is full.
  for (let i = 0; i < 150; i++) {
    if (await page.evaluate(() => window.__proto3d.game.isGameOver)) break;
    await key(glasses[i % glasses.length]);
    await settled();
    await drop();
  }
  await shot('17-game-over');
  // Once the game is over the hub can be looked around at once, and the
  // banner keeps out of the way.
  await key('ArrowLeft');
  await settled();
  await wait(200);
  await snap('18-game-over-look');
} finally {
  await browser.close();
  await server.close();
}
if (errors.length) {
  console.error(errors.join('\n'));
  process.exitCode = 1;
}
