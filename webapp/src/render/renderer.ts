import { EMPTY } from '../game/board';
import { fallSeconds, gridSize, type GameConfig } from '../game/config';
import type { GameEngine, GameState } from '../game/engine';
import { worldToView } from '../game/glass';
import type { IncomingPiece } from '../game/incoming';
import { pieceDepth, pieceOffsets, pieceWidth, type BlockColor } from '../game/piece';
import { SIDES, type Side } from '../game/side';
import type { Effects } from './effects';
import { BLOCK_TONES, THEME, rgba, tonesOf } from './theme';

const QUARTER = Math.PI / 2;

/** The cross is drawn a touch smaller than its canvas so that glows and the
 * recoil of a hard drop are not clipped at the edges. */
const FIT = 0.965;

/** Where a click landed, in the turned view: a screen slot (0 = the active
 * arm on top, then clockwise), the centre, or nothing. */
export type ClickZone = Side | 'center' | null;

/** Draws the whole playfield on a 2D canvas: four glasses sharing the
 * central square, their falling pieces, settled blocks and every effect.
 *
 * Everything is drawn in cell units, in the world frame of the cross, and
 * turned as a whole by the view angle. The game model itself never rotates. */
export class GameRenderer {
  private readonly ctx: CanvasRenderingContext2D;
  private cssSize = 0;
  private dpr = 1;
  private sprites: HTMLCanvasElement[] = [];
  private spriteSize = 0;

  constructor(private readonly canvas: HTMLCanvasElement) {
    this.ctx = canvas.getContext('2d')!;
  }

  /** Sets the square canvas to `cssSize` logical pixels. */
  resize(cssSize: number, dpr: number): void {
    this.cssSize = cssSize;
    this.dpr = dpr;
    const pixels = Math.max(1, Math.round(cssSize * dpr));
    if (this.canvas.width !== pixels) this.canvas.width = pixels;
    if (this.canvas.height !== pixels) this.canvas.height = pixels;
  }

  /** Which part of the cross is under a point of the canvas (CSS pixels). */
  zoneAt(x: number, y: number, config: GameConfig): ClickZone {
    const cell = (this.cssSize / gridSize(config)) * FIT;
    const cx = (x - this.cssSize / 2) / cell;
    const cy = (y - this.cssSize / 2) / cell;
    const half = config.boardSize / 2;
    const reach = half + config.armLength;
    if (Math.abs(cx) <= half && Math.abs(cy) <= half) return 'center';
    if (Math.abs(cx) <= half && Math.abs(cy) <= reach) return cy < 0 ? 0 : 2;
    if (Math.abs(cy) <= half && Math.abs(cx) <= reach) return cx > 0 ? 1 : 3;
    return null;
  }

  draw(engine: GameEngine, fx: Effects): void {
    const { ctx } = this;
    const config = engine.config;
    const state = engine.state;
    const cell = this.cssSize / gridSize(config);
    if (cell <= 0) return;
    this.ensureSprites(Math.round(cell * this.dpr));

    const view: View = {
      n: config.boardSize,
      arm: config.armLength,
      half: config.boardSize / 2,
      reach: config.boardSize / 2 + config.armLength,
      grid: gridSize(config),
      px: 1 / (cell * FIT),
      turns: fx.targetTurns,
    };

    ctx.setTransform(this.dpr, 0, 0, this.dpr, 0, 0);
    ctx.clearRect(0, 0, this.cssSize, this.cssSize);
    ctx.save();
    ctx.translate(
      this.cssSize / 2 + (fx.kickX + fx.shakeX) * cell,
      this.cssSize / 2 + (fx.kickY + fx.shakeY) * cell,
    );
    const scale = cell * FIT * fx.viewScale;
    ctx.scale(scale, scale);
    ctx.rotate(fx.viewAngle);

    this.drawField(view);
    this.drawActiveGlass(view, fx);
    for (const side of SIDES) this.drawCrowdedWarning(view, engine, fx, side);
    for (const beam of fx.beams) this.drawBeam(view, beam);
    for (const piece of state.incoming.values()) this.drawAim(view, engine, fx, piece);
    this.drawSettled(view, engine, fx);
    this.drawRings(view, fx);
    this.drawParticles(fx);
    for (const piece of state.incoming.values()) this.drawIncoming(view, engine, fx, piece);
    this.drawDrop(view, state);
    ctx.restore();

    for (const piece of state.incoming.values()) this.drawCountdown(view, engine, fx, piece, cell);
  }

