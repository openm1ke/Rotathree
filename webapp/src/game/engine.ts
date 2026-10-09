import { Board } from './board';
import { clearMatch, scoreFor } from './cascade';
import { GLASS_ORDER, dropSeconds, fallPhaseSeconds, sidesInPlay, type GameConfig } from './config';
import { PieceGenerator } from './generator';
import { settle, type BlockMove } from './gravity';
import { IncomingController, type IncomingPiece } from './incoming';
import { findMatches, type MatchResult } from './matchDetector';
import { fits, headroom, placementAt, type PlacedCell, type Placement } from './placement';
import { stepsTo, turned, type Side } from './side';
import { makePiece, type BlockColor, type Orientation, type Piece } from './piece';
import { integer, list, number, record } from './snapshotReader';

/** Explicit phases of the engine. Input is applied in `playing`; movement
 * and turns can be queued during resolution, but hard drops are never buffered. */
export type GamePhase =
  /** Pieces fall; the player can switch, move, rotate and drop. */
  | 'playing'
  /** A hard-dropped piece is flying to its resting place. */
  | 'pieceDropping'
  /** The match made by a placement is flashing. */
  | 'matching'
  /** Matched cells are popping. */
  | 'clearing'
  /** Blocks are falling into the freed space. */
  | 'settling'
  /** A follow-up match (combo ×2 and up) is flashing. */
  | 'cascading'
  /** A new glass is being built; its first piece appears at the end. */
  | 'building'
  | 'gameOver';

/** Things that happened inside the engine, for the renderer to react to. */
export type GameEvent =
  | { type: 'sideSwitched'; from: Side; to: Side; quarterTurns: number }
  | { type: 'pieceMoved'; side: Side; direction: number; blocked: boolean }
  | { type: 'pieceRotated'; side: Side; blocked: boolean }
  | { type: 'pieceStepped'; side: Side }
  | { type: 'pieceDropped'; side: Side; cells: number }
  | { type: 'pieceLanded'; placement: Placement; dropped: boolean }
  | { type: 'matchScored'; combo: number; score: number; match: MatchResult }
  | { type: 'cellsPopped'; cells: PlacedCell[] }
  | { type: 'blocksFell'; moves: BlockMove[] }
  | { type: 'glassAdded'; side: Side }
  | { type: 'speedUp'; level: number; activeStep: number; inactiveStep: number }
  | { type: 'gameEnded'; side: Side };

/** A speed that rises with the score: every `everyPoints` the step times are
 * multiplied by `factor`, never going below the minimums. */
export interface SpeedRamp {
  everyPoints: number;
  factor: number;
  minActive: number;
  minInactive: number;
}

/** A hard-dropped piece on its way to where it lands. */
export interface DropInFlight {
  placement: Placement;
  /** Row of the piece's top square when the drop began. */
  startRow: number;
}

/** Everything the renderer needs to draw a frame. Owned by the engine. */
export interface GameState {
  board: Board;
  /** The piece currently falling down each glass in play. */
  incoming: Map<Side, IncomingPiece>;
  activeSide: Side;
  phase: GamePhase;
  phaseElapsed: number;
  phaseDuration: number;
  score: number;
  /** Combo level of the chain being resolved (0 when idle). */
  combo: number;
  bestCombo: number;
  /** Number of matched lines popped so far. */
  matches: number;
  clearedCells: number;
  piecesPlaced: number;
  /** Pieces that locked on their own, without a hard drop. */
  selfLocked: number;
  elapsedSeconds: number;
  drop: DropInFlight | null;
  /** Cells flashing (matching / cascading) or popping (clearing). */
  activeMatch: MatchResult | null;
  /** Blocks falling during `settling`; the board already holds them at
   * their destination. */
  moves: BlockMove[];
  /** The glass being built during `building`. */
  buildingSide: Side | null;
  /** How many speed-ups the score has earned (0 without a ramp). */
  speedLevel: number;
  /** The glass that overflowed, once the game is over. */
  gameOverSide: Side | null;
}

