import type { Board } from './board';
import { spawnColumnOf, type GameConfig } from './config';
import type { PieceGenerator } from './generator';
import { isHorizontal, pieceWidth, rotatePiece, type Piece } from './piece';
import { fits, landingRow } from './placement';
import { SIDES, type Side } from './side';

/** A stick falling down one of the four glasses, one whole cell at a time. */
export interface IncomingPiece {
  readonly side: Side;
  piece: Piece;
  /** Leftmost lane across the glass, in the frame of its own side. */
  column: number;
  /** Row of the piece's top square, counted from the far end of its glass. */
  row: number;
  /** How far the wait for its next step has got, 0..1. A fraction, so that
   * it carries over when its glass becomes active or stops being active. */
  stepProgress: number;
}

/** Absorbs floating-point error when a step falls due. */
const EPSILON = 1e-9;

/** (rows, lanes) nudges tried when a rotation does not fit, gentlest first. */
const KICKS: readonly (readonly [number, number])[] = [
  [0, 0], [0, -1], [0, 1], [-1, 0], [1, 0],
  [0, -2], [0, 2], [-1, -1], [-1, 1], [-2, 0],
];

/** Owns the four independent streams of falling pieces, one per glass.
 *
 * Every piece falls along its own glass — through the arm and on through
 * the central square — one whole cell per step. Steps come quickly in the
 * active glass and slowly in the other three. A piece whose next step is
 * blocked locks instead. Falling pieces do not collide with each other,
 * only with settled blocks. */
export class IncomingController {
  readonly pieces = new Map<Side, IncomingPiece>();

  /** While true, the active piece steps at the soft-drop rate as long as
   * it has room to fall. */
  softDrop = false;

  constructor(
    private readonly config: GameConfig,
    private readonly generator: PieceGenerator,
  ) {}

  get spawnColumn(): number {
    return spawnColumnOf(this.config);
  }

  pieceAt(side: Side): IncomingPiece | undefined {
    return this.pieces.get(side);
  }

  /** Seconds between two steps of `piece` while `active` is on top. */
  stepSeconds(piece: IncomingPiece, active: Side, board: Board): number {
    if (piece.side !== active) return this.config.inactiveStepSeconds;
    // Soft drop only speeds up actual falling: a piece that has landed keeps
    // its full step to be slid or turned before it locks.
    if (this.softDrop && fits(board, piece.side, piece.piece, piece.row + 1, piece.column)) {
      return Math.min(this.config.softDropStepSeconds, this.config.activeStepSeconds);
    }
    return this.config.activeStepSeconds;
  }

  /** Starts a fresh game: one piece per glass, staggered so that TOP is the
   * furthest along and LEFT starts at the very end of its arm. */
  reset(): void {
    this.pieces.clear();
    this.softDrop = false;
    for (const side of SIDES) {
      const headStart = (SIDES.length - 1 - side) * this.config.initialProgressStagger;
      this.put(side, this.generator.next(), { row: Math.round(headStart * this.config.armLength) });
    }
  }

  /** Puts a new piece at the far end of `side`'s glass. Returns null when
   * the glass is full up to there — the game is over. */
  spawn(side: Side, board: Board): IncomingPiece | null {
    const piece = this.generator.next();
    if (!fits(board, side, piece, 0, this.spawnColumn)) return null;
    return this.put(side, piece);
  }

  /** Places a specific piece in a glass (spawning, tests). */
  put(
    side: Side,
    piece: Piece,
    at: { column?: number; row?: number; stepProgress?: number } = {},
  ): IncomingPiece {
    const maxColumn = this.config.boardSize - pieceWidth(piece);
    const incoming: IncomingPiece = {
      side,
      piece,
      column: Math.max(0, Math.min(maxColumn, at.column ?? this.spawnColumn)),
      row: at.row ?? 0,
      stepProgress: at.stepProgress ?? 0,
    };
    this.pieces.set(side, incoming);
    return incoming;
  }

  /** Removes and returns the piece of `side` (it is being locked). */
  take(side: Side): IncomingPiece | undefined {
    const piece = this.pieces.get(side);
    this.pieces.delete(side);
    return piece;
  }

  /** The row where `piece` will come to rest if nothing changes. */
  restRow(piece: IncomingPiece, board: Board): number {
    return landingRow(board, piece.side, piece.piece, piece.column, piece.row) ?? piece.row;
  }

  /** Seconds until `piece` locks by itself if it is left alone: the steps
   * down to where it rests, plus the one step it then fails to take. Soft
   * drop is ignored — this is what the countdown shows. */
  secondsToLock(piece: IncomingPiece, board: Board, active: Side): number {
    const stepsDown = this.restRow(piece, board) - piece.row;
    const interval =
      piece.side === active ? this.config.activeStepSeconds : this.config.inactiveStepSeconds;
    return (1 - piece.stepProgress + stepsDown) * interval;
  }

