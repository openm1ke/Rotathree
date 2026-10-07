import { describe, expect, it } from 'vitest';
import {
  ACTIONS,
  actionForCode,
  bindKey,
  defaultBindings,
  keyLabel,
  sanitizeBindings,
  unbindKey,
} from '../input/bindings';
import { KeyboardController, type Handling } from '../input/keyboard';
import { defaultSettings, loadSettings, sanitizeSettings, saveSettings } from '../services/settingsStore';

describe('key bindings', () => {
  it('every action has a default key and no key does two things', () => {
    const codes = ACTIONS.flatMap(({ id }) => defaultBindings[id]);
    expect(ACTIONS.every(({ id }) => defaultBindings[id].length > 0)).toBe(true);
    expect(new Set(codes).size).toBe(codes.length);
    expect(actionForCode(defaultBindings, 'Space')).toBe('hardDrop');
    expect(actionForCode(defaultBindings, 'KeyA')).toBe('glassLeft');
    expect(actionForCode(defaultBindings, 'KeyQ')).toBeNull();
  });

  it('rebinding replaces the key in that slot', () => {
    const next = bindKey(defaultBindings, 'hardDrop', 0, 'Enter');
    expect(next.hardDrop).toEqual(['Enter']);
    expect(actionForCode(next, 'Space')).toBeNull();
    expect(defaultBindings.hardDrop).toEqual(['Space']); // the original is untouched
  });

  it('a second slot adds an alternative key', () => {
    const next = bindKey(defaultBindings, 'hardDrop', 1, 'Enter');
    expect(next.hardDrop).toEqual(['Space', 'Enter']);
  });

  it('a key taken from another action is removed there', () => {
    // Rotation on the key that used to switch to the left glass.
    const next = bindKey(defaultBindings, 'rotateCW', 0, 'KeyA');
    expect(next.rotateCW).toEqual(['KeyA', 'KeyX']);
    expect(next.glassLeft).toEqual([]);
    expect(actionForCode(next, 'KeyA')).toBe('rotateCW');
  });

  it('a slot can be emptied', () => {
    expect(unbindKey(defaultBindings, 'rotateCW', 0).rotateCW).toEqual(['KeyX']);
  });

  it('stored bindings are cleaned up on load', () => {
    const cleaned = sanitizeBindings({
      hardDrop: ['Enter', 42, '', 'KeyJ', 'KeyK'],
      rotateCW: ['Enter'], // the same key twice: the action listed first keeps it
      bogus: ['KeyQ'],
    });
    expect(cleaned.rotateCW).toEqual(['Enter']);
    expect(cleaned.hardDrop).toEqual(['KeyJ']);
    expect(cleaned.moveLeft).toEqual(['ArrowLeft']);
    expect(sanitizeBindings(null)).toEqual(defaultBindings);
  });

  it('names keys the way they are printed on them', () => {
    expect(keyLabel('KeyA')).toBe('A');
    expect(keyLabel('Digit7')).toBe('7');
    expect(keyLabel('ArrowLeft')).toBe('←');
    expect(keyLabel('Space')).toBe('Пробел');
    expect(keyLabel('F5')).toBe('F5');
  });
});

