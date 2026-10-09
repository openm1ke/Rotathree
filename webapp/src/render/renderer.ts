import { EMPTY } from '../game/board';
import { fallSeconds, gridSize, type GameConfig } from '../game/config';
import type { GameEngine, GameState } from '../game/engine';
import { worldToView } from '../game/glass';
import type { IncomingPiece } from '../game/incoming';
import { isHorizontal, pieceDepth, pieceWidth, type BlockColor, type Piece } from '../game/piece';
import { SIDES, type Side } from '../game/side';
import type { Effects } from './effects';
import { fieldViewport } from './viewport';
import { THEME, paletteRevision, paletteTones, rgba, tonesOf } from './theme';

const QUARTER = Math.PI / 2;

/** Cosine and sine of 0, 1, 2 and 3 quarter turns, exactly. `Math.cos` of a
 * quarter turn is 6e-17, not 0, and that is enough to push every block off
 * the pixel grid. */
const QUARTER_COS = [1, 0, -1, 0] as const;
const QUARTER_SIN = [0, 1, 0, -1] as const;

/** The cross is drawn a touch smaller than its canvas so that glows and the
 * recoil of a hard drop are not clipped at the edges. */
const FIT = 0.965;

/** Blur of the glow round the active glass and round a piece, in device
 * pixels. Canvas shadows are slow, so each glow is drawn once into an image
 * and that image is drawn every frame. */
const WELL_BLUR = 18;
const HALO_BLUR = 14;

const ARM_FILL = 'rgba(255, 255, 255, 0.022)';
const ARM_GRID = 'rgba(255, 255, 255, 0.045)';
const CENTRE_FILL = 'rgba(255, 255, 255, 0.05)';
const CENTRE_GRID = 'rgba(255, 255, 255, 0.07)';
const OUTLINE = 'rgba(255, 255, 255, 0.16)';
const CENTRE_OUTLINE = 'rgba(255, 255, 255, 0.22)';
const ICE = '240, 250, 255';

/** Where a click landed, in the turned view: a screen slot (0 = the active
 * arm on top, then clockwise), the centre, or nothing. */
export type ClickZone = Side | 'center' | null;

/** A glow drawn once and reused. */
interface Glow {
  image: HTMLCanvasElement;
  /** Device pixels between the edge of the image and the origin of its shape. */
  pad: number;
}

type Landing = Effects['landings'][number];

/** Draws the whole playfield on a 2D canvas: four glasses sharing the
 * central square, their falling pieces, settled blocks and every effect.
 *
 * Everything is laid out in cell units, in the world frame of the cross, and
 * turned as a whole by the view angle. The game model itself never rotates.
 *
 * Two things keep a frame cheap. A cell is a whole number of device pixels and
 * the centre of the cross sits on a pixel boundary, so a field at rest is
 * copied block by block with no resampling. And nothing uses a canvas shadow
 * while playing: the glows are images made once (see `Glow`). */
export class GameRenderer {
  private readonly ctx: CanvasRenderingContext2D;
  private cssSize = 0;
  /** Side of the canvas in device pixels; always even. */
  private pixels = 0;

  private sprites: HTMLCanvasElement[] = [];
  private spriteSize = 0;
  private spriteRevision = -1;

  private glowKey = '';
  private well: Glow | null = null;
  private warning: Glow | null = null;
  private readonly halos = new Map<string, Glow>();

  private pathKey = '';
  private armGrid!: Path2D;
  private centreGrid!: Path2D;
  private armOutline!: Path2D;
  private wallOutline!: Path2D;
  private beamFill: CanvasGradient | null = null;
  private laneFill: CanvasGradient | null = null;

  private fontSize = -1;
  private fontCalm = '';
  private fontUrgent = '';

  // Reused by the pass that has to know which cells are in motion.
  private readonly moving = new Set<number>();
  private readonly landing = new Map<number, Landing>();

  // ------------------------------------------------ the frame being drawn
  private n = 0;
  private arm = 0;
  private half = 0;
  private reach = 0;
  private grid = 0;
  /** Device pixels to a cell while the cross is at rest; a whole number. */
  private unit = 1;
  /** One CSS pixel, in cells. */
  private px = 1;
  /** Scale and origin of the cross on the canvas, in device pixels. */
  private s = 1;
  private tx = 0;
  private ty = 0;
  /** True once a turn is over: frames are then at whole quarter turns. */
  private atRest = true;
  /** The quarter turn the cross is settling on, 0..3. */
  private turnsQ = 0;
  /** Cosine and sine of each glass's frame on the screen. */
  private readonly cos = [1, 0, -1, 0];
  private readonly sin = [0, 1, 0, -1];
  /** What is left of the turn: blocks stay upright at the end of it. */
  private dcos = 1;
  private dsin = 0;
  /** Whether the canvas is in the transform of `base()` right now. */
  private based = false;
  private visible: readonly Side[] = [];
  private viewAngle = 0;
  private grow = 1;