type Input =
  | { kind: 'turn'; quarterTurns: number }
  | { kind: 'activate'; side: Side }
  | { kind: 'move'; delta: number }
  | { kind: 'rotate'; clockwise: boolean }
  | { kind: 'drop' };

const EPSILON = 1e-9;

/** The whole game, independent of the DOM.
 *
 * Rules in short:
 *  * the playfield is a cross: a central square and four arms. Each side
 *    owns a glass — its arm plus the central square — and the glasses share
 *    the centre. One to four of them are in play; the arms of the rest do
 *    not exist yet, and a glass can be added during play;
 *  * the pieces fall at the same time, one per glass, a whole cell per
 *    step — quickly in the active glass, slowly in the others — through the
 *    arm and on through the centre. A piece whose next step is blocked by
 *    the floor of its glass or by a block locks instead;
 *  * the player turns the cross to pick the active glass, slides and
 *    rotates its piece and can drop it;
 *  * lines of 3+ of a colour pop, the blocks above them fall towards the
 *    bottom of the screen and cascades raise the combo multiplier;
 *  * a glass that is full up to the far end of its arm ends the game.
 *
 * Time only moves through `update`. */
export class GameEngine {
  /** Step times may change during a game (see `setSteps` and `setRamp`). */
  config: GameConfig;
  readonly incoming: IncomingController;
  /** The glasses in play, in the order they came into play. */
  sides: Side[];
  state!: GameState;

  /** Saves timed phases and queued input as well as the visible field. */
  snapshot(): Record<string, unknown> {
    const s = this.state;
    const cells: number[][] = [];
    this.board.forEachBlock((row, col, color) => cells.push([row, col, color]));
    return {
      version: 1,
      center: this.board.center,
      arm: this.board.arm,
      board: cells,
      sides: [...this.sides],
      activeSide: this.activeSide,
      incoming: [...this.incoming.pieces.values()].map((p) => ({
        ...p,
        piece: { ...p.piece, colors: [...p.piece.colors] },
      })),
      phase: s.phase,
      phaseElapsed: s.phaseElapsed,
      phaseDuration: s.phaseDuration,
      score: s.score,
      combo: s.combo,
      bestCombo: s.bestCombo,
      matches: s.matches,
      clearedCells: s.clearedCells,
      piecesPlaced: s.piecesPlaced,
      selfLocked: s.selfLocked,
      elapsedSeconds: s.elapsedSeconds,
      dropCooldown: Math.min(GameEngine.DROP_DEBOUNCE_SECONDS, Math.max(0, this.dropReadyAt - s.elapsedSeconds)),
      speedLevel: s.speedLevel,
      buildingSide: s.buildingSide,
      drop:
        s.drop == null
          ? null
          : {
              side: s.drop.placement.side,
              piece: s.drop.placement.piece,
              column: s.drop.placement.column,
              row: s.drop.placement.row,
              startRow: s.drop.startRow,
            },
      moves: s.moves.map((m) => [m.from.row, m.from.col, m.to.row, m.to.col, m.color]),
      waiting: [...this.awaitingPiece],
      inputs: this.inputs.map((input) => ({ ...input })),
      activeStep: this.config.activeStepSeconds,
      inactiveStep: this.config.inactiveStepSeconds,
      rampBaseActive: this.rampBase.active,
      rampBaseInactive: this.rampBase.inactive,
      randomSeed: this.incoming.generator.seed,
      generated: this.incoming.generator.generated,
    };
  }

