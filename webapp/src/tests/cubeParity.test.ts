import { readFileSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { CubeGame, defaultCubeConfig, mulberry32, sideOfNormal, SIDES, type CubeConfig, type CubeEvent, type Vec, type ViewFrame } from '../cube/rules';

/** Rules parity of Cube with the Flutter app (test/cube/cube_parity_test.dart).
 *
 * Cube was made on the web, so this test is the reference: it plays scripted
 * games and writes `parity/cube-trace.json`, the hash of the whole state after
 * every action. The Dart test replays the same scripts and must reproduce
 * every hash. Regenerate after an intended change of the rules with
 *   ROTATHREE_WRITE_CUBE_PARITY=1 npx vitest run src/tests/cubeParity.test.ts
 * The line format, the script and the hash are defined here and in the Dart
 * file; keep them in step. */

const FIXTURE = resolve(process.cwd(), '../parity/cube-trace.json');
const CHECKPOINT_EVERY = 200;
/** Every this many actions the script starts a new game. */
const GAME_LENGTH = 500;

interface Spec {
  name: string;
  seed: number;
  actionSeed: number;
  steps: number;
  config: Partial<CubeConfig>;
}

const SCENARIOS: Spec[] = [
  { name: 'classic', seed: 11, actionSeed: 111, steps: 1500, config: {} },
  { name: 'even cube', seed: 12, actionSeed: 222, steps: 1500, config: { centre: 10, arm: 9 } },
  { name: 'depth falls, five colours', seed: 13, actionSeed: 333, steps: 1500, config: { depthFalls: true, numberOfColors: 5 } },
  {
    name: 'ramp, still glasses',
    seed: 14,
    actionSeed: 444,
    steps: 1500,
    config: { inactiveFalls: false, ramp: { everyPoints: 300, factor: 0.9, minActive: 0.4, minInactive: 1.2 } },
  },
];

type Action =
  | { op: 'move'; way: 'right' | 'left' | 'up' | 'down' }
  | { op: 'rotate'; axis: 'toward' | 'away' | 'up' }
  | { op: 'cross'; q: 1 | -1 }
  | { op: 'tip'; q: 1 | -1 }
  | { op: 'control'; which: 'front' | 'back' | 'top' }
  | { op: 'drop' }
  | { op: 'soft'; held: boolean }
  | { op: 'restart' }
  | { op: 'update'; ms: number };

function draw(rnd: () => number): Action {
  const r = rnd();
  if (r < 0.22) return { op: 'move', way: (['right', 'left', 'up', 'down'] as const)[Math.floor(rnd() * 4)] };
  if (r < 0.32) return { op: 'rotate', axis: (['toward', 'away', 'up'] as const)[Math.floor(rnd() * 3)] };
  if (r < 0.38) return { op: 'cross', q: rnd() < 0.5 ? 1 : -1 };
  if (r < 0.43) return { op: 'tip', q: rnd() < 0.5 ? 1 : -1 };
  if (r < 0.47) return { op: 'control', which: (['front', 'back', 'top'] as const)[Math.floor(rnd() * 3)] };
  if (r < 0.5) return { op: 'drop' };
  if (r < 0.54) return { op: 'soft', held: rnd() < 0.5 };
  if (r < 0.545) return { op: 'restart' };
  return { op: 'update', ms: 1 + Math.floor(rnd() * 420) };
}

function script(seed: number, count: number): Action[] {
  const rnd = mulberry32(seed);
  const actions: Action[] = [];
  for (let i = 0; i < count; i++) {
    const action = draw(rnd);
    actions.push((i + 1) % GAME_LENGTH === 0 ? { op: 'restart' } : action);
  }
  return actions;
}

const neg = (v: Vec): Vec => [-v[0], -v[1], -v[2]] as Vec;

/** The hub turned a quarter in the screen, counterclockwise for +1. */
function crossTurn(game: CubeGame, q: 1 | -1): void {
  const { right, up } = game.viewFrame;
  const frame: ViewFrame = q === 1 ? { right: neg(up), up: [...right] as Vec } : { right: [...up] as Vec, up: neg(right) };
  game.turn(sideOfNormal(frame.up), [...game.plane] as Vec, frame, false);
}

/** The hub tipped over about the screen's right: +1 brings the glass behind
 * to the top, −1 the one in front. */
function tip(game: CubeGame, q: 1 | -1): void {
  const { right, up } = game.viewFrame;
  const plane = game.plane;
  const frame: ViewFrame = q === 1 ? { right: [...right] as Vec, up: neg(plane) } : { right: [...right] as Vec, up: [...plane] as Vec };
  game.turn(sideOfNormal(frame.up), q === 1 ? ([...up] as Vec) : neg(up), frame, true);
}

function apply(game: CubeGame, a: Action): void {
  switch (a.op) {
    case 'move': {
      const { right, up } = game.viewFrame;
      game.move(a.way === 'right' ? [...right] as Vec : a.way === 'left' ? neg(right) : a.way === 'up' ? [...up] as Vec : neg(up));
      break;
    }
    case 'rotate':
      game.rotate(a.axis === 'toward' ? [...game.plane] as Vec : a.axis === 'away' ? neg(game.plane) : [...game.viewFrame.up] as Vec);
      break;
    case 'cross':
      crossTurn(game, a.q);
      break;
    case 'tip':
      tip(game, a.q);
      break;
    case 'control':
      game.control(a.which === 'front' ? sideOfNormal(game.plane) : a.which === 'back' ? sideOfNormal(neg(game.plane)) : game.down);
      break;
    case 'drop':
      game.dropActive();
      break;
    case 'soft':
      game.softDrop = a.held;
      break;
    case 'update':
      game.update(a.ms / 1000);
      break;
    case 'restart':
      break;
  }
}

const micro = (value: number): number => Math.round(value * 1000000);
const ms = (seconds: number): number => Math.floor(seconds * 1000);
const v = (p: readonly number[]): string => p.join(',');

function event(e: CubeEvent): string {
  switch (e.type) {
    case 'switched':
      return `switched:${e.from}:${e.to}`;
    case 'moved':
    case 'rotated':
      return `${e.type}:${e.blocked ? 1 : 0}`;
    case 'stepped':
      return `stepped:${e.side}`;
    case 'dropped':
      return `dropped:${e.side}:${e.cells}`;
    case 'landed':
      return `landed:${e.side}:${e.dropped ? 1 : 0}`;
    case 'matched':
      return `matched:${e.combo}:${e.score}:${e.match.cells.size}`;
    case 'popped':
      return `popped:${e.cells.length}`;
    case 'fell':
      return `fell:${e.moves.length}`;
    case 'speedUp':
      return `speedUp:${e.level}`;
    case 'gameEnded':
      return `gameEnded:${e.side}`;
  }
}

/** One line with everything the rules decide. */
function canonical(g: CubeGame, events: CubeEvent[]): string {
  const parts = [
    `ph=${g.phase}`,
    `a=${g.active}`,
    `d=${g.down}`,
    `pl=${v(g.plane)}`,
    `vf=${v(g.viewFrame.right)};${v(g.viewFrame.up)}`,
    `sc=${g.score}`,
    `cb=${g.combo}`,
    `bc=${g.bestCombo}`,
    `pp=${g.placed}`,
    `mt=${g.matches}`,
    `cc=${g.cleared}`,
    `sl=${g.speedLevel}`,
    `et=${ms(g.seconds)}`,
    `pe=${ms(g.phaseElapsed)}`,
    `pd=${ms(g.phaseDuration)}`,
    `go=${g.gameOverSide ?? -1}`,
    `iq=${g.inputs.length}`,
    `cfg=${micro(g.config.activeStepSeconds)},${micro(g.config.inactiveStepSeconds)}`,
  ];
  for (const s of SIDES) {
    const p = g.pieces.get(s.id);
    if (p) parts.push(`p${s.id}=${p.colors.join('')}@${v(p.pivot)}/${v(p.dir)}/${micro(p.progress)}`);
    parts.push(`n${s.id}=${g.nextOf(s.id).join('')}`);
  }
  const blocks: string[] = [];
  g.hub.forEachBlock((_p, color, index) => blocks.push(`${index}:${color}`));
  parts.push(`hub=${blocks.join(',')}`);
  parts.push(`ev=${events.map(event).join(',')}`);
  return parts.join('|');
}

/** FNV-1a, 32 bit. The Dart test computes the same function. */
function hash(text: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < text.length; i++) {
    h ^= text.charCodeAt(i);
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h;
}

function run(spec: Spec) {
  let restarts = 0;
  const fresh = () => new CubeGame({ ...spec.config, seed: spec.seed + restarts });
  let game = fresh();
  const actions = script(spec.actionSeed, spec.steps);
  let trace = '';
  const checkpoints: Record<string, string> = {};
  const record = (step: number) => {
    const line = canonical(game, game.events.splice(0));
    trace += hash(line).toString(16).padStart(8, '0');
    if (step % CHECKPOINT_EVERY === 0) checkpoints[step] = line;
  };
  record(0);
  for (let step = 1; step <= spec.steps; step++) {
    const action = actions[step - 1];
    if (action.op === 'restart') {
      restarts++;
      game = fresh();
    } else {
      apply(game, action);
    }
    record(step);
  }
  return { ...spec, trace, checkpoints };
}

/** Every default the rules depend on; the Dart side writes the same text. */
function configDigest(c: CubeConfig): string {
  return Object.entries(c)
    .filter(([key]) => key !== 'ramp' && key !== 'seed')
    .map(([key, value]) => `${key}=${typeof value === 'number' ? micro(value) : value}`)
    .join(';');
}

describe('Cube rules parity', () => {
  it('reproduces the stored trace, the one the Flutter app replays', () => {
    const fixture = { format: 'rotathree-cube-parity', version: 1, config: configDigest(defaultCubeConfig), scenarios: SCENARIOS.map(run) };
    if (process.env.ROTATHREE_WRITE_CUBE_PARITY === '1') {
      writeFileSync(FIXTURE, `${JSON.stringify(fixture, null, 2)}\n`);
    }
    const stored = JSON.parse(readFileSync(FIXTURE, 'utf8'));
    expect(fixture.config).toBe(stored.config);
    for (const [i, scenario] of fixture.scenarios.entries()) {
      expect(scenario.trace, scenario.name).toBe(stored.scenarios[i].trace);
    }
  });
});
