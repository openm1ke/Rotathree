/**
 * The player's hands: the keys and pointers that are down, and when the last
 * press came. An interstitial that opens by itself, between campaign levels,
 * waits until they have been still for a moment, so that it never lands under
 * a finger or a key that was about to press (Playgama's game checklist,
 * item 13). A key or a pointer whose release the window never saw (it lost
 * the focus meanwhile) is forgotten with the focus.
 */
export class PlayerHands {
  private readonly keys = new Set<string>();
  private readonly pointers = new Set<number>();
  private lastPress = -Infinity;

  keyDown(code: string, now: number): void {
    this.keys.add(code);
    this.lastPress = now;
  }

  keyUp(code: string): void {
    this.keys.delete(code);
  }

  pointerDown(id: number, now: number): void {
    this.pointers.add(id);
    this.lastPress = now;
  }

  pointerUp(id: number): void {
    this.pointers.delete(id);
  }

  clear(): void {
    this.keys.clear();
    this.pointers.clear();
  }

  /** Nothing is held, and nothing has been pressed for `ms`. */
  stillFor(ms: number, now: number): boolean {
    return this.keys.size === 0 && this.pointers.size === 0 && now - this.lastPress >= ms;
  }

  /** Follows the keys and pointers of the window; answers the way to stop. */
  watch(target: Window = window): () => void {
    const now = () => performance.now();
    const listeners: [string, (event: Event) => void][] = [
      ['keydown', (event) => this.keyDown((event as KeyboardEvent).code, now())],
      ['keyup', (event) => this.keyUp((event as KeyboardEvent).code)],
      ['pointerdown', (event) => this.pointerDown((event as PointerEvent).pointerId, now())],
      ['pointerup', (event) => this.pointerUp((event as PointerEvent).pointerId)],
      ['pointercancel', (event) => this.pointerUp((event as PointerEvent).pointerId)],
      ['blur', () => this.clear()],
    ];
    // Capture: a press counts even where the game itself stops it.
    for (const [type, listener] of listeners) target.addEventListener(type, listener, true);
    return () => {
      for (const [type, listener] of listeners) target.removeEventListener(type, listener, true);
    };
  }
}
