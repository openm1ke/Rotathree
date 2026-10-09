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

it('pad size and drag positions persist inside separate responsive bounds', async () => {
  const { padGeometry, padAreaHeight, movePad, sanitizePositions } = await import('../input/padPlacement');
  const positions = sanitizePositions({ left: { size: 200, x: 0.5, y: 0 }, right: { size: 180, x: 0.5, y: 0 } });
  for (const width of [304, 374, 884]) {
    const height = padAreaHeight(568, positions, width),
      g = padGeometry(width, height, positions);
    expect(
      g.left.x + g.left.size <= g.right.x ||
        g.right.x + g.right.size <= g.left.x ||
        g.left.y + g.left.size <= g.right.y ||
        g.right.y + g.right.size <= g.left.y,
    ).toBe(true);
    for (const r of Object.values(g)) {
      expect(r.x >= 0 && r.y >= 0 && r.x + r.size <= width && r.y + r.size <= height).toBe(true);
      expect((r.size - 4) / 3).toBeGreaterThanOrEqual(44);
    }
    const moved = movePad(positions, 'left', -1000, 1000, width, height);
    expect(moved.left.x).toBe(0);
    expect(moved.left.y).toBe(1);
  }
});
