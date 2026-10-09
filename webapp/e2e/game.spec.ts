import { expect, test, type Page } from '@playwright/test';
import type { GameEngine } from '../src/game/engine';
import type { RunSave } from '../src/services/runSave';

async function startCampaign(page: Page, onboarded = true) {
  if (onboarded) await page.addInitScript(() => localStorage.setItem('rotathree.tutorial.v1', 'true'));
  await page.goto('/');
  await page.getByRole('button', { name: /Кампания/ }).click();
  await page.getByRole('button', { name: 'Уровень 1, цель 1200', exact: true }).click();
}
async function finishLevel(page: Page) {
  await page.evaluate(() => {
    (window as unknown as { __rotathree: GameEngine }).__rotathree.state.score = 1200;
  });
  await expect(page.getByText('Уровень 1 пройден', { exact: true })).toBeVisible();
}

test('first game offers practical training before starting the chosen mode', async ({ page }) => {
  await startCampaign(page, false);
  await expect(page.getByRole('heading', { name: 'Одна фигура — три клетки' })).toBeVisible();
  await page.getByRole('button', { name: 'Дальше', exact: true }).click();
  await expect(page.getByRole('button', { name: 'Дальше', exact: true })).toBeDisabled();
  await page.keyboard.press('KeyD');
  await page.getByRole('button', { name: '✓ Дальше', exact: true }).click();
  await page.keyboard.press('KeyW');
  await page.getByRole('button', { name: '✓ Дальше', exact: true }).click();
  await page.keyboard.press('Space');
  await page.getByRole('button', { name: '✓ Дальше', exact: true }).click();
  await expect
    .poll(() => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.phase))
    .toBe('playing');
  await page.keyboard.press('ArrowRight');
  await page.getByRole('button', { name: '✓ Дальше', exact: true }).click();
  await page.getByRole('button', { name: 'Играть', exact: true }).click();
  await expect(page.getByText('Уровень 1 / 15', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('rotathree.tutorial.v1'))).toBe('true');
});

test('phone-sized browser gets touch controls and a complete tutorial', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/');
  await page.getByRole('button', { name: /Обучение/ }).click();
  const left = page.getByRole('group', { name: 'Левая крестовина' });
  const right = page.getByRole('group', { name: 'Правая крестовина' });
  await expect(left).toBeVisible();
  await expect(right).toBeVisible();
  await page.getByRole('button', { name: 'Дальше', exact: true }).click();
  await left.getByRole('button', { name: 'Сдвинуть фигуру вправо', exact: true }).click();
  await page.getByRole('button', { name: '✓ Дальше', exact: true }).click();
  await right.getByRole('button', { name: 'Повернуть фигуру на четверть оборота', exact: true }).click();
  await page.getByRole('button', { name: '✓ Дальше', exact: true }).click();
  await left.getByRole('button', { name: 'Мгновенно поставить фигуру', exact: true }).click();
  await page.getByRole('button', { name: '✓ Дальше', exact: true }).click();
  await expect
    .poll(() => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.phase))
    .toBe('playing');
  await right.getByRole('button', { name: 'Поднять наверх стакан, который справа', exact: true }).click();
  await page.getByRole('button', { name: '✓ Дальше', exact: true }).click();
  await page.getByRole('button', { name: 'Играть', exact: true }).click();
  await page.getByRole('button', { name: /Настройки/ }).click();
  await expect(page.getByRole('heading', { name: 'Левая крестовина' })).toBeVisible();
  await expect(page.locator('.bind__key')).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});

test('pause traps focus, Space activates Continue, saved transition resumes after reload', async ({ page }) => {
  await startCampaign(page);
  await finishLevel(page);
  await page.getByRole('button', { name: 'Пауза', exact: true }).click();
  const pause = page.getByRole('dialog', { name: 'Пауза', exact: true });
  await expect(pause).toBeVisible();
  await page.getByRole('button', { name: 'Завершить партию' }).focus();
  await page.keyboard.press('Tab');
  await expect(page.getByRole('button', { name: 'Продолжить', exact: true })).toBeFocused();
  await page.waitForTimeout(2400);
  expect(await page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.sides.length)).toBe(
    1,
  );
  await page.getByRole('button', { name: 'В меню', exact: true }).click();
  const save = await page.evaluate(
    () => (JSON.parse(localStorage.getItem('rotathree.run.web.v1')!) as { runs: { campaign: RunSave } }).runs.campaign,
  );
  expect(save.banner?.pendingLevel).toBe(1);
  await page.reload();
  await page.getByRole('button', { name: /Продолжить.*Сохранённые игры/ }).click();
  await page.getByRole('button', { name: 'Продолжить Кампания', exact: true }).click();
  await expect(pause).toBeVisible();
  expect(await page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.snapshot())).toEqual(
    save.engine,
  );
  await page.keyboard.press('Space');
  await expect(pause).toHaveCount(0);
  await expect
    .poll(() => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.sides.length))
    .toBe(2);
});

test('settings freeze campaign banners and ending a run records statistics', async ({ page }) => {
  await startCampaign(page);
  await finishLevel(page);
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.waitForTimeout(2400);
  expect(await page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.sides.length)).toBe(
    1,
  );
  await page.getByRole('button', { name: '← Назад', exact: true }).click();
  await page.getByRole('button', { name: 'Пауза', exact: true }).click();
  await page.getByRole('button', { name: 'Завершить партию' }).click();
  await expect
    .poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('rotathree.stats.v1')!).modes.campaign.games))
    .toBe(1);
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('rotathree.run.web.v1')!).runs)).toEqual({});
  await page.reload();
  await expect(page.getByRole('button', { name: /Продолжить.*Сохранённые игры/ })).toHaveCount(0);
});

test('unavailable storage warns the player while the app remains usable', async ({ page }) => {
  await page.addInitScript(() => {
    Storage.prototype.setItem = () => {
      throw new DOMException('Full', 'QuotaExceededError');
    };
  });
  await page.goto('/');
  await expect(page.getByText(/Не удалось сохранить данные/)).toBeVisible();
  await page.getByRole('button', { name: /Обучение/ }).click();
  await expect(page.getByRole('heading', { name: 'Одна фигура — три клетки' })).toBeVisible();
});

test('controls follow viewport changes and remain visible in a mobile landscape browser', async ({ page, browser }) => {
  await startCampaign(page);
  await expect(page.locator('.dpad')).toHaveCount(0);
  await page.setViewportSize({ width: 390, height: 844 });
  await expect(page.locator('.dpad')).toHaveCount(2);
  await page.setViewportSize({ width: 1280, height: 800 });
  await expect(page.locator('.dpad')).toHaveCount(0);
  const context = await browser.newContext({
    userAgent: 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/130.0 Mobile Safari/537.36',
    viewport: { width: 900, height: 500 },
  });
  const mobile = await context.newPage();
  await startCampaign(mobile);
  await expect(mobile.locator('.dpad')).toHaveCount(2);
  const button = await mobile.getByRole('button', { name: 'Мгновенно поставить фигуру', exact: true }).boundingBox();
  expect(button!.width).toBeGreaterThanOrEqual(44);
  expect(button!.height).toBeGreaterThanOrEqual(44);
  const canvas = await mobile.getByLabel('Игровое поле').boundingBox();
  expect(canvas!.y + canvas!.height).toBeLessThanOrEqual(501);
  await context.close();
});
