import type { GameEngine, GameEvent } from '../game/engine';
import { slotOfSide } from '../game/glass';
import type { IncomingPiece } from '../game/incoming';
import type { Orientation } from '../game/piece';
import type { Placement } from '../game/placement';
import { SIDES, type Side } from '../game/side';
import { tonesOf } from './theme';

/** One shard or spark. Positions are in cells, relative to the centre of
 * the cross, in the world frame (they turn with the cross). */
export interface Particle {
  x: number;
  y: number;
  vx: number;
  vy: number;
  size: number;
  life: number;
  age: number;
  color: string;
}

/** An expanding ring where blocks popped. */
export interface Ring {
  x: number;
  y: number;
  age: number;
  life: number;
  color: string;
  reach: number;
}

/** The streak a hard drop leaves down its lane (glass coordinates). */
export interface Beam {
  side: Side;
  column: number;
  width: number;
  fromRow: number;
  toRow: number;
  age: number;
  life: number;
}

/** A piece that has just locked: its cells flash and squash. */
export interface Landing {
  placement: Placement;
  age: number;
  life: number;
  dropped: boolean;
}

interface StepTrack {
  piece: IncomingPiece;
  row: number;
  orientation: Orientation;
  steppedAt: number;
}

const QUARTER = Math.PI / 2;

/** Purely visual state layered on top of the engine: the turn of the cross,
 * kicks and shakes, particles, flashes. Nothing here feeds back into the
 * rules. */
export class Effects {
  /** Seconds of animation time. */
  clock = 0;
  /** Board kicks and shakes can be switched off in the settings. */
  screenShake = true;

  /** How strongly each glass is lit as the active one, 0..1. */
  readonly activeness: number[] = [1, 0, 0, 0];
  readonly particles: Particle[] = [];
  readonly rings: Ring[] = [];
  readonly beams: Beam[] = [];
  readonly landings: Landing[] = [];

  /** Offset of the whole field, in cells: a spring that is kicked by drops
   * and bumps and pulls itself back. */
  kickX = 0;
  kickY = 0;
  private kickVx = 0;
  private kickVy = 0;
  /** Random jitter amplitude, in cells; decays quickly. */
  private shake = 0;
  shakeX = 0;
  shakeY = 0;
  /** Extra zoom on a combo; decays to 0. */
  punch = 0;

  // The view angle is counted in quarter turns; negative is anticlockwise.
  private fromTurns = 0;
  private toTurns = 0;
  private turnStartedAt = -Infinity;
  private turnDuration = 0;

  private readonly steps = new Map<Side, StepTrack>();
  private burstMatch: object | null = null;

  /** Slide of a piece into its next cell, in seconds. */
  static readonly stepSlideSeconds = 0.07;
  static readonly turnSeconds = 0.2;

  reset(active: Side): void {
    this.clock = 0;
    this.particles.length = 0;
    this.rings.length = 0;
    this.beams.length = 0;
    this.landings.length = 0;
    this.steps.clear();
    this.burstMatch = null;
    this.kickX = this.kickY = this.kickVx = this.kickVy = 0;
    this.shake = this.shakeX = this.shakeY = this.punch = 0;
    this.fromTurns = this.toTurns = -active;
    this.turnStartedAt = -Infinity;
    SIDES.forEach((side) => (this.activeness[side] = side === active ? 1 : 0));
  }

  private get turnProgress(): number {
    if (this.turnDuration <= 0) return 1;
    return Math.min(1, Math.max(0, (this.clock - this.turnStartedAt) / this.turnDuration));
  }

  /** Current rotation of the cross in radians (positive is clockwise). */
  get viewAngle(): number {
    const t = this.turnProgress;
    // Ease out with a small overshoot: the cross snaps round and settles.
    const c = 1.4;
    const eased = 1 + (c + 1) * Math.pow(t - 1, 3) + c * Math.pow(t - 1, 2);
    return (this.fromTurns + (this.toTurns - this.fromTurns) * eased) * QUARTER;
  }