  restoreSnapshot(raw: unknown): void {
    const r = record(raw);
    if (r.version !== 1 || r.center !== this.board.center || r.arm !== this.board.arm)
      throw new Error('Incompatible save');
    const board = new Board(this.board.center, this.board.arm);
    const occupied = new Set<number>();
    for (const rawCell of list(r.board, board.size * board.size)) {
      const c = list(rawCell, 3);
      if (c.length !== 3) throw new Error('Invalid saved cell');
      const row = integer(c[0], 0, board.size - 1),
        col = integer(c[1], 0, board.size - 1);
      const color = integer(c[2], 0, this.config.numberOfColors - 1);
      if (!board.isInside(row, col) || occupied.has(board.index(row, col))) throw new Error('Invalid saved board');
      occupied.add(board.index(row, col));
      board.set(row, col, color);
    }
    const side = (raw: unknown): Side => integer(raw, 0, 3) as Side;
    const piece = (raw: unknown): Piece => {
      const p = record(raw),
        colors = list(p.colors, this.config.pieceLength);
      if (colors.length !== this.config.pieceLength) throw new Error('Invalid saved piece');
      return makePiece(
        colors.map((c) => integer(c, 0, this.config.numberOfColors - 1) as BlockColor),
        integer(p.orientation, 0, 3) as Orientation,
      );
    };
    const sides = list(r.sides, 4).map(side),
      active = side(r.activeSide);
    if (sides.length === 0 || new Set(sides).size !== sides.length || !sides.includes(active))
      throw new Error('Invalid saved glasses');
    const phases: GamePhase[] = [
      'playing',
      'pieceDropping',
      'matching',
      'clearing',
      'settling',
      'cascading',
      'building',
    ];
    if (!phases.includes(r.phase as GamePhase)) throw new Error('Invalid saved phase');
    const phase = r.phase as GamePhase;
    const elapsed = number(r.phaseElapsed, 0, 60),
      duration = number(r.phaseDuration, 0, 60);
    if (elapsed > duration) throw new Error('Invalid phase time');
    const incoming: IncomingPiece[] = list(r.incoming, 4).map((raw) => {
      const p = record(raw),
        s = side(p.side),
        shape = piece(p.piece);
      const row = integer(p.row, 0, this.config.armLength + this.config.boardSize - 1);
      const column = integer(p.column, 0, this.config.boardSize - 1);
      if (!sides.includes(s) || !fits(board, s, shape, row, column)) throw new Error('Invalid incoming piece');
      return { side: s, piece: shape, row, column, stepProgress: number(p.stepProgress, 0, 1) };
    });
    if (new Set(incoming.map((p) => p.side)).size !== incoming.length) throw new Error('Duplicate incoming piece');
    let drop: DropInFlight | null = null;
    if (r.drop !== null) {
      const d = record(r.drop),
        s = side(d.side),
        shape = piece(d.piece);
      const row = integer(d.row, 0, this.config.armLength + this.config.boardSize - 1);
      const col = integer(d.column, 0, this.config.boardSize - 1);
      if (!sides.includes(s) || !fits(board, s, shape, row, col)) throw new Error('Invalid saved drop');
      drop = { placement: placementAt(board, s, shape, col, row), startRow: integer(d.startRow, 0, row) };
    }
    if ((phase === 'pieceDropping') !== (drop !== null)) throw new Error('Missing saved drop');
    const activeMatch = ['matching', 'clearing', 'cascading'].includes(phase)
      ? findMatches(board, this.config.minMatchLength)
      : null;
    if (activeMatch !== null && activeMatch.runs.length === 0) throw new Error('Missing saved match');
    const buildingSide = r.buildingSide === null ? null : side(r.buildingSide);
    if (phase === 'building' && (buildingSide === null || !sides.includes(buildingSide)))
      throw new Error('Invalid building glass');
    const moves: BlockMove[] = list(r.moves, board.size * board.size).map((raw) => {
      const m = list(raw, 5);
      if (m.length !== 5) throw new Error('Invalid saved move');
      const from = { row: integer(m[0], 0, board.size - 1), col: integer(m[1], 0, board.size - 1) };
      const to = { row: integer(m[2], 0, board.size - 1), col: integer(m[3], 0, board.size - 1) };
      if (!board.isInside(from.row, from.col) || !board.isInside(to.row, to.col)) throw new Error('Invalid saved move');
      return {
        from,
        to,
        color: integer(m[4], 0, this.config.numberOfColors - 1) as BlockColor,
        distance: Math.abs(to.row - from.row) + Math.abs(to.col - from.col),
      };
    });
    const waiting = list(r.waiting, 4).map(side);
    if (waiting.some((s) => !sides.includes(s))) throw new Error('Invalid waiting glass');
    const inputs: Input[] = list(r.inputs, this.config.maxQueuedInputs).map((raw) => {
      const i = record(raw);
      switch (i.kind) {
        case 'turn':
          return { kind: 'turn', quarterTurns: integer(i.quarterTurns, -2, 2) };
        case 'activate':
          return { kind: 'activate', side: side(i.side) };
        case 'move':
          return { kind: 'move', delta: integer(i.delta, -this.config.boardSize, this.config.boardSize) };
        case 'rotate':
          if (typeof i.clockwise !== 'boolean') throw new Error('Invalid rotation');
          return { kind: 'rotate', clockwise: i.clockwise };
        case 'drop':
          return { kind: 'drop' };
        default:
          throw new Error('Invalid saved input');
      }
    });
    const partition = [
      ...incoming.map((p) => p.side),
      ...waiting,
      ...(drop ? [drop.placement.side] : []),
      ...(phase === 'building' ? [buildingSide!] : []),
    ];
    if (partition.length !== sides.length || new Set(partition).size !== sides.length)
      throw new Error('Incomplete saved glasses');
    const steps = { active: number(r.activeStep, 0.01, 60), inactive: number(r.inactiveStep, 0.01, 60) };
    const base = { active: number(r.rampBaseActive, 0.01, 60), inactive: number(r.rampBaseInactive, 0.01, 60) };
    const seed = integer(r.randomSeed, 0, 0xffffffff),
      generated = integer(r.generated, 0, 100000);
    const restored: GameState = {
      board,
      incoming: this.incoming.pieces,
      activeSide: active,
      phase,
      phaseElapsed: elapsed,
      phaseDuration: duration,
      score: integer(r.score),
      combo: integer(r.combo),
      bestCombo: integer(r.bestCombo),
      matches: integer(r.matches),
      clearedCells: integer(r.clearedCells),
      piecesPlaced: integer(r.piecesPlaced),
      selfLocked: integer(r.selfLocked),
      elapsedSeconds: number(r.elapsedSeconds),
      speedLevel: integer(r.speedLevel),
      buildingSide,
      drop,
      activeMatch,
      moves,
      gameOverSide: null,
    };
    const dropCooldown = number(r.dropCooldown ?? 0, 0, GameEngine.DROP_DEBOUNCE_SECONDS);
    this.setSteps(steps.active, steps.inactive);
    this.rampBase = base;
    this.incoming.generator.restore(seed, generated);
    this.incoming.pieces.clear();
    for (const p of incoming) this.incoming.pieces.set(p.side, p);
    this.incoming.softDrop = false;
    this.sides = sides;
    this.awaitingPiece.length = 0;
    this.awaitingPiece.push(...waiting);
    this.inputs.length = 0;
    // Older saves may contain a second drop buffered for the next piece.
    this.inputs.push(...inputs.filter((input) => input.kind !== 'drop'));
    this.events = [];
    this.state = restored;
    this.dropReadyAt = restored.elapsedSeconds + dropCooldown;
  }