  constructor(private readonly canvas: HTMLCanvasElement) {
    this.ctx = canvas.getContext('2d')!;
  }

  /** Sets the square canvas to `cssSize` logical pixels, drawn at `dpr`
   * device pixels each. */
  resize(cssSize: number, dpr: number): void {
    this.cssSize = cssSize;
    // An even number keeps the centre of the cross on a pixel boundary.
    const pixels = Math.max(2, 2 * Math.round((cssSize * dpr) / 2));
    if (this.canvas.width !== pixels) this.canvas.width = pixels;
    if (this.canvas.height !== pixels) this.canvas.height = pixels;
    this.pixels = pixels;
  }

  /** Hit testing uses the exact camera transform of the last drawn frame. */
  zoneAt(x: number, y: number, config: GameConfig): ClickZone {
    if (this.cssSize <= 0) return null;
    const ratio = this.pixels / this.cssSize;
    const cx = (x * ratio - this.tx) / this.s, cy = (y * ratio - this.ty) / this.s;
    const c = Math.cos(this.viewAngle), s = Math.sin(this.viewAngle);
    const wx = c * cx + s * cy, wy = -s * cx + c * cy;
    const half = config.boardSize / 2, reach = half + config.armLength;
    if (Math.abs(wx) <= half && Math.abs(wy) <= half) return 'center';
    for (const side of this.visible) {
      const turn = side * QUARTER, cos = Math.cos(turn), sin = Math.sin(turn);
      const rx = cos * wx + sin * wy, ry = -sin * wx + cos * wy;
      if (Math.abs(rx) <= half && ry <= -half && ry >= -reach)
        return (((side + Math.round(this.viewAngle / QUARTER)) % 4 + 4) % 4) as Side;
    }
    return null;
  }

  draw(engine: GameEngine, fx: Effects, reduceMotion = false): void {
    const { ctx, pixels } = this;
    if (pixels < 2 || this.cssSize <= 0) return;
    const config = engine.config;
    const state = engine.state;
    const grid = gridSize(config);
    const viewport = fieldViewport(config.boardSize, config.armLength, engine.sides, fx.viewAngle,
      state.phase === 'building' ? state.buildingSide : null,
      state.phaseDuration > 0 ? state.phaseElapsed / state.phaseDuration : 1, reduceMotion);
    const unit = Math.max(1, Math.floor(pixels * FIT / viewport.span));
    this.grow = viewport.grow;
    this.visible = engine.sides;
    this.viewAngle = fx.viewAngle;
    const scale = pixels / this.cssSize;

    this.n = config.boardSize;
    this.arm = config.armLength;
    this.half = this.n / 2;
    this.reach = this.half + this.arm;
    this.grid = grid;
    this.unit = unit;
    this.px = scale / unit;
    this.ensureSprites(unit);
    this.ensureGlows(scale);
    this.ensurePaths();

    // Where each glass's frame points on the screen. At rest that is a whole
    // number of quarter turns, and it is written down exactly.
    const delta = fx.viewAngle - fx.targetTurns * QUARTER;
    const atRest = Math.abs(delta) < 1e-7;
    this.atRest = atRest;
    this.turnsQ = ((Math.round(fx.targetTurns) % 4) + 4) % 4;
    for (let frame = 0; frame < 4; frame++) {
      if (atRest) {
        const q = (this.turnsQ + frame) & 3;
        this.cos[frame] = QUARTER_COS[q];
        this.sin[frame] = QUARTER_SIN[q];
      } else {
        const angle = fx.viewAngle + frame * QUARTER;
        this.cos[frame] = Math.cos(angle);
        this.sin[frame] = Math.sin(angle);
      }
    }
    this.dcos = atRest ? 1 : Math.cos(delta);
    this.dsin = atRest ? 0 : Math.sin(delta);

    // Combo pulses stay inside the fitted camera and zoom about its center.
    this.s = Math.min(unit * (1 + fx.punch), pixels * 0.985 / viewport.span);
    const nudge = pixels / grid;
    this.tx = Math.round(pixels / 2 - viewport.cx * this.s) + (fx.kickX + fx.shakeX) * nudge;
    this.ty = Math.round(pixels / 2 - viewport.cy * this.s) + (fx.kickY + fx.shakeY) * nudge;

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    this.based = false;
    ctx.globalAlpha = 1;
    ctx.clearRect(0, 0, pixels, pixels);

    this.drawField(engine.sides, 1 - 0.7 * fx.turnMotion, state);
    this.drawActiveGlass(fx);
    for (const side of SIDES) this.drawCrowdedWarning(engine, fx, side);
    for (const beam of fx.beams) this.drawBeam(beam);
    for (const piece of state.incoming.values()) this.drawAim(engine, fx, piece);
    this.drawSettled(engine, fx);
    this.frame(0);
    this.drawRings(fx);
    this.drawFlashes(fx);
    this.drawParticles(fx);
    for (const piece of state.incoming.values()) this.drawIncoming(engine, fx, piece);
    this.drawDrop(state);

    ctx.setTransform(1, 0, 0, 1, 0, 0);
    for (const piece of state.incoming.values()) this.drawCountdown(engine, fx, piece, scale);
  }

