import { expect, test, type Page } from '@playwright/test';
import type { CubeGame } from '../src/cube/rules';

/** The running game of Cube (development builds expose it). */
const cube = <T,>(page: Page, read: (game: CubeGame) => T) =>
  page.evaluate(`(${read.toString()})(window.__rotathreeCube.game)`) as Promise<T>;

async function openCube(page: Page, { lessonsSeen = true } = {}) {
  await page.addInitScript((seen) => {
    localStorage.setItem('rotathree.tutorial.v1', 'true');
    if (seen) localStorage.setItem('rotathree.cube-tutorial.v1', 'true');
  }, lessonsSeen);
  await page.goto('/');
  await page.getByRole('button', { name: /Шесть стаканов в 3D/ }).click();
  await expect(page.getByRole('heading', { name: 'Куб', exact: true })).toBeVisible();
}

async function play(page: Page) {
  await page.getByRole('button', { name: 'Играть', exact: true }).click();
  await expect(page.locator('.game__readout')).toBeVisible();
  await expect.poll(() => cube(page, (game) => game.phase)).toBe('playing');
}

const line = (page: Page) => page.locator('.cube-line');

test('the first game of Cube begins with its lessons; skipping them goes into the game', async ({ page }) => {
  await openCube(page, { lessonsSeen: false });
  await page.getByRole('button', { name: 'Играть', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Это куб' })).toBeVisible();
  await page.keyboard.press('Backspace');
  await expect(page.locator('.tutorial')).toHaveCount(0);
  await expect(page.locator('.game__readout')).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('rotathree.cube-tutorial.v1'))).toBe('true');
});

test('every lesson is done with the keys it teaches, and a miss lays it out again', async ({ page }) => {
  await openCube(page);
  await page.getByRole('button', { name: 'Обучение', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Это куб' })).toBeVisible();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Линия — из того, что видно' })).toBeVisible();
  // Moved off the gap, the stick misses: the board is laid out again.
  await page.keyboard.press('KeyA');
  await page.keyboard.press('KeyA');
  await page.keyboard.press('Space');
  await expect(page.locator('.tutorial__hint')).toHaveText('Мимо — попробуй ещё раз');
  await page.keyboard.press('Space');
  await expect(page.getByRole('heading', { name: 'Стакан спереди' })).toBeVisible();
  await page.keyboard.press('Space');
  await expect(page.locator('.tutorial__hint')).toHaveText('Сначала возьми стакан спереди');
  await page.keyboard.press('KeyZ');
  await expect(line(page)).toHaveText('Передний стакан');
  await page.keyboard.press('Space');
  await expect(page.getByRole('heading', { name: 'Опрокинь куб' })).toBeVisible();
  await page.keyboard.down('ArrowUp');
  await expect(line(page)).toContainText('лопнет 3');
  await page.keyboard.up('ArrowUp');
  await expect(page.getByRole('heading', { name: 'Загляни в объём' })).toBeVisible();
  await page.keyboard.down('KeyV');
  await expect(page.getByRole('heading', { name: 'Теперь сам' })).toBeVisible();
  await page.keyboard.up('KeyV');
  await page.keyboard.press('Enter');
  await expect(page.locator('.tutorial')).toHaveCount(0);
  await expect(page.locator('.game__readout')).toBeVisible();
});