describe('keyboard controller', () => {
  const setup = (handling: Handling = { dasMs: 150, arrMs: 50 }, bindings = defaultBindings) => {
    const log: string[] = [];
    const controller = new KeyboardController(
      () => bindings,
      () => handling,
      {
        move: (direction, toWall) => log.push(`move ${direction}${toWall ? ' wall' : ''}`),
        press: (action) => log.push(action),
        softDrop: (held) => log.push(`soft ${held}`),
      },
    );
    return { controller, log };
  };

  it('one-shot actions fire once per press, whatever the OS repeats', () => {
    const { controller, log } = setup();
    expect(controller.keyDown('Space')).toBe(true);
    controller.keyDown('Space', true);
    controller.keyDown('Space');
    controller.keyUp('Space');
    controller.keyDown('Space');
    controller.keyDown('KeyD');
    controller.keyDown('KeyZ');
    expect(log).toEqual(['hardDrop', 'hardDrop', 'glassRight', 'rotateCCW']);
  });

  it('keys that are not bound are left to the browser', () => {
    const { controller, log } = setup();
    expect(controller.keyDown('KeyQ')).toBe(false);
    expect(controller.keyDown('F5')).toBe(false);
    expect(log).toEqual([]);
  });

  it('a held direction moves at once, waits, then repeats', () => {
    const { controller, log } = setup({ dasMs: 150, arrMs: 50 });
    controller.keyDown('ArrowLeft');
    expect(log).toEqual(['move -1']);
    controller.update(0.1);
    expect(log).toHaveLength(1); // still inside the delay
    controller.update(0.05);
    expect(log).toHaveLength(2); // the delay has just run out
    controller.update(0.1);
    expect(log).toHaveLength(4); // two more repeats, 50 ms apart
    controller.keyUp('ArrowLeft');
    controller.update(0.5);
    expect(log).toHaveLength(4);
  });

  it('the most recently pressed direction wins; releasing it returns to the other', () => {
    const { controller, log } = setup({ dasMs: 100, arrMs: 50 });
    controller.keyDown('ArrowLeft');
    controller.keyDown('ArrowRight');
    controller.update(0.1);
    expect(log).toEqual(['move -1', 'move 1', 'move 1']);
    controller.keyUp('ArrowRight');
    controller.update(0.1);
    expect(log.at(-1)).toBe('move -1');
  });

  it('with zero repeat interval the piece slides straight to the wall', () => {
    const { controller, log } = setup({ dasMs: 100, arrMs: 0 });
    controller.keyDown('ArrowRight');
    controller.update(0.2);
    controller.update(0.2);
    expect(log).toEqual(['move 1', 'move 1 wall']);
  });

  it('soft drop is held, not pressed', () => {
    const { controller, log } = setup();
    controller.keyDown('ArrowDown');
    controller.keyDown('ArrowDown', true);
    controller.keyUp('ArrowDown');
    expect(log).toEqual(['soft true', 'soft false']);
  });

  it('follows rebinding immediately', () => {
    let bindings = defaultBindings;
    const log: string[] = [];
    const controller = new KeyboardController(
      () => bindings,
      () => ({ dasMs: 150, arrMs: 50 }),
      { move: () => {}, press: (action) => log.push(action), softDrop: () => {} },
    );
    bindings = bindKey(bindings, 'hardDrop', 0, 'Enter');
    controller.keyDown('Space');
    controller.keyDown('Enter');
    expect(log).toEqual(['hardDrop']);
  });

  it('does nothing while disabled and forgets held keys when told to', () => {
    const { controller, log } = setup();
    controller.keyDown('ArrowDown');
    controller.keyDown('ArrowLeft');
    controller.releaseAll();
    controller.update(1);
    expect(log).toEqual(['soft true', 'move -1', 'soft false']);
    controller.enabled = false;
    expect(controller.keyDown('Space')).toBe(false);
  });
});

describe('settings', () => {
  it('survive a round trip through storage', () => {
    const memory = new Map<string, string>();
    const storage = {
      getItem: (key: string) => memory.get(key) ?? null,
      setItem: (key: string, value: string) => void memory.set(key, value),
    };
    const settings = defaultSettings();
    settings.bindings = bindKey(settings.bindings, 'glassLeft', 0, 'KeyQ');
    settings.handling.dasMs = 90;
    settings.game.armLength = 8;
    saveSettings(settings, storage);
    expect(loadSettings(storage)).toEqual(settings);
  });

  it('fall back to defaults for anything missing or out of range', () => {
    const cleaned = sanitizeSettings({
      handling: { dasMs: -5, arrMs: 'fast' },
      game: { armLength: 99, numberOfColors: 7, gravityScope: 'sideways' },
    });
    expect(cleaned.handling).toEqual({ dasMs: 0, arrMs: 35 });
    expect(cleaned.game.armLength).toBe(12);
    expect(cleaned.game.numberOfColors).toBe(4);
    expect(cleaned.game.gravityScope).toBe('wholeGlass');
    expect(cleaned.bindings).toEqual(defaultBindings);
    expect(loadSettings({ getItem: () => '{broken' })).toEqual(defaultSettings());
  });
});