  // ------------------------------------------------------------- sprites

  /** One pre-rendered block per colour: flat, with a lit top edge and a
   * shaded bottom one. */
  private ensureSprites(size: number): void {
    if (size === this.spriteSize && this.sprites.length > 0) return;
    this.spriteSize = size;
    this.sprites = BLOCK_TONES.map((tones) => {
      const sprite = document.createElement('canvas');
      sprite.width = sprite.height = Math.max(4, size);
      const g = sprite.getContext('2d')!;
      const s = sprite.width;
      const pad = s * 0.045;
      const side = s - pad * 2;
      const radius = s * 0.16;

      const body = g.createLinearGradient(0, pad, 0, pad + side);
      body.addColorStop(0, tones.light);
      body.addColorStop(0.3, tones.base);
      body.addColorStop(1, tones.dark);
      g.fillStyle = body;
      roundedRect(g, pad, pad, side, side, radius);
      g.fill();

      // A flat face set into the bevel.
      const inset = s * 0.16;
      g.fillStyle = tones.base;
      roundedRect(g, inset, inset, s - inset * 2, s - inset * 2, radius * 0.6);
      g.fill();

      // A soft highlight across the top of the face.
      const shine = g.createLinearGradient(0, inset, 0, s - inset);
      shine.addColorStop(0, 'rgba(255, 255, 255, 0.38)');
      shine.addColorStop(0.5, 'rgba(255, 255, 255, 0)');
      g.fillStyle = shine;
      roundedRect(g, inset, inset, s - inset * 2, s - inset * 2, radius * 0.6);
      g.fill();
      return sprite;
    });
  }

  /** Draws one block centred at (`x`, `y`). `quarter` is the extra turn of
   * the canvas at this point, so the block's lit edge ends up facing the top
   * of the screen however the cross is turned. */
  private block(
    view: View,
    color: BlockColor,
    x: number,
    y: number,
    quarter: number,
    options: { scaleX?: number; scaleY?: number; alpha?: number; flash?: number } = {},
  ): void {
    const { ctx } = this;
    const { scaleX = 1, scaleY = 1, alpha = 1, flash = 0 } = options;
    ctx.save();
    ctx.translate(x, y);
    if (scaleX !== 1 || scaleY !== 1) ctx.scale(scaleX, scaleY);
    ctx.rotate(-(view.turns + quarter) * QUARTER);
    ctx.globalAlpha = alpha;
    ctx.drawImage(this.sprites[color], -0.5, -0.5, 1, 1);
    if (flash > 0) {
      ctx.globalAlpha = Math.min(1, flash) * alpha;
      ctx.fillStyle = '#ffffff';
      roundedRect(ctx, -0.455, -0.455, 0.91, 0.91, 0.15);
      ctx.fill();
    }
    ctx.restore();
  }

  // ------------------------------------------------------------- playfield

  private drawField(view: View): void {
    const { ctx } = this;
    const { n, arm, half, reach, px } = view;

    for (const side of SIDES) {
      ctx.save();
      ctx.rotate(side * QUARTER);
      ctx.fillStyle = 'rgba(255, 255, 255, 0.022)';
      ctx.fillRect(-half, -reach, n, arm);
      ctx.beginPath();
      for (let i = 1; i < n; i++) {
        ctx.moveTo(-half + i, -reach);
        ctx.lineTo(-half + i, -half);
      }
      for (let j = 1; j < arm; j++) {
        ctx.moveTo(-half, -reach + j);
        ctx.lineTo(half, -reach + j);
      }
      ctx.strokeStyle = 'rgba(255, 255, 255, 0.045)';
      ctx.lineWidth = px;
      ctx.stroke();
      ctx.restore();
    }

    ctx.fillStyle = 'rgba(255, 255, 255, 0.05)';
    ctx.fillRect(-half, -half, n, n);
    ctx.beginPath();
    for (let i = 1; i < n; i++) {
      ctx.moveTo(-half + i, -half);
      ctx.lineTo(-half + i, half);
      ctx.moveTo(-half, -half + i);
      ctx.lineTo(half, -half + i);
    }
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.07)';
    ctx.lineWidth = px;
    ctx.stroke();

