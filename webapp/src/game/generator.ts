import type { GameConfig } from './config';
import { makePiece, type BlockColor, type Piece } from './piece';
import { createRandom } from './random';

/** Rolls the colours of new sticks. Deterministic for a given seed. */
export class PieceGenerator {
  private random: () => number;
  seed: number;
  generated = 0;

  constructor(
    private readonly config: GameConfig,
    random?: () => number,
  ) {
    this.seed = config.seed ?? Math.floor(Math.random() * 0xffffffff);
    this.random = random ?? createRandom(this.seed);
  }

  restore(seed: number, count: number): void {
    this.seed = seed;
    this.random = createRandom(seed);
    this.generated = 0;
    for (let i = 0; i < count; i++) this.next();
  }

  private pick(count: number): number {
    return Math.floor(this.random() * count);
  }

  next(): Piece {
    this.generated++;
    const palette = this.config.numberOfColors;
    const rolled: BlockColor[] = [];
    for (let i = 0; i < this.config.pieceLength; i++) rolled.push(this.pick(palette) as BlockColor);

    const isMono = rolled.every((color) => color === rolled[0]);
    if (isMono && this.random() >= this.config.monoPieceKeepChance) {
      // Single-colour sticks pop themselves on landing, so they are made
      // rarer than a fair roll would give: repaint one square.
      const other = ((rolled[0] + 1 + this.pick(palette - 1)) % palette) as BlockColor;
      rolled[this.pick(rolled.length)] = other;
    }
    return makePiece(rolled);
  }
}
