import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { Board } from '../game/board';
import { defaultConfig, type GameConfig } from '../game/config';
import { GameEngine, type GameEvent, type SpeedRamp } from '../game/engine';
import { createRandom } from '../game/random';
import type { Side } from '../game/side';

/** Rules parity with the Flutter engine (test/game/rules_parity_test.dart).
 *
 * The Dart test is the reference and writes `parity/rules-trace.json`. This
 * test replays the same scripted games and must reproduce every state hash.
 * The line format and the hash are defined in the Dart file; keep them in step. */

// The npm scripts run from webapp/, so the shared fixture is one level up.
const FIXTURE = resolve(process.cwd(), '../parity/rules-trace.json');
const CHECKPOINT_EVERY = 250;

interface Scenario {
  name: string;
  seed: number;
  actionSeed: number;
  steps: number;
  config: Record<string, unknown>;
  ramp: SpeedRamp | null;
  trace: string;
  checkpoints: Record<string, string>;
}

interface Fixture {
  format: string;
  version: number;
  config: string;
  scenarios: Scenario[];
}

type Action =
  | { op: 'move'; delta: number }
  | { op: 'rotate'; cw: boolean }
  | { op: 'turn'; q: number }
  | { op: 'activate'; side: number }
  | { op: 'drop' }
  | { op: 'soft'; held: boolean }
  | { op: 'add' }
  | { op: 'restart' }
  | { op: 'update'; ms: number };

const micro = (value: number): number => Math.round(value * 1000000);
const ms = (seconds: number): number => Math.floor(seconds * 1000);

/** Every default the rules depend on; the Dart side writes the same text. */
function configDigest(c: GameConfig): string {
  return [
    `boardSize=${c.boardSize}`,
    `armLength=${c.armLength}`,
    `glassCount=${c.glassCount}`,
    `pieceLength=${c.pieceLength}`,
    `numberOfColors=${c.numberOfColors}`,
    `minMatchLength=${c.minMatchLength}`,
    `activeStepSeconds=${micro(c.activeStepSeconds)}`,
    `inactiveStepSeconds=${micro(c.inactiveStepSeconds)}`,
    `softDropStepSeconds=${micro(c.softDropStepSeconds)}`,
    `buildSeconds=${micro(c.buildSeconds)}`,
    `initialProgressStagger=${micro(c.initialProgressStagger)}`,
    `spawnColumn=${c.spawnColumn ?? -1}`,
    `monoPieceKeepChance=${micro(c.monoPieceKeepChance)}`,
    `settleAfterBoardRotation=${c.settleAfterBoardRotation}`,
    `pauseIncomingDuringCascade=${c.pauseIncomingDuringCascade}`,
    `gravityScope=${c.gravityScope}`,
    `crowdedHeadroom=${c.crowdedHeadroom}`,
    `dropBaseSeconds=${micro(c.dropBaseSeconds)}`,
    `dropSecondsPerCell=${micro(c.dropSecondsPerCell)}`,
    `matchSeconds=${micro(c.matchSeconds)}`,
    `clearSeconds=${micro(c.clearSeconds)}`,
    `fallBaseSeconds=${micro(c.fallBaseSeconds)}`,
    `fallSecondsPerRootCell=${micro(c.fallSecondsPerRootCell)}`,
    `fallBounceSeconds=${micro(c.fallBounceSeconds)}`,
    `maxQueuedInputs=${c.maxQueuedInputs}`,
    `basePoints=${c.basePoints}`,
  ].join(';');
}

