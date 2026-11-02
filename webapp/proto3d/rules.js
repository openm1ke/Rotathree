// The rules of a 3D mode of RotaThree, mirrored from webapp/src/game where
// they carry over: six glasses (arms) along ±x, ±y, ±z share a cube of a
// centre, a stick of three falls down each glass one whole cell per step, the
// steered glass steps fast and the others slowly, a stick that cannot step
// locks, cascades repeat, and a glass whose far end is full when a new stick
// is due ends the game.
//
// The game is played on what the screen shows: the hub seen along the line
// of sight, each cell of the screen showing the nearest block behind it.
// Lines of three or more of a colour pop in that picture, and the cells of
// the glass on top fall down it, each with everything behind it — as in the
// 2D game. The sticks of the four glasses around the screen live in the
// middle layer of the cube and stop on whatever the screen shows. The
// glasses in front of and behind the screen drop their sticks along the line
// of sight, into any layer, and are steered in place. Tipping the hub over
// (↑/↓) shows it from another side: what was depth becomes up or across, and
// the new picture settles and pops.
//
// Everything here is in the fixed data frame: cells are integer [x, y, z] in
// an N³ grid, N = centre + 2·arm. Turning the hub only changes which glass is
// on top and which way the eye looks; the renderer turns the picture.

export const EMPTY = -1;

/** The six glasses. `axis` 0/1/2 = x/y/z, `sign` says which end of it. The
 * numbers are those of a die: opposite glasses add up to seven. */
export const SIDES = [
  { id: 0, axis: 1, sign: 1, label: '1' },
  { id: 1, axis: 0, sign: 1, label: '2' },
  { id: 2, axis: 2, sign: -1, label: '3' },
  { id: 3, axis: 2, sign: 1, label: '4' },
  { id: 4, axis: 0, sign: -1, label: '5' },
  { id: 5, axis: 1, sign: -1, label: '6' },
];

export const normalOf = (side) => {
  const n = [0, 0, 0];
  n[SIDES[side].axis] = SIDES[side].sign;
  return n;
};

export const sideOfNormal = (n) =>
  SIDES.findIndex((s) => n[s.axis] === s.sign && n[(s.axis + 1) % 3] === 0 && n[(s.axis + 2) % 3] === 0);

export const add = (a, b) => [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
export const scale = (a, k) => [a[0] * k, a[1] * k, a[2] * k];
export const cross = (a, b) => [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]];
export const dot = (a, b) => a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
const isZero = (a) => a[0] === 0 && a[1] === 0 && a[2] === 0;

export const defaultConfig = {
  /** Side of the shared centre cube, and the cross-section of every arm.
   * Odd, so that the cube has a middle layer whichever way it is turned. */
  centre: 7,
  /** Length of each arm, in cells. A glass is one arm plus the centre. */
  arm: 8,
  pieceLength: 3,
  numberOfColors: 4,
  minMatchLength: 3,
  activeStepSeconds: 1,
  inactiveStepSeconds: 3,
  /** Sticks in the five other glasses step too (slowly) — the 2D rule. */
  inactiveFalls: true,
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
  seed: null,
};

