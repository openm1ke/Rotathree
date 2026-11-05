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
  await expect(page.getByRole('heading', { name: 'Поверни куб' })).toBeVisible();
  // A key the lesson does not teach is answered with what to press.
  await page.keyboard.press('Space');
  await expect(page.locator('.tutorial__hint')).toHaveText('Нажми подсвеченную клавишу');
  await page.keyboard.press('ArrowLeft');
  await expect(page.getByRole('heading', { name: 'Поверни скрытые стаканы' })).toBeVisible();
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
  await expect(line(page)).toContainText('Отпустите — повернуть куб');
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

test('quick presses turn the cross all the way round the way they were pressed, sticks and backdrop together', async ({ page }) => {
  await openCube(page);
  await play(page);
  await page.evaluate(() => {
    (window as unknown as { __rotathreeCube: { game: CubeGame } }).__rotathreeCube.game.stepsHeld = true;
  });
  // ← clockwise, → counterclockwise, as in the flat game.
  for (const [code, way] of [['ArrowLeft', -1], ['ArrowRight', 1]] as const) {
    const turned = await page.evaluate(async ({ code }) => {
      // The view's insides, as a development build lets them be read.
      type Turning = { pieceViews: Map<number, { at: { clone(): { applyQuaternion(q: unknown): { x: number; y: number } }; length(): number } }>; hubGroup: { quaternion: unknown }; crossGroup: { rotation: { z: number } } };
      const view = (window as unknown as { __rotathreeCube: { view: Turning } }).__rotathreeCube.view;
      const stick = () => {
        const far = [...view.pieceViews.values()].find((v) => v.at.length() > 5)!;
        const at = far.at.clone().applyQuaternion(view.hubGroup.quaternion);
        return (Math.atan2(at.y, at.x) * 180) / Math.PI;
      };
      const press = () => {
        document.body.dispatchEvent(new KeyboardEvent('keydown', { code, bubbles: true }));
        document.body.dispatchEvent(new KeyboardEvent('keyup', { code, bubbles: true }));
      };
      const wrap = (a: number) => ((a + 540) % 360) - 180;
      let before = stick();
      let total = 0;
      const steps = new Set<number>();
      const cross = new Set<number>();
      for (let i = 0; i < 3; i++) press();
      for (let i = 0; i < 40; i++) {
        await new Promise((r) => setTimeout(r, 40));
        const now = stick();
        const step = wrap(now - before);
        total += step;
        if (Math.abs(step) > 0.3) steps.add(Math.sign(step));
        if (Math.abs(view.crossGroup.rotation.z) > 0.01) cross.add(Math.sign(view.crossGroup.rotation.z));
        before = now;
      }
      return { total: Math.round(total), steps: [...steps], cross: [...cross] };
    }, { code });
    expect(turned).toEqual({ total: 270 * way, steps: [way], cross: [way] });
  }
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

  // The game is played out here and now rather than on a timer: it only
  // moves on with the frames drawn, and a slow runner draws few of them.
  await page.evaluate(() => {
    const game = (window as unknown as { __rotathreeCube: { game: CubeGame } }).__rotathreeCube.game;
    for (let i = 0; i < 20_000 && !game.isGameOver; i++) {
      game.dropActive();
      game.update(0.05);
    }
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

test('the campaign holds Cube\'s levels after the flat ones: open one by one, on to the next, one left unfinished kept', async ({ page }) => {
  await page.addInitScript(() => {
    localStorage.setItem('rotathree.tutorial.v1', 'true');
    localStorage.setItem('rotathree.cube-tutorial.v1', 'true');
  });
  await page.goto('/');
  await page.getByRole('button', { name: /Кампания/ }).click();
  const parts = page.locator('.campaign-part');
  await expect(parts).toHaveCount(2);
  await expect(parts.first().getByRole('heading', { name: 'Стаканы · 2D' })).toBeVisible();
  const cubePart = parts.last();
  await expect(cubePart.getByRole('heading', { name: 'Куб · 3D' })).toBeVisible();
  await expect(cubePart).toContainText('пройдено 0 из 8');
  await expect(cubePart.getByRole('button', { name: 'Уровень 2, цель 2000', exact: true })).toBeDisabled();
  await cubePart.getByRole('button', { name: 'Уровень 1, цель 1500', exact: true }).click();
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
  await expect(cubePart).toContainText('пройдено 1 из 8');
  await expect(page.locator('.cube-campaign')).toContainText('Уровень 2 не закончен');
  await page.getByRole('button', { name: 'Продолжить', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Пауза' })).toBeVisible();
  expect(await cube(page, (game) => [game.placed, game.config.numberOfColors])).toEqual([1, 4]);
  await expect(page.locator('.game__readout')).toContainText('Уровень 2 / 8');
});

test('Cube\'s screen turns off what the picture shows, and its settings over a game open on them', async ({ page }) => {
  await openCube(page);
  const hide = (label: string) =>
    page.locator('.row').filter({ hasText: label }).getByRole('button', { name: 'скрыть', exact: true }).click();
  await hide('Спрятанные фигуры сквозь блоки в объёме');
  await hide('Рёбра стаканов в объёме (3D-сетка)');
  await expect
    .poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('rotathree.settings.v2')!).cube))
    .toMatchObject({ xray: false, volumeEdges: false });
  await play(page);
  expect(await page.evaluate(() => {
    const { look } = (window as unknown as { __rotathreeCube: { view: { look: Record<string, boolean> } } }).__rotathreeCube.view;
    return [look.xray, look.volumeEdges];
  })).toEqual([false, false]);
  await page.keyboard.press('KeyP');
  await page.getByRole('dialog', { name: 'Пауза', exact: true }).getByRole('button', { name: 'Настройки', exact: true }).click();
  await expect(page.getByRole('tab', { name: 'Интерфейс' })).toHaveAttribute('aria-selected', 'true');
  await expect(page.locator('.overlay--settings section.group').first().getByRole('heading', { name: 'Куб' })).toBeVisible();
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

test('a phone lays out the pads of Cube in the settings, apart from those of the flat game', async ({ page }) => {
  await page.setViewportSize({ width: 375, height: 740 });
  await openCube(page);
  await page.goto('/');
  await page.getByRole('button', { name: /Настройки/ }).click();
  await page.getByRole('button', { name: 'Куб', exact: true }).click();
  const right = page.locator('section.group').filter({ has: page.getByRole('heading', { name: 'Правая крестовина' }) });
  await right.locator('label.row').filter({ hasText: 'Центр' }).locator('select').selectOption('frontGlass');
  await expect
    .poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('rotathree.settings.v2')!)))
    .toMatchObject({ cubePads: { right: { center: 'frontGlass' } }, pads: { right: { center: 'glassOpposite' } } });
  await page.getByRole('button', { name: 'Назад', exact: true }).click();
  await page.getByRole('button', { name: /Шесть стаканов в 3D/ }).click();
  await expect(page.locator('.cube-keys')).toContainText('Передний стакан');
  await play(page);
  await page.getByRole('group', { name: 'Правая крестовина' })
    .getByRole('button', { name: 'Вести его фигуру; ещё раз — назад к верхнему', exact: true }).click();
  await expect(line(page)).toHaveText('Передний стакан');
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
    await page.goto('/');
    await page.getByRole('button', { name: /Campaign/ }).click();
    await expect(page.getByRole('heading', { name: 'Cube · 3D' })).toBeVisible();
    await english();
  });
});
