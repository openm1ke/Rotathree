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

test('tutorial can be completed using only the keyboard with gated, repeat-safe Enter', async ({ page }) => {
  await startCampaign(page, false);
  await expect(page.getByRole('heading', { name: 'Одна фигура — три клетки' })).toBeVisible();
  await expect(page.locator('.tutorial__action kbd')).toHaveText(['Backspace', 'Enter']);
  await expect(page.locator('.tutorial__next')).toHaveClass(/is-ready/);
  await page.keyboard.down('Enter');
  await page.keyboard.down('Enter');
  await page.keyboard.up('Enter');
  await expect(page.getByRole('button', { name: 'Дальше', exact: true })).toBeDisabled();
  await expect(page.locator('.tutorial__next')).not.toHaveClass(/is-ready/);
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Сдвиньте фигуру' })).toBeVisible();
  await page.keyboard.press('KeyD');
  await expect(page.locator('.tutorial__next')).toBeEnabled();
  await page.keyboard.press('Enter');
  await page.keyboard.press('KeyW');
  await expect(page.locator('.tutorial__next')).toBeEnabled();
  await page.keyboard.press('Enter');
  await page.keyboard.press('Space');
  await expect(page.locator('.tutorial__next')).toBeEnabled();
  await page.keyboard.press('Enter');
  await expect
    .poll(() => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.phase))
    .toBe('playing');
  await page.keyboard.press('ArrowRight');
  await expect(page.locator('.tutorial__next')).toBeEnabled();
  await page.keyboard.press('Enter');
  await page.keyboard.press('Enter');
  await expect(page.getByText('Уровень 1 / 15', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('rotathree.tutorial.v1'))).toBe('true');
});

test('phone-sized browser gets touch controls and a complete tutorial', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 568 });
  await page.goto('/');
  await page.getByRole('button', { name: /Обучение/ }).click();
  const left = page.getByRole('group', { name: 'Левая крестовина' });
  const right = page.getByRole('group', { name: 'Правая крестовина' });
  await expect(page.locator('.tutorial kbd')).toHaveCount(0);
  await expect(left.locator('.dpad__button--up')).toHaveAttribute('aria-label', 'Повернуть фигуру на четверть оборота');
  await expect(left.locator('.dpad__button--down')).toHaveAttribute('aria-label', 'Мгновенно поставить фигуру');
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

test('tutorial shortcuts respect settings and custom Enter bindings, Backspace skips', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('rotathree.settings.v2', JSON.stringify({
    bindings: { moveRight: ['Enter'] },
  })));
  await startCampaign(page, false);
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Сдвиньте фигуру' })).toBeVisible();
  await page.getByRole('button', { name: 'Настройки', exact: true }).focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Настройки', exact: true })).toBeVisible();
  await page.keyboard.press('Backspace');
  await expect(page.getByRole('heading', { name: 'Сдвиньте фигуру' })).toBeVisible();
  await page.getByLabel('Игровое поле').focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('button', { name: '✓ Дальше', exact: true })).toBeEnabled();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Поверните фигуру' })).toBeVisible();
  await page.keyboard.press('Backspace');
  await expect(page.locator('.tutorial')).toHaveCount(0);
  await expect(page.getByText('Уровень 1 / 15', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('rotathree.tutorial.v1'))).toBe('true');
});

