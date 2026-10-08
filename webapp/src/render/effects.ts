import type { GameEngine, GameEvent } from '../game/engine';
import { slotOfSide } from '../game/glass';
import type { IncomingPiece } from '../game/incoming';
import type { MatchResult } from '../game/matchDetector';
import type { Orientation } from '../game/piece';
import type { Placement } from '../game/placement';
import { SIDES, type Side } from '../game/side';
import { tonesOf, type BlockTones } from './theme';

/** One shard or spark. Positions are in cells, relative to the centre of the
 * cross, in the world frame (they turn with the cross). */
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

/** An expanding ring. A negative age means it has not started yet. */
export interface Ring {
  x: number;
  y: number;
  age: number;
  life: number;
  /** A CSS colour; the ring fades through the canvas's alpha. */
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

/** A bar of light laid over a line of popped blocks, in world cells. */
export interface Flash {
  x0: number;
  y0: number;
  x1: number;
  y1: number;
  age: number;
  life: number;
  /** A CSS colour; the bar fades through the canvas's alpha. */
  color: string;
}

/** A whole-field wash of light for a triple clear. */
export interface Veil {
  age: number;
  life: number;
}

/** How one line of popped blocks explodes. */
interface Signature {
  shards: number;
  speed: number;
  rings: number;
  flash: number;
  shake: number;
  gold: boolean;
}

/** Explosions per length of line. Lines of six and more get the most. */
const SIGNATURES: Record<3 | 4 | 5 | 6, Signature> = {
  3: { shards: 9, speed: 6.5, rings: 1, flash: 0, shake: 0.04, gold: false },
  4: { shards: 15, speed: 8, rings: 2, flash: 0.18, shake: 0.06, gold: false },
  5: { shards: 22, speed: 9.5, rings: 2, flash: 0.24, shake: 0.08, gold: false },
  6: { shards: 30, speed: 11, rings: 3, flash: 0.3, shake: 0.11, gold: true },
};

/** The one explosion the "unified" style uses for everything. */
const UNIFIED = SIGNATURES[3];

export type ExplosionStyle = 'unified' | 'varied';

interface StepTrack {
  piece: IncomingPiece;
  row: number;
  orientation: Orientation;
  steppedAt: number;
}

const QUARTER = Math.PI / 2;

/** The most shards alive at once. A huge cascade drops its oldest ones rather
 * than slowing the frame it is celebrated in. */
const MAX_PARTICLES = 1500;

/** Purely visual state layered on top of the engine: the turn of the cross,
 * kicks and shakes, particles, flashes. Nothing here feeds back into the
 * rules. */
export class Effects {
  /** Seconds of animation time. */
  clock = 0;
  /** Board kicks and shakes can be switched off in the settings. */
  screenShake = true;
  /** Whether each kind of clear explodes in its own way. */
  explosion: ExplosionStyle = 'varied';
  /** Seconds a quarter turn of the cross takes; 0 turns it at once. */
  turnSeconds = 0.26;
  /** How fast the cross is turning right now, 0 at rest … 1 at the fastest
   * point of a turn. Fine lines fade by it so that they do not flicker. */
  turnMotion = 0;

  /** How strongly each glass is lit as the active one, 0..1. */
  readonly activeness: number[] = [1, 0, 0, 0];
  readonly particles: Particle[] = [];
  readonly rings: Ring[] = [];
  readonly beams: Beam[] = [];
  readonly landings: Landing[] = [];
  readonly flashes: Flash[] = [];
  readonly veils: Veil[] = [];

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
  /** Speed at the start of the current turn, in quarter turns a second. */
  private turnVelocity = 0;
  private turnStartedAt = -Infinity;
  private turnDuration = 0;

  private readonly steps = new Map<Side, StepTrack>();
  private burstMatch: MatchResult | null = null;

  /** Slide of a piece into its next cell, in seconds. */
  static readonly stepSlideSeconds = 0.07;

  reset(active: Side): void {
    this.clock = 0;
    this.particles.length = 0;
    this.rings.length = 0;
    this.beams.length = 0;
    this.landings.length = 0;
    this.flashes.length = 0;
    this.veils.length = 0;
    this.steps.clear();
    this.burstMatch = null;
    this.kickX = this.kickY = this.kickVx = this.kickVy = 0;
    this.shake = this.shakeX = this.shakeY = this.punch = 0;
    this.fromTurns = this.toTurns = -active;
    this.turnVelocity = this.turnMotion = 0;
    this.turnStartedAt = -Infinity;
    SIDES.forEach((side) => (this.activeness[side] = side === active ? 1 : 0));
  }

  private get turnProgress(): number {
    if (this.turnDuration <= 0) return 1;
    return Math.min(1, Math.max(0, (this.clock - this.turnStartedAt) / this.turnDuration));
  }

