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

test('music volume and toggle survive reload without resetting existing preferences', async ({ page }) => {
  await page.goto('/');
  const openSound = async () => {
    await page.getByRole('button', { name: /Настройки/ }).click();
    await page.getByRole('tab', { name: 'Звуки', exact: true }).click();
  };
  await openSound();
  const slider = page.getByRole('slider', { name: 'Громкость музыки', exact: true });
  await expect(slider).toHaveValue('10');
  await slider.fill('35');
  await expect.poll(() => page.evaluate(() => JSON.parse(localStorage.getItem('rotathree.settings.v2')!).audio.musicVolume)).toBe(0.35);
  await page.reload();
  await openSound();
  await expect(slider).toHaveValue('35');
  await page.getByRole('tabpanel').locator('section.group').filter({ hasText: 'Фоновая музыка' }).getByRole('button', { name: 'выкл', exact: true }).click();
  await page.reload();
  await openSound();
  await expect(slider).toHaveValue('35');
  expect(await page.evaluate(() => JSON.parse(localStorage.getItem('rotathree.settings.v2')!).audio.music)).toBe(false);
  await slider.fill('0');
  await page.reload();
  await openSound();
  await expect(slider).toHaveValue('0');
});

async function captureBrowserAudio(page: Page) {
  await page.addInitScript(() => {
    const state = window as typeof window & { musicTestPlayers: HTMLAudioElement[]; musicTestGains: GainNode[] };
    state.musicTestPlayers = [];
    state.musicTestGains = [];
    const NativeAudio = window.Audio;
    window.Audio = function (src?: string) {
      const audio = new NativeAudio(src);
      state.musicTestPlayers.push(audio);
      return audio;
    } as typeof Audio;
    const NativeContext = window.AudioContext;
    window.AudioContext = class extends NativeContext {
      createGain(): GainNode {
        const gain = super.createGain();
        state.musicTestGains.push(gain);
        return gain;
      }
    };
  });
}

test('real browser audio uses the chosen gain and advances sequentially', async ({ page }) => {
  await captureBrowserAudio(page);
  await page.goto('/');
  await page.getByRole('button', { name: /Настройки/ }).click();
  await page.getByRole('tab', { name: 'Звуки', exact: true }).click();
  await expect.poll(() => page.evaluate(() => {
    const state = window as typeof window & { musicTestPlayers: HTMLAudioElement[]; musicTestGains: GainNode[] };
    return state.musicTestPlayers.some((audio) => !audio.paused && audio.currentTime > 0);
  })).toBe(true);
  await page.getByRole('slider', { name: 'Громкость музыки', exact: true }).fill('35');
  await expect.poll(() => page.evaluate(() => {
    const state = window as typeof window & { musicTestGains: GainNode[] };
    return state.musicTestGains.at(-1)?.gain.value;
  })).toBeCloseTo(0.35, 5);
  await page.evaluate(() => {
    const state = window as typeof window & { musicTestPlayers: HTMLAudioElement[] };
    const audio = state.musicTestPlayers.find((player) => !player.paused)!;
    audio.currentTime = audio.duration - 0.2;
  });
  await expect.poll(() => page.evaluate(() => {
    const state = window as typeof window & { musicTestPlayers: HTMLAudioElement[] };
    return state.musicTestPlayers.filter((audio) => !audio.paused).map((audio) => new URL(audio.src).pathname);
  })).toEqual(['/music/project-utopia-loop.mp3']);
  await page.getByRole('tabpanel').locator('section.group').filter({ hasText: 'Фоновая музыка' }).getByRole('button', { name: 'выкл', exact: true }).click();
  await expect.poll(() => page.evaluate(() => {
    const state = window as typeof window & { musicTestPlayers: HTMLAudioElement[] };
    return state.musicTestPlayers.every((audio) => audio.paused);
  })).toBe(true);
});