  /** Seconds until the first piece is due to step; null if there is none. */
  secondsToNextStep(active: Side, board: Board): number | null {
    let best: number | null = null;
    for (const piece of this.pieces.values()) {
      const left = (1 - piece.stepProgress) * this.stepSeconds(piece, active, board);
      if (best === null || left < best) best = left;
    }
    return best === null ? null : Math.max(0, best);
  }

  private isDue(side: Side): boolean {
    return (this.pieces.get(side)?.stepProgress ?? 0) >= 1 - EPSILON;
  }

  /** Sides whose piece is due to step, the active one first. */
  dueSides(active: Side): Side[] {
    const due: Side[] = [];
    if (this.isDue(active)) due.push(active);
    for (const side of SIDES) if (side !== active && this.isDue(side)) due.push(side);
    return due;
  }

  /** Lets `seconds` pass for every piece. Nothing moves here: a piece only
   * becomes due for its next step (see `step`). */
  advance(seconds: number, active: Side, board: Board): void {
    if (seconds <= 0) return;
    for (const piece of this.pieces.values()) {
      const progress = piece.stepProgress + seconds / this.stepSeconds(piece, active, board);
      piece.stepProgress = progress >= 1 - EPSILON ? 1 : progress;
    }
  }

  /** Takes the due step of the piece of `side`: one row down. Returns false
   * when that row is blocked — the piece has to lock where it is. */
  step(side: Side, board: Board): boolean {
    const piece = this.pieces.get(side);
    if (!piece) return true;
    if (!fits(board, side, piece.piece, piece.row + 1, piece.column)) return false;
    piece.row++;
    piece.stepProgress = 0;
    return true;
  }

  /** Slides the piece of `side` towards lane `column` one lane at a time,
   * stopping at the wall of the glass or at a settled block. Returns how
   * many lanes it actually moved. */
  setColumn(side: Side, column: number, board: Board): number {
    const piece = this.pieces.get(side);
    if (!piece) return 0;
    const step = column > piece.column ? 1 : -1;
    let moved = 0;
    while (piece.column !== column) {
      if (!fits(board, side, piece.piece, piece.row, piece.column + step)) break;
      piece.column += step;
      moved++;
    }
    return moved;
  }

  move(side: Side, delta: number, board: Board): number {
    const piece = this.pieces.get(side);
    if (!piece || delta === 0) return 0;
    return this.setColumn(side, piece.column + delta, board);
  }

  /** Where `piece` would be after a quarter turn around its middle square,
   * or null if it cannot turn. If it does not fit there it is nudged
   * sideways or along the glass. Does not change anything. */
  rotated(piece: IncomingPiece, board: Board, clockwise = true): IncomingPiece | null {
    const pivot = Math.floor(piece.piece.colors.length / 2);
    const turned = rotatePiece(piece.piece, clockwise);
    const lying = isHorizontal(turned);
    const column = lying ? piece.column - pivot : piece.column + pivot;
    const row = lying ? piece.row + pivot : piece.row - pivot;
    for (const [rows, lanes] of KICKS) {
      if (fits(board, piece.side, turned, row + rows, column + lanes)) {
        return {
          side: piece.side,
          piece: turned,
          column: column + lanes,
          row: row + rows,
          stepProgress: piece.stepProgress,
        };
      }
    }
    return null;
  }

  /** Turns the stick of `side` a quarter turn. The colour order never
   * changes: four turns bring the first colour to the left, the top, the
   * right and the bottom. Returns false when there is no room to turn. */
  rotate(side: Side, board: Board, clockwise = true): boolean {
    const piece = this.pieces.get(side);
    if (!piece) return false;
    const turned = this.rotated(piece, board, clockwise);
    if (!turned) return false;
    piece.piece = turned.piece;
    piece.column = turned.column;
    piece.row = turned.row;
    return true;
  }

  /** Call after settled blocks appeared in new cells (a lock, a fall). A
   * falling piece that now overlaps one of them is moved back towards the
   * far end of its own glass until it fits again. Returns the sides whose
   * piece has no room left at all. */
  resolveOverlaps(board: Board): Side[] {
    const crushed: Side[] = [];
    for (const piece of this.pieces.values()) {
      let row = piece.row;
      while (row >= 0 && !fits(board, piece.side, piece.piece, row, piece.column)) row--;
      if (row < 0) crushed.push(piece.side);
      else piece.row = row;
    }
    return crushed;
  }
}