  /** The angle the cross is turning towards, in quarter turns. */
  get targetTurns(): number {
    return this.toTurns;
  }

  /** The cross shrinks a little mid-turn so its corners stay on screen. */
  get viewScale(): number {
    return 1 - 0.07 * Math.sin(Math.PI * this.turnProgress) + this.punch;
  }

  /** How much of a cell the piece still has to slide to reach its row. */
  slideLeft(piece: IncomingPiece): number {
    const track = this.steps.get(piece.side);
    if (!track || track.piece !== piece) return 0;
    const t = Math.min(1, (this.clock - track.steppedAt) / Effects.stepSlideSeconds);
    return (1 - t) * (1 - t);
  }

  /** Reacts to what the engine did since the last frame. */
  consume(events: GameEvent[], engine: GameEngine): void {
    const active = engine.activeSide;
    for (const event of events) {
      switch (event.type) {
        case 'sideSwitched':
          this.fromTurns = this.viewAngle / QUARTER;
          this.toTurns -= event.quarterTurns;
          this.turnStartedAt = this.clock;
          this.turnDuration = Effects.turnSeconds * (1 + 0.45 * (Math.abs(event.quarterTurns) - 1));
          break;
        case 'pieceMoved':
          if (event.blocked) this.kick(event.direction * 0.14, 0);
          break;
        case 'pieceRotated':
          if (event.blocked) this.addShake(0.05);
          break;
        case 'pieceDropped': {
          const drop = engine.state.drop;
          if (drop) {
            this.beams.push({
              side: event.side,
              column: drop.placement.column,
              width: drop.placement.piece.orientation % 2 === 0 ? drop.placement.piece.colors.length : 1,
              fromRow: drop.startRow,
              toRow: drop.placement.row,
              age: 0,
              life: 0.32,
            });
          }
          break;
        }
        case 'pieceLanded': {
          this.landings.push({ placement: event.placement, age: 0, life: 0.24, dropped: event.dropped });
          // The field recoils the way the piece was travelling on screen.
          const [dx, dy] = travelOnScreen(slotOfSide(active, event.placement.side));
          const force = event.dropped ? 0.3 : 0.08;
          this.kick(dx * force, dy * force);
          if (event.dropped) this.sparks(event.placement, engine);
          break;
        }
        case 'matchScored':
          this.addShake(0.05 + 0.04 * event.combo);
          this.punch = Math.min(0.06, 0.012 * event.combo);
          break;
        case 'cellsPopped':
        case 'pieceStepped':
        case 'blocksFell':
        case 'gameEnded':
          break;
      }
    }
  }

  /** Advances every animation by `seconds`. */
  update(seconds: number, engine: GameEngine): void {
    this.clock += seconds;
    const state = engine.state;

    // The moment matched blocks start to pop, they burst.
    const match = state.activeMatch;
    if (state.phase === 'clearing' && match && match !== this.burstMatch) {
      this.burstMatch = match;
      this.burst([...match.cells], engine);
    }

    this.trackSteps(engine);

    // Spring back to rest.
    const stiffness = 520;
    const damping = 30;
    this.kickVx += (-stiffness * this.kickX - damping * this.kickVx) * seconds;
    this.kickVy += (-stiffness * this.kickY - damping * this.kickVy) * seconds;
    this.kickX += this.kickVx * seconds;
    this.kickY += this.kickVy * seconds;
    this.shake *= Math.exp(-14 * seconds);
    this.shakeX = (Math.random() * 2 - 1) * this.shake;
    this.shakeY = (Math.random() * 2 - 1) * this.shake;
    this.punch *= Math.exp(-9 * seconds);

    const drag = Math.max(0, 1 - 3.4 * seconds);
    for (const particle of this.particles) {
      particle.age += seconds;
      particle.x += particle.vx * seconds;
      particle.y += particle.vy * seconds;
      particle.vx *= drag;
      particle.vy *= drag;
    }
    prune(this.particles, (particle) => particle.age < particle.life);
    for (const ring of this.rings) ring.age += seconds;
    prune(this.rings, (ring) => ring.age < ring.life);
    for (const beam of this.beams) beam.age += seconds;
    prune(this.beams, (beam) => beam.age < beam.life);
    for (const landing of this.landings) landing.age += seconds;
    prune(this.landings, (landing) => landing.age < landing.life);

    const rate = Math.min(1, seconds * 18);
    for (const side of SIDES) {
      const target = side === engine.activeSide ? 1 : 0;
      this.activeness[side] += (target - this.activeness[side]) * rate;
    }
  }

