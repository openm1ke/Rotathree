/** Lowers the resolution the field is drawn at when the machine cannot keep
 * up, one step at a time, and only for as long as that actually helps.
 *
 * Full resolution is the rule. A step down is taken when a window of frames
 * averages below about 45 a second; if the frames after it are no faster, the
 * limit is somewhere else (a browser that caps the rate to save power, say),
 * so the step is taken back and nothing more is tried. */
export class AdaptiveQuality {
  /** Fractions of the device's own resolution, best first. */
  static readonly LEVELS: readonly number[] = [1, 0.85, 0.7, 0.6];
  /** Frames averaged before a decision. */
  static readonly WINDOW = 90;
  /** Frames ignored after a change, while the canvas settles. */
  static readonly SETTLE = 30;
  /** An average frame longer than this many milliseconds is too slow. */
  static readonly SLOW_MS = 22;
  /** A frame longer than this is a hitch or a switched tab, not a measure. */
  static readonly HITCH_MS = 100;

  private level = 0;
  private sum = 0;
  private count = 0;
  private settle = AdaptiveQuality.SETTLE;
  /** The average before the last step down, until it has been judged. */
  private before: number | null = null;
  private locked = false;

  /** The fraction of the device's resolution to draw at. */
  get scale(): number {
    return AdaptiveQuality.LEVELS[this.level];
  }

  /** Forgets the frames gathered so far (the canvas changed size, the game
   * was paused): they say nothing about what comes next. */
  restart(): void {
    this.sum = 0;
    this.count = 0;
    this.settle = AdaptiveQuality.SETTLE;
  }

  /** Takes the time one frame took, in milliseconds. Returns true when the
   * scale has changed and the canvas should be resized. */
  sample(frameMs: number): boolean {
    if (this.locked || frameMs > AdaptiveQuality.HITCH_MS) return false;
    if (this.settle > 0) {
      this.settle--;
      return false;
    }
    this.sum += frameMs;
    if (++this.count < AdaptiveQuality.WINDOW) return false;
    const mean = this.sum / this.count;
    this.restart();

    if (this.before !== null) {
      const before = this.before;
      this.before = null;
      if (mean > before * 0.9) {
        // Drawing fewer pixels bought nothing: give them back and stop.
        this.level--;
        this.locked = true;
        return true;
      }
    }
    if (mean > AdaptiveQuality.SLOW_MS && this.level < AdaptiveQuality.LEVELS.length - 1) {
      this.before = mean;
      this.level++;
      return true;
    }
    return false;
  }
}