/** FNV-1a, 32 bit: the same function as in the Dart test. */
function hash(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

/** The scripted actions, drawn in exactly the order the Dart script draws them. */
function draw(rnd: () => number): Action {
  const r = rnd();
  if (r < 0.28) return { op: 'move', delta: rnd() < 0.5 ? -1 : 1 };
  if (r < 0.4) return { op: 'rotate', cw: rnd() < 0.5 };
  if (r < 0.46) return { op: 'turn', q: 1 + Math.floor(rnd() * 3) };
  if (r < 0.5) return { op: 'activate', side: Math.floor(rnd() * 4) };
  if (r < 0.52) return { op: 'drop' };
  if (r < 0.56) return { op: 'soft', held: rnd() < 0.5 };
  if (r < 0.565) return { op: 'add' };
  if (r < 0.566) return { op: 'restart' };
  return { op: 'update', ms: 1 + Math.floor(rnd() * 420) };
}

/** Every this many actions the script starts a new game (as in the Dart file). */
const GAME_LENGTH = 600;

function script(seed: number, count: number): Action[] {
  const rnd = createRandom(seed);
  const actions: Action[] = [];
  for (let i = 0; i < count; i++) {
    const action = draw(rnd);
    actions.push((i + 1) % GAME_LENGTH === 0 ? { op: 'restart' } : action);
  }
  return actions;
}

function apply(engine: GameEngine, a: Action): void {
  switch (a.op) {
    case 'move':
      engine.moveActive(a.delta);
      break;
    case 'rotate':
      engine.rotateActive(a.cw);
      break;
    case 'turn':
      engine.switchSide(a.q);
      break;
    case 'activate':
      engine.activateSide(a.side as Side);
      break;
    case 'drop':
      engine.dropActive();
      break;
    case 'soft':
      engine.setSoftDrop(a.held);
      break;
    case 'add':
      engine.addGlass();
      break;
    case 'restart':
      engine.restart();
      break;
    case 'update':
      engine.update(a.ms / 1000);
      break;
  }
}

function board(b: Board): string {
  const rows: string[] = [];
  for (let row = 0; row < b.size; row++) {
    let line = '';
    for (let col = 0; col < b.size; col++) {
      if (!b.isInside(row, col)) line += '-';
      else {
        const colour = b.at(row, col);
        line += colour < 0 ? '.' : String(colour);
      }
    }
    rows.push(line);
  }
  return rows.join('/');
}

function event(ev: GameEvent): string {
  switch (ev.type) {
    case 'sideSwitched':
      return 'sideSwitched';
    case 'pieceMoved':
      return `pieceMoved:${ev.direction}:${ev.blocked ? 1 : 0}`;
    case 'pieceRotated':
      return `pieceRotated:${ev.blocked ? 1 : 0}`;
    case 'pieceStepped':
      return 'pieceStepped';
    case 'pieceDropped':
      return `pieceDropped:${ev.cells}`;
    case 'pieceLanded':
      return `pieceLanded:${ev.dropped ? 1 : 0}`;
    case 'matchScored':
      return `matchScored:${ev.combo}:${ev.score}`;
    case 'cellsPopped':
      return 'cellsPopped';
    case 'blocksFell':
      return 'blocksFell';
    case 'glassAdded':
      return `glassAdded:${ev.side}`;
    case 'speedUp':
      return `speedUp:${ev.level}`;
    case 'gameEnded':
      return `gameEnded:${ev.side}`;
  }
}

/** One line with everything a player can see or the score depends on. */
function canonical(engine: GameEngine, events: GameEvent[]): string {
  const s = engine.state;
  const parts = [
    `ph=${s.phase}`,
    `a=${s.activeSide}`,
    `sc=${s.score}`,
    `cb=${s.combo}`,
    `bc=${s.bestCombo}`,
    `mt=${s.matches}`,
    `cc=${s.clearedCells}`,
    `pp=${s.piecesPlaced}`,
    `sl=${s.selfLocked}`,
    `sp=${s.speedLevel}`,
    `et=${ms(s.elapsedSeconds)}`,
    `pe=${ms(s.phaseElapsed)}`,
    `pd=${ms(s.phaseDuration)}`,
    `go=${s.gameOverSide ?? -1}`,
    `bs=${s.buildingSide ?? -1}`,
    `mv=${s.moves.length}`,
    `am=${s.activeMatch ? s.activeMatch.cells.size : -1}`,
    `dr=${s.drop ? s.drop.startRow : -1}`,
    `sides=${engine.sides.join(',')}`,
    `cfg=${micro(engine.config.activeStepSeconds)},${micro(engine.config.inactiveStepSeconds)}`,
  ];
  for (const side of [0, 1, 2, 3] as const) {
    const p = s.incoming.get(side);
    if (!p) continue;
    parts.push(
      `in${side}=${p.piece.colors.join('')}o${p.piece.orientation}@${p.column},${p.row},${micro(p.stepProgress)}`,
    );
  }
  parts.push(`board=${board(s.board)}`);
  parts.push(`ev=${events.map(event).join(',')}`);
  return parts.join('|');
}

interface Replay {
  trace: string;
  checkpoints: Record<string, string>;
  lines: string[];
}

function replay(spec: Scenario): Replay {
  const config: GameConfig = { ...defaultConfig, ...(spec.config as Partial<GameConfig>) };
  const engine = new GameEngine(config, createRandom(spec.seed));
  if (spec.ramp) engine.setRamp(spec.ramp);
  const actions = script(spec.actionSeed, spec.steps);
  const result: Replay = { trace: '', checkpoints: {}, lines: [] };

  const record = (step: number, events: GameEvent[]) => {
    const line = canonical(engine, events);
    result.trace += hash(line).toString(16).padStart(8, '0');
    if (step % CHECKPOINT_EVERY === 0) result.checkpoints[String(step)] = line;
    result.lines.push(line);
  };

  record(0, []);
  for (let step = 1; step <= spec.steps; step++) {
    apply(engine, actions[step - 1]);
    record(step, engine.drainEvents());
  }
  return result;
}

/** The first step whose hash differs, or -1 when the traces agree. */
function firstDifference(actual: string, expected: string): number {
  const steps = expected.length / 8;
  for (let step = 0; step < steps; step++) {
    const from = step * 8;
    if (actual.slice(from, from + 8) !== expected.slice(from, from + 8)) return step;
  }
  return actual.length === expected.length ? -1 : steps;
}

const dumpLines: string[] = [];

describe('rules parity with the Flutter engine', () => {
  const stored = JSON.parse(readFileSync(FIXTURE, 'utf8')) as Fixture;

  it('reads the fixture format it understands', () => {
    expect(stored.format).toBe('rotathree-rules-parity');
    expect(stored.version).toBe(1);
  });

  it('uses the same default configuration as the Dart engine', () => {
    expect(configDigest(defaultConfig)).toBe(stored.config);
  });

  for (const spec of stored.scenarios) {
    it(`replays "${spec.name}" to the same state after every action`, () => {
      const actual = replay(spec);
      if (process.env.ROTATHREE_PARITY_DUMP) {
        actual.lines.forEach((line, step) => dumpLines.push(`${spec.name}\t${step}\t${line}`));
      }
      const step = firstDifference(actual.trace, spec.trace);
      if (step >= 0) {
        const action = step === 0 ? 'the start' : `action ${step} ${JSON.stringify(script(spec.actionSeed, step)[step - 1])}`;
        const checkpoint = Math.floor(step / CHECKPOINT_EVERY) * CHECKPOINT_EVERY;
        expect.fail(
          `"${spec.name}" diverges at ${action}.\n` +
            `web:  ${actual.lines[step]}\n` +
            `dart (checkpoint ${checkpoint}): ${spec.checkpoints[String(checkpoint)]}`,
        );
      }
      expect(actual.checkpoints).toEqual(spec.checkpoints);
    });
  }

  it('writes the dump when asked to', () => {
    const target = process.env.ROTATHREE_PARITY_DUMP;
    if (target) writeFileSync(target, dumpLines.join('\n') + '\n');
  });
});