test('web forms are centered and settings tabs scroll and swipe without wrapping', async ({ page }) => {
  await page.goto('/');
  await page.evaluate(() => document.fonts.ready);
  const viewportCenter = 640;
  for (const selector of ['.home__content', '.logo']) {
    const box = await page.locator(selector).boundingBox();
    expect(Math.abs(box!.x + box!.width / 2 - viewportCenter)).toBeLessThan(2);
  }
  const menu = await page.getByRole('navigation', { name: 'Главное меню' }).boundingBox();
  expect(menu!.x).toBeGreaterThan(100);
  expect(await page.locator('.navitem').first().evaluate((el) => getComputedStyle(el).textAlign)).toBe('left');
  await page.getByRole('button', { name: /Кастом/ }).click();
  const custom = await page.locator('.form-layout').boundingBox();
  expect(custom!.width).toBeLessThanOrEqual(780);
  expect(Math.abs(custom!.x + custom!.width / 2 - 640)).toBeLessThan(12);
  const customHead = await page.locator('.screen__head').boundingBox();
  expect(Math.abs(customHead!.x - custom!.x)).toBeLessThan(12);
  expect(Math.abs(customHead!.width - custom!.width)).toBeLessThan(12);
  await expect(page.locator('.summary strong')).toHaveText('4 стакана · 3 цвета · рукав: 9 клеток');
  const start = await page.getByRole('button', { name: 'Начать', exact: true }).boundingBox();
  expect(start!.x + start!.width).toBeLessThanOrEqual(custom!.x + custom!.width + 1);
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: /Настройки/ }).click();
  const settings = await page.locator('.form-layout').boundingBox();
  expect(Math.abs(settings!.x + settings!.width / 2 - 640)).toBeLessThan(12);
  const settingsHead = await page.locator('.screen__head').boundingBox();
  expect(Math.abs(settingsHead!.x - settings!.x)).toBeLessThan(12);
  expect(Math.abs(settingsHead!.width - settings!.width)).toBeLessThan(12);
  await page.getByRole('tab', { name: 'Управление', exact: true }).focus();
  await page.keyboard.press('End');
  await expect(page.getByRole('tab', { name: 'Интерфейс', exact: true })).toBeFocused();
  await page.keyboard.press('Home');
  await expect(page.getByRole('tab', { name: 'Управление', exact: true })).toBeFocused();
  await page.setViewportSize({ width: 390, height: 844 });
  const tabs = await page.getByRole('tab').all();
  const tops = await Promise.all(tabs.map(async (tab) => (await tab.boundingBox())!.y));
  expect(new Set(tops).size).toBe(1);
  const touch = await page.context().newCDPSession(page);
  const swipe = async (from: number, to: number) => {
    const heading = await page.getByRole('tabpanel').getByRole('heading').first().boundingBox();
    const y = heading!.y + heading!.height / 2;
    await touch.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: from, y }] });
    for (let step = 1; step <= 5; step++) {
      await touch.send('Input.dispatchTouchEvent', { type: 'touchMove', touchPoints: [{ x: from + (to - from) * step / 5, y }] });
    }
    await touch.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] });
  };
  await swipe(300, 70);
  await expect(page.getByRole('tab', { name: 'Цвета', exact: true })).toHaveAttribute('aria-selected', 'true');
  await swipe(70, 300);
  await expect(page.getByRole('tab', { name: 'Управление', exact: true })).toHaveAttribute('aria-selected', 'true');
  await page.getByRole('tab', { name: 'Интерфейс', exact: true }).click();
  expect(await page.locator('.tabs').evaluate((el) => el.scrollLeft)).toBeGreaterThan(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
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
    locale: 'ru-RU',
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

async function expectEnglish(page: Page) {
  const russian = (await page.locator('body').innerText()).replaceAll('Русский', '');
  expect(russian).not.toMatch(/[А-Яа-яЁё]/);
}

test('manual language applies immediately, persists and preserves a frozen game', async ({ page }) => {
  await startCampaign(page);
  await finishLevel(page);
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('tab', { name: 'Интерфейс', exact: true }).click();
  const snapshot = await page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.snapshot());
  await page.locator('[data-language="en"]').click();
  await expect(page.getByRole('tab', { name: 'Interface', exact: true })).toBeVisible();
  await expectEnglish(page);
  expect(await page.evaluate(() => document.documentElement.lang)).toBe('en');
  expect(await page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.snapshot())).toEqual(snapshot);
  await page.getByRole('button', { name: '← Back', exact: true }).click();
  await expect(page.getByText('Level 1 complete', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Pause', exact: true }).click();
  await page.getByRole('button', { name: 'Main menu', exact: true }).click();
  await page.reload();
  await page.getByRole('button', { name: /Continue.*Saved games/ }).click();
  await page.getByRole('button', { name: 'Continue Campaign', exact: true }).click();
  await expect(page.getByRole('dialog', { name: 'Pause', exact: true })).toBeVisible();
  expect(await page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.snapshot())).toEqual(snapshot);
  await page.getByRole('dialog', { name: 'Pause', exact: true }).getByRole('button', { name: 'Settings', exact: true }).click();
  await page.getByRole('tab', { name: 'Interface', exact: true }).click();
  await page.locator('[data-language="auto"]').click();
  await expect(page.getByRole('tab', { name: 'Интерфейс', exact: true })).toBeVisible();
  expect(await page.evaluate(() => document.documentElement.lang)).toBe('ru');
});

test.describe('automatic English locale', () => {
  test.use({ locale: 'en-GB' });
  test('every menu and settings tab has English text', async ({ page }) => {
    await page.goto('/');
    for (const title of ['Campaign', 'Custom', 'Statistics', 'Settings']) {
      await page.getByRole('button', { name: new RegExp(title) }).click();
      await expect(page.getByRole('heading', { name: title, exact: true })).toBeVisible();
      await expectEnglish(page);
      if (title === 'Settings') {
        for (const tab of ['Colors', 'Effects', 'Interface', 'Controls']) {
          await page.getByRole('tab', { name: tab, exact: true }).click();
          await expectEnglish(page);
        }
        await page.getByRole('tab', { name: 'Colors', exact: true }).click();
        await page.getByRole('button', { name: 'Copy current palette', exact: true }).click();
        await expect(page.getByRole('button', { name: 'My palette 1', exact: true })).toBeVisible();
        await expectEnglish(page);
      }
      await page.getByRole('button', { name: '← Back', exact: true }).click();
    }
  });
  test('phone tutorial translates instructions and accessible D-pad actions', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 568 });
    await page.goto('/');
    await page.getByRole('button', { name: /Tutorial/ }).click();
    const left = page.getByRole('group', { name: 'Left D-pad' });
    const right = page.getByRole('group', { name: 'Right D-pad' });
    await expectEnglish(page);
    await page.getByRole('button', { name: 'Next', exact: true }).click();
    await left.getByRole('button', { name: 'Move the piece right', exact: true }).click();
    await page.getByRole('button', { name: '✓ Next', exact: true }).click();
    await right.getByRole('button', { name: 'Rotate the piece a quarter turn', exact: true }).click();
    await page.getByRole('button', { name: '✓ Next', exact: true }).click();
    await left.getByRole('button', { name: 'Drop the piece instantly', exact: true }).click();
    await page.getByRole('button', { name: '✓ Next', exact: true }).click();
    await expect.poll(() => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.phase)).toBe('playing');
    await right.getByRole('button', { name: 'Bring the right glass to the top', exact: true }).click();
    await page.getByRole('button', { name: '✓ Next', exact: true }).click();
    await expectEnglish(page);
    await page.getByRole('button', { name: 'Play', exact: true }).click();
    await expect(page.getByRole('button', { name: /Campaign/ })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });
});
