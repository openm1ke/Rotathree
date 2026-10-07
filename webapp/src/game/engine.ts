import { Board } from './board';
import { clearMatch, scoreFor } from './cascade';
import { dropSeconds, fallPhaseSeconds, sidesInPlay, type GameConfig } from './config';
import { PieceGenerator } from './generator';
import { settle, type BlockMove } from './gravity';
import { IncomingController, type IncomingPiece } from './incoming';
import { findMatches, type MatchResult } from './matchDetector';
import { headroom, placementAt, type PlacedCell, type Placement } from './placement';
import { stepsTo, turned, type Side } from './side';

/** Explicit phases of the engine. Player input is only applied in
 * `playing`; in every other phase it is queued and replayed afterwards, so
 * rotation, drops, pops and gravity can never interleave. */
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
  | { type: 'gameEnded'; side: Side };

/** A hard-dropped piece on its way to where it lands. */
export interface DropInFlight {
  placement: Placement;
  /** Row of the piece's top square when the drop began. */
  startRow: number;
}

/** Everything the renderer needs to draw a frame. Owned by the engine. */
export interface GameState {
  board: Board;
  /** The piece currently falling down each glass. */
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
 *    owns a glass — its arm plus the central square — and the glasses
 *    share the centre. Two to four of them are in play; the arms of the
 *    rest do not exist;
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
  readonly incoming: IncomingController;
  /** The glasses in play, in the order TOP → RIGHT → BOTTOM → LEFT. */
  readonly sides: readonly Side[];
  state!: GameState;

  private readonly inputs: Input[] = [];
  private events: GameEvent[] = [];
  /** Glasses whose piece has locked and that get a new one as soon as the
   * board has come to rest. */
  private awaitingPiece: Side[] = [];

  constructor(
    readonly config: GameConfig,
    random?: () => number,
  ) {
    this.sides = sidesInPlay(config);
    this.incoming = new IncomingController(config, new PieceGenerator(config, random));
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

  /** True while falling pieces are frozen for a match animation. */
  get incomingPaused(): boolean {
    const phase = this.state.phase;
    return (
      this.config.pauseIncomingDuringCascade &&
      (phase === 'matching' || phase === 'clearing' || phase === 'settling' || phase === 'cascading')
    );
  }

  restart(): void {
    this.inputs.length = 0;
    this.events = [];
    this.awaitingPiece = [];
    this.incoming.reset();
    this.state = {
      board: new Board(this.config.boardSize, this.config.armLength),
      incoming: this.incoming.pieces,
      activeSide: 0,
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
      gameOverSide: null,
    };
  }

  /** Returns the events raised since the last call and forgets them. */
  drainEvents(): GameEvent[] {
    const events = this.events;
    this.events = [];
    return events;
  }

  // -------------------------------------------------------------- queries

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

  /** Seconds until the piece of `side` locks if it is left alone. */
  secondsToLock(side: Side): number | null {
    const piece = this.incoming.pieceAt(side);
    return piece ? this.incoming.secondsToLock(piece, this.state.board, this.state.activeSide) : null;
  }

  /** Free rows at the far end of the glass of `side`, in the lanes where
   * its pieces appear. At 0 the next piece has no room and the game ends. */
  headroom(side: Side): number {
    return headroom(this.state.board, side, this.incoming.spawnColumn, this.config.pieceLength);
  }

  /** True when the glass of `side` is close to overflowing. */
  isCrowded(side: Side): boolean {
    return this.headroom(side) <= this.config.crowdedHeadroom;
  }

  // ---------------------------------------------------------------- input

  /** Turns the cross: ±1 goes on round TOP → RIGHT → BOTTOM → LEFT to the
   * next glass in play, 2 goes to the glass opposite if there is one. */
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
   * skips the sides that are not in play; any other turn only happens when
   * a glass is exactly there. */
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
    this.enterPhase(state.combo === 1 ? 'matching' : 'cascading', this.config.matchSeconds);
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