export function mulberry32(seed) {
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
  constructor(centre, arm) {
    this.centre = centre;
    this.arm = arm;
    this.size = centre + 2 * arm;
    this.cells = new Int8Array(this.size ** 3).fill(EMPTY);
    this.version = 0;
  }

  index([x, y, z]) {
    return (x * this.size + y) * this.size + z;
  }

  cellOf(index) {
    const n = this.size;
    return [Math.floor(index / (n * n)), Math.floor(index / n) % n, index % n];
  }

  inBand(v) {
    return v >= this.arm && v < this.arm + this.centre;
  }

  /** Whether the cell is in the centre or in one of the six arms. */
  isInside(p) {
    let outside = 0;
    for (const v of p) {
      if (v < 0 || v >= this.size) return false;
      if (!this.inBand(v)) outside++;
    }
    return outside <= 1;
  }

  isCentre(p) {
    return this.inBand(p[0]) && this.inBand(p[1]) && this.inBand(p[2]);
  }

  /** The outer shell of the centre, the cells x-ray makes faint. */
  isCentreShell(p) {
    if (!this.isCentre(p)) return false;
    const lo = this.arm;
    const hi = this.arm + this.centre - 1;
    return p.some((v) => v === lo || v === hi);
  }

  at(p) {
    return this.cells[this.index(p)];
  }

  set(p, color) {
    this.cells[this.index(p)] = color;
    this.version++;
  }

  /** Which arm a cell lies in (a side id), or null in the centre / outside. */
  armOf(p) {
    if (!this.isInside(p) || this.isCentre(p)) return null;
    for (const s of SIDES) {
      const v = p[s.axis];
      if (s.sign > 0 && v >= this.arm + this.centre) return s.id;
      if (s.sign < 0 && v < this.arm) return s.id;
    }
    return null;
  }

  // --- One glass: its arm plus the centre. Row 0 is the far end of the arm,
  // the last row the floor (the far wall of the centre); lanes (a, b) run
  // across it along the other two axes, in increasing axis order.

  depth() {
    return this.arm + this.centre;
  }

  crossAxes(side) {
    const k = SIDES[side].axis;
    return [0, 1, 2].filter((i) => i !== k);
  }

  toWorld(side, row, a, b) {
    const { axis, sign } = SIDES[side];
    const [k1, k2] = this.crossAxes(side);
    const p = [0, 0, 0];
    p[axis] = sign > 0 ? this.size - 1 - row : row;
    p[k1] = this.arm + a;
    p[k2] = this.arm + b;
    return p;
  }

  /** (row, a, b) of a cell in the glass of `side`, or null outside it. */
  fromWorld(side, p) {
    const { axis, sign } = SIDES[side];
    const [k1, k2] = this.crossAxes(side);
    if (!this.inBand(p[k1]) || !this.inBand(p[k2])) return null;
    const row = sign > 0 ? this.size - 1 - p[axis] : p[axis];
    if (row < 0 || row >= this.depth()) return null;
    return { row, a: p[k1] - this.arm, b: p[k2] - this.arm };
  }

  inGlass(side, p) {
    for (const v of p) if (v < 0 || v >= this.size) return false;
    return this.fromWorld(side, p) !== null;
  }

  isFreeIn(side, p) {
    return this.inGlass(side, p) && this.at(p) === EMPTY;
  }

  /** Free rows at the far end of the glass, over all its lanes: how much
   * room a new stick has. */
  headroom(side) {
    let free = this.depth();
    for (let a = 0; a < this.centre; a++) {
      for (let b = 0; b < this.centre; b++) {
        let row = 0;
        while (row < this.depth() && this.at(this.toWorld(side, row, a, b)) === EMPTY) row++;
        if (row < free) free = row;
      }
    }
    return free;
  }

  forEachBlock(visit) {
    for (let i = 0; i < this.cells.length; i++) {
      if (this.cells[i] !== EMPTY) visit(this.cellOf(i), this.cells[i], i);
    }
  }
}

/** A stick: its middle square sits at `pivot`, square i at
 * pivot + (i − 1)·dir. `dir` is a unit axis vector; turning the stick turns
 * `dir`, so the colour order never changes. */
export const pieceCells = (piece) =>
  piece.colors.map((color, i) => ({ p: add(piece.pivot, scale(piece.dir, i - Math.floor(piece.colors.length / 2))), color }));

export const fallOf = (side) => scale(normalOf(side), -1);

export class Game {
  constructor(config = {}) {
    this.config = { ...defaultConfig, ...config };
    this.seed = this.config.seed ?? Math.floor(Math.random() * 0xffffffff);
    this.random = mulberry32(this.seed);
    this.hub = new Hub(this.config.centre, this.config.arm);
    /** The glass on top of the screen: its fall is "down". */
    this.down = 0;
    /** The glass whose stick the player steers and that steps fast: the one
     * on top, or the one in front of or behind the screen. */
    this.active = 0;
    /** The data direction towards the eye. */
    this.plane = [0, 0, 1];
    /** Data directions of the screen's right and up, set by the view. */
    this.viewFrame = { right: [1, 0, 0], up: [0, 1, 0] };
    /** side → { side, colors, pivot, dir, progress } */
    this.pieces = new Map();
    this.queue = [];
    this.phase = 'playing';
    this.phaseElapsed = 0;
    this.phaseDuration = 0;
    this.score = 0;
    this.combo = 0;
    this.bestCombo = 0;
    this.placed = 0;
    this.cleared = 0;
    this.drop = null;
    this.activeMatch = null;
    this.moves = [];
    this.awaiting = [];
    this.inputs = [];
    this.events = [];
    this.gameOverSide = null;
    for (let i = 0; i < 2; i++) this.queue.push(this.roll());
    for (const s of SIDES) this.spawn(s.id);
  }

  get activePiece() {
    return this.pieces.get(this.active);
  }

  get isGameOver() {
    return this.phase === 'gameOver';
  }

  /** Index of the middle of the hub along any axis; also its middle layer. */
  get middle() {
    return (this.hub.size - 1) / 2;
  }