  private readonly startConfig: GameConfig;
  private readonly inputs: Input[] = [];
  private static readonly DROP_DEBOUNCE_SECONDS = 0.3;
  private dropReadyAt = 0;
  private events: GameEvent[] = [];
  /** Glasses whose piece has locked and that get a new one as soon as the
   * board has come to rest. */
  private awaitingPiece: Side[] = [];
  private ramp: SpeedRamp | null = null;
  private rampBase = { active: 1, inactive: 3 };

  constructor(config: GameConfig, random?: () => number) {
    this.startConfig = config;
    this.config = config;
    this.incoming = new IncomingController(config, new PieceGenerator(config, random));
    this.sides = sidesInPlay(config);
    this.restart();
  }

  get board(): Board {
    return this.state.board;
  }

  get activeSide(): Side {
    return this.state.activeSide;
  }

  get phase(): GamePhase {
    return this.state.phase;
  }

  get isGameOver(): boolean {
    return this.state.phase === 'gameOver';
  }

  get activePiece(): IncomingPiece | undefined {
    return this.incoming.pieceAt(this.state.activeSide);
  }

  /** True while falling pieces are frozen for a match or a new glass. */
  get incomingPaused(): boolean {
    const phase = this.state.phase;
    return (
      this.config.pauseIncomingDuringCascade &&
      (phase === 'matching' ||
        phase === 'clearing' ||
        phase === 'settling' ||
        phase === 'cascading' ||
        phase === 'building')
    );
  }