test('game pause ducks music until Continue or leaving for the menu', async ({ page }) => {
  await captureBrowserAudio(page);
  await startCampaign(page);
  const playing = () => page.evaluate(() => {
    const state = window as typeof window & { musicTestPlayers: HTMLAudioElement[] };
    return state.musicTestPlayers.some((audio) => !audio.paused);
  });
  const gain = () => page.evaluate(() => {
    const state = window as typeof window & { musicTestGains: GainNode[] };
    return state.musicTestGains.at(-1)?.gain.value;
  });
  await expect.poll(playing).toBe(true);
  await expect.poll(() => page.evaluate(() => {
    const state = window as typeof window & { musicTestGains: GainNode[] };
    return state.musicTestGains.at(-1)?.gain.value;
  })).toBeCloseTo(0.1, 5);
  await page.getByRole('button', { name: 'Пауза', exact: true }).click();
  await expect.poll(playing).toBe(true);
  await expect.poll(gain).toBeCloseTo(0.01, 5);
  await page.keyboard.press('Shift');
  await page.getByRole('dialog', { name: 'Пауза', exact: true }).getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('tab', { name: 'Звуки', exact: true }).click();
  await page.getByRole('slider', { name: 'Громкость музыки', exact: true }).fill('35');
  await page.getByRole('tabpanel').locator('section.group').filter({ hasText: 'Фоновая музыка' }).getByRole('button', { name: 'выкл', exact: true }).click();
  await page.getByRole('tabpanel').locator('section.group').filter({ hasText: 'Фоновая музыка' }).getByRole('button', { name: 'вкл', exact: true }).click();
  await expect.poll(playing).toBe(true);
  await expect.poll(gain).toBeCloseTo(0.035, 5);
  await page.keyboard.press('Escape');
  await page.getByRole('button', { name: 'Продолжить', exact: true }).click();
  await expect.poll(playing).toBe(true);
  await expect.poll(gain).toBeCloseTo(0.35, 5);
  await page.getByRole('button', { name: 'Пауза', exact: true }).click();
  await expect.poll(playing).toBe(true);
  await page.getByRole('button', { name: 'В меню', exact: true }).click();
  await expect.poll(playing).toBe(true);
  await expect.poll(gain).toBeCloseTo(0.35, 5);
  await page.getByRole('button', { name: /Продолжить/ }).click();
  await page.getByRole('button', { name: /Кампания/ }).click();
  await expect(page.getByRole('dialog', { name: 'Пауза', exact: true })).toBeVisible();
  await expect.poll(playing).toBe(true);
  await expect.poll(gain).toBeCloseTo(0.035, 5);
});

test('tutorial teaches by doing: lesson above the glass, hints on wrong keys, steps that move on by themselves', async ({ page }) => {
  await startCampaign(page, false);
  const phase = () => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.phase);
  await expect(page.getByRole('heading', { name: 'Собирай 3 в ряд' })).toBeVisible();
  await expect(page.locator('.tutorial__next')).toBeFocused();
  // Read top-down: the lesson, then the glass under it.
  const lesson = (await page.locator('.tutorial').boundingBox())!;
  const stage = (await page.locator('.stage').boundingBox())!;
  expect(lesson.y + lesson.height).toBeLessThanOrEqual(stage.y + 1);
  // A held Enter starts the lessons once and does not run through them.
  await page.keyboard.down('Enter');
  await page.keyboard.down('Enter');
  await page.keyboard.up('Enter');
  await expect(page.getByRole('heading', { name: 'Двигай фигуру' })).toBeVisible();
  await expect(page.locator('.tutorial__controls kbd')).toHaveText(['A', 'D']);
  await expect(page.locator('.tutorial__next')).toHaveCount(0);
  // The arrows turn the cross: pressed here, they say which keys move the piece.
  await page.keyboard.press('ArrowLeft');
  await expect(page.locator('.tutorial__hint')).toHaveText('Стрелки поворачивают крест — фигуру двигают эти клавиши');
  await page.keyboard.press('KeyD');
  await expect(page.locator('.tutorial--done')).toBeVisible();
  await expect(page.getByRole('heading', { name: 'Поверни фигуру' })).toBeVisible();
  await expect(page.locator('.tutorial__hint')).toHaveCount(0);
  await page.keyboard.press('KeyW');
  await expect(page.getByRole('heading', { name: 'Брось — собери 3' })).toBeVisible();
  await page.keyboard.press('Space');
  await expect(page.getByRole('heading', { name: 'Поверни крест' })).toBeVisible();
  // Left and right only: with two glasses there is none opposite to bring up.
  // Q and E do it too, for a hand that stays on A, W, S, D.
  await expect(page.locator('.tutorial__control')).toHaveText(['Q или ←', 'E или →']);
  await expect.poll(phase).toBe('playing');
  await page.keyboard.press('ArrowUp');
  await expect(page.locator('.tutorial__hint')).toHaveText('Нажми подсвеченную клавишу');
  await page.keyboard.press('ArrowRight');
  await expect(page.getByRole('heading', { name: 'Следи за всеми стаканами' })).toBeVisible();
  await expect(page.locator('.tutorial__next')).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(page.getByText('Уровень 1 / 16', { exact: true })).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('rotathree.tutorial.v1'))).toBe('true');
});