test('the keys play the cube: move, turn, tip, the glass in front', async ({ page }) => {
  await openCube(page);
  await play(page);
  const across = () => cube(page, (game) => game.screenOf(game.activePiece!.pivot)[0]);
  const before = await across();
  await page.keyboard.press('KeyA');
  await expect.poll(across).toBe(before - 1);
  const dir = await cube(page, (game) => game.activePiece!.dir.join());
  await page.keyboard.press('KeyW');
  await expect.poll(() => cube(page, (game) => game.activePiece!.dir.join())).not.toBe(dir);
  // ← brings the glass on the left to the top, as in 2D.
  const top = await cube(page, (game) => game.active);
  await page.keyboard.press('ArrowLeft');
  await expect.poll(() => cube(page, (game) => game.active)).not.toBe(top);
  // ↑ held shows the tip; let go, it is made: the cube is seen from above.
  await expect.poll(() => cube(page, (game) => game.phase)).toBe('playing');
  await page.keyboard.down('ArrowUp');
  await expect(line(page)).toContainText('Отпустите — опрокинуть');
  await page.keyboard.up('ArrowUp');
  await expect.poll(() => cube(page, (game) => game.plane.map(Math.abs).join())).not.toBe('0,0,1');
  await expect(line(page)).toHaveCount(0);
  // Z takes the glass in front, Z again gives it back.
  await expect.poll(() => cube(page, (game) => game.phase)).toBe('playing');
  await page.keyboard.press('KeyZ');
  await expect(line(page)).toHaveText('Передний стакан');
  await page.keyboard.press('KeyZ');
  await expect(line(page)).toHaveCount(0);
});

test('a pause lets the cube be looked at; a lost game shows, records and can be looked at too', async ({ page }) => {
  await openCube(page);
  await play(page);
  await page.keyboard.press('KeyP');
  await page.getByRole('button', { name: 'Осмотреть куб', exact: true }).click();
  await expect(line(page)).toContainText('Осмотр');
  await page.keyboard.press('ArrowUp');
  await page.keyboard.press('Escape');
  await expect(line(page)).toHaveCount(0);
  await expect(page.getByRole('dialog')).toHaveCount(0);

  await page.evaluate(() => {
    const game = (window as unknown as { __rotathreeCube: { game: CubeGame } }).__rotathreeCube.game;
    const id = setInterval(() => (game.isGameOver ? clearInterval(id) : game.dropActive()), 60);
  });
  await expect(page.getByRole('heading', { name: 'Игра окончена' })).toBeVisible({ timeout: 20_000 });
  await expect(page.getByText(/стакан заполнился до конца рукава/)).toBeVisible();
  await expect
    .poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('rotathree.stats.v1')!).modes.cube.games))
    .toBe(1);
  await page.waitForTimeout(800);
  await page.getByRole('button', { name: 'Осмотреть куб', exact: true }).click();
  await expect(line(page)).toContainText('Осмотр');
  await page.getByRole('button', { name: 'К итогам', exact: true }).click();
  await page.getByRole('button', { name: 'В меню', exact: true }).click();
  await page.getByRole('button', { name: /Статистика/ }).click();
  const card = page.locator('.mode-card').filter({ has: page.getByRole('heading', { name: 'Куб', exact: true }) });
  await expect(card).toContainText('Партий1');
});

test('a game left for the menu is kept through a reload, goes on paused, and a new one gives it up', async ({ page }) => {
  await openCube(page);
  await play(page);
  for (let i = 0; i < 3; i++) {
    await page.keyboard.press('Space');
    await expect.poll(() => cube(page, (game) => game.placed)).toBe(i + 1);
    await expect.poll(() => cube(page, (game) => game.phase)).toBe('playing');
  }
  await page.keyboard.press('KeyP');
  await page.getByRole('button', { name: 'В меню', exact: true }).click();
  await page.reload();
  await page.getByRole('button', { name: /Продолжить.*Сохранённые игры/ }).click();
  await page.getByRole('button', { name: 'Продолжить Куб', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Пауза' })).toBeVisible();
  expect(await cube(page, (game) => game.placed)).toBe(3);
  const endless = () => page.evaluate(() => JSON.parse(localStorage.getItem('rotathree.cube-run.v1') ?? 'null')?.runs?.endless?.id ?? null);
  const kept = await endless();
  expect(kept).not.toBeNull();
  await page.getByRole('button', { name: 'К режиму', exact: true }).click();
  await expect(page.getByText(/Партия не закончена/)).toBeVisible();
  await page.getByRole('button', { name: 'Новая игра', exact: true }).click();
  await expect
    .poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('rotathree.stats.v1')!).recent[0]))
    .toMatchObject({ id: kept, mode: 'cube', pieces: 3, interrupted: true });
  await expect.poll(endless).not.toBe(kept);
});

