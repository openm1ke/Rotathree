import { describe, expect, it } from 'vitest';
import { PadController } from '../input/pads';
import { needsTouchControls } from '../input/touch';
import { defaultSettings, sanitizeSettings } from '../services/storage';

describe('adaptive touch controls', () => {
  it('detects phone portrait windows and mobile browsers independently', () => {
    expect(needsTouchControls(390, 844, 'Desktop')).toBe(true);
    expect(needsTouchControls(1280, 800, 'Desktop')).toBe(false);
    expect(needsTouchControls(580, 400, 'Desktop')).toBe(false);
    expect(needsTouchControls(900, 500, 'Android')).toBe(true);
    expect(needsTouchControls(1024, 768, 'Desktop', 'MacIntel', 5)).toBe(true);
  });
  it('fills old settings with defaults and rejects unknown pad actions', () => {
    const settings = sanitizeSettings({ pads: { left: { up: 'bad', right: 'rotateCW' } } });
    expect(settings.pads.left.up).toBe(defaultSettings().pads.left.up);
    expect(settings.pads.left.right).toBe('rotateCW');
    expect(settings.pads.right).toEqual(defaultSettings().pads.right);
  });
  it('two fingers hold independently and a cancelled gesture stops repetition', () => {
    const moves: number[] = [],
      soft: boolean[] = [];
    const controller = new PadController(
      { move: (direction) => moves.push(direction), press: () => {}, softDrop: (held) => soft.push(held) },
      () => ({ dasMs: 150, arrMs: 35 }),
    );
    controller.down('moveLeft');
    controller.down('moveLeft');
    controller.down('softDrop');
    controller.up('moveLeft');
    controller.update(0.185);
    expect(moves).toEqual([-1, -1, -1]);
    expect(soft).toEqual([true]);
    controller.releaseAll();
    controller.update(1);
    expect(moves).toHaveLength(3);
    expect(soft).toEqual([true, false]);
  });
});