  restart(): void {
    this.config = this.startConfig;
    this.rampBase = { active: this.config.activeStepSeconds, inactive: this.config.inactiveStepSeconds };
    this.sides = sidesInPlay(this.startConfig);
    this.incoming.setConfig(this.config);
    this.inputs.length = 0;
    this.dropReadyAt = 0;
    this.events = [];
    this.awaitingPiece = [];
    this.incoming.reset(this.sides);
    this.state = {
      board: new Board(this.config.boardSize, this.config.armLength),
      incoming: this.incoming.pieces,
      activeSide: this.sides[0],
      phase: 'playing',
      phaseElapsed: 0,
      phaseDuration: 0,
      score: 0,
      combo: 0,
      bestCombo: 0,
      matches: 0,
      clearedCells: 0,
      piecesPlaced: 0,
      selfLocked: 0,
      elapsedSeconds: 0,
      drop: null,
      activeMatch: null,
      moves: [],
      buildingSide: null,
      speedLevel: 0,
      gameOverSide: null,
    };
  }

  /** Returns the events raised since the last call and forgets them. */
  drainEvents(): GameEvent[] {
    const events = this.events;
    this.events = [];
    return events;
  }

  // ------------------------------------------------------------- settings

  /** Changes the step times from now on. Pieces keep their progress. */
  setSteps(activeStepSeconds: number, inactiveStepSeconds: number): void {
    this.config = { ...this.config, activeStepSeconds, inactiveStepSeconds };
    this.incoming.setConfig(this.config);
  }

  /** Makes the speed rise with the score (or stops it when null). The
   * current step times are the ones it starts from. */
  setRamp(ramp: SpeedRamp | null): void {
    this.ramp = ramp;
    this.rampBase = { active: this.config.activeStepSeconds, inactive: this.config.inactiveStepSeconds };
    this.state.speedLevel = 0;
  }

  /** Brings the next glass into play: its arm grows, and its first piece
   * appears at the far end when the building phase is over. Returns the
   * glass, or null when all four are in play or the board is busy. */
  addGlass(): Side | null {
    if (this.state.phase !== 'playing') return null;
    const side = GLASS_ORDER.find((candidate) => !this.sides.includes(candidate));
    if (side === undefined) return null;
    this.sides = [...this.sides, side];
    this.state.buildingSide = side;
    this.enterPhase('building', this.config.buildSeconds);
    return side;
  }

  // ------------------------------------------------------------- queries

  /** Where the piece of `side` comes to rest if it falls straight down from
   * where it is; null when that glass has no piece at the moment. */
  previewDrop(side: Side): Placement | null {
    const piece = this.incoming.pieceAt(side);
    if (!piece) return null;
    return placementAt(
      this.state.board,
      side,
      piece.piece,
      piece.column,
      this.incoming.restRow(piece, this.state.board),
    );
  }

