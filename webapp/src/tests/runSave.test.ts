import { expect, it } from 'vitest';
import { GameEngine } from '../game/engine';
import { planFor, type Session } from '../game/session';
import { abandonedRun, sanitizeRunSave, type RunSave } from '../services/runSave';
import { addRun, defaultStats, loadRun, saveRun, saveStats } from '../services/storage';

it('a complete run save survives storage and cannot count abandonment twice', () => {
  const session: Session = { mode: 'campaign', level: 0 },
    engine = new GameEngine(planFor(session).config);
  engine.state.score = 1200;
  const save: RunSave = {
    version: 1,
    id: 'resume-1',
    session,
    engine: engine.snapshot(),
    carry: { score: 0, pieces: 0, matches: 0, bestCombo: 0, seconds: 0 },
    levelBase: 0,
    savedAt: Date.now(),
    banner: { kicker: 'Уровень 1 пройден', title: '1200', left: 1.7, blocking: true, pendingLevel: 1, colours: 0 },
  };
  expect(saveRun(save)).toBe(true);
  expect(loadRun()).toEqual(save);
  const run = abandonedRun(loadRun()!);
  const stats = addRun(defaultStats(), run);
  expect(addRun(stats, run)).toBe(stats);
  expect(run.interrupted).toBe(true);
  expect(sanitizeRunSave({ ...save, banner: { ...save.banner, pendingLevel: 5 } })).toBeNull();
  expect(saveRun(null)).toBe(true);
  expect(loadRun()).toBeNull();
});
it('storage errors are observable by the app', () => {
  expect(
    saveStats(defaultStats(), {
      setItem: () => {
        throw Error('Full');
      },
    }),
  ).toBe(false);
  expect(loadRun({ getItem: () => '{ broken' })).toBeNull();
});