  // ----------------------------------------------------------- transforms

  /** Draws in the frame of glass `frame`: its arm on top, cells as units. */
  private frame(frame: number): void {
    const { s } = this;
    const c = this.cos[frame];
    const n = this.sin[frame];
    this.ctx.setTransform(s * c, s * n, -s * n, s * c, this.tx, this.ty);
    this.based = false;
  }

  /** Draws in screen axes, cells as units: what plain blocks are copied in. */
  private base(): void {
    this.ctx.setTransform(this.s, 0, 0, this.s, this.tx, this.ty);
    this.based = true;
  }

  // ------------------------------------------------------------- sprites

  /** One pre-rendered block per colour, exactly a cell big: flat, with a lit
   * top edge and a shaded bottom one. */
  private ensureSprites(size: number): void {
    if (size === this.spriteSize && this.spriteRevision === paletteRevision()) return;
    this.spriteSize = size;
    this.spriteRevision = paletteRevision();
    this.sprites = paletteTones().map((tones) => {
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

  /** Draws one block centred at (`x`, `y`) of the frame of glass `frame`
   * (0 is the world frame). Its lit edge faces the top of the screen however
   * the cross is turned, and `scaleX`/`scaleY` stretch it along that frame's
   * axes. Sets the transform it needs. */
  private block(
    color: BlockColor,
    x: number,
    y: number,
    frame: number,
    scaleX = 1,
    scaleY = 1,
    flash = 0,
  ): void {
    const { ctx } = this;
    const c = this.cos[frame];
    const n = this.sin[frame];
    const px = c * x - n * y;
    const py = n * x + c * y;
    if (this.atRest && scaleX === 1 && scaleY === 1 && flash <= 0) {
      // The common case: a plain copy, on whole pixels when nothing shakes.
      if (!this.based) this.base();
      ctx.drawImage(this.sprites[color], px - 0.5, py - 0.5, 1, 1);
      return;
    }
    // Stretching happens along the frame's axes, which on the screen are
    // swapped when the frame ends up a quarter turn from upright.
    const swapped = ((this.turnsQ + frame) & 1) === 1;
    const sx = this.s * (swapped ? scaleY : scaleX);
    const sy = this.s * (swapped ? scaleX : scaleY);
    ctx.setTransform(
      this.dcos * sx,
      this.dsin * sx,
      -this.dsin * sy,
      this.dcos * sy,
      this.tx + this.s * px,
      this.ty + this.s * py,
    );
    ctx.drawImage(this.sprites[color], -0.5, -0.5, 1, 1);
    if (flash > 0) {
      ctx.globalAlpha = Math.min(1, flash);
      ctx.fillStyle = '#ffffff';
      roundedRect(ctx, -0.455, -0.455, 0.91, 0.91, 0.15);
      ctx.fill();
      ctx.globalAlpha = 1;
    }
    this.based = false;
  }

  // --------------------------------------------------------------- glows

  private ensureGlows(scale: number): void {
    const key = `${this.unit}:${scale}:${this.n}:${this.arm}`;
    if (key === this.glowKey) return;
    this.glowKey = key;
    this.halos.clear();
    const { unit, px, n } = this;
    const depth = this.arm + n;

    // The active glass: one tall well — its arm and the central square —
    // open at the top, with bright walls and a heavy floor.
    this.well = makeGlow(n, depth, unit, WELL_BLUR, (g) => {
      const fill = g.createLinearGradient(0, 0, 0, depth);
      fill.addColorStop(0, rgba(THEME.accent, 0.13));
      fill.addColorStop(1, rgba(THEME.accent, 0.035));
      g.fillStyle = fill;
      g.fillRect(0, 0, n, depth);

      g.shadowColor = rgba(THEME.accent, 0.9);
      g.shadowBlur = WELL_BLUR;
      g.strokeStyle = rgba(ICE, 0.95);
      g.lineJoin = 'round';
      g.lineWidth = 2.2 * px;
      g.beginPath();
      g.moveTo(0, 0);
      g.lineTo(0, depth);
      g.lineTo(n, depth);
      g.lineTo(n, 0);
      g.stroke();
      g.lineWidth = 4.5 * px;
      g.beginPath();
      g.moveTo(0, depth);
      g.lineTo(n, depth);
      g.stroke();
    });

    // The far end of a glass that is nearly full.
    this.warning = makeGlow(n, 0, unit, HALO_BLUR, (g) => {
      g.shadowColor = rgba(THEME.danger, 1);
      g.shadowBlur = HALO_BLUR;
      g.strokeStyle = rgba(THEME.danger, 1);
      g.lineWidth = 3 * px;
      g.beginPath();
      g.moveTo(0, 0);
      g.lineTo(n, 0);
      g.stroke();
    });
  }

  /** The halo round a piece `width` by `depth` cells, in colour `rgb`. */
  private halo(width: number, depth: number, rgb: string): Glow {
    const key = `${width}x${depth}:${rgb}`;
    let halo = this.halos.get(key);
    if (halo === undefined) {
      const { px } = this;
      halo = makeGlow(width, depth, this.unit, HALO_BLUR, (g) => {
        g.shadowColor = rgba(rgb, 0.9);
        g.shadowBlur = HALO_BLUR;
        g.strokeStyle = rgba(rgb, 0.95);
        g.lineWidth = 1.8 * px;
        roundedRect(g, -0.03, -0.03, width + 0.06, depth + 0.06, 0.2);
        g.stroke();
      });
      this.halos.set(key, halo);
    }
    return halo;
  }

  /** Draws a glow with its shape's origin at (`x`, `y`) of the current frame. */
  private glow(glow: Glow, x: number, y: number, alpha: number): void {
    const { ctx, unit } = this;
    const { image, pad } = glow;
    ctx.globalAlpha = Math.min(1, alpha);
    ctx.drawImage(image, x - pad / unit, y - pad / unit, image.width / unit, image.height / unit);
    ctx.globalAlpha = 1;
  }

  // ------------------------------------------------------------- playfield

  /** The lines of the field never change while the board keeps its shape. */
  private ensurePaths(): void {
    const key = `${this.n}:${this.arm}`;
    if (key === this.pathKey) return;
    this.pathKey = key;
    const { n, arm, half, reach } = this;

    this.armGrid = new Path2D();
    for (let i = 1; i < n; i++) {
      this.armGrid.moveTo(-half + i, -reach);
      this.armGrid.lineTo(-half + i, -half);
    }
    for (let j = 1; j < arm; j++) {
      this.armGrid.moveTo(-half, -reach + j);
      this.armGrid.lineTo(half, -reach + j);
    }

    this.centreGrid = new Path2D();
    for (let i = 1; i < n; i++) {
      this.centreGrid.moveTo(-half + i, -half);
      this.centreGrid.lineTo(-half + i, half);
      this.centreGrid.moveTo(-half, -half + i);
      this.centreGrid.lineTo(half, -half + i);
    }

    this.armOutline = new Path2D();
    this.armOutline.moveTo(-half, -half);
    this.armOutline.lineTo(-half, -reach);
    this.armOutline.lineTo(half, -reach);
    this.armOutline.lineTo(half, -half);

    this.wallOutline = new Path2D();
    this.wallOutline.moveTo(-half, -half);
    this.wallOutline.lineTo(half, -half);
  }

  /** The cross: the central square and the arm of every glass in play. A
   * glass being built grows out of the centre. `lines` fades the grid while
   * the cross is turning. */
  private drawField(sides: readonly Side[], lines: number, state: GameState): void {
    const { ctx, n, arm, half, reach, px } = this;
    const building = state.phase === 'building' ? state.buildingSide : null;
    const grow = this.grow;
    const far = half + arm * grow;

    ctx.lineWidth = px;
    for (const side of sides) {
      this.frame(side);
      ctx.fillStyle = ARM_FILL;
      ctx.strokeStyle = ARM_GRID;
      if (side !== building) {
        ctx.fillRect(-half, -reach, n, arm);
        ctx.globalAlpha = lines;
        ctx.stroke(this.armGrid);
      } else {
        ctx.fillRect(-half, -far, n, far - half);
        ctx.globalAlpha = lines;
        ctx.beginPath();
        for (let i = 1; i < n; i++) {
          ctx.moveTo(-half + i, -far);
          ctx.lineTo(-half + i, -half);
        }
        for (let j = 1; j < arm; j++) {
          const y = -reach + j;
          if (y < -far) continue;
          ctx.moveTo(-half, y);
          ctx.lineTo(half, y);
        }
        ctx.stroke();
      }
      ctx.globalAlpha = 1;
    }

    this.frame(0);
    ctx.fillStyle = CENTRE_FILL;
    ctx.fillRect(-half, -half, n, n);
    ctx.globalAlpha = lines;
    ctx.strokeStyle = CENTRE_GRID;
    ctx.stroke(this.centreGrid);
    ctx.globalAlpha = 1;

    // Outline of the whole cross — an arm where a glass is in play, the wall
    // of the centre where there is none — and of the centre, brighter.
    ctx.strokeStyle = OUTLINE;
    ctx.lineWidth = 1.5 * px;
    ctx.lineJoin = 'round';
    for (const side of SIDES) {
      this.frame(side);
      if (!sides.includes(side)) {
        ctx.stroke(this.wallOutline);
      } else if (side !== building) {
        ctx.stroke(this.armOutline);
      } else {
        ctx.beginPath();
        ctx.moveTo(-half, -half);
        ctx.lineTo(-half, -far);
        ctx.lineTo(half, -far);
        ctx.lineTo(half, -half);
        ctx.stroke();
      }
    }
    if (building !== null) {
      // The leading edge of the glass that is growing.
      this.frame(building);
      ctx.strokeStyle = rgba(THEME.accent, 0.9 * (1 - grow));
      ctx.lineWidth = 3 * px;
      ctx.beginPath();
      ctx.moveTo(-half, -far);
      ctx.lineTo(half, -far);
      ctx.stroke();
      ctx.lineWidth = 1.5 * px;
    }
    this.frame(0);
    ctx.strokeStyle = CENTRE_OUTLINE;
    ctx.strokeRect(-half, -half, n, n);
  }

  /** Bars of light over the popped lines, and the wash of a triple clear. */
  private drawFlashes(fx: Effects): void {
    const { ctx, grid } = this;
    for (const flash of fx.flashes) {
      ctx.globalAlpha = 0.85 * (1 - flash.age / flash.life);
      ctx.fillStyle = flash.color;
      ctx.fillRect(flash.x0, flash.y0, flash.x1 - flash.x0, flash.y1 - flash.y0);
    }
    ctx.fillStyle = '#ffffff';
    for (const veil of fx.veils) {
      ctx.globalAlpha = 0.22 * (1 - veil.age / veil.life);
      ctx.fillRect(-grid, -grid, grid * 2, grid * 2);
    }
    ctx.globalAlpha = 1;
  }

  /** The glass being steered glows; the glow moves over as the cross turns. */
  private drawActiveGlass(fx: Effects): void {
    const well = this.well;
    if (well === null) return;
    for (const side of SIDES) {
      const lit = fx.activeness[side];
      if (lit < 0.01) continue;
      this.frame(side);
      this.glow(well, -this.half, -this.reach, lit);
    }
  }

  /** A glass that is nearly full up to its far end pulses red there. */
  private drawCrowdedWarning(engine: GameEngine, fx: Effects, side: Side): void {
    if (engine.isGameOver ? engine.state.gameOverSide !== side : !engine.isCrowded(side)) return;
    const { ctx, n, arm, half, reach } = this;
    const pulse = engine.isGameOver ? 1 : 0.5 + 0.5 * Math.sin(fx.clock * 9);
    this.frame(side);
    const wash = ctx.createLinearGradient(0, -reach, 0, -half);
    wash.addColorStop(0, rgba(THEME.danger, 0.1 + 0.2 * pulse));
    wash.addColorStop(1, rgba(THEME.danger, 0.02));
    ctx.fillStyle = wash;
    ctx.fillRect(-half, -reach, n, arm);
    if (this.warning !== null) this.glow(this.warning, -half, -reach, 0.5 + 0.5 * pulse);
  }

  /** The streak a hard drop leaves down its lane. */
  private drawBeam(beam: Effects['beams'][number]): void {
    const { ctx, half, reach } = this;
    const t = beam.age / beam.life;
    const fade = (1 - t) * (1 - t);
    const left = -half + beam.column;
    const top = -reach + beam.fromRow;
    const bottom = -reach + beam.toRow;
    if (bottom <= top) return;
    this.beamFill ??= unitGradient(ctx, 0, 0.34);
    this.fillStretched(this.beamFill, beam.side, left, top, beam.width, bottom - top, fade);
  }

  /** Fills a rectangle of glass `frame` with a gradient made for a unit
   * square, so that one gradient serves every size and never has to be made
   * again. */
  private fillStretched(
    fill: CanvasGradient,
    frame: number,
    left: number,
    top: number,
    width: number,
    height: number,
    alpha: number,
  ): void {
    const { ctx } = this;
    this.frame(frame);
    ctx.transform(width, 0, 0, height, left, top);
    ctx.globalAlpha = alpha;
    ctx.fillStyle = fill;
    ctx.fillRect(0, 0, 1, 1);
    ctx.globalAlpha = 1;
  }

  /** Where a piece will land: the lane of the active one, and an outline of
   * its resting place. Pieces nobody is steering only show theirs when they
   * are about to lock. */
  private drawAim(engine: GameEngine, fx: Effects, piece: IncomingPiece): void {
    const rest = engine.restRow(piece.side);
    if (rest === null || rest === piece.row || engine.isGameOver) return;
    const lit = fx.activeness[piece.side];
    const urgent = (engine.secondsToLock(piece.side) ?? 99) < 6;
    const strength = Math.max(lit, urgent ? 0.4 : 0.16);

    const { ctx, half, reach, px } = this;
    const stick = piece.piece;
    const left = -half + piece.column;
    const width = pieceWidth(stick);
    const top = -reach + piece.row - fx.slideLeft(piece) + pieceDepth(stick);
    const bottom = -reach + rest;

    if (lit > 0.05 && bottom > top) {
      this.laneFill ??= unitGradient(ctx, 0.02, 0.085);
      this.fillStretched(this.laneFill, piece.side, left, top, width, bottom - top, lit);
    }
    this.frame(piece.side);
    const count = stick.colors.length;
    const lying = isHorizontal(stick);
    ctx.lineWidth = 1.6 * px;
    for (let i = 0; i < count; i++) {
      // The outline is the same whichever end the first colour is at, but
      // each square keeps its own colour.
      const along = stick.orientation >= 2 ? count - 1 - i : i;
      const tone = tonesOf(stick.colors[i]).base;
      roundedRect(
        ctx,
        left + (lying ? along : 0) + 0.07,
        -reach + rest + (lying ? 0 : along) + 0.07,
        0.86,
        0.86,
        0.14,
      );
      ctx.globalAlpha = 0.14 * strength;
      ctx.fillStyle = tone;
      ctx.fill();
      ctx.globalAlpha = 0.9 * strength;
      ctx.strokeStyle = tone;
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  // ----------------------------------------------------------------- blocks

  private drawSettled(engine: GameEngine, fx: Effects): void {
    const state = engine.state;
    const board = state.board;
    const size = board.size;
    // Centre of the cell in the top left corner of the grid.
    const origin = -this.grid / 2 + 0.5;
    const matched = state.activeMatch?.cells;

    if (state.moves.length === 0 && fx.landings.length === 0) {
      // Nothing is falling or landing: every block is where the board says.
      for (let row = 0, index = 0; row < size; row++) {
        for (let col = 0; col < size; col++, index++) {
          const color = board.atIndex(index);
          if (color === EMPTY || (matched !== undefined && matched.has(index))) continue;
          this.block(color as BlockColor, origin + col, origin + row, 0);
        }
      }
    } else {
      const moving = this.moving;
      moving.clear();
      for (const move of state.moves) moving.add(board.index(move.to.row, move.to.col));

      // Cells still reacting to a landing are drawn in their own pass.
      const landing = this.landing;
      landing.clear();
      for (const effect of fx.landings) {
        for (const cell of effect.placement.cells) {
          const index = board.index(cell.row, cell.col);
          if (board.atIndex(index) === cell.color && !matched?.has(index) && !moving.has(index)) {
            landing.set(index, effect);
          }
        }
      }

      for (let row = 0, index = 0; row < size; row++) {
        for (let col = 0; col < size; col++, index++) {
          const color = board.atIndex(index);
          if (color === EMPTY) continue;
          if (matched?.has(index) || moving.has(index) || landing.has(index)) continue;
          this.block(color as BlockColor, origin + col, origin + row, 0);
        }
      }

      // Falling: each block accelerates over its own distance, so short
      // falls land first, and wobbles once when it arrives.
      const side = state.activeSide;
      for (const move of state.moves) {
        const from = worldToView(move.from.row, move.from.col, side, size);
        const to = worldToView(move.to.row, move.to.col, side, size);
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
          move.color,
          origin + to.col,
          origin + row + 0.44 * (1 - Math.min(scaleY, 1)),
          side,
          scaleX,
          scaleY,
        );
      }

      // Landing: a white flash, and after a hard drop a squash along the fall.
      for (const effect of fx.landings) {
        const u = effect.age / effect.life;
        const wave = effect.dropped ? Math.sin(u * Math.PI * 2) * (1 - u) : 0;
        const scaleY = 1 - 0.26 * wave;
        const scaleX = 1 + 0.15 * wave;
        const frame = effect.placement.side;
        for (const cell of effect.placement.cells) {
          if (landing.get(board.index(cell.row, cell.col)) !== effect) continue;
          const local = worldToView(cell.row, cell.col, frame, size);
          this.block(
            cell.color,
            origin + local.col,
            origin + local.row + 0.44 * (1 - Math.min(scaleY, 1)),
            frame,
            scaleX,
            scaleY,
            0.85 * (1 - u) * (1 - u),
          );
        }
      }
    }

    // Match: flash to white and swell, then collapse while shards fly off.
    if (matched !== undefined && matched.size > 0) {
      const t = state.phaseDuration > 0 ? Math.min(1, state.phaseElapsed / state.phaseDuration) : 1;
      const popping = state.phase === 'clearing';
      const scale = popping ? 1.22 * Math.max(0, 1 - t * 1.7) : 1 + 0.22 * (1 - (1 - t) * (1 - t));
      const flash = popping ? 1 : 0.3 + 0.7 * t;
      if (scale > 0.01) {
        for (const index of matched) {
          const color = board.atIndex(index);
          if (color === EMPTY) continue;
          const row = Math.floor(index / size);
          this.block(color as BlockColor, origin + (index - row * size), origin + row, 0, scale, scale, flash);
        }
      }
    }
  }

  private drawRings(fx: Effects): void {
    const { ctx, px } = this;
    for (const ring of fx.rings) {
      if (ring.age < 0) continue;
      const t = ring.age / ring.life;
      const eased = 1 - (1 - t) * (1 - t);
      ctx.beginPath();
      ctx.arc(ring.x, ring.y, 0.3 + ring.reach * eased, 0, Math.PI * 2);
      ctx.globalAlpha = 0.75 * (1 - t);
      ctx.strokeStyle = ring.color;
      ctx.lineWidth = Math.max(px, 0.16 * (1 - t));
      ctx.stroke();
    }
    ctx.globalAlpha = 1;
  }

  private drawParticles(fx: Effects): void {
    const { ctx } = this;
    let color = '';
    for (const particle of fx.particles) {
      const strength = 1 - particle.age / particle.life;
      const size = particle.size * (0.4 + 0.6 * strength);
      ctx.globalAlpha = strength;
      if (particle.color !== color) {
        color = particle.color;
        ctx.fillStyle = color;
      }
      ctx.fillRect(particle.x - size / 2, particle.y - size / 2, size, size);
    }
    ctx.globalAlpha = 1;
  }

  private drawIncoming(engine: GameEngine, fx: Effects, piece: IncomingPiece): void {
    const { half, reach } = this;
    const side = piece.side;
    const stick = piece.piece;
    const lit = fx.activeness[side];
    const secondsLeft = engine.secondsToLock(side) ?? 0;
    const urgent = secondsLeft < 3;

    const top = -reach + piece.row - fx.slideLeft(piece);
    const left = -half + piece.column;

    // Halo: white for the piece being steered, coloured when time runs out.
    const strength = Math.max(lit, urgent ? 0.85 : 0);
    if (strength > 0.02) {
      const warn = urgent && lit < 0.5;
      const pulse = warn ? 0.6 + 0.4 * Math.sin(fx.clock * 10) : 1;
      const halo = this.halo(pieceWidth(stick), pieceDepth(stick), warn ? urgencyColor(secondsLeft) : ICE);
      this.frame(side);
      this.glow(halo, left, top, strength * pulse);
    }

    this.stick(stick, left, top, side);
  }

  /** The squares of a stick whose top left cell is at (`left`, `top`) of the
   * frame of glass `frame`. */
  private stick(piece: Piece, left: number, top: number, frame: number, scaleY = 1, flash = 0): void {
    const count = piece.colors.length;
    const lying = isHorizontal(piece);
    const flipped = piece.orientation >= 2;
    for (let i = 0; i < count; i++) {
      const along = flipped ? count - 1 - i : i;
      this.block(
        piece.colors[i],
        left + (lying ? along : 0) + 0.5,
        top + (lying ? 0 : along) + 0.5,
        frame,
        1,
        scaleY,
        flash,
      );
    }
  }

  /** A hard-dropped piece streaking down to where it lands. */
  private drawDrop(state: GameState): void {
    const drop = state.drop;
    if (!drop) return;
    const t = state.phaseDuration > 0 ? Math.min(1, state.phaseElapsed / state.phaseDuration) : 1;
    const row = drop.startRow + (drop.placement.row - drop.startRow) * t * t;
    this.stick(
      drop.placement.piece,
      -this.half + drop.placement.column,
      -this.reach + row,
      drop.placement.side,
      1 + 0.18 * t,
      0.25 * t,
    );
  }

  /** Seconds until a piece locks by itself, written upright beside it. Drawn
   * straight in device pixels, after everything else. */
  private drawCountdown(engine: GameEngine, fx: Effects, piece: IncomingPiece, scale: number): void {
    if (engine.isGameOver) return;
    const secondsLeft = engine.secondsToLock(piece.side) ?? 0;
    const lit = fx.activeness[piece.side];
    // The piece being steered only needs its timer when it is about to lock.
    if (lit > 0.5 && secondsLeft >= 3) return;

    // A point just beyond the left end of the piece, in its glass's frame,
    // turned with its glass and with the cross.
    const localX = -this.half + piece.column - 0.75;
    const localY = -this.reach + piece.row - fx.slideLeft(piece) + pieceDepth(piece.piece) / 2;
    const c = this.cos[piece.side];
    const n = this.sin[piece.side];
    const x = this.tx + (localX * c - localY * n) * this.s;
    const y = this.ty + (localX * n + localY * c) * this.s;

    const size = Math.max(10, (this.cssSize / this.grid) * 0.72) * scale;
    if (size !== this.fontSize) {
      this.fontSize = size;
      this.fontCalm = `600 ${size}px "Exo 2", system-ui, sans-serif`;
      this.fontUrgent = `800 ${size}px "Exo 2", system-ui, sans-serif`;
    }
    const { ctx } = this;
    const urgent = secondsLeft < 3;
    ctx.font = urgent ? this.fontUrgent : this.fontCalm;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = !urgent ? CALM_TEXT : secondsLeft < 1.5 ? DANGER_TEXT : WARNING_TEXT;
    ctx.fillText(secondsLeft < 10 ? secondsLeft.toFixed(1) : String(Math.round(secondsLeft)), x, y);
  }
}

const CALM_TEXT = rgba(THEME.text, 0.42);
const WARNING_TEXT = rgba(THEME.warning, 1);
const DANGER_TEXT = rgba(THEME.danger, 1);

/** White, from `top` to `bottom` opacity down a unit square. */
function unitGradient(ctx: CanvasRenderingContext2D, top: number, bottom: number): CanvasGradient {
  const gradient = ctx.createLinearGradient(0, 0, 0, 1);
  gradient.addColorStop(0, `rgba(255, 255, 255, ${top})`);
  gradient.addColorStop(1, `rgba(255, 255, 255, ${bottom})`);
  return gradient;
}

const urgencyColor = (secondsLeft: number): string =>
  secondsLeft < 1.5 ? THEME.danger : THEME.warning;

/** Draws a glowing shape once, into an image with room for its glow. `draw`
 * works in cells, with the origin of the shape at (0, 0); the shape is
 * `width` by `height` cells. */
function makeGlow(
  width: number,
  height: number,
  unit: number,
  blur: number,
  draw: (g: CanvasRenderingContext2D) => void,
): Glow {
  const pad = blur * 2 + 12;
  const image = document.createElement('canvas');
  image.width = Math.ceil(width * unit) + pad * 2;
  image.height = Math.ceil(height * unit) + pad * 2;
  const g = image.getContext('2d')!;
  g.translate(pad, pad);
  g.scale(unit, unit);
  draw(g);
  return { image, pad };
}

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