    // Outline of the whole cross, and of the centre a little brighter.
    ctx.beginPath();
    ctx.moveTo(-half, -reach);
    ctx.lineTo(half, -reach);
    ctx.lineTo(half, -half);
    ctx.lineTo(reach, -half);
    ctx.lineTo(reach, half);
    ctx.lineTo(half, half);
    ctx.lineTo(half, reach);
    ctx.lineTo(-half, reach);
    ctx.lineTo(-half, half);
    ctx.lineTo(-reach, half);
    ctx.lineTo(-reach, -half);
    ctx.lineTo(-half, -half);
    ctx.closePath();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.16)';
    ctx.lineWidth = 1.5 * px;
    ctx.stroke();
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.22)';
    ctx.strokeRect(-half, -half, n, n);
  }

  /** The active glass is one tall well — its arm and the central square —
   * open at the top, with bright walls and a heavy floor. */
  private drawActiveGlass(view: View, fx: Effects): void {
    const { ctx } = this;
    const { n, arm, half, reach, px } = view;
    for (const side of SIDES) {
      const lit = fx.activeness[side];
      if (lit < 0.01) continue;
      ctx.save();
      ctx.rotate(side * QUARTER);

      const fill = ctx.createLinearGradient(0, -reach, 0, half);
      fill.addColorStop(0, rgba(THEME.accent, 0.13 * lit));
      fill.addColorStop(1, rgba(THEME.accent, 0.035 * lit));
      ctx.fillStyle = fill;
      ctx.fillRect(-half, -reach, n, arm + n);

      ctx.shadowColor = rgba(THEME.accent, 0.9 * lit);
      ctx.shadowBlur = 18;
      ctx.strokeStyle = `rgba(240, 250, 255, ${0.95 * lit})`;
      ctx.lineJoin = 'round';
      ctx.lineWidth = 2.2 * px;
      ctx.beginPath();
      ctx.moveTo(-half, -reach);
      ctx.lineTo(-half, half);
      ctx.lineTo(half, half);
      ctx.lineTo(half, -reach);
      ctx.stroke();
      ctx.lineWidth = 4.5 * px;
      ctx.beginPath();
      ctx.moveTo(-half, half);
      ctx.lineTo(half, half);
      ctx.stroke();
      ctx.restore();
    }
  }

  /** A glass that is nearly full up to its far end pulses red there. */
  private drawCrowdedWarning(view: View, engine: GameEngine, fx: Effects, side: Side): void {
    if (engine.isGameOver ? engine.state.gameOverSide !== side : !engine.isCrowded(side)) return;
    const { ctx } = this;
    const { n, arm, half, reach, px } = view;
    const pulse = engine.isGameOver ? 1 : 0.5 + 0.5 * Math.sin(fx.clock * 9);
    ctx.save();
    ctx.rotate(side * QUARTER);
    const wash = ctx.createLinearGradient(0, -reach, 0, -half);
    wash.addColorStop(0, rgba(THEME.danger, 0.1 + 0.2 * pulse));
    wash.addColorStop(1, rgba(THEME.danger, 0.02));
    ctx.fillStyle = wash;
    ctx.fillRect(-half, -reach, n, arm);
    ctx.shadowColor = rgba(THEME.danger, 1);
    ctx.shadowBlur = 14;
    ctx.strokeStyle = rgba(THEME.danger, 0.5 + 0.5 * pulse);
    ctx.lineWidth = 3 * px;
    ctx.beginPath();
    ctx.moveTo(-half, -reach);
    ctx.lineTo(half, -reach);
    ctx.stroke();
    ctx.restore();
  }

  /** The streak a hard drop leaves down its lane. */
  private drawBeam(view: View, beam: Effects['beams'][number]): void {
    const { ctx } = this;
    const { half, reach } = view;
    const t = beam.age / beam.life;
    const fade = (1 - t) * (1 - t);
    const left = -half + beam.column;
    const top = -reach + beam.fromRow;
    const bottom = -reach + beam.toRow;
    if (bottom <= top) return;
    ctx.save();
    ctx.rotate(beam.side * QUARTER);
    const streak = ctx.createLinearGradient(0, top, 0, bottom);
    streak.addColorStop(0, 'rgba(255, 255, 255, 0)');
    streak.addColorStop(1, `rgba(255, 255, 255, ${0.34 * fade})`);
    ctx.fillStyle = streak;
    ctx.fillRect(left, top, beam.width, bottom - top);
    ctx.restore();
  }

  /** Where a piece will land: the lane of the active one, and an outline of
   * its resting place. Pieces nobody is steering only show theirs when they
   * are about to lock. */
  private drawAim(view: View, engine: GameEngine, fx: Effects, piece: IncomingPiece): void {
    const placement = engine.previewDrop(piece.side);
    if (!placement || placement.row === piece.row || engine.isGameOver) return;
    const lit = fx.activeness[piece.side];
    const urgent = (engine.secondsToLock(piece.side) ?? 99) < 6;
    const strength = Math.max(lit, urgent ? 0.4 : 0.16);

    const { ctx } = this;
    const { half, reach, px } = view;
    const left = -half + piece.column;
    const width = pieceWidth(piece.piece);
    const top = -reach + piece.row - fx.slideLeft(piece) + pieceDepth(piece.piece);
    const bottom = -reach + placement.row;

    ctx.save();
    ctx.rotate(piece.side * QUARTER);
    if (lit > 0.05 && bottom > top) {
      const lane = ctx.createLinearGradient(0, top, 0, bottom);
      lane.addColorStop(0, `rgba(255, 255, 255, ${0.02 * lit})`);
      lane.addColorStop(1, `rgba(255, 255, 255, ${0.085 * lit})`);
      ctx.fillStyle = lane;
      ctx.fillRect(left, top, width, bottom - top);
    }
    const offsets = pieceOffsets(piece.piece);
    offsets.forEach((offset, i) => {
      const tones = tonesOf(piece.piece.colors[i]);
      const x = left + offset.col + 0.07;
      const y = -reach + placement.row + offset.row + 0.07;
      roundedRect(ctx, x, y, 0.86, 0.86, 0.14);
      ctx.fillStyle = rgba(tones.rgb, 0.14 * strength);
      ctx.fill();
      ctx.strokeStyle = rgba(tones.rgb, 0.9 * strength);
      ctx.lineWidth = 1.6 * px;
      ctx.stroke();
    });
    ctx.restore();
  }

  // ----------------------------------------------------------------- blocks

  private drawSettled(view: View, engine: GameEngine, fx: Effects): void {
    const { ctx } = this;
    const state = engine.state;
    const board = state.board;
    const origin = -view.grid / 2;
    const matched = state.activeMatch?.cells;
    const moving = new Set(state.moves.map((move) => board.index(move.to.row, move.to.col)));

    // Cells still reacting to a landing are drawn in their own pass.
    const landing = new Map<number, Effects['landings'][number]>();
    for (const effect of fx.landings) {
      for (const cell of effect.placement.cells) {
        const index = board.index(cell.row, cell.col);
        if (board.atIndex(index) === cell.color && !matched?.has(index) && !moving.has(index)) {
          landing.set(index, effect);
        }
      }
    }

    board.forEachBlock((row, col, color) => {
      const index = board.index(row, col);
      if (matched?.has(index) || moving.has(index) || landing.has(index)) return;
      this.block(view, color, origin + col + 0.5, origin + row + 0.5, 0);
    });

    // Falling: each block accelerates over its own distance, so short falls
    // land first, and wobbles once when it arrives.
    if (state.moves.length > 0) {
      const side = state.activeSide;
      ctx.save();
      ctx.rotate(side * QUARTER);
      for (const move of state.moves) {
        const from = worldToView(move.from.row, move.from.col, side, board.size);
        const to = worldToView(move.to.row, move.to.col, side, board.size);
        const flight = fallSeconds(engine.config, move.distance);
        const t = Math.min(1, state.phaseElapsed / flight);
        const row = from.row + (to.row - from.row) * t * t;
        let scaleX = 1;
        let scaleY = 1 + 0.12 * Math.sin(t * Math.PI);
        if (t >= 1) {
          const b = Math.min(1, (state.phaseElapsed - flight) / engine.config.fallBounceSeconds);
          const wave = Math.sin(b * Math.PI) * (1 - b);
          scaleY = 1 - 0.3 * wave;
          scaleX = 1 + 0.16 * wave;
        }
        this.block(
          view,
          move.color,
          origin + to.col + 0.5,
          origin + row + 0.5 + 0.44 * (1 - Math.min(scaleY, 1)),
          side,
          { scaleX, scaleY },
        );
      }
      ctx.restore();
    }

    // Match: flash to white and swell, then collapse while shards fly off.
    if (matched && matched.size > 0) {
      const t = state.phaseDuration > 0 ? Math.min(1, state.phaseElapsed / state.phaseDuration) : 1;
      const popping = state.phase === 'clearing';
      const scale = popping ? 1.22 * Math.max(0, 1 - t * 1.7) : 1 + 0.22 * (1 - (1 - t) * (1 - t));
      const flash = popping ? 1 : 0.3 + 0.7 * t;
      if (scale > 0.01) {
        for (const index of matched) {
          const color = board.atIndex(index);
          if (color === EMPTY) continue;
          const row = Math.floor(index / board.size);
          const col = index % board.size;
          this.block(view, color as BlockColor, origin + col + 0.5, origin + row + 0.5, 0, {
            scaleX: scale,
            scaleY: scale,
            flash,
          });
        }
      }
    }

    // Landing: a white flash, and after a hard drop a squash along the fall.
    for (const effect of fx.landings) {
      const u = effect.age / effect.life;
      const wave = effect.dropped ? Math.sin(u * Math.PI * 2) * (1 - u) : 0;
      const scaleY = 1 - 0.26 * wave;
      const scaleX = 1 + 0.15 * wave;
      const side = effect.placement.side;
      ctx.save();
      ctx.rotate(side * QUARTER);
      for (const cell of effect.placement.cells) {
        if (landing.get(board.index(cell.row, cell.col)) !== effect) continue;
        const local = worldToView(cell.row, cell.col, side, board.size);
        this.block(
          view,
          cell.color,
          origin + local.col + 0.5,
          origin + local.row + 0.5 + 0.44 * (1 - Math.min(scaleY, 1)),
          side,
          { scaleX, scaleY, flash: 0.85 * (1 - u) * (1 - u) },
        );
      }
      ctx.restore();
    }
  }

  private drawRings(view: View, fx: Effects): void {
    const { ctx } = this;
    for (const ring of fx.rings) {
      const t = ring.age / ring.life;
      const eased = 1 - (1 - t) * (1 - t);
      ctx.beginPath();
      ctx.arc(ring.x, ring.y, 0.3 + ring.reach * eased, 0, Math.PI * 2);
      ctx.strokeStyle = rgba(ring.color, 0.75 * (1 - t));
      ctx.lineWidth = Math.max(view.px, 0.16 * (1 - t));
      ctx.stroke();
    }
  }

  private drawParticles(fx: Effects): void {
    const { ctx } = this;
    for (const particle of fx.particles) {
      const strength = 1 - particle.age / particle.life;
      const size = particle.size * (0.4 + 0.6 * strength);
      ctx.globalAlpha = strength;
      ctx.fillStyle = particle.color;
      ctx.fillRect(particle.x - size / 2, particle.y - size / 2, size, size);
    }
    ctx.globalAlpha = 1;
  }

  private drawIncoming(view: View, engine: GameEngine, fx: Effects, piece: IncomingPiece): void {
    const { ctx } = this;
    const { half, reach, px } = view;
    const side = piece.side;
    const lit = fx.activeness[side];
    const secondsLeft = engine.secondsToLock(side) ?? 0;
    const urgent = secondsLeft < 3;

    const top = -reach + piece.row - fx.slideLeft(piece);
    const left = -half + piece.column;
    const width = pieceWidth(piece.piece);
    const depth = pieceDepth(piece.piece);

    ctx.save();
    ctx.rotate(side * QUARTER);

    // Halo: white for the piece being steered, coloured when time runs out.
    const strength = Math.max(lit, urgent ? 0.85 : 0);
    if (strength > 0.02) {
      const color = urgent && lit < 0.5 ? urgencyColor(secondsLeft) : '240, 250, 255';
      const pulse = urgent && lit < 0.5 ? 0.6 + 0.4 * Math.sin(fx.clock * 10) : 1;
      ctx.shadowColor = rgba(color, 0.9 * strength);
      ctx.shadowBlur = 14;
      ctx.strokeStyle = rgba(color, 0.95 * strength * pulse);
      ctx.lineWidth = 1.8 * px;
      roundedRect(ctx, left - 0.03, top - 0.03, width + 0.06, depth + 0.06, 0.2);
      ctx.stroke();
      ctx.shadowBlur = 0;
    }

    pieceOffsets(piece.piece).forEach((offset, i) => {
      this.block(view, piece.piece.colors[i], left + offset.col + 0.5, top + offset.row + 0.5, side);
    });
    ctx.restore();
  }

  /** A hard-dropped piece streaking down to where it lands. */
  private drawDrop(view: View, state: GameState): void {
    const drop = state.drop;
    if (!drop) return;
    const { ctx } = this;
    const { half, reach } = view;
    const t = state.phaseDuration > 0 ? Math.min(1, state.phaseElapsed / state.phaseDuration) : 1;
    const row = drop.startRow + (drop.placement.row - drop.startRow) * t * t;
    const piece = drop.placement.piece;
    const side = drop.placement.side;
    const left = -half + drop.placement.column;
    const top = -reach + row;

    ctx.save();
    ctx.rotate(side * QUARTER);
    pieceOffsets(piece).forEach((offset, i) => {
      this.block(view, piece.colors[i], left + offset.col + 0.5, top + offset.row + 0.5, side, {
        scaleY: 1 + 0.18 * t,
        flash: 0.25 * t,
      });
    });
    ctx.restore();
  }

  /** Seconds until a piece locks by itself, written upright beside it. */
  private drawCountdown(
    view: View,
    engine: GameEngine,
    fx: Effects,
    piece: IncomingPiece,
    cell: number,
  ): void {
    if (engine.isGameOver) return;
    const secondsLeft = engine.secondsToLock(piece.side) ?? 0;
    const lit = fx.activeness[piece.side];
    // The piece being steered only needs its timer when it is about to lock.
    if (lit > 0.5 && secondsLeft >= 3) return;

    // A point just beyond the left end of the piece, in its glass's frame…
    const localX = -view.half + piece.column - 0.75;
    const localY = -view.reach + piece.row - fx.slideLeft(piece) + pieceDepth(piece.piece) / 2;
    // …turned with its glass and with the cross into screen pixels.
    const angle = fx.viewAngle + piece.side * QUARTER;
    const scale = cell * FIT * fx.viewScale;
    const x = this.cssSize / 2 + (fx.kickX + fx.shakeX) * cell +
      (localX * Math.cos(angle) - localY * Math.sin(angle)) * scale;
    const y = this.cssSize / 2 + (fx.kickY + fx.shakeY) * cell +
      (localX * Math.sin(angle) + localY * Math.cos(angle)) * scale;

    const { ctx } = this;
    const urgent = secondsLeft < 3;
    ctx.font = `${urgent ? 800 : 600} ${Math.max(10, cell * 0.72)}px "Exo 2", system-ui, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = urgent ? rgba(urgencyColor(secondsLeft), 1) : rgba(THEME.text, 0.42);
    ctx.fillText(secondsLeft < 10 ? secondsLeft.toFixed(1) : String(Math.round(secondsLeft)), x, y);
  }
}

/** Measurements shared by the drawing passes, in cells. */
interface View {
  n: number;
  arm: number;
  half: number;
  reach: number;
  grid: number;
  /** One CSS pixel. */
  px: number;
  /** The quarter turn the cross is settling on. */
  turns: number;
}

const urgencyColor = (secondsLeft: number): string =>
  secondsLeft < 1.5 ? THEME.danger : THEME.warning;

function roundedRect(
  ctx: CanvasRenderingContext2D,
  x: number,
  y: number,
  width: number,
  height: number,
  radius: number,
): void {
  const r = Math.min(radius, width / 2, height / 2);
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + width, y, x + width, y + height, r);
  ctx.arcTo(x + width, y + height, x, y + height, r);
  ctx.arcTo(x, y + height, x, y, r);
  ctx.arcTo(x, y, x + width, y, r);
  ctx.closePath();
}