  /** The row where the piece of `side` comes to rest if it falls straight
   * down; null when that glass has no piece at the moment. */
  restRow(side: Side): number | null {
    const piece = this.incoming.pieceAt(side);
    return piece ? this.incoming.restRow(piece, this.state.board) : null;
  }

  /** Seconds until the piece of `side` locks if it is left alone. */
  secondsToLock(side: Side): number | null {
    const piece = this.incoming.pieceAt(side);
    return piece ? this.incoming.secondsToLock(piece, this.state.board, this.state.activeSide) : null;
  }

  /** Free rows at the far end of the glass of `side`, in the lanes where its
   * pieces appear. At 0 the next piece has no room and the game ends. */
  headroom(side: Side): number {
    return headroom(this.state.board, side, this.incoming.spawnColumn, this.config.pieceLength);
  }

  /** True when the glass of `side` is close to overflowing. */
  isCrowded(side: Side): boolean {
    return this.headroom(side) <= this.config.crowdedHeadroom;
  }

  // ---------------------------------------------------------------- input

  /** Turns the cross: ±1 goes on to the next glass in play, 2 goes to the
   * glass opposite if there is one. */
  switchSide(quarterTurns: number): void {
    this.submit({ kind: 'turn', quarterTurns });
  }

  /** Makes `side` the active one, turning the short way round. */
  activateSide(side: Side): void {
    this.submit({ kind: 'activate', side });
  }

  /** Slides the active piece across its glass. */
  moveActive(delta: number): void {
    this.submit({ kind: 'move', delta });
  }

  /** Turns the active piece a quarter turn. */
  rotateActive(clockwise = true): void {
    this.submit({ kind: 'rotate', clockwise });
  }

  /** Sends the active piece straight down to where it lands. */
  dropActive(): void {
    this.submit({ kind: 'drop' });
  }

  /** Holds or releases soft drop: while held, the active piece steps fast. */
  setSoftDrop(held: boolean): void {
    this.incoming.softDrop = held;
  }

  private submit(input: Input): void {
    if (this.isGameOver) return;
    // A hard drop belongs to the visible piece, never to the next spawn.
    // Debounce also covers double taps when a short flight has already ended.
    if (
      input.kind === 'drop' &&
      (this.state.phase !== 'playing' || this.inputs.length > 0 || this.state.elapsedSeconds < this.dropReadyAt)
    ) return;
    if (this.state.phase === 'playing' && this.inputs.length === 0) {
      this.apply(input);
      return;
    }
    if (this.inputs.length < this.config.maxQueuedInputs) this.inputs.push(input);
  }

  private flushInputs(): void {
    while (this.inputs.length > 0 && this.state.phase === 'playing') {
      this.apply(this.inputs.shift()!);
    }
  }

  private apply(input: Input): void {
    const side = this.state.activeSide;
    switch (input.kind) {
      case 'turn':
        this.turnTo(this.sideAfter(side, input.quarterTurns));
        break;
      case 'activate':
        if (this.sides.includes(input.side)) this.turnTo(input.side);
        break;
      case 'move': {
        if (!this.incoming.pieceAt(side)) break;
        const moved = this.incoming.move(side, input.delta, this.state.board);
        this.events.push({
          type: 'pieceMoved',
          side,
          direction: Math.sign(input.delta),
          blocked: moved < Math.abs(input.delta),
        });
        break;
      }
      case 'rotate': {
        if (!this.incoming.pieceAt(side)) break;
        const ok = this.incoming.rotate(side, this.state.board, input.clockwise);
        this.events.push({ type: 'pieceRotated', side, blocked: !ok });
        break;
      }
      case 'drop':
        this.beginDrop();
        break;
    }
  }

  /** The glass a turn of `quarterTurns` leads to from `side`. A single step
   * skips the sides that are not in play; any other turn only happens when a
   * glass is exactly there. */
  private sideAfter(side: Side, quarterTurns: number): Side {
    if (Math.abs(quarterTurns) !== 1) {
      const to = turned(side, quarterTurns);
      return this.sides.includes(to) ? to : side;
    }
    let to = turned(side, quarterTurns);
    while (!this.sides.includes(to)) to = turned(to, quarterTurns);
    return to;
  }

