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
import { defaultSettings, loadSettings, sanitizeSettings, saveSettings, type Settings } from '../services/storage';

describe('key bindings', () => {
  it('every key does one thing, and the defaults are the ones agreed for the game', () => {
    const codes = ACTIONS.flatMap(({ id }) => defaultBindings[id]);
    expect(new Set(codes).size).toBe(codes.length);
    expect(actionForCode(defaultBindings, 'KeyW')).toBe('rotateCW');
    expect(actionForCode(defaultBindings, 'KeyA')).toBe('moveLeft');
    expect(actionForCode(defaultBindings, 'KeyD')).toBe('moveRight');
    expect(actionForCode(defaultBindings, 'KeyS')).toBe('hardDrop');
    expect(actionForCode(defaultBindings, 'Space')).toBe('hardDrop');
    expect(actionForCode(defaultBindings, 'ArrowLeft')).toBe('glassLeft');
    expect(actionForCode(defaultBindings, 'ArrowRight')).toBe('glassRight');
    expect(actionForCode(defaultBindings, 'ArrowUp')).toBe('glassOpposite');
    expect(actionForCode(defaultBindings, 'ArrowDown')).toBe('glassOpposite');
    expect(actionForCode(defaultBindings, 'KeyN')).toBe('restart');
    expect(defaultBindings.rotateCCW).toEqual([]);
    expect(defaultBindings.softDrop).toEqual([]);
  });

  it('rebinding replaces the key in that slot', () => {
    const next = bindKey(defaultBindings, 'hardDrop', 0, 'Enter');
    expect(next.hardDrop).toEqual(['Enter', 'Space']);
    expect(actionForCode(next, 'KeyS')).toBeNull();
    expect(defaultBindings.hardDrop).toEqual(['KeyS', 'Space']); // the original is untouched
  });

  it('a key taken from another action is removed there', () => {
    // W used to turn clockwise; now A turns it, and A no longer moves left.
    const next = bindKey(defaultBindings, 'rotateCW', 0, 'KeyA');
    expect(next.rotateCW).toEqual(['KeyA']);
    expect(next.moveLeft).toEqual([]);
    expect(actionForCode(next, 'KeyA')).toBe('rotateCW');
  });

  it('a slot can be emptied, and a second slot can be filled', () => {
    expect(unbindKey(defaultBindings, 'hardDrop', 0).hardDrop).toEqual(['Space']);
    expect(bindKey(defaultBindings, 'rotateCCW', 0, 'KeyQ').rotateCCW).toEqual(['KeyQ']);
  });

  it('stored bindings are cleaned up on load', () => {
    const cleaned = sanitizeBindings({
      rotateCW: ['Enter'], // listed first in the actions: it keeps Enter
      hardDrop: ['Enter', 42, '', 'KeyJ', 'KeyK'],
      bogus: ['KeyQ'],
    });
    expect(cleaned.rotateCW).toEqual(['Enter']);
    expect(cleaned.hardDrop).toEqual(['KeyJ']); // two slots are read; the duplicate Enter goes
    expect(cleaned.moveLeft).toEqual(['KeyA']);
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
    controller.keyDown('ArrowRight');
    controller.keyDown('KeyW');
    expect(log).toEqual(['hardDrop', 'hardDrop', 'glassRight', 'rotateCW']);
  });

  it('keys that are not bound are left to the browser', () => {
    const { controller, log } = setup();
    expect(controller.keyDown('KeyQ')).toBe(false);
    expect(controller.keyDown('F5')).toBe(false);
    expect(log).toEqual([]);
  });

  it('a held direction moves at once, waits, then repeats', () => {
    const { controller, log } = setup({ dasMs: 150, arrMs: 50 });
    controller.keyDown('KeyA');
    expect(log).toEqual(['move -1']);
    controller.update(0.1);
    expect(log).toHaveLength(1); // still inside the delay
    controller.update(0.05);
    expect(log).toHaveLength(2); // the delay has just run out
    controller.update(0.1);
    expect(log).toHaveLength(4); // two more repeats, 50 ms apart
    controller.keyUp('KeyA');
    controller.update(0.5);
    expect(log).toHaveLength(4);
  });

  it('the most recently pressed direction wins; releasing it returns to the other', () => {
    const { controller, log } = setup({ dasMs: 100, arrMs: 50 });
    controller.keyDown('KeyA');
    controller.keyDown('KeyD');
    controller.update(0.1);
    expect(log).toEqual(['move -1', 'move 1', 'move 1']);
    controller.keyUp('KeyD');
    controller.update(0.1);
    expect(log.at(-1)).toBe('move -1');
  });

  it('with zero repeat interval the piece slides straight to the wall', () => {
    const { controller, log } = setup({ dasMs: 100, arrMs: 0 });
    controller.keyDown('KeyD');
    controller.update(0.2);
    controller.update(0.2);
    expect(log).toEqual(['move 1', 'move 1 wall']);
  });

  it('soft drop is held, not pressed', () => {
    const bindings = bindKey(defaultBindings, 'softDrop', 0, 'ArrowDown');
    const { controller, log } = setup(undefined, bindings);
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
    controller.keyDown('KeyS');
    controller.keyDown('Enter');
    expect(log).toEqual(['hardDrop']);
  });

  it('does nothing while disabled and forgets held keys when told to', () => {
    const bindings = bindKey(defaultBindings, 'softDrop', 0, 'ArrowDown');
    const { controller, log } = setup(undefined, bindings);
    controller.keyDown('ArrowDown');
    controller.keyDown('KeyA');
    controller.releaseAll();
    controller.update(1);
    expect(log).toEqual(['soft true', 'move -1', 'soft false']);
    controller.enabled = false;
    expect(controller.keyDown('Space')).toBe(false);
  });
});

