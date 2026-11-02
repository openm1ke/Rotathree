// The rules of a 3D RotaThree, mirrored from webapp/src/game where they carry
// over: six glasses (arms) along ±x, ±y, ±z share a cube of a centre, a stick
// of three falls down each glass one whole cell per step, the active glass
// steps fast, a stick that cannot step locks, lines of three or more of a
// colour along x, y or z pop, the blocks of the active glass fall towards its
// floor (the far wall of the centre), cascades repeat, and a glass whose far
// end is full when a new stick is due ends the game.
//
// Everything here is in the fixed data frame: cells are integer [x, y, z] in
// an N³ grid, N = centre + 2·arm. Turning the hub only changes which glass is
// active; the renderer turns the picture.

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
  /** Side of the shared centre cube, and the cross-section of every arm. */
  centre: 4,
  /** Length of each arm, in cells. A glass is one arm plus the centre. */
  arm: 6,
  pieceLength: 3,
  numberOfColors: 4,
  minMatchLength: 3,
  activeStepSeconds: 1,
  inactiveStepSeconds: 3,
  /** Sticks in the five other glasses step too (slowly) — the 2D rule. Off
   * by default here: they wait where they are. */
  inactiveFalls: false,
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

/** Lines of `minLength`+ cells of one colour along x, y or z, anywhere in
 * the hub. Cells outside the hub are always empty, so they end a line. */
export function findMatches(hub, minLength = 3) {
  const runs = [];
  const n = hub.size;
  for (let axis = 0; axis < 3; axis++) {
    const [k1, k2] = [0, 1, 2].filter((i) => i !== axis);
    for (let i = 0; i < n; i++) {
      for (let j = 0; j < n; j++) {
        const cell = (t) => {
          const p = [0, 0, 0];
          p[axis] = t;
          p[k1] = i;
          p[k2] = j;
          return p;
        };
        let start = 0;
        while (start < n) {
          const color = hub.at(cell(start));
          let end = start + 1;
          if (color !== EMPTY) {
            while (end < n && hub.at(cell(end)) === color) end++;
            if (end - start >= minLength) {
              const cells = [];
              for (let t = start; t < end; t++) cells.push(hub.index(cell(t)));
              runs.push({ color, cells, axis });
            }
          }
          start = end;
        }
      }
    }
  }
  return { runs, cells: new Set(runs.flatMap((run) => run.cells)) };
}

/** Plain gravity in the active glass: every block of it falls towards its
 * floor until it rests. Blocks in the other five arms never move. Mutates
 * `hub` and returns what moved. */