  /** Half the side of the centre, in whole cells from its middle. */
  get half() {
    return Math.floor(this.config.centre / 2);
  }

  /** Whether the glass lies across the screen (top, left, right, bottom)
   * rather than along the line of sight. */
  inPlane(side) {
    return dot(normalOf(side), this.plane) === 0;
  }

  // ------------------------------------------------------- what is seen

  /** The cell of the screen a data cell is seen in: across and up from the
   * middle of the hub. */
  screenOf(p) {
    const q = p.map((v) => v - this.middle);
    return [dot(q, this.viewFrame.right), dot(q, this.viewFrame.up)];
  }

  /** The depth of a cell, in layers from the middle one: + towards the eye. */
  depthOf(p) {
    return dot(p.map((v) => v - this.middle), this.plane);
  }

  /** The data cell seen at screen cell (`sx`, `sy`) at depth `d`. */
  cellAt(sx, sy, d) {
    const { right, up } = this.viewFrame;
    return [0, 1, 2].map((i) => this.middle + sx * right[i] + sy * up[i] + d * this.plane[i]);
  }

  /** The blocks seen at a screen cell, nearest first. */
  stackAt(sx, sy) {
    const stack = [];
    for (let d = this.middle; d >= -this.middle; d--) {
      const p = this.cellAt(sx, sy, d);
      if (this.hub.isInside(p) && this.hub.at(p) !== EMPTY) stack.push(p);
    }
    return stack;
  }

  /** The block the screen shows at a screen cell, or null. */
  seenAt(sx, sy) {
    for (let d = this.middle; d >= -this.middle; d--) {
      const p = this.cellAt(sx, sy, d);
      if (this.hub.isInside(p) && this.hub.at(p) !== EMPTY) return p;
    }
    return null;
  }

  /** Whether nothing at all is seen where `p` is, at any depth. */
  clearOnScreen(p) {
    const [sx, sy] = this.screenOf(p);
    return this.seenAt(sx, sy) === null;
  }

  /** Whether a stick of `side` may cover `p`: inside its glass and, for a
   * glass across the screen, where the screen shows nothing — sticks there
   * stop on what is seen, whatever its depth. */
  isFree(side, p) {
    if (!this.hub.inGlass(side, p)) return false;
    return this.inPlane(side) ? this.clearOnScreen(p) : this.hub.at(p) === EMPTY;
  }