describe('settings storage', () => {
  const memory = () => {
    const values = new Map<string, string>();
    return {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => void values.set(key, value),
    };
  };

  it('survive a round trip through storage', () => {
    const storage = memory();
    const settings: Settings = defaultSettings();
    settings.bindings = bindKey(settings.bindings, 'glassLeft', 0, 'KeyQ');
    settings.handling.dasMs = 90;
    settings.effects = { explosion: 'unified', screenShake: false, turnMs: 420 };
    settings.hud = { keyHints: false, score: true, stats: false, opacity: 0.35 };
    settings.palettes = {
      active: 'mine',
      sets: [
        ...defaultSettings().palettes.sets,
        {
          id: 'mine',
          name: 'Мой',
          colours: ['#000000', '#111111', '#222222', '#333333', '#444444', '#555555', '#666666', '#777777', '#888888'],
          builtin: false,
        },
      ],
    };
    expect(saveSettings(settings, storage)).toBe(true);
    expect(loadSettings(storage)).toEqual(settings);
  });

  it('report it when the browser will not store them', () => {
    const full = {
      setItem: () => {
        throw new Error('quota');
      },
    };
    expect(saveSettings(defaultSettings(), full)).toBe(false);
    expect(saveSettings(defaultSettings(), null)).toBe(false);
  });

  it('fall back to defaults for anything missing or out of range', () => {
    const cleaned = sanitizeSettings({
      handling: { dasMs: -5, arrMs: 'fast' },
      effects: { explosion: 'sideways', turnMs: 5000 },
      hud: { keyHints: 'no', opacity: 0 },
    });
    expect(cleaned.handling).toEqual({ dasMs: 0, arrMs: 35 });
    expect(cleaned.effects).toEqual({ explosion: 'varied', screenShake: true, turnMs: 800 });
    expect(cleaned.hud).toEqual({ keyHints: true, score: true, stats: true, opacity: 0.1 });
    expect(cleaned.bindings).toEqual(defaultBindings);
    expect(loadSettings({ getItem: () => '{broken' })).toEqual(defaultSettings());
  });

  it('a palette that is not there any more falls back to the classic one', () => {
    const cleaned = sanitizeSettings({ palettes: { active: 'gone', sets: [{ id: 'x', name: 'X', colours: ['bad'] }] } });
    expect(cleaned.palettes.active).toBe('classic');
    const set = cleaned.palettes.sets.find((s) => s.id === 'x');
    expect(set?.colours).toHaveLength(9);
    expect(set?.colours.every((c) => /^#[0-9a-f]{6}$/i.test(c))).toBe(true);
  });
});
