// The rules of Cube, the 3D mode of RotaThree, carried over from the 2D game
// (src/game) where they apply: six glasses (arms) along ±x, ±y, ±z share a
// cube of a centre, a stick of three falls down each glass one whole cell per
// step, the steered glass steps fast and the others slowly, a stick that
// cannot step locks, cascades repeat, and a glass whose far end is full when a
// new stick is due ends the game.
//
// The game is played on what the screen shows: the hub seen along the line
// of sight, each cell of the screen showing the nearest block behind it.
// Lines of three or more of a colour pop in that picture, and the cells of
// the glass on top fall down it, each with everything behind it — as in the
// 2D game. The sticks of the four glasses around the screen live in the
// middle layer of the cube and stop on whatever the screen shows. The glasses
// in front of and behind the screen drop their sticks along the line of
// sight, into any layer, and are steered in place; unless `depthFalls`, their
// sticks wait until they are steered. Tipping the hub over shows it from
// another side: what was depth becomes up or across, and the new picture
// settles and pops.
//
// Everything here is in the fixed data frame: cells are integer [x, y, z] in
// an N³ grid, N = centre + 2·arm. Turning the hub only changes which glass is
// on top and which way the eye looks; the view turns the picture. The first
// version of these rules is the prototype in proto3d/rules.js.

export const EMPTY = -1;

export type Vec = [number, number, number];

export interface SideInfo {
  id: number;
  /** 0, 1, 2 for x, y, z. */
  axis: number;
  /** Which end of the axis. */
  sign: 1 | -1;
  /** The number of a die: opposite glasses add up to seven. */
  label: string;
}

/** The six glasses. */
export const SIDES: readonly SideInfo[] = [
  { id: 0, axis: 1, sign: 1, label: '1' },
  { id: 1, axis: 0, sign: 1, label: '2' },
  { id: 2, axis: 2, sign: -1, label: '3' },
  { id: 3, axis: 2, sign: 1, label: '4' },
  { id: 4, axis: 0, sign: -1, label: '5' },
  { id: 5, axis: 1, sign: -1, label: '6' },
];

export const normalOf = (side: number): Vec => {
  const n: Vec = [0, 0, 0];
  n[SIDES[side].axis] = SIDES[side].sign;
  return n;
};

export const sideOfNormal = (n: readonly number[]): number =>
  SIDES.findIndex((s) => n[s.axis] === s.sign && n[(s.axis + 1) % 3] === 0 && n[(s.axis + 2) % 3] === 0);

export const add = (a: Vec, b: Vec): Vec => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
export const scale = (a: Vec, k: number): Vec => [a[0] * k, a[1] * k, a[2] * k];
export const cross = (a: Vec, b: Vec): Vec => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
export const dot = (a: readonly number[], b: readonly number[]): number => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const isZero = (a: Vec) => a[0] === 0 && a[1] === 0 && a[2] === 0;
const vec = (f: (i: number) => number): Vec => [f(0), f(1), f(2)];

/** How the falling speeds up with the score: every `everyPoints` the steps
 * get `factor` times as long, down to the floors. */
export interface CubeRamp {
  everyPoints: number;
  factor: number;
  minActive: number;
  minInactive: number;
}

export interface CubeConfig {
  /** Side of the shared centre cube, and the cross-section of every arm.
   * Odd or even: an even cube has two layers in the middle, and the sticks
   * across the screen fall in the nearer of them (`layer`). */
  centre: number;
  /** Length of each arm, in cells. A glass is one arm plus the centre. */
  arm: number;
  pieceLength: number;
  numberOfColors: number;
  minMatchLength: number;
  activeStepSeconds: number;
  inactiveStepSeconds: number;
  /** While soft drop is held, the steered stick steps this often. */
  softDropStepSeconds: number;
  /** Sticks in the five other glasses step too (slowly) — the 2D rule. */
  inactiveFalls: boolean;
  /** …including the glasses in front of and behind the screen, more slowly
   * still. Off: those sticks wait until they are steered. */
  depthFalls: boolean;
  depthStepSeconds: number;
  monoPieceKeepChance: number;
  pauseIncomingDuringCascade: boolean;
  dropBaseSeconds: number;
  dropSecondsPerCell: number;
  matchSeconds: number;
  clearSeconds: number;
  fallBaseSeconds: number;
  fallSecondsPerRootCell: number;
  fallBounceSeconds: number;
  basePoints: number;
  maxQueuedInputs: number;
  ramp: CubeRamp | null;
  seed: number | null;
}