  /** The turn as a cubic that starts at the speed the cross already had and
   * comes to rest exactly on its target: from standstill that is a plain ease
   * in and out with no overshoot, and a turn ordered while another is still
   * running carries on from it without a jerk. */
  private turnsAt(s: number): number {
    const s2 = s * s;
    const s3 = s2 * s;
    return (
      (2 * s3 - 3 * s2 + 1) * this.fromTurns +
      (s3 - 2 * s2 + s) * this.turnDuration * this.turnVelocity +
      (3 * s2 - 2 * s3) * this.toTurns
    );
  }

  /** Speed of the turn at `s`, in quarter turns a second. */
  private turnSpeedAt(s: number): number {
    if (this.turnDuration <= 0 || s >= 1) return 0;
    const s2 = s * s;
    return (
      ((6 * s2 - 6 * s) * (this.fromTurns - this.toTurns)) / this.turnDuration +
      (3 * s2 - 4 * s + 1) * this.turnVelocity
    );
  }

  /** Current rotation of the cross in radians (positive is clockwise). */
  get viewAngle(): number {
    return this.turnsAt(this.turnProgress) * QUARTER;
  }

  /** The angle the cross is turning towards, in quarter turns. */
  get targetTurns(): number {
    return this.toTurns;
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
        case 'sideSwitched': {
          const s = this.turnProgress;
          const speed = this.turnSpeedAt(s);
          this.fromTurns = this.turnsAt(s);
          this.toTurns -= event.quarterTurns;
          const distance = Math.abs(this.toTurns - this.fromTurns);
          // A half turn takes half as long again, not twice as long.
          this.turnDuration = this.turnSeconds * (1 + 0.5 * Math.max(0, distance - 1));
          // Faster than this at the start and the curve would swing past its
          // target.
          const limit = this.turnDuration > 0 ? (3 * distance) / this.turnDuration : 0;
          this.turnVelocity = Math.max(-limit, Math.min(limit, speed));
          this.turnStartedAt = this.clock;
          break;
        }
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
          if (this.screenShake) this.punch = Math.min(0.06, 0.012 * event.combo);
          break;
        case 'glassAdded': {
          // A ring runs out from the far end of the glass as it is finished.
          const far = farEnd(event.side, engine.config.armLength + engine.config.boardSize / 2);
          this.rings.push({ x: far.x, y: far.y, age: 0, life: 0.7, color: 'rgb(120, 205, 255)', reach: 3 });
          this.addShake(0.04);
          break;
        }
        case 'cellsPopped':
        case 'pieceStepped':
        case 'blocksFell':
        case 'speedUp':
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
      this.burst(match, engine);
    }

    this.trackSteps(engine);

    // A turn from standstill peaks at 1.5 quarter turns per `turnSeconds`.
    this.turnMotion = Math.min(1, (Math.abs(this.turnSpeedAt(this.turnProgress)) * this.turnSeconds) / 1.5);

    // Spring back to rest.
    const stiffness = 520;
    const damping = 30;
    this.kickVx += (-stiffness * this.kickX - damping * this.kickVx) * seconds;
    this.kickVy += (-stiffness * this.kickY - damping * this.kickVy) * seconds;
    this.kickX += this.kickVx * seconds;
    this.kickY += this.kickVy * seconds;
    this.shake *= Math.exp(-14 * seconds);
    this.punch *= Math.exp(-9 * seconds);
    // Everything comes to a dead stop instead of creeping towards it for
    // ever: a field at rest is drawn on whole pixels, which is both sharper
    // and much cheaper.
    if (this.shake < 1e-4) this.shake = 0;
    if (this.punch < 1e-5) this.punch = 0;
    if (Math.abs(this.kickX) < 1e-4 && Math.abs(this.kickVx) < 1e-3) this.kickX = this.kickVx = 0;
    if (Math.abs(this.kickY) < 1e-4 && Math.abs(this.kickVy) < 1e-3) this.kickY = this.kickVy = 0;
    this.shakeX = (Math.random() * 2 - 1) * this.shake;
    this.shakeY = (Math.random() * 2 - 1) * this.shake;

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
    for (const flash of this.flashes) flash.age += seconds;
    prune(this.flashes, (flash) => flash.age < flash.life);
    for (const veil of this.veils) veil.age += seconds;
    prune(this.veils, (veil) => veil.age < veil.life);

    const rate = Math.min(1, seconds * 18);
    for (const side of SIDES) {
      const target = side === engine.activeSide ? 1 : 0;
      const next = this.activeness[side] + (target - this.activeness[side]) * rate;
      this.activeness[side] = Math.abs(target - next) < 0.002 ? target : next;
    }
  }

