import { actionForCode, type Action, type Bindings } from './bindings';

/** How held movement keys repeat, in the terms players of falling-block
 * games know: the delay before auto-shift starts and the interval between
 * repeats once it has. */
export interface Handling {
  /** Delayed auto shift: milliseconds a direction is held before it repeats. */
  dasMs: number;
  /** Auto repeat rate: milliseconds between repeats; 0 slides to the wall. */
  arrMs: number;
}

export const defaultHandling: Handling = { dasMs: 150, arrMs: 35 };

/** What the keyboard asks of the game. */
export interface ActionSink {
  /** One shift of the active piece; `toWall` slides it as far as it goes. */
  move(direction: -1 | 1, toWall: boolean): void;
  /** A one-shot action: rotate, drop, switch glass, pause, restart. */
  press(action: Exclude<Action, 'moveLeft' | 'moveRight' | 'softDrop'>): void;
  softDrop(held: boolean): void;
}

/** Turns key events into game actions. Movement auto-repeats with DAS/ARR
 * timing driven by `update`, not by the operating system's key repeat, so it
 * feels the same on every machine and is easy to test. */
export class KeyboardController {
  /** Set to false while something else (a key-capture dialog, an overlay)
   * owns the keyboard. */
  enabled = true;

  private readonly down = new Set<string>();
  /** Held directions, the most recent last: the latest one pressed wins. */
  private readonly directions: (-1 | 1)[] = [];
  private shiftCharge = 0;
  private repeatCharge = 0;

  constructor(
    private readonly bindings: () => Bindings,
    private readonly handling: () => Handling,
    private readonly sink: ActionSink,
  ) {}

  /** Returns true when the key belongs to the game (and its default browser
   * behaviour — scrolling on arrows and space — should be suppressed). */
  keyDown(code: string, isRepeat = false): boolean {
    if (!this.enabled) return false;
    const action = actionForCode(this.bindings(), code);
    if (action === null) return false;
    if (isRepeat || this.down.has(code)) return true;
    this.down.add(code);

    switch (action) {
      case 'moveLeft':
      case 'moveRight': {
        const direction = action === 'moveLeft' ? -1 : 1;
        this.dropDirection(direction);
        this.directions.push(direction);
        this.shiftCharge = 0;
        this.repeatCharge = 0;
        this.sink.move(direction, false);
        break;
      }
      case 'softDrop':
        this.sink.softDrop(true);
        break;
      default:
        this.sink.press(action);
    }
    return true;
  }

  keyUp(code: string): boolean {
    if (!this.down.delete(code)) return false;
    const action = actionForCode(this.bindings(), code);
    if (action === 'moveLeft' || action === 'moveRight') {
      const direction = action === 'moveLeft' ? -1 : 1;
      // Another key for the same direction may still be held.
      if (!this.isHeld(action)) {
        const wasCurrent = this.directions.at(-1) === direction;
        this.dropDirection(direction);
        if (wasCurrent) {
          this.shiftCharge = 0;
          this.repeatCharge = 0;
        }
      }
    } else if (action === 'softDrop' && !this.isHeld('softDrop')) {
      this.sink.softDrop(false);
    }
    return action !== null;
  }

  /** Advances the auto-repeat timers by `seconds` of real time. */
  update(seconds: number): void {
    const direction = this.directions.at(-1);
    if (direction === undefined || !this.enabled) return;
    const { dasMs, arrMs } = this.handling();
    const before = this.shiftCharge;
    this.shiftCharge += seconds * 1000;
    if (this.shiftCharge < dasMs) return;

    if (arrMs <= 0) {
      // Instant auto-repeat: once, straight to the wall.
      if (before < dasMs) this.sink.move(direction, true);
      return;
    }
    // Time spent past the delay, including what is left over from before.
    this.repeatCharge += before < dasMs ? this.shiftCharge - dasMs : seconds * 1000;
    if (before < dasMs) {
      this.sink.move(direction, false);
    }
    while (this.repeatCharge >= arrMs) {
      this.repeatCharge -= arrMs;
      this.sink.move(direction, false);
    }
  }

  /** Forgets every held key (window lost focus, an overlay opened). */
  releaseAll(): void {
    const wasSoftDropping = this.isHeld('softDrop');
    this.down.clear();
    this.directions.length = 0;
    this.shiftCharge = 0;
    this.repeatCharge = 0;
    if (wasSoftDropping) this.sink.softDrop(false);
  }

  private isHeld(action: Action): boolean {
    return this.bindings()[action].some((code) => this.down.has(code));
  }

  private dropDirection(direction: -1 | 1): void {
    const index = this.directions.indexOf(direction);
    if (index >= 0) this.directions.splice(index, 1);
  }
}