test('a player who tries the basics before Start goes straight to turning the cross', async ({ page }) => {
  await startCampaign(page, false);
  const phase = () => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.phase);
  await expect(page.getByRole('heading', { name: 'Собирай 3 в ряд' })).toBeVisible();
  await page.keyboard.press('KeyD');
  await page.keyboard.press('KeyW');
  await expect(page.getByRole('heading', { name: 'Собирай 3 в ряд' })).toBeVisible();
  await page.keyboard.press('KeyS');
  await expect(page.getByRole('heading', { name: 'Поверни крест' })).toBeVisible();
  await expect(page.locator('.tutorial__count')).toHaveText('5 / 6');
  await expect.poll(phase).toBe('playing');
  await page.keyboard.press('KeyE');
  await expect(page.getByRole('heading', { name: 'Следи за всеми стаканами' })).toBeVisible();
  await expect(page.locator('.tutorial__keys-hint kbd')).toHaveText(['Enter']);
  // The last screen is the game itself: the pieces fall by themselves, and
  // Space drops one, as in the game, while Play waits for Enter.
  const row = () => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.activePiece?.row ?? -1);
  await expect.poll(phase).toBe('playing');
  const from = await row();
  await expect.poll(row, { timeout: 4000 }).toBeGreaterThan(from);
  const landed = () => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.state.piecesPlaced);
  const before = await landed();
  await page.keyboard.press('Space');
  await expect.poll(landed).toBeGreaterThan(before);
  await expect(page.getByRole('heading', { name: 'Следи за всеми стаканами' })).toBeVisible();
  await page.keyboard.press('KeyA');
  await page.keyboard.press('Enter');
  await expect(page.getByText('Уровень 1 / 16', { exact: true })).toBeVisible();
});

test('a basic tried before Start skips its lesson, and Space starts', async ({ page }) => {
  await startCampaign(page, false);
  await page.keyboard.press('KeyA');
  await page.keyboard.press('Space');
  await expect(page.getByRole('heading', { name: 'Поверни фигуру' })).toBeVisible();
  await expect(page.locator('.tutorial__count')).toHaveText('3 / 6');
});