  private kick(x: number, y: number): void {
    if (!this.screenShake) return;
    this.kickVx += x * 46;
    this.kickVy += y * 46;
  }

  private addShake(amount: number): void {
    if (this.screenShake) this.shake = Math.max(this.shake, amount);
  }

  private trackSteps(engine: GameEngine): void {
    for (const side of SIDES) {
      const piece = engine.state.incoming.get(side);
      const track = this.steps.get(side);
      if (!piece) {
        this.steps.delete(side);
      } else if (!track || track.piece !== piece) {
        // A new piece slides in from beyond the far end.
        this.steps.set(side, {
          piece,
          row: piece.row,
          orientation: piece.piece.orientation,
          steppedAt: this.clock,
        });
      } else {
        // A rotation also shifts the row; only a plain step down slides.
        if (piece.row > track.row && piece.piece.orientation === track.orientation) {
          track.steppedAt = this.clock;
        }
        track.row = piece.row;
        track.orientation = piece.piece.orientation;
      }
    }
  }

  /** Shards and a ring for every popped block. */
  private burst(indices: number[], engine: GameEngine): void {
    const board = engine.board;
    const half = board.size / 2;
    for (const index of indices) {
      const color = board.atIndex(index);
      if (color < 0) continue;
      const tones = tonesOf(color as 0 | 1 | 2 | 3);
      const x = -half + (index % board.size) + 0.5;
      const y = -half + Math.floor(index / board.size) + 0.5;
      this.rings.push({ x, y, age: 0, life: 0.34, color: tones.rgb, reach: 1.25 });
      for (let i = 0; i < 9; i++) {
        const angle = Math.random() * Math.PI * 2;
        const speed = 2.5 + Math.random() * 6.5;
        this.particles.push({
          x: x + (Math.random() - 0.5) * 0.5,
          y: y + (Math.random() - 0.5) * 0.5,
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed,
          size: 0.1 + Math.random() * 0.16,
          life: 0.3 + Math.random() * 0.3,
          age: 0,
          color: i % 3 === 0 ? '#ffffff' : i % 3 === 1 ? tones.light : tones.base,
        });
      }
    }
  }

  /** A few sparks where a hard-dropped piece hits. */
  private sparks(placement: Placement, engine: GameEngine): void {
    const half = engine.board.size / 2;
    for (const cell of placement.cells) {
      for (let i = 0; i < 4; i++) {
        const angle = Math.random() * Math.PI * 2;
        const speed = 1.5 + Math.random() * 3.5;
        this.particles.push({
          x: -half + cell.col + 0.5,
          y: -half + cell.row + 0.5,
          vx: Math.cos(angle) * speed,
          vy: Math.sin(angle) * speed,
          size: 0.06 + Math.random() * 0.08,
          life: 0.18 + Math.random() * 0.2,
          age: 0,
          color: '#ffffff',
        });
      }
    }
  }
}

/** Screen direction in which a piece shown in `slot` travels. */
function travelOnScreen(slot: Side): [number, number] {
  switch (slot) {
    case 0:
      return [0, 1];
    case 1:
      return [-1, 0];
    case 2:
      return [0, -1];
    default:
      return [1, 0];
  }
}

function prune<T>(items: T[], keep: (item: T) => boolean): void {
  let write = 0;
  for (const item of items) if (keep(item)) items[write++] = item;
  items.length = write;
}