  private turnTo(to: Side): void {
    const from = this.state.activeSide;
    if (to === from) return;
    this.state.activeSide = to;
    // The cross always turns the short way round.
    this.events.push({ type: 'sideSwitched', from, to, quarterTurns: stepsTo(from, to) });

    // By default the structure turns as one rigid body and nothing falls.
    if (!this.config.settleAfterBoardRotation) return;
    const moves = settle(this.state.board, to);
    if (moves.length === 0) return;
    this.state.combo = 0;
    this.startFalling(moves);
  }

  // ----------------------------------------------------------------- time

  /** Advances the game by `seconds` of game time. */
  update(seconds: number): void {
    let left = seconds;
    while (left > EPSILON && !this.isGameOver) {
      if (this.state.phase === 'playing') {
        const next = this.incoming.secondsToNextStep(this.state.activeSide, this.state.board);
        if (next === null || next > left) {
          this.advanceClock(left);
          left = 0;
        } else {
          this.advanceClock(next);
          left -= next;
          this.stepDuePieces();
        }
      } else {
        const remaining = this.state.phaseDuration - this.state.phaseElapsed;
        const step = Math.min(left, Math.max(remaining, 0));
        this.state.phaseElapsed += step;
        this.advanceClock(step);
        left -= step;
        if (this.state.phaseElapsed >= this.state.phaseDuration - EPSILON) this.completePhase();
      }
    }
  }

  private advanceClock(seconds: number): void {
    this.state.elapsedSeconds += seconds;
    if (!this.incomingPaused) {
      this.incoming.advance(seconds, this.state.activeSide, this.state.board);
    }
  }

  /** Every piece whose step is due moves one row down. The first one that
   * cannot move locks where it is; the board then changes, so any others
   * still due wait until play resumes. */
  private stepDuePieces(): void {
    for (const side of this.incoming.dueSides(this.state.activeSide)) {
      if (this.incoming.step(side, this.state.board)) {
        this.events.push({ type: 'pieceStepped', side });
        continue;
      }
      const piece = this.incoming.take(side)!;
      this.state.selfLocked++;
      this.commit(placementAt(this.state.board, side, piece.piece, piece.column, piece.row), false);
      return;
    }
  }

  private beginDrop(): void {
    const piece = this.activePiece;
    if (!piece) return;
    this.dropReadyAt = this.state.elapsedSeconds + GameEngine.DROP_DEBOUNCE_SECONDS;
    const placement = this.previewDrop(piece.side)!;
    this.incoming.take(piece.side);
    const cells = placement.row - piece.row;
    this.state.drop = { placement, startRow: piece.row };
    this.events.push({ type: 'pieceDropped', side: piece.side, cells });
    this.enterPhase('pieceDropping', dropSeconds(this.config, cells));
  }

  /** Writes a piece into the board and resolves what follows from it. */
  private commit(placement: Placement, dropped: boolean): void {
    for (const cell of placement.cells) this.state.board.set(cell.row, cell.col, cell.color);
    this.state.piecesPlaced++;
    this.state.combo = 0;
    this.awaitingPiece.push(placement.side);
    this.events.push({ type: 'pieceLanded', placement, dropped });
    if (!this.makeRoomForFallingPieces()) return;
    this.checkMatches();
  }

  /** Falling pieces pass through each other, so a block that has just
   * appeared may sit inside one of them; such a piece backs off towards its
   * own arm. Returns false when one of them has nowhere to go: game over. */
  private makeRoomForFallingPieces(): boolean {
    const crushed = this.incoming.resolveOverlaps(this.state.board);
    if (crushed.length === 0) return true;
    this.endGame(crushed[0]);
    return false;
  }