test('the campaign opens its levels one by one, goes on to the next, and keeps a level left unfinished', async ({ page }) => {
  await openCube(page);
  await expect(page.locator('.cube-campaign')).toContainText('уровень 1 из 8 · Первые линии');
  await page.getByRole('button', { name: 'Уровни', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Уровень 2, цель 2000', exact: true })).toBeDisabled();
  await page.getByRole('button', { name: 'Уровень 1, цель 1500', exact: true }).click();
  await expect(page.getByRole('progressbar', { name: 'Прогресс уровня 1' })).toBeVisible();
  await expect(page.locator('.game__readout')).toContainText('Уровень 1 / 8');
  await expect.poll(() => cube(page, (game) => game.config.numberOfColors)).toBe(3);
  await page.evaluate(() => {
    (window as unknown as { __rotathreeCube: { game: CubeGame } }).__rotathreeCube.game.score = 1500;
  });
  await expect(page.getByRole('heading', { name: 'Уровень 1 пройден' })).toBeVisible();
  await expect(page.getByText('Дальше: Четыре цвета · цель 2 000')).toBeVisible();
  const stored = (key: string) => page.evaluate((k) => JSON.parse(localStorage.getItem(k)!), key);
  expect(await stored('rotathree.cube-progress.v1')).toMatchObject({ unlocked: 1, best: [1500, 0, 0, 0, 0, 0, 0, 0] });
  expect((await stored('rotathree.stats.v1')).recent[0]).toMatchObject({ mode: 'cubeCampaign', level: 2, completed: false });
  await page.waitForTimeout(800);
  await page.getByRole('button', { name: 'Следующий уровень', exact: true }).click();
  await expect(page.locator('.game__readout')).toContainText('Уровень 2 / 8');
  await expect.poll(() => cube(page, (game) => game.config.numberOfColors)).toBe(4);
  await page.keyboard.press('Space');
  await expect.poll(() => cube(page, (game) => game.placed)).toBe(1);
  await expect.poll(() => cube(page, (game) => game.phase)).toBe('playing');
  await page.keyboard.press('KeyP');
  await page.getByRole('button', { name: 'К уровням', exact: true }).click();
  await expect(page.locator('.cube-campaign')).toContainText('Уровень 2 не закончен');
  await page.getByRole('button', { name: 'Продолжить', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Пауза' })).toBeVisible();
  expect(await cube(page, (game) => [game.placed, game.config.numberOfColors])).toEqual([1, 4]);
  await expect(page.locator('.game__readout')).toContainText('Уровень 2 / 8');
});

test('a phone plays Cube with its own pads', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 740 });
  await openCube(page);
  await play(page);
  const left = page.getByRole('group', { name: 'Левая крестовина' });
  const right = page.getByRole('group', { name: 'Правая крестовина' });
  await expect(left.getByText('Глубина')).toBeVisible();
  await expect(right.getByText('Объём')).toBeVisible();
  await left.getByRole('button', { name: 'По кругу: верхний, передний, задний', exact: true }).click();
  await expect(line(page)).toHaveText('Передний стакан');
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
});

test.describe('in English', () => {
  test.use({ locale: 'en-GB' });
  test('Cube, its lessons and its game speak English', async ({ page }) => {
    const english = async () => expect((await page.locator('body').innerText()).replaceAll('Русский', '')).not.toMatch(/[А-Яа-яЁё]/);
    await page.addInitScript(() => localStorage.setItem('rotathree.tutorial.v1', 'true'));
    await page.goto('/');
    await page.getByRole('button', { name: /Six glasses in 3D/ }).click();
    await english();
    await page.getByRole('button', { name: 'Play', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'This is a cube' })).toBeVisible();
    await english();
    await page.keyboard.press('Enter');
    await english();
    await page.keyboard.press('Backspace');
    await expect(page.locator('.game__readout')).toBeVisible();
    await page.keyboard.press('KeyZ');
    await english();
    await page.keyboard.press('KeyP');
    await english();
    await page.getByRole('button', { name: 'Look around the cube', exact: true }).click();
    await english();
  });
});
