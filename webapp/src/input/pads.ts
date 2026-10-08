import type { Action } from './bindings';
import type { ActionSink, Handling } from './keyboard';

export type PadSlot = 'up' | 'left' | 'center' | 'right' | 'down';
export type PadAction = Action | 'none';
export type PadLayout = Record<PadSlot, PadAction>;
export const PAD_SLOTS: PadSlot[] = ['up', 'left', 'right', 'down', 'center'];
export const SLOT_LABELS: Record<PadSlot, string> = {
  up: 'Вверх',
  left: 'Влево',
  right: 'Вправо',
  down: 'Вниз',
  center: 'Центр',
};
export const DEFAULT_PADS = {
  left: { up: 'hardDrop', left: 'moveLeft', right: 'moveRight', down: 'softDrop', center: 'none' } as PadLayout,
  right: {
    up: 'rotateCW',
    left: 'glassLeft',
    right: 'glassRight',
    down: 'rotateCCW',
    center: 'glassOpposite',
  } as PadLayout,
};

/** Multi-touch holds use the same timing as hardware movement keys. */
export class PadController {
  private holders = new Map<Action, number>();
  private directions: (-1 | 1)[] = [];
  private charge = 0;
  private repeats = 0;
  private wall = false;
  constructor(
    private sink: ActionSink,
    private handling: () => Handling,
  ) {}
  down(action: PadAction): void {
    if (action === 'none') return;
    if (!['moveLeft', 'moveRight', 'softDrop'].includes(action)) {
      this.sink.press(action as Exclude<Action, 'moveLeft' | 'moveRight' | 'softDrop'>);
      return;
    }
    const count = (this.holders.get(action) ?? 0) + 1;
    this.holders.set(action, count);
    if (count > 1) return;
    if (action === 'softDrop') {
      this.sink.softDrop(true);
      return;
    }
    const direction = action === 'moveLeft' ? -1 : 1;
    this.directions = this.directions.filter((d) => d !== direction);
    this.directions.push(direction);
    this.reset();
    this.sink.move(direction, false);
  }
  up(action: PadAction): void {
    if (action === 'none') return;
    const count = this.holders.get(action) ?? 0;
    if (count === 0) return;
    if (count > 1) {
      this.holders.set(action, count - 1);
      return;
    }
    this.holders.delete(action);
    if (action === 'softDrop') {
      this.sink.softDrop(false);
      return;
    }
    const direction = action === 'moveLeft' ? -1 : 1;
    const current = this.directions.at(-1) === direction;
    this.directions = this.directions.filter((d) => d !== direction);
    if (current) this.reset();
  }
  update(seconds: number): void {
    const d = this.directions.at(-1);
    if (d === undefined) return;
    const { dasMs, arrMs } = this.handling(),
      before = this.charge;
    this.charge += seconds * 1000;
    if (this.charge < dasMs - 1e-6) return;
    if (arrMs <= 0) {
      if (!this.wall) {
        this.wall = true;
        this.sink.move(d, true);
      }
      return;
    }
    if (before < dasMs - 1e-6) {
      this.sink.move(d, false);
      this.repeats = this.charge - dasMs;
    } else this.repeats += seconds * 1000;
    while (this.repeats >= arrMs - 1e-6) {
      this.repeats -= arrMs;
      this.sink.move(d, false);
    }
  }
  releaseAll(): void {
    const soft = this.holders.has('softDrop');
    this.holders.clear();
    this.directions = [];
    this.reset();
    if (soft) this.sink.softDrop(false);
  }
  private reset(): void {
    this.charge = 0;
    this.repeats = 0;
    this.wall = false;
  }
}