  /** Lines of `minMatchLength`+ of one colour in the picture on the screen,
   * across or up it — the 2D rule on what is seen. A line pops the blocks
   * that are seen, and shows what was behind them. */
  findMatches() {
    const reach = this.middle;
    const min = this.config.minMatchLength;
    const seen = new Map();
    const at = (sx, sy) => {
      const key = `${sx},${sy}`;
      if (!seen.has(key)) {
        const p = this.seenAt(sx, sy);
        seen.set(key, p && { index: this.hub.index(p), color: this.hub.at(p) });
      }
      return seen.get(key);
    };
    const runs = [];
    for (const across of [true, false]) {
      for (let line = -reach; line <= reach; line++) {
        const cell = (k) => (across ? at(k, line) : at(line, k));
        let start = -reach;
        while (start <= reach) {
          const first = cell(start);
          let end = start + 1;
          if (first) {
            while (end <= reach && cell(end)?.color === first.color) end++;
            if (end - start >= min) {
              const cells = [];
              for (let k = start; k < end; k++) cells.push(cell(k).index);
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
  settle() {
    const half = this.half;
    const shift = (k) => scale(this.viewFrame.up, k);
    const moves = [];
    for (let sx = -half; sx <= half; sx++) {
      let target = -half;
      for (let sy = -half; sy <= this.middle; sy++) {
        const stack = this.stackAt(sx, sy);
        if (stack.length === 0) continue;
        if (sy !== target) {
          for (const from of stack) {
            const color = this.hub.at(from);
            const to = add(from, shift(target - sy));
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

  /** Free rows at the far end of the glass, over all its lanes: how much
   * room a new stick has. */
  headroom(side) {
    const hub = this.hub;
    let free = hub.depth();
    for (let a = 0; a < hub.centre; a++) {
      for (let b = 0; b < hub.centre; b++) {
        let row = 0;
        while (row < hub.depth() && this.isFree(side, hub.toWorld(side, row, a, b))) row++;
        free = Math.min(free, row);
      }
    }
    return free;
  }

  // --------------------------------------------------------------- sticks

  roll() {
    const palette = this.config.numberOfColors;
    const pick = (count) => Math.floor(this.random() * count);
    const colors = [];
    for (let i = 0; i < this.config.pieceLength; i++) colors.push(pick(palette));
    if (colors.every((c) => c === colors[0]) && this.random() >= this.config.monoPieceKeepChance) {
      const others = [];
      for (let c = 0; c < palette; c++) if (c !== colors[0]) others.push(c);
      colors[pick(colors.length)] = others[pick(others.length)];
    }
    return colors;
  }

  /** The next stick to appear, whichever glass needs it first. */
  get nextColors() {
    return this.queue[0];
  }

  fits(side, pivot, dir) {
    return pieceCells({ pivot, dir, colors: [0, 0, 0] }).every(({ p }) => this.isFree(side, p));
  }

  /** Whether a stick of `side` may be at `pivot`/`dir`: free cells, and for
   * a glass across the screen, flat in the middle layer. */
  allowed(side, pivot, dir) {
    if (this.inPlane(side) && (dot(dir, this.plane) !== 0 || this.depthOf(pivot) !== 0)) return false;
    return this.fits(side, pivot, dir);
  }

  /** A new stick lies across its glass along the screen's right, or along
   * its up when right is the way the glass falls. */
  spawnDir(side) {
    const n = normalOf(side);
    const { right, up } = this.viewFrame;
    return dot(right, n) === 0 ? [...right] : [...up];
  }

  /** Where a new stick of `side` appears: the far end of its glass, in the
   * middle of it — so in the middle layer, for the glasses across the screen. */
  spawnPivot(side) {
    const lane = Math.floor(this.config.centre / 2);
    return this.hub.toWorld(side, 0, lane, lane);
  }

  /** Puts a new stick at the far end of the glass. False when it does not
   * fit there — the game is over. */
  spawn(side) {
    const colors = this.queue.shift();
    this.queue.push(this.roll());
    const dir = this.spawnDir(side);
    const pivot = this.spawnPivot(side);
    if (!this.allowed(side, pivot, dir)) return false;
    this.pieces.set(side, { side, colors, pivot, dir, progress: 0 });
    return true;
  }

  restRow(piece) {
    const fall = fallOf(piece.side);
    let pivot = piece.pivot;
    while (this.fits(piece.side, add(pivot, fall), piece.dir)) pivot = add(pivot, fall);
    return pivot;
  }

  /** Where the stick of `side` would land: its cells, or null. */
  ghost(side = this.active) {
    const piece = this.pieces.get(side);
    if (!piece) return null;
    return pieceCells({ ...piece, pivot: this.restRow(piece) });
  }

  /** For a stick in front or behind: the layer it would land in, and how
   * many of its squares would be seen there rather than hidden. */
  landing(side = this.active) {
    const cells = this.ghost(side);
    if (!cells) return null;
    const seen = cells.filter(({ p }) => {
      const [sx, sy] = this.screenOf(p);
      const front = this.seenAt(sx, sy);
      return front === null || this.depthOf(front) < this.depthOf(p);
    }).length;
    return { layer: this.depthOf(cells[0].p), seen, of: cells.length };
  }

  // --------------------------------------------------------------- input

  submit(input) {
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

  move(vector) {
    this.submit({ kind: 'move', vector });
  }

  /** Quarter turn of the stick around its middle square, about `axis`. */
  rotate(axis) {
    this.submit({ kind: 'rotate', axis });
  }

  dropActive() {
    this.submit({ kind: 'drop' });
  }

  /** The hub has been turned: `down` is the glass now on top, and the one
   * the player steers. After tipping it over (`settle`) the new picture
   * settles and pops. */
  turn(down, plane, viewFrame, settle) {
    this.submit({ kind: 'turn', down, plane, viewFrame, settle });
  }

  /** Steers the stick of another glass without turning anything. */
  control(side) {
    this.submit({ kind: 'control', side });
  }

  apply(input) {
    const piece = this.activePiece;
    switch (input.kind) {
      case 'turn': {
        const from = this.active;
        this.down = input.down;
        this.active = input.down;
        this.plane = input.plane;
        this.viewFrame = input.viewFrame;
        this.reseat();
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
        const across = this.hub.crossAxes(piece.side).map((k) => {
          const e = [0, 0, 0];
          e[k] = 1;
          return e;
        });
        const kicks = [[0, 0, 0]];
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
   * longer fits; failing that it starts again from there. */
  reseat() {
    const k = this.plane.findIndex((v) => v !== 0);
    for (const piece of this.pieces.values()) {
      const n = normalOf(piece.side);
      let dir = piece.dir;
      const pivot = [...piece.pivot];
      if (this.inPlane(piece.side)) {
        if (dot(dir, this.plane) !== 0) dir = cross(n, this.plane);
        pivot[k] = this.middle;
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

  flushInputs() {
    while (this.inputs.length > 0 && this.phase === 'playing') this.apply(this.inputs.shift());
  }

  // ---------------------------------------------------------------- time

  stepSeconds(piece) {
    return piece.side === this.active ? this.config.activeStepSeconds : this.config.inactiveStepSeconds;
  }

  advancePieces(seconds) {
    for (const piece of this.pieces.values()) {
      if (piece.side !== this.active && !this.config.inactiveFalls) continue;
      piece.progress = Math.min(1, piece.progress + seconds / this.stepSeconds(piece));
    }
  }

  update(seconds) {
    if (this.isGameOver || seconds <= 0) return;
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
  stepDuePieces() {
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

  beginDrop() {
    const piece = this.activePiece;
    if (!piece) return;
    const rest = this.restRow(piece);
    const cells = Math.abs(dot(add(rest, scale(piece.pivot, -1)), fallOf(piece.side)));
    this.pieces.delete(piece.side);
    this.drop = { piece: { ...piece, pivot: rest }, from: piece.pivot, cells };
    this.events.push({ type: 'dropped', side: piece.side, cells });
    this.enterPhase('dropping', this.config.dropBaseSeconds + this.config.dropSecondsPerCell * cells);
  }

  commit(piece, dropped) {
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
  makeRoom() {
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
  resolve() {
    const moves = this.settle();
    if (moves.length > 0) this.startFalling(moves);
    else this.checkMatches();
  }

  startFalling(moves) {
    this.moves = moves;
    const far = moves.reduce((m, move) => Math.max(m, move.distance), 0);
    this.events.push({ type: 'fell', moves });
    this.enterPhase('settling', this.config.fallBaseSeconds + this.config.fallSecondsPerRootCell * Math.sqrt(far) + this.config.fallBounceSeconds);
    this.makeRoom();
  }

  checkMatches() {
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
    this.cleared += match.cells.size;
    this.activeMatch = match;
    this.events.push({ type: 'matched', combo: this.combo, score, match });
    this.enterPhase('matching', this.config.matchSeconds);
  }

  completePhase() {
    switch (this.phase) {
      case 'dropping': {
        const { piece } = this.drop;
        this.drop = null;
        this.commit(piece, true);
        break;
      }
      case 'matching':
        this.enterPhase('clearing', this.config.clearSeconds);
        break;
      case 'clearing': {
        const match = this.activeMatch;
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

  finishResolution() {
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

  enterPhase(phase, duration) {
    this.phase = phase;
    this.phaseElapsed = 0;
    this.phaseDuration = duration;
  }

  endGame(side) {
    this.gameOverSide = side;
    this.inputs.length = 0;
    this.enterPhase('gameOver', 0);
    this.events.push({ type: 'gameEnded', side });
  }

  /** Fills the bottom rows of the picture, each cell with one to three
   * blocks at random depths, so that something waits behind what is seen.
   * The colours that are seen make no line. */
  fillForTesting(rows = 3) {
    const half = this.half;
    const palette = this.config.numberOfColors;
    const pick = (count) => Math.floor(this.random() * count);
    const seenColor = (sx, sy) => {
      const p = this.seenAt(sx, sy);
      return p ? this.hub.at(p) : EMPTY;
    };
    for (let sy = -half; sy < -half + rows; sy++) {
      for (let sx = -half; sx <= half; sx++) {
        if (this.seenAt(sx, sy) !== null) continue;
        if (sy > -half && this.seenAt(sx, sy - 1) === null) continue;
        if (this.random() < (sy === -half + rows - 1 ? 0.5 : 0.12)) continue;
        // Depths, nearest first; the nearest gets a colour that makes no line.
        const depths = [...Array(2 * half + 1).keys()].map((d) => d - half).sort(() => this.random() - 0.5);
        const count = 1 + pick(3);
        const chosen = depths.slice(0, count).sort((a, b) => b - a);
        const start = pick(palette);
        let front = start;
        for (let k = 0; k < palette; k++) {
          const c = (start + k) % palette;
          const line = (dx, dy) => seenColor(sx - dx, sy - dy) === c && seenColor(sx - 2 * dx, sy - 2 * dy) === c;
          if (!line(1, 0) && !line(0, 1)) {
            front = c;
            break;
          }
        }
        chosen.forEach((d, i) => this.hub.set(this.cellAt(sx, sy, d), i === 0 ? front : pick(palette)));
      }
    }
    this.makeRoom();
  }
}