  /** True when nothing is animating: no turn, no shake, no particles. Two
   * frames drawn while this holds look the same unless the game moved. */
  get settled(): boolean {
    return (
      this.particles.length === 0 &&
      this.rings.length === 0 &&
      this.beams.length === 0 &&
      this.landings.length === 0 &&
      this.flashes.length === 0 &&
      this.veils.length === 0 &&
      this.kickX === 0 &&
      this.kickY === 0 &&
      this.shake === 0 &&
      this.punch === 0 &&
      this.turnProgress >= 1 &&
      this.activeness.every((lit) => lit === 0 || lit === 1)
    );
  }

  /** A level has been finished: rings roll out from the centre of the cross
   * and confetti in the colours in play flies after them. */
  celebrate(colours: number): void {
    for (let i = 0; i < 3; i++) {
      this.rings.push({ x: 0, y: 0, age: -0.16 * i, life: 0.9, color: '#ffffff', reach: 13 });
    }
    for (let i = 0; i < 150; i++) {
      const tones = tonesOf(i % colours);
      const angle = Math.random() * Math.PI * 2;
      const speed = 8 + Math.random() * 26;
      this.particles.push({
        x: Math.cos(angle) * 0.6,
        y: Math.sin(angle) * 0.6,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        size: 0.14 + Math.random() * 0.22,
        life: 0.7 + Math.random() * 0.8,
        age: 0,
        color: i % 4 === 0 ? '#ffffff' : i % 2 === 0 ? tones.light : tones.base,
      });
    }
    this.capParticles();
    if (this.screenShake) this.punch = 0.05;
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

  /** Every popped block bursts. In the varied style each line shows its own
   * kind of explosion; several lines at once send a wave out from each of
   * them, and three or more also flash the whole field. */
  private burst(match: MatchResult, engine: GameEngine): void {
    const board = engine.board;
    const half = board.size / 2;
    const at = (index: number) => ({
      x: -half + (index % board.size) + 0.5,
      y: -half + Math.floor(index / board.size) + 0.5,
    });
    const varied = this.explosion === 'varied';
    const shot = new Set<number>();

    for (const run of match.runs) {
      const sig = varied ? SIGNATURES[Math.min(6, run.cells.length) as 3 | 4 | 5 | 6] : UNIFIED;
      for (const index of run.cells) {
        if (shot.has(index)) continue;
        shot.add(index);
        const color = board.atIndex(index);
        if (color < 0) continue;
        const p = at(index);
        const tones = tonesOf(color);
        this.shards(p, tones, sig);
        for (let r = 0; r < sig.rings; r++) {
          this.rings.push({
            x: p.x,
            y: p.y,
            age: -0.05 * r,
            life: 0.34 + 0.05 * r,
            color: tones.base,
            reach: 1.25 + 0.3 * r,
          });
        }
      }
      if (varied) {
        if (sig.flash > 0) {
          const a = at(run.cells[0]);
          const b = at(run.cells[run.cells.length - 1]);
          this.flashes.push({
            x0: Math.min(a.x, b.x) - 0.5,
            y0: Math.min(a.y, b.y) - 0.5,
            x1: Math.max(a.x, b.x) + 0.5,
            y1: Math.max(a.y, b.y) + 0.5,
            age: 0,
            life: sig.flash,
            color: sig.gold ? '#ffd76a' : '#ffffff',
          });
        }
        this.addShake(sig.shake);
      }
    }

    if (varied && match.runs.length >= 2) {
      match.runs.forEach((run, i) => {
        if (i === 0) return;
        const mid = at(run.cells[Math.floor(run.cells.length / 2)]);
        this.rings.push({ x: mid.x, y: mid.y, age: -0.08 * i, life: 0.55, color: '#ffffff', reach: 2.6 });
      });
      this.addShake(0.03 * (match.runs.length - 1));
    }
    if (varied && match.runs.length >= 3) this.veils.push({ age: 0, life: 0.2 });
    this.capParticles();
  }

  private capParticles(): void {
    const extra = this.particles.length - MAX_PARTICLES;
    if (extra > 0) this.particles.splice(0, extra);
  }

  private shards(p: { x: number; y: number }, tones: BlockTones, sig: Signature): void {
    for (let i = 0; i < sig.shards; i++) {
      const angle = Math.random() * Math.PI * 2;
      const speed = 2.5 + Math.random() * sig.speed;
      const gold = sig.gold && i % 4 === 0;
      this.particles.push({
        x: p.x + (Math.random() - 0.5) * 0.5,
        y: p.y + (Math.random() - 0.5) * 0.5,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        size: 0.1 + Math.random() * 0.16,
        life: 0.3 + Math.random() * 0.3,
        age: 0,
        color: gold ? '#ffd76a' : i % 3 === 0 ? '#ffffff' : i % 3 === 1 ? tones.light : tones.base,
      });
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

/** The point at the far end of a glass, in world cells from the centre. */
function farEnd(side: Side, reach: number): { x: number; y: number } {
  const turn = side * QUARTER;
  return { x: reach * Math.sin(turn), y: -reach * Math.cos(turn) };
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