  private completePhase(): void {
    const state = this.state;
    switch (state.phase) {
      case 'pieceDropping': {
        const drop = state.drop!;
        state.drop = null;
        this.commit(drop.placement, true);
        break;
      }
      case 'matching':
      case 'cascading':
        this.enterPhase('clearing', this.config.clearSeconds);
        break;
      case 'clearing': {
        const match = state.activeMatch!;
        const size = state.board.size;
        this.events.push({
          type: 'cellsPopped',
          cells: [...match.cells].map((index) => ({
            row: Math.floor(index / size),
            col: index % size,
            color: state.board.atIndex(index) as PlacedCell['color'],
          })),
        });
        clearMatch(state.board, match);
        state.activeMatch = null;
        const moves = settle(state.board, state.activeSide, this.config.gravityScope, match.cells);
        if (moves.length === 0) this.checkMatches();
        else this.startFalling(moves);
        break;
      }
      case 'settling':
        state.moves = [];
        this.checkMatches();
        break;
      case 'building': {
        const side = state.buildingSide!;
        state.buildingSide = null;
        // The arm is empty, so the first piece always finds room.
        this.incoming.spawn(side, state.board);
        this.events.push({ type: 'glassAdded', side });
        this.enterPhase('playing', 0);
        this.flushInputs();
        break;
      }
      default:
        break;
    }
  }

  /** Blocks have been moved to where they fall; show them falling. */
  private startFalling(moves: BlockMove[]): void {
    this.state.moves = moves;
    const furthest = moves.reduce((far, move) => Math.max(far, move.distance), 0);
    this.events.push({ type: 'blocksFell', moves });
    this.enterPhase('settling', fallPhaseSeconds(this.config, furthest));
    this.makeRoomForFallingPieces();
  }

  private checkMatches(): void {
    const state = this.state;
    const match = findMatches(state.board, this.config.minMatchLength);
    if (match.runs.length === 0) {
      this.finishResolution();
      return;
    }
    state.combo++;
    if (state.combo > state.bestCombo) state.bestCombo = state.combo;
    const score = scoreFor(this.config, match, state.combo);
    state.score += score;
    state.matches += match.runs.length;
    state.clearedCells += match.cells.size;
    state.activeMatch = match;
    this.events.push({ type: 'matchScored', combo: state.combo, score, match });
    this.applyRamp();
    this.enterPhase(state.combo === 1 ? 'matching' : 'cascading', this.config.matchSeconds);
  }

  /** Steps the speed up when the score has passed another multiple of the
   * ramp's interval. */
  private applyRamp(): void {
    const ramp = this.ramp;
    if (!ramp) return;
    const level = Math.floor(this.state.score / ramp.everyPoints);
    if (level === this.state.speedLevel) return;
    this.state.speedLevel = level;
    const factor = Math.pow(ramp.factor, level);
    const activeStep = Math.max(ramp.minActive, this.rampBase.active * factor);
    const inactiveStep = Math.max(ramp.minInactive, this.rampBase.inactive * factor);
    this.setSteps(activeStep, inactiveStep);
    this.events.push({ type: 'speedUp', level, activeStep, inactiveStep });
  }

  private finishResolution(): void {
    this.state.combo = 0;
    this.enterPhase('playing', 0);

    // The board is at rest: refill the glasses whose piece has locked.
    const waiting = this.awaitingPiece;
    this.awaitingPiece = [];
    for (const side of waiting) {
      if (this.incoming.spawn(side, this.state.board) === null) {
        this.endGame(side);
        return;
      }
    }
    // Queued input next, so a move typed during the animation still counts.
    this.flushInputs();
  }

  private enterPhase(phase: GamePhase, duration: number): void {
    this.state.phase = phase;
    this.state.phaseElapsed = 0;
    this.state.phaseDuration = duration;
  }

  private endGame(side: Side): void {
    this.state.gameOverSide = side;
    this.inputs.length = 0;
    this.enterPhase('gameOver', 0);
    this.events.push({ type: 'gameEnded', side });
  }
}