test('a waiting lesson says again what to press', async ({ page }) => {
  await startCampaign(page, false);
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Двигай фигуру' })).toBeVisible();
  await expect(page.locator('.tutorial__hint')).toHaveText('Нажми подсвеченную клавишу', { timeout: 6000 });
  await expect(page.locator('.tutorial__controls')).toHaveClass(/is-urging/);
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
  await page.getByRole('button', { name: 'Начать', exact: true }).click();
  // The lesson's own pad buttons glow; the others step back.
  await expect(left.locator('.dpad__button.is-hinted')).toHaveCount(2);
  await expect(left).toHaveClass(/dpad--hinting/);
  await expect(page.locator('.tutorial__pads')).toBeVisible();
  await left.getByRole('button', { name: 'Сдвинуть фигуру вправо', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Поверни фигуру' })).toBeVisible();
  await right.getByRole('button', { name: 'Повернуть фигуру на четверть оборота', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Брось — собери 3' })).toBeVisible();
  await left.getByRole('button', { name: 'Мгновенно поставить фигуру', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Поверни крест' })).toBeVisible();
  // The two glass buttons glow, not the opposite one.
  await expect(right.locator('.dpad__button.is-hinted')).toHaveCount(2);
  await expect(right.getByRole('button', { name: 'Развернуть поле на 180°', exact: true })).not.toHaveClass(/is-hinted/);
  await expect
    .poll(() => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.phase))
    .toBe('playing');
  await right.getByRole('button', { name: 'Поднять наверх стакан, который справа', exact: true }).click();
  await page.getByRole('button', { name: 'Играть', exact: true }).click();
  await expect(page.locator('.tutorial')).toHaveCount(0);
  await expect(page.getByLabel('Уровень 1 / 16', { exact: true })).toBeVisible();
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Левая крестовина' })).toBeVisible();
  await expect(page.locator('.bind__key')).toHaveCount(0);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= window.innerWidth)).toBe(true);
});

test('skipping a tutorial opened from the menu returns to the menu', async ({ page }) => {
  await page.goto('/');
  await page.getByRole('button', { name: /Обучение/ }).click();
  await page.getByRole('button', { name: 'Пропустить', exact: true }).click();
  await expect(page.locator('.tutorial')).toHaveCount(0);
  await expect(page.getByRole('button', { name: /Кампания/ })).toBeVisible();
  expect(await page.evaluate(() => localStorage.getItem('rotathree.tutorial.v1'))).toBe('true');
});

test('tutorial shortcuts respect settings and custom Enter bindings, Backspace skips', async ({ page }) => {
  await page.addInitScript(() => localStorage.setItem('rotathree.settings.v2', JSON.stringify({
    bindings: { moveRight: ['Enter'] },
  })));
  await startCampaign(page, false);
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Двигай фигуру' })).toBeVisible();
  await expect(page.locator('.tutorial__controls kbd')).toContainText(['A', 'Enter']);
  await page.getByRole('button', { name: 'Настройки', exact: true }).focus();
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Настройки', exact: true })).toBeVisible();
  await page.keyboard.press('Backspace');
  await expect(page.getByRole('heading', { name: 'Двигай фигуру' })).toBeVisible();
  await expect(page.locator('.tutorial')).toBeFocused();
  // Enter is the move here: it does the lesson, which then moves on.
  await page.keyboard.press('Enter');
  await expect(page.getByRole('heading', { name: 'Поверни фигуру' })).toBeVisible();
  await page.keyboard.press('Backspace');
  await expect(page.locator('.tutorial')).toHaveCount(0);
  await expect(page.getByText('Уровень 1 / 16', { exact: true })).toBeVisible();
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
  await expect(page.getByRole('tab', { name: 'Лицензии', exact: true })).toBeFocused();
  await page.keyboard.press('Home');
  await expect(page.getByRole('tab', { name: 'Управление', exact: true })).toBeFocused();
  await page.getByRole('tab', { name: 'Звуки', exact: true }).click();
  await expect(page.getByRole('heading', { name: 'Музыка', exact: true })).toBeVisible();
  await expect(page.getByRole('slider', { name: 'Громкость музыки', exact: true })).toHaveValue('10');
  await page.getByRole('tab', { name: 'Управление', exact: true }).click();
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

for (const legacyTabPause of [false, true]) {
  test(`game Tab cycles menu buttons without pausing${legacyTabPause ? ' with an older Tab pause binding' : ''}`, async ({ page }) => {
    if (legacyTabPause) await page.addInitScript(() => localStorage.setItem('rotathree.settings.v2', JSON.stringify({
      bindings: { pause: ['Tab'] },
    })));
    await startCampaign(page);
    const pause = page.getByRole('button', { name: 'Пауза', exact: true });
    const sound = page.getByRole('button', { name: 'Выключить звук', exact: true });
    const settings = page.getByRole('button', { name: 'Настройки', exact: true });
    const field = page.getByLabel('Игровое поле');
    await expect(field).toHaveAttribute('tabindex', '-1');
    await field.focus();
    expect(await field.evaluate((el) => getComputedStyle(el).outlineStyle)).toBe('none');
    await page.keyboard.press('Shift+Tab');
    await expect(settings).toBeFocused();
    for (let i = 0; i < 5; i++) {
      await page.keyboard.press('Tab');
      await expect(pause).toBeFocused();
      await page.keyboard.press('Tab');
      await expect(sound).toBeFocused();
      await page.keyboard.press('Tab');
      await expect(settings).toBeFocused();
      await page.keyboard.press('Shift+Tab');
      await expect(sound).toBeFocused();
      await page.keyboard.press('Shift+Tab');
      await expect(pause).toBeFocused();
      await page.keyboard.press('Shift+Tab');
      await expect(settings).toBeFocused();
    }
    await expect(page.getByRole('dialog')).toHaveCount(0);
    await expect(field).not.toBeFocused();
    const seconds = () => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.state.elapsedSeconds);
    const before = await seconds();
    await expect.poll(seconds).toBeGreaterThan(before);

    await page.keyboard.press('Tab');
    await page.keyboard.press('Enter');
    await expect(page.getByRole('dialog', { name: 'Пауза', exact: true })).toBeVisible();
    await page.keyboard.press('Tab');
    await expect(page.getByRole('dialog', { name: 'Пауза', exact: true })).toBeVisible();
    await page.getByRole('button', { name: 'Продолжить', exact: true }).click();
    await page.keyboard.press('Tab');
    await expect(sound).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(settings).toBeFocused();
    await page.keyboard.press('Enter');
    await expect(page.getByRole('heading', { name: 'Настройки', exact: true })).toBeVisible();
    await page.keyboard.press('Escape');
    await expect(settings).toBeFocused();
    await page.keyboard.press('Tab');
    await expect(pause).toBeFocused();
    await expect(page.getByRole('dialog')).toHaveCount(0);
  });
}

test('the pause menu is walked with the arrows and with W and S, round its ends', async ({ page }) => {
  await startCampaign(page);
  await page.keyboard.press('KeyP');
  const dialog = page.getByRole('dialog', { name: 'Пауза', exact: true });
  const item = (name: string) => dialog.getByRole('button', { name, exact: true });
  await expect(item('Продолжить')).toBeFocused();
  await page.keyboard.press('ArrowDown');
  await expect(item('Повторить уровень')).toBeFocused();
  await page.keyboard.press('KeyS');
  await expect(item('Настройки')).toBeFocused();
  await page.keyboard.press('ArrowUp');
  await page.keyboard.press('KeyW');
  await expect(item('Продолжить')).toBeFocused();
  await page.keyboard.press('ArrowUp');
  await expect(item('Завершить партию')).toBeFocused();
  await page.keyboard.press('KeyS');
  await expect(item('Продолжить')).toBeFocused();
  // The keys only move the focus: the game stays paused until a choice.
  await expect(dialog).toBeVisible();
  await page.keyboard.press('Enter');
  await expect(dialog).toHaveCount(0);
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

test('the result screen ignores a key held and a tap begun before it could answer', async ({ page }) => {
  await startCampaign(page);
  const pause = page.getByRole('button', { name: 'Пауза', exact: true });
  const over = page.getByRole('dialog').filter({ hasText: 'Игра окончена' });
  const retry = over.getByRole('button', { name: 'Повторить уровень', exact: true });
  const fillGlass = () =>
    page.evaluate(() => (window as unknown as { __rotathree: { endGame(side: number): void } }).__rotathree.endGame(0));

  // The drop key goes down, the glass fills on that press, and the key stays
  // held: its auto-repeat runs on past the moment the buttons wake up.
  await expect(pause).toBeVisible();
  await page.keyboard.down('Space');
  await fillGlass();
  await expect(retry).toBeVisible();
  await expect(retry).not.toBeFocused();
  for (let i = 0; i < 25; i++) {
    await page.waitForTimeout(33);
    await page.keyboard.down('Space');
  }
  await expect(retry).toBeFocused();
  await page.keyboard.up('Space');
  await page.waitForTimeout(100);
  await expect(over).toBeVisible();
  // A deliberate press starts the level again.
  await page.keyboard.press('Space');
  await expect(over).toHaveCount(0);

  // A finger that was already down when the screen opened.
  await expect(pause).toBeVisible();
  await fillGlass();
  const box = (await retry.boundingBox())!;
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2);
  await page.mouse.down();
  await expect(over).toHaveAttribute('data-armed', 'true');
  await page.mouse.up();
  await page.waitForTimeout(100);
  await expect(over).toBeVisible();
  await retry.click();
  await expect(over).toHaveCount(0);

  // A player still hammering the drop key well past the first moment: each
  // press is a new one, yet none of them picks the next step.
  await expect(pause).toBeVisible();
  await fillGlass();
  await expect(retry).toBeVisible();
  for (let i = 0; i < 10; i++) {
    await page.keyboard.press('Space');
    await page.waitForTimeout(150);
  }
  await expect(over).toBeVisible();
  await expect(retry).toBeFocused();
  await page.keyboard.press('Enter');
  await expect(over).toHaveCount(0);
});

test('settings freeze campaign banners and ending a run records statistics', async ({ page }) => {
  await startCampaign(page);
  await finishLevel(page);
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.waitForTimeout(2400);
  expect(await page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.sides.length)).toBe(
    1,
  );
  await page.getByRole('button', { name: 'Назад', exact: true }).click();
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
  await expect(page.getByRole('heading', { name: 'Собирай 3 в ряд' })).toBeVisible();
});

test('small phone shares the header row and uses free space above the configured pads', async ({ page }) => {
  await page.setViewportSize({ width: 320, height: 510 });
  await startCampaign(page);
  const field = page.getByLabel('Игровое поле');
  const bar = page.getByRole('progressbar');
  await expect.poll(async () => (await field.boundingBox())!.width).toBeGreaterThan(285);
  const original = (await field.boundingBox())!;
  const header = (await page.locator('.game__readout').boundingBox())!;
  const progress = (await bar.boundingBox())!;
  expect(header.height).toBe(44);
  expect(progress.height).toBeLessThanOrEqual(14);
  expect(progress.y + progress.height).toBeLessThanOrEqual(original.y);
  expect(await page.evaluate(({ x, y }) => document.elementFromPoint(x, y)?.tagName,
    { x: original.x + original.width / 2, y: original.y + original.height - 4 })).toBe('CANVAS');
  for (const pad of await page.locator('.dpad').all()) {
    expect((await pad.boundingBox())!.y).toBeGreaterThanOrEqual(original.y + original.height);
  }
  await page.getByRole('button', { name: 'Настройки', exact: true }).click();
  await page.getByRole('tab', { name: 'Управление', exact: true }).click();
  // Move the left pad upwards in the same preview used on a real phone.
  const previewPad = page.locator('.pad-surface--editor [data-pad="left"]');
  await previewPad.focus();
  for (let i = 0; i < 10; i++) await page.keyboard.press('ArrowUp');
  await page.keyboard.press('Escape');
  await expect.poll(async () => (await field.boundingBox())!.width).toBeLessThan(original.width - 10);
  const smaller = (await field.boundingBox())!;
  for (const pad of await page.locator('.game .dpad').all()) {
    expect((await pad.boundingBox())!.y).toBeGreaterThanOrEqual(smaller.y + smaller.height);
  }
  expect((await page.locator('.game__readout').boundingBox())!).toEqual(header);
  expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
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
  // Turned sideways, the field keeps the whole height and the pads stand
  // beside it, in a game and in the tutorial alike.
  const clearOfPads = async () => {
    const field = (await mobile.getByLabel('Игровое поле').boundingBox())!;
    expect(field.width).toBeGreaterThan(300);
    for (const pad of await mobile.locator('.pad-surface__pad').all()) {
      const r = (await pad.boundingBox())!;
      expect(r.x + r.width <= field.x || r.x >= field.x + field.width || r.y + r.height <= field.y).toBe(true);
    }
  };
  await clearOfPads();
  await mobile.goto('/');
  await mobile.getByRole('button', { name: /Обучение/ }).click();
  await expect(mobile.locator('.tutorial')).toBeVisible();
  await clearOfPads();
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
  await page.getByRole('button', { name: 'Back', exact: true }).click();
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
        for (const tab of ['Colors', 'Effects', 'Interface', 'Controls', 'Sound', 'Licenses']) {
          await page.getByRole('tab', { name: tab, exact: true }).click();
          await expectEnglish(page);
        }
        await page.getByRole('tab', { name: 'Colors', exact: true }).click();
        await page.getByRole('button', { name: 'Copy current palette', exact: true }).click();
        await expect(page.getByRole('button', { name: 'My palette 1', exact: true })).toBeVisible();
        await expectEnglish(page);
      }
      await page.getByRole('button', { name: 'Back', exact: true }).click();
    }
  });
  test('phone tutorial translates instructions and accessible D-pad actions', async ({ page }) => {
    await page.setViewportSize({ width: 320, height: 568 });
    await page.goto('/');
    await page.getByRole('button', { name: /Tutorial/ }).click();
    const left = page.getByRole('group', { name: 'Left D-pad' });
    const right = page.getByRole('group', { name: 'Right D-pad' });
    await expectEnglish(page);
    await page.getByRole('button', { name: 'Start', exact: true }).click();
    await expectEnglish(page);
    await left.getByRole('button', { name: 'Move the piece right', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Rotate the piece' })).toBeVisible();
    await right.getByRole('button', { name: 'Rotate the piece a quarter turn', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Drop it — match 3' })).toBeVisible();
    await left.getByRole('button', { name: 'Drop the piece instantly', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Turn the cross' })).toBeVisible();
    await expect.poll(() => page.evaluate(() => (window as unknown as { __rotathree: GameEngine }).__rotathree.phase)).toBe('playing');
    await right.getByRole('button', { name: 'Bring the right glass to the top', exact: true }).click();
    await expect(page.getByRole('heading', { name: 'Watch every glass' })).toBeVisible();
    await expectEnglish(page);
    await page.getByRole('button', { name: 'Play', exact: true }).click();
    await expect(page.getByLabel('Level 1 / 16', { exact: true })).toBeVisible();
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
  });
});