export function settle(hub, active) {
  const depth = hub.depth();
  const moves = [];
  for (let a = 0; a < hub.centre; a++) {
    for (let b = 0; b < hub.centre; b++) {
      let target = depth - 1;
      for (let row = depth - 1; row >= 0; row--) {
        const from = hub.toWorld(active, row, a, b);
        const color = hub.at(from);
        if (color === EMPTY) continue;
        if (target !== row) {
          const to = hub.toWorld(active, target, a, b);
          hub.set(from, EMPTY);
          hub.set(to, color);
          moves.push({ from, to, color, distance: target - row });
        }
        target--;
      }
    }
  }
  return moves;
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
    this.active = 0;
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
    /** Data-frame vectors of the screen's right and far directions, set by
     * the view; a new stick lies along whichever crosses its glass. */
    this.viewFrame = { right: [1, 0, 0], far: [0, 0, -1] };
    for (let i = 0; i < 2; i++) this.queue.push(this.roll());
    for (const s of SIDES) this.spawn(s.id);
  }

  get activePiece() {
    return this.pieces.get(this.active);
  }

  get isGameOver() {
    return this.phase === 'gameOver';
  }

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

  fits(side, pivot, dir, colors = [0, 0, 0]) {
    return pieceCells({ pivot, dir, colors }).every(({ p }) => this.hub.isFreeIn(side, p));
  }

  /** The axis a new stick of `side` lies along: the screen's right if it
   * crosses the glass, else the screen's far direction. */
  spawnDir(side) {
    const n = normalOf(side);
    const { right, far } = this.viewFrame;
    return dot(right, n) === 0 ? [...right] : [...far];
  }

  /** Puts a new stick at the far end of the glass. False when it does not
   * fit there — the game is over. */
  spawn(side) {
    const colors = this.queue.shift();
    this.queue.push(this.roll());
    const dir = this.spawnDir(side);
    const lane = Math.floor((this.config.centre - 1) / 2);
    let pivot = this.hub.toWorld(side, 0, lane, lane);
    // A stick lying along the second cross axis keeps its lane centred too.
    if (!this.fits(side, pivot, dir)) {
      const other = this.hub.toWorld(side, 0, lane + 1, lane + 1);
      if (this.fits(side, other, dir)) pivot = other;
      else return false;
    }
    this.pieces.set(side, { side, colors, pivot, dir, progress: 0 });
    return true;
  }

  restRow(piece) {
    const fall = fallOf(piece.side);
    let pivot = piece.pivot;
    while (this.fits(piece.side, add(pivot, fall), piece.dir)) pivot = add(pivot, fall);
    return pivot;
  }

  /** Where the active stick would land: its cells, or null. */
  ghost(side = this.active) {
    const piece = this.pieces.get(side);
    if (!piece) return null;
    return pieceCells({ ...piece, pivot: this.restRow(piece) });
  }

  // --------------------------------------------------------------- input

  submit(input) {
    if (this.isGameOver) return;
    if (this.phase === 'playing') {
      this.apply(input);
      return;
    }
    // Hard drops are never buffered; everything else is replayed after.
    if (input.kind === 'drop') return;
    if (this.inputs.length < this.config.maxQueuedInputs) this.inputs.push(input);
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

  /** Makes another glass the active one (the hub has been turned). */
  switchTo(side) {
    this.submit({ kind: 'switch', side });
  }

  apply(input) {
    const piece = this.activePiece;
    switch (input.kind) {
      case 'switch':
        if (input.side !== this.active) {
          const from = this.active;
          this.active = input.side;
          this.events.push({ type: 'switched', from, to: input.side });
        }
        return;
      case 'move': {
        if (!piece) return;
        const to = add(piece.pivot, input.vector);
        const ok = dot(input.vector, normalOf(piece.side)) === 0 && this.fits(piece.side, to, piece.dir);
        if (ok) piece.pivot = to;
        this.events.push({ type: 'moved', blocked: !ok });
        return;
      }
      case 'rotate': {
        if (!piece) return;
        const dir = cross(input.axis, piece.dir);
        if (isZero(dir)) {
          // A turn about the stick's own length changes nothing.
          this.events.push({ type: 'rotated', blocked: true });
          return;
        }
        // Nudges tried when the turn does not fit, gentlest first: across the
        // glass, then back towards its far end, then down.
        const [u, v] = this.hub.crossAxes(piece.side).map((k) => {
          const e = [0, 0, 0];
          e[k] = 1;
          return e;
        });
        const up = normalOf(piece.side);
        const kicks = [
          [0, 0, 0], scale(u, -1), u, scale(v, -1), v, up, scale(up, -1),
          scale(u, -2), scale(u, 2), scale(v, -2), scale(v, 2), scale(up, 2),
        ];
        for (const kick of kicks) {
          const pivot = add(piece.pivot, kick);
          if (this.fits(piece.side, pivot, dir)) {
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

  flushInputs() {
    while (this.inputs.length > 0 && this.phase === 'playing') this.apply(this.inputs.shift());
  }

  // ---------------------------------------------------------------- time

  stepSeconds(piece) {
    return piece.side === this.active ? this.config.activeStepSeconds : this.config.inactiveStepSeconds;
  }

  update(seconds) {
    if (this.isGameOver || seconds <= 0) return;
    if (this.phase === 'playing') {
      for (const piece of this.pieces.values()) {
        if (piece.side !== this.active && !this.config.inactiveFalls) continue;
        piece.progress = Math.min(1, piece.progress + seconds / this.stepSeconds(piece));
      }
      this.stepDuePieces();
      return;
    }
    if (!this.config.pauseIncomingDuringCascade) {
      for (const piece of this.pieces.values()) {
        if (piece.side !== this.active && !this.config.inactiveFalls) continue;
        piece.progress = Math.min(1, piece.progress + seconds / this.stepSeconds(piece));
      }
    }
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
   * just appeared may sit inside one; it backs off towards its own far end.
   * False when one has nowhere to go: game over. */
  makeRoom() {
    for (const piece of this.pieces.values()) {
      const back = normalOf(piece.side);
      let pivot = piece.pivot;
      while (!this.fits(piece.side, pivot, piece.dir)) {
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

  checkMatches() {
    const match = findMatches(this.hub, this.config.minMatchLength);
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
        const moves = settle(this.hub, this.active);
        if (moves.length === 0) {
          this.checkMatches();
        } else {
          this.moves = moves;
          const far = moves.reduce((m, move) => Math.max(m, move.distance), 0);
          this.events.push({ type: 'fell', moves });
          this.enterPhase('settling', this.config.fallBaseSeconds + this.config.fallSecondsPerRootCell * Math.sqrt(far) + this.config.fallBounceSeconds);
          this.makeRoom();
        }
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

  /** Fills the lower part of the centre (seen from the active glass) with
   * random blocks that make no line, to try x-ray and depth on a busy
   * board. */
  fillForTesting(layers = this.config.centre - 1) {
    const hub = this.hub;
    const depth = hub.depth();
    const palette = this.config.numberOfColors;
    const makesLine = (p, color) => {
      for (let axis = 0; axis < 3; axis++) {
        let count = 1;
        for (const sign of [-1, 1]) {
          const q = [...p];
          for (;;) {
            q[axis] += sign;
            if (!hub.isInside(q) || hub.at(q) !== color) break;
            count++;
          }
        }
        if (count >= this.config.minMatchLength) return true;
      }
      return false;
    };
    for (let row = depth - 1; row >= depth - layers; row--) {
      for (let a = 0; a < hub.centre; a++) {
        for (let b = 0; b < hub.centre; b++) {
          const p = hub.toWorld(this.active, row, a, b);
          if (hub.at(p) !== EMPTY) continue;
          const below = hub.toWorld(this.active, row + 1, a, b);
          if (row < depth - 1 && hub.at(below) === EMPTY) continue;
          // Leave some holes so the stack has a shape to aim at.
          if (row === depth - layers && this.random() < 0.45) continue;
          const start = Math.floor(this.random() * palette);
          for (let k = 0; k < palette; k++) {
            const color = (start + k) % palette;
            if (!makesLine(p, color)) {
              hub.set(p, color);
              break;
            }
          }
        }
      }
    }
    this.makeRoom();
  }
}