export const defaultCubeConfig: CubeConfig = {
  centre: 7,
  arm: 8,
  pieceLength: 3,
  numberOfColors: 4,
  minMatchLength: 3,
  activeStepSeconds: 1,
  inactiveStepSeconds: 3,
  softDropStepSeconds: 0.05,
  inactiveFalls: true,
  depthFalls: false,
  depthStepSeconds: 6,
  monoPieceKeepChance: 0.4,
  pauseIncomingDuringCascade: true,
  dropBaseSeconds: 0.06,
  dropSecondsPerCell: 0.012,
  matchSeconds: 0.22,
  clearSeconds: 0.2,
  fallBaseSeconds: 0.09,
  fallSecondsPerRootCell: 0.1,
  fallBounceSeconds: 0.08,
  basePoints: 100,
  maxQueuedInputs: 8,
  ramp: null,
  seed: null,
};

export function mulberry32(seed: number): () => number {
  return () => {
    seed |= 0;
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

/** The settled blocks of the whole hub. */
export class Hub {
  readonly size: number;
  readonly cells: Int8Array;
  /** Grows with every write, so that what is worked out from the hub can
   * tell when it is out of date. */
  version = 0;

  constructor(
    readonly centre: number,
    readonly arm: number,
  ) {
    this.size = centre + 2 * arm;
    this.cells = new Int8Array(this.size ** 3).fill(EMPTY);
  }

  index([x, y, z]: Vec): number {
    return (x * this.size + y) * this.size + z;
  }

  cellOf(index: number): Vec {
    const n = this.size;
    return [Math.floor(index / (n * n)), Math.floor(index / n) % n, index % n];
  }

  inBand(v: number): boolean {
    return v >= this.arm && v < this.arm + this.centre;
  }

  /** Whether the cell is in the centre or in one of the six arms. */
  isInside(p: Vec): boolean {
    let outside = 0;
    for (const v of p) {
      if (v < 0 || v >= this.size) return false;
      if (!this.inBand(v)) outside++;
    }
    return outside <= 1;
  }

  at(p: Vec): number {
    return this.cells[this.index(p)];
  }

  set(p: Vec, color: number): void {
    this.cells[this.index(p)] = color;
    this.version++;
  }

  // --- One glass: its arm plus the centre. Row 0 is the far end of the arm,
  // the last row the floor (the far wall of the centre); lanes (a, b) run
  // across it along the other two axes, in increasing axis order.

  depth(): number {
    return this.arm + this.centre;
  }

  crossAxes(side: number): [number, number] {
    const k = SIDES[side].axis;
    const [k1, k2] = [0, 1, 2].filter((i) => i !== k);
    return [k1, k2];
  }

  toWorld(side: number, row: number, a: number, b: number): Vec {
    const { axis, sign } = SIDES[side];
    const [k1, k2] = this.crossAxes(side);
    const p: Vec = [0, 0, 0];
    p[axis] = sign > 0 ? this.size - 1 - row : row;
    p[k1] = this.arm + a;
    p[k2] = this.arm + b;
    return p;
  }

  /** (row, a, b) of a cell in the glass of `side`, or null outside it. */
  fromWorld(side: number, p: Vec): { row: number; a: number; b: number } | null {
    const { axis, sign } = SIDES[side];
    const [k1, k2] = this.crossAxes(side);
    if (!this.inBand(p[k1]) || !this.inBand(p[k2])) return null;
    const row = sign > 0 ? this.size - 1 - p[axis] : p[axis];
    if (row < 0 || row >= this.depth()) return null;
    return { row, a: p[k1] - this.arm, b: p[k2] - this.arm };
  }

  inGlass(side: number, p: Vec): boolean {
    for (const v of p) if (v < 0 || v >= this.size) return false;
    return this.fromWorld(side, p) !== null;
  }

  clone(): Hub {
    const other = new Hub(this.centre, this.arm);
    other.cells.set(this.cells);
    return other;
  }

  forEachBlock(visit: (p: Vec, color: number, index: number) => void): void {
    for (let i = 0; i < this.cells.length; i++) {
      if (this.cells[i] !== EMPTY) visit(this.cellOf(i), this.cells[i], i);
    }
  }
}

/** A stick in flight: its middle square sits at `pivot`, square i at
 * pivot + (i − 1)·dir. `dir` is a unit axis vector; turning the stick turns
 * `dir`, so the colour order never changes. */
export interface Stick {
  side: number;
  colors: number[];
  pivot: Vec;
  dir: Vec;
  /** How far the wait for its next step has got, 0..1. */
  progress: number;
}

export interface StickCell {
  p: Vec;
  color: number;
}

export const pieceCells = (piece: Pick<Stick, 'colors' | 'pivot' | 'dir'>): StickCell[] =>
  piece.colors.map((color, i) => ({ p: add(piece.pivot, scale(piece.dir, i - Math.floor(piece.colors.length / 2))), color }));

export const fallOf = (side: number): Vec => scale(normalOf(side), -1);

/** Data directions of the screen's right and up. */
export interface ViewFrame {
  right: Vec;
  up: Vec;
}

export interface Run {
  color: number;
  /** Hub indices of the cells. */
  cells: number[];
  across: boolean;
}

export interface Match {
  runs: Run[];
  cells: Set<number>;
}

export interface BlockMove {
  from: Vec;
  to: Vec;
  color: number;
  distance: number;
}

export type CubePhase = 'playing' | 'dropping' | 'matching' | 'clearing' | 'settling' | 'gameOver';

export type CubeEvent =
  | { type: 'switched'; from: number; to: number }
  | { type: 'moved'; blocked: boolean }
  | { type: 'rotated'; blocked: boolean }
  | { type: 'stepped'; side: number }
  | { type: 'dropped'; side: number; cells: number }
  | { type: 'landed'; side: number; cells: StickCell[]; dropped: boolean }
  | { type: 'matched'; combo: number; score: number; match: Match }
  | { type: 'popped'; cells: StickCell[] }
  | { type: 'fell'; moves: BlockMove[] }
  | { type: 'speedUp'; level: number }
  | { type: 'gameEnded'; side: number };

type CubeInput =
  | { kind: 'turn'; down: number; plane: Vec; viewFrame: ViewFrame; settle: boolean }
  | { kind: 'control'; side: number }
  | { kind: 'move'; vector: Vec }
  | { kind: 'rotate'; axis: Vec }
  | { kind: 'drop' };

/** What tipping the hub over would give (`previewTurn`). */
export interface TurnPreview {
  view: CubeGame;
  match: Match;
  rounds: number;
  popped: number;
}

export class CubeGame {
  config!: CubeConfig;
  seed = 0;
  random: () => number = Math.random;
  hub!: Hub;
  /** The glass on top of the screen: its fall is "down". */
  down = 0;
  /** The glass whose stick the player steers and that steps fast: the one
   * on top, or the one in front of or behind the screen. */
  active = 0;
  /** The data direction towards the eye. */
  plane: Vec = [0, 0, 1];
  viewFrame: ViewFrame = { right: [1, 0, 0], up: [0, 1, 0] };
  pieces = new Map<number, Stick>();
  /** The stick each glass gets next, as each glass of the flat game has its
   * own. */
  next = new Map<number, number[]>();
  phase: CubePhase = 'playing';
  phaseElapsed = 0;
  phaseDuration = 0;
  score = 0;
  combo = 0;
  bestCombo = 0;
  placed = 0;
  matches = 0;
  cleared = 0;
  /** Seconds of play, not counting a pause. */
  seconds = 0;
  speedLevel = 0;
  softDrop = false;
  /** The tutorial's sticks hold still: they move only when moved. */
  stepsHeld = false;
  drop: { piece: Stick; from: Vec; cells: number } | null = null;
  activeMatch: Match | null = null;
  moves: BlockMove[] = [];
  awaiting: number[] = [];
  inputs: CubeInput[] = [];
  events: CubeEvent[] = [];
  gameOverSide: number | null = null;
  private baseSteps = { active: 1, inactive: 3 };

  constructor(config: Partial<CubeConfig> = {}) {
    this.config = { ...defaultCubeConfig, ...config };
    this.seed = this.config.seed ?? Math.floor(Math.random() * 0xffffffff);
    this.random = mulberry32(this.seed);
    this.hub = new Hub(this.config.centre, this.config.arm);
    this.baseSteps = { active: this.config.activeStepSeconds, inactive: this.config.inactiveStepSeconds };
    for (const s of SIDES) this.next.set(s.id, this.roll());
    for (const s of SIDES) this.spawn(s.id);
  }

  get activePiece(): Stick | undefined {
    return this.pieces.get(this.active);
  }

  get isGameOver(): boolean {
    return this.phase === 'gameOver';
  }

  /** Index of the middle of the hub along any axis: a half for an even
   * hub, whose screen cells then sit at halves from the middle (±0.5,
   * ±1.5, …). */
  get middle(): number {
    return (this.hub.size - 1) / 2;
  }

  /** From the middle of the centre to the middle of its outer cells: 3 for
   * a centre of 7, 4.5 for one of 10. */
  get half(): number {
    return (this.config.centre - 1) / 2;
  }

  /** The depth of the layer the sticks across the screen fall in: the
   * middle one, or of an even cube's two middle ones the nearer. */
  get layer(): number {
    return this.hub.size % 2 === 1 ? 0 : 0.5;
  }

  /** The index of the sticks' layer along the axis looked along. */
  private layerIndex(): { axis: number; index: number } {
    const axis = this.plane.findIndex((v) => v !== 0);
    return { axis, index: this.middle + this.layer * this.plane[axis] };
  }

  /** Whether the glass lies across the screen (top, left, right, bottom)
   * rather than along the line of sight. */
  inPlane(side: number): boolean {
    return dot(normalOf(side), this.plane) === 0;
  }

  // ------------------------------------------------------- what is seen

  /** The cell of the screen a data cell is seen in: across and up from the
   * middle of the hub. */
  screenOf(p: Vec): [number, number] {
    const q = vec((i) => p[i] - this.middle);
    return [dot(q, this.viewFrame.right), dot(q, this.viewFrame.up)];
  }

  /** The depth of a cell, in layers from the middle one: + towards the eye. */
  depthOf(p: Vec): number {
    return dot(vec((i) => p[i] - this.middle), this.plane);
  }

  /** The data cell seen at screen cell (`sx`, `sy`) at depth `d`. */
  cellAt(sx: number, sy: number, d: number): Vec {
    const { right, up } = this.viewFrame;
    return vec((i) => this.middle + sx * right[i] + sy * up[i] + d * this.plane[i]);
  }

  /** The blocks seen at a screen cell, nearest first. */
  stackAt(sx: number, sy: number): Vec[] {
    const stack: Vec[] = [];
    for (let d = this.middle; d >= -this.middle; d--) {
      const p = this.cellAt(sx, sy, d);
      if (this.hub.isInside(p) && this.hub.at(p) !== EMPTY) stack.push(p);
    }
    return stack;
  }

  /** The block the screen shows at a screen cell, or null. */
  seenAt(sx: number, sy: number): Vec | null {
    for (let d = this.middle; d >= -this.middle; d--) {
      const p = this.cellAt(sx, sy, d);
      if (this.hub.isInside(p) && this.hub.at(p) !== EMPTY) return p;
    }
    return null;
  }

  /** Whether nothing at all is seen where `p` is, at any depth. */
  clearOnScreen(p: Vec): boolean {
    const [sx, sy] = this.screenOf(p);
    return this.seenAt(sx, sy) === null;
  }

  /** Whether a stick of `side` may cover `p`: inside its glass and, for a
   * glass across the screen, where the screen shows nothing — sticks there
   * stop on what is seen, whatever its depth. */
  isFree(side: number, p: Vec): boolean {
    if (!this.hub.inGlass(side, p)) return false;
    return this.inPlane(side) ? this.clearOnScreen(p) : this.hub.at(p) === EMPTY;
  }

  /** Lines of `minMatchLength`+ of one colour in the picture on the screen,
   * across or up it — the 2D rule on what is seen. A line pops the blocks
   * that are seen, and shows what was behind them. */
  findMatches(): Match {
    const reach = this.middle;
    const min = this.config.minMatchLength;
    const seen = new Map<string, { index: number; color: number } | null>();
    const at = (sx: number, sy: number) => {
      const key = `${sx},${sy}`;
      if (!seen.has(key)) {
        const p = this.seenAt(sx, sy);
        seen.set(key, p && { index: this.hub.index(p), color: this.hub.at(p) });
      }
      return seen.get(key) ?? null;
    };
    const runs: Run[] = [];
    for (const across of [true, false]) {
      for (let line = -reach; line <= reach; line++) {
        const cell = (k: number) => (across ? at(k, line) : at(line, k));
        let start = -reach;
        while (start <= reach) {
          const first = cell(start);
          let end = start + 1;
          if (first) {
            while (end <= reach && cell(end)?.color === first.color) end++;
            if (end - start >= min) {
              const cells: number[] = [];
              for (let k = start; k < end; k++) cells.push(cell(k)!.index);
              runs.push({ color: first.color, cells, across });
            }
          }
          start = end;
        }
      }
    }
    return { runs, cells: new Set(runs.flatMap((run) => run.cells)) };
  }

  /** Gravity of the 2D game on the picture: in the glass on top, every cell
   * of the screen that shows something falls down it to the next one that
   * does, taking everything behind it along. Blocks in the other glasses
   * never move. Mutates the hub and returns what moved. */
  settle(): BlockMove[] {
    const half = this.half;
    const moves: BlockMove[] = [];
    for (let sx = -half; sx <= half; sx++) {
      let target = -half;
      for (let sy = -half; sy <= this.middle; sy++) {
        const stack = this.stackAt(sx, sy);
        if (stack.length === 0) continue;
        if (sy !== target) {
          for (const from of stack) {
            const color = this.hub.at(from);
            const to = add(from, scale(this.viewFrame.up, target - sy));
            this.hub.set(from, EMPTY);
            this.hub.set(to, color);
            moves.push({ from, to, color, distance: sy - target });
          }
        }
        target++;
      }
    }
    return moves;
  }

  // --------------------------------------------------------------- sticks

  roll(): number[] {
    const palette = this.config.numberOfColors;
    const pick = (count: number) => Math.floor(this.random() * count);
    const colors: number[] = [];
    for (let i = 0; i < this.config.pieceLength; i++) colors.push(pick(palette));
    if (colors.every((c) => c === colors[0]) && this.random() >= this.config.monoPieceKeepChance) {
      const others: number[] = [];
      for (let c = 0; c < palette; c++) if (c !== colors[0]) others.push(c);
      colors[pick(colors.length)] = others[pick(others.length)];
    }
    return colors;
  }

  /** The stick the glass gets after the one in it now. */
  nextOf(side: number): number[] {
    return this.next.get(side) ?? [];
  }

  fits(side: number, pivot: Vec, dir: Vec): boolean {
    return pieceCells({ pivot, dir, colors: [0, 0, 0] }).every(({ p }) => this.isFree(side, p));
  }

  /** Whether a stick of `side` may be at `pivot`/`dir`: free cells, and for
   * a glass across the screen, flat in the middle layer. */
  allowed(side: number, pivot: Vec, dir: Vec): boolean {
    if (this.inPlane(side) && (dot(dir, this.plane) !== 0 || this.depthOf(pivot) !== this.layer)) return false;
    return this.fits(side, pivot, dir);
  }

  /** A new stick lies across its glass along the screen's right, or along
   * its up when right is the way the glass falls. */
  spawnDir(side: number): Vec {
    const n = normalOf(side);
    const { right, up } = this.viewFrame;
    return dot(right, n) === 0 ? [...right] : [...up];
  }

  /** Where a new stick of `side` appears: the far end of its glass, in the
   * middle of it — so in the middle layer, for the glasses across the screen. */
  spawnPivot(side: number): Vec {
    const lane = Math.floor(this.config.centre / 2);
    const pivot = this.hub.toWorld(side, 0, lane, lane);
    if (this.inPlane(side)) {
      const { axis, index } = this.layerIndex();
      pivot[axis] = index;
    }
    return pivot;
  }

  /** Puts a new stick at the far end of the glass. False when it does not
   * fit there — the game is over. */
  spawn(side: number): boolean {
    const colors = this.next.get(side) ?? this.roll();
    this.next.set(side, this.roll());
    const dir = this.spawnDir(side);
    const pivot = this.spawnPivot(side);
    if (!this.allowed(side, pivot, dir)) return false;
    this.pieces.set(side, { side, colors, pivot, dir, progress: 0 });
    return true;
  }

  restRow(piece: Stick): Vec {
    const fall = fallOf(piece.side);
    let pivot = piece.pivot;
    while (this.fits(piece.side, add(pivot, fall), piece.dir)) pivot = add(pivot, fall);
    return pivot;
  }

  /** Where the stick of `side` would land: its cells, or null. */
  ghost(side = this.active): StickCell[] | null {
    const piece = this.pieces.get(side);
    if (!piece) return null;
    return pieceCells({ ...piece, pivot: this.restRow(piece) });
  }

  /** For a stick in front or behind: the layer it would land in, and for
   * each square whether it would be seen there or hidden behind blocks. */
  landing(side = this.active): { layer: number; seen: boolean[]; count: number } | null {
    const cells = this.ghost(side);
    if (!cells) return null;
    const seen = cells.map(({ p }) => {
      const [sx, sy] = this.screenOf(p);
      const front = this.seenAt(sx, sy);
      return front === null || this.depthOf(front) < this.depthOf(p);
    });
    return { layer: this.depthOf(cells[0].p), seen, count: seen.filter(Boolean).length };
  }

  /** The same hub seen from another side: a view that can be settled and
   * searched without touching the game. Works on a copy of the hub unless
   * one is given. */
  lookFrom(plane: Vec, viewFrame: ViewFrame, hub: Hub = this.hub.clone()): CubeGame {
    const view = Object.create(CubeGame.prototype) as CubeGame;
    return Object.assign(view, { config: this.config, hub, plane, viewFrame, pieces: new Map(), active: this.active });
  }

  /** What tipping the hub over to look along `plane` would give: the
   * settled picture with the sticks in flight on it, what pops in it first,
   * and how many blocks the whole cascade would pop in how many rounds. */
  previewTurn(plane: Vec, viewFrame: ViewFrame): TurnPreview {
    const view = this.lookFrom(plane, viewFrame);
    view.settle();
    const settled = this.lookFrom(plane, viewFrame, view.hub.clone());
    // The sticks in flight, laid on the new side as the tip would lay them;
    // the glass on top is the one steered then.
    settled.pieces = new Map([...this.pieces].map(([side, piece]) => [side, { ...piece, pivot: [...piece.pivot] as Vec, dir: [...piece.dir] as Vec }]));
    settled.active = sideOfNormal(viewFrame.up);
    settled.reseat({ plane: this.plane, viewFrame: this.viewFrame });
    const first = view.findMatches();
    let match = first;
    let rounds = 0;
    let popped = 0;
    while (match.runs.length > 0) {
      rounds++;
      popped += match.cells.size;
      for (const i of match.cells) view.hub.set(view.hub.cellOf(i), EMPTY);
      view.settle();
      match = view.findMatches();
    }
    return { view: settled, match: first, rounds, popped };
  }

  // --------------------------------------------------------------- input

  private submit(input: CubeInput): void {
    if (this.isGameOver) return;
    if (this.phase === 'playing') {
      this.apply(input);
      return;
    }
    // Hard drops are never buffered; everything else is replayed after. A
    // turn always is, or the picture and the rules would disagree.
    if (input.kind === 'drop') return;
    if (input.kind === 'turn' || this.inputs.length < this.config.maxQueuedInputs) this.inputs.push(input);
  }

  move(vector: Vec): void {
    this.submit({ kind: 'move', vector });
  }

  /** Quarter turn of the stick around its middle square, about `axis`. */
  rotate(axis: Vec): void {
    this.submit({ kind: 'rotate', axis });
  }

  dropActive(): void {
    this.submit({ kind: 'drop' });
  }

  /** The hub has been turned: `down` is the glass now on top, and the one
   * the player steers. After tipping it over (`settle`) the new picture
   * settles and pops. */
  turn(down: number, plane: Vec, viewFrame: ViewFrame, settle: boolean): void {
    this.submit({ kind: 'turn', down, plane, viewFrame, settle });
  }

  /** Steers the stick of another glass without turning anything. */
  control(side: number): void {
    this.submit({ kind: 'control', side });
  }

  private apply(input: CubeInput): void {
    const piece = this.activePiece;
    switch (input.kind) {
      case 'turn': {
        const from = this.active;
        this.down = input.down;
        this.active = input.down;
        const previous = { plane: this.plane, viewFrame: this.viewFrame };
        this.plane = input.plane;
        this.viewFrame = input.viewFrame;
        this.reseat(previous);
        this.events.push({ type: 'switched', from, to: input.down });
        if (input.settle) this.resolve();
        return;
      }
      case 'control':
        if (input.side !== this.active) {
          const from = this.active;
          this.active = input.side;
          this.events.push({ type: 'switched', from, to: input.side });
        }
        return;
      case 'move': {
        if (!piece) return;
        const to = add(piece.pivot, input.vector);
        const ok = dot(input.vector, normalOf(piece.side)) === 0 && this.allowed(piece.side, to, piece.dir);
        if (ok) piece.pivot = to;
        this.events.push({ type: 'moved', blocked: !ok });
        return;
      }
      case 'rotate': {
        if (!piece) return;
        const dir = cross(input.axis, piece.dir);
        if (isZero(dir)) {
          this.events.push({ type: 'rotated', blocked: true });
          return;
        }
        // Nudges tried when the turn does not fit, gentlest first: across the
        // glass, back towards its far end, down. A stick of a glass across the
        // screen is only nudged within the screen (`allowed`).
        const n = normalOf(piece.side);
        const across = this.hub.crossAxes(piece.side).map((k) => vec((i) => (i === k ? 1 : 0)));
        const kicks: Vec[] = [[0, 0, 0]];
        for (const step of [1, 2]) {
          for (const e of across) kicks.push(scale(e, -step), scale(e, step));
          kicks.push(scale(n, step), scale(n, -step));
        }
        for (const kick of kicks) {
          const pivot = add(piece.pivot, kick);
          if (this.allowed(piece.side, pivot, dir)) {
            piece.pivot = pivot;
            piece.dir = dir;
            this.events.push({ type: 'rotated', blocked: false });
            return;
          }
        }
        this.events.push({ type: 'rotated', blocked: true });
        return;
      }
      case 'drop':
        this.beginDrop();
        return;
    }
  }

  /** After tipping the hub over some sticks in flight point at the eye or
   * have left the middle layer. Each is laid flat again — in the middle
   * layer for a glass across the screen, across the line of sight for the
   * one in front or behind — and backs off towards its far end if it no
   * longer fits; failing that it starts again from there.
   *
   * After a tip, a glass that lies across the screen both before and after
   * it (on its axis) keeps its stick where the screen showed it, lying the
   * same way on the screen, so that it need not turn at all. A turn in the
   * screen moves no stick: each goes round with its glass, as in 2D.
   * `previous` is the plane and frame looked along before. */
  reseat(previous: { plane: Vec; viewFrame: ViewFrame } | null = null): void {
    const k = this.plane.findIndex((v) => v !== 0);
    const middle = this.middle;
    const tipped = previous !== null && dot(previous.plane, this.plane) === 0;
    for (const piece of this.pieces.values()) {
      const n = normalOf(piece.side);
      let dir = piece.dir;
      let pivot: Vec = [...piece.pivot];
      if (tipped && previous && this.inPlane(piece.side) && dot(n, previous.plane) === 0) {
        const { right, up } = previous.viewFrame;
        const at = vec((i) => pivot[i] - middle);
        const [sx, sy] = [dot(at, right), dot(at, up)];
        const [dx, dy] = [dot(dir, right), dot(dir, up)];
        const now = this.viewFrame;
        pivot = vec((i) => middle + sx * now.right[i] + sy * now.up[i] + this.layer * this.plane[i]);
        dir = vec((i) => dx * now.right[i] + dy * now.up[i]);
      } else if (this.inPlane(piece.side)) {
        if (dot(dir, this.plane) !== 0) dir = cross(n, this.plane);
        pivot[k] = this.layerIndex().index;
      } else if (dot(dir, n) !== 0) {
        dir = [...this.viewFrame.up];
      }
      let at = pivot;
      while (this.hub.inGlass(piece.side, at) && !this.allowed(piece.side, at, dir)) at = add(at, n);
      if (this.allowed(piece.side, at, dir)) {
        piece.pivot = at;
        piece.dir = dir;
        continue;
      }
      const start = this.spawnPivot(piece.side);
      const flat = this.spawnDir(piece.side);
      if (this.allowed(piece.side, start, flat)) {
        piece.pivot = start;
        piece.dir = flat;
        piece.progress = 0;
      }
    }
  }

  private flushInputs(): void {
    while (this.inputs.length > 0 && this.phase === 'playing') this.apply(this.inputs.shift()!);
  }

  // ---------------------------------------------------------------- time

  stepSeconds(piece: Stick): number {
    if (piece.side === this.active) {
      // Soft drop only speeds up actual falling: a stick that has landed
      // keeps its full step to be slid or turned before it locks.
      const falling = this.softDrop && this.fits(piece.side, add(piece.pivot, fallOf(piece.side)), piece.dir);
      return falling ? Math.min(this.config.softDropStepSeconds, this.config.activeStepSeconds) : this.config.activeStepSeconds;
    }
    return this.inPlane(piece.side) ? this.config.inactiveStepSeconds : this.config.depthStepSeconds;
  }

  /** Whether a stick nobody steers falls by itself. */
  fallsAlone(piece: Stick): boolean {
    if (piece.side === this.active) return true;
    if (!this.config.inactiveFalls) return false;
    return this.inPlane(piece.side) || this.config.depthFalls;
  }

  private advancePieces(seconds: number): void {
    if (this.stepsHeld) return;
    for (const piece of this.pieces.values()) {
      if (!this.fallsAlone(piece)) continue;
      piece.progress = Math.min(1, piece.progress + seconds / this.stepSeconds(piece));
    }
  }

  update(seconds: number): void {
    if (this.isGameOver || seconds <= 0) return;
    this.seconds += seconds;
    if (this.phase === 'playing') {
      this.advancePieces(seconds);
      this.stepDuePieces();
      return;
    }
    if (!this.config.pauseIncomingDuringCascade) this.advancePieces(seconds);
    this.phaseElapsed += seconds;
    if (this.phaseElapsed >= this.phaseDuration) this.completePhase();
  }

  /** Every due stick steps one cell; the first that cannot locks, and the
   * others wait until the board is at rest again. */
  private stepDuePieces(): void {
    const order = [this.active, ...SIDES.map((s) => s.id).filter((s) => s !== this.active)];
    for (const side of order) {
      const piece = this.pieces.get(side);
      if (!piece || piece.progress < 1) continue;
      const to = add(piece.pivot, fallOf(side));
      if (this.fits(side, to, piece.dir)) {
        piece.pivot = to;
        piece.progress = 0;
        this.events.push({ type: 'stepped', side });
        continue;
      }
      this.pieces.delete(side);
      this.commit(piece, false);
      return;
    }
  }

  private beginDrop(): void {
    const piece = this.activePiece;
    if (!piece) return;
    const rest = this.restRow(piece);
    const cells = Math.abs(dot(add(rest, scale(piece.pivot, -1)), fallOf(piece.side)));
    this.pieces.delete(piece.side);
    this.drop = { piece: { ...piece, pivot: rest }, from: piece.pivot, cells };
    this.events.push({ type: 'dropped', side: piece.side, cells });
    this.enterPhase('dropping', this.config.dropBaseSeconds + this.config.dropSecondsPerCell * cells);
  }

  private commit(piece: Stick, dropped: boolean): void {
    for (const { p, color } of pieceCells(piece)) this.hub.set(p, color);
    this.placed++;
    this.combo = 0;
    this.awaiting.push(piece.side);
    this.events.push({ type: 'landed', side: piece.side, cells: pieceCells(piece), dropped });
    if (!this.makeRoom()) return;
    this.checkMatches();
  }

  /** Sticks pass through each other while falling, so a block that has
   * just appeared may cover one; it backs off towards its own far end.
   * False when one has nowhere to go: game over. */
  private makeRoom(): boolean {
    for (const piece of this.pieces.values()) {
      const back = normalOf(piece.side);
      let pivot = piece.pivot;
      while (!this.allowed(piece.side, pivot, piece.dir)) {
        pivot = add(pivot, back);
        if (!this.hub.inGlass(piece.side, pivot)) {
          this.endGame(piece.side);
          return false;
        }
      }
      piece.pivot = pivot;
    }
    return true;
  }

  /** Lets the picture settle, then pops what lines up (a tipped hub). */
  private resolve(): void {
    const moves = this.settle();
    if (moves.length > 0) this.startFalling(moves);
    else this.checkMatches();
  }

  private startFalling(moves: BlockMove[]): void {
    this.moves = moves;
    const far = moves.reduce((m, move) => Math.max(m, move.distance), 0);
    this.events.push({ type: 'fell', moves });
    this.enterPhase('settling', this.config.fallBaseSeconds + this.config.fallSecondsPerRootCell * Math.sqrt(far) + this.config.fallBounceSeconds);
    this.makeRoom();
  }

  private checkMatches(): void {
    const match = this.findMatches();
    if (match.runs.length === 0) {
      this.finishResolution();
      return;
    }
    this.combo++;
    this.bestCombo = Math.max(this.bestCombo, this.combo);
    const score = match.runs.reduce(
      (sum, run) => sum + this.config.basePoints * (run.cells.length - this.config.minMatchLength + 1) * this.combo,
      0,
    );
    this.score += score;
    this.matches += match.runs.length;
    this.cleared += match.cells.size;
    this.activeMatch = match;
    this.events.push({ type: 'matched', combo: this.combo, score, match });
    this.applyRamp();
    this.enterPhase('matching', this.config.matchSeconds);
  }

  /** Steps the speed up when the score has passed another multiple of the
   * ramp's interval. */
  private applyRamp(): void {
    const ramp = this.config.ramp;
    if (!ramp) return;
    const level = Math.floor(this.score / ramp.everyPoints);
    if (level === this.speedLevel) return;
    this.speedLevel = level;
    const factor = ramp.factor ** level;
    this.config = {
      ...this.config,
      activeStepSeconds: Math.max(ramp.minActive, this.baseSteps.active * factor),
      inactiveStepSeconds: Math.max(ramp.minInactive, this.baseSteps.inactive * factor),
    };
    this.events.push({ type: 'speedUp', level });
  }

  private completePhase(): void {
    switch (this.phase) {
      case 'dropping': {
        const { piece } = this.drop!;
        this.drop = null;
        this.commit(piece, true);
        break;
      }
      case 'matching':
        this.enterPhase('clearing', this.config.clearSeconds);
        break;
      case 'clearing': {
        const match = this.activeMatch!;
        this.events.push({
          type: 'popped',
          cells: [...match.cells].map((i) => ({ p: this.hub.cellOf(i), color: this.hub.cells[i] })),
        });
        for (const i of match.cells) this.hub.set(this.hub.cellOf(i), EMPTY);
        this.activeMatch = null;
        // What was behind the popped blocks is seen now; the picture falls.
        const moves = this.settle();
        if (moves.length === 0) this.checkMatches();
        else this.startFalling(moves);
        break;
      }
      case 'settling':
        this.moves = [];
        if (!this.isGameOver) this.checkMatches();
        break;
      default:
        break;
    }
  }

  private finishResolution(): void {
    this.combo = 0;
    this.enterPhase('playing', 0);
    const waiting = this.awaiting;
    this.awaiting = [];
    for (const side of waiting) {
      if (!this.spawn(side)) {
        this.endGame(side);
        return;
      }
    }
    this.flushInputs();
  }

  private enterPhase(phase: CubePhase, duration: number): void {
    this.phase = phase;
    this.phaseElapsed = 0;
    this.phaseDuration = duration;
  }

  private endGame(side: number): void {
    this.gameOverSide = side;
    this.inputs.length = 0;
    this.enterPhase('gameOver', 0);
    this.events.push({ type: 'gameEnded', side });
  }
}
