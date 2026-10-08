import { describe, expect, it } from 'vitest';
import { CAMPAIGN } from '../game/campaign';
import { addRun, defaultProgress, defaultStats, sanitizeProgress, sanitizeStats, type RunRecord } from '../services/storage';

const run = (overrides: Partial<RunRecord> = {}): RunRecord => ({
  id: 'x',
  mode: 'custom',
  at: 1,
  score: 100,
  pieces: 5,
  matches: 1,
  bestCombo: 1,
  seconds: 30,
  level: 1,
  completed: false,
  ...overrides,
});

describe('statistics', () => {
  it('add a run to its mode and keep the best of each figure', () => {
    let stats = addRun(defaultStats(), run({ score: 300, pieces: 10, bestCombo: 2, seconds: 60 }));
    stats = addRun(stats, run({ score: 200, pieces: 4, bestCombo: 3, seconds: 20, level: 4 }));
    const custom = stats.modes.custom;
    expect(custom.games).toBe(2);
    expect(custom.totalScore).toBe(500);
    expect(custom.bestScore).toBe(300);
    expect(custom.totalPieces).toBe(14);
    expect(custom.bestCombo).toBe(3);
    expect(custom.totalSeconds).toBe(80);
    expect(custom.bestLevel).toBe(4);
    expect(stats.modes.campaign.games).toBe(0);
  });

  it('count finished campaigns apart and keep only the last runs', () => {
    let stats = defaultStats();
    stats = addRun(stats, run({ mode: 'campaign', completed: true, level: 15 }));
    expect(stats.modes.campaign.completed).toBe(1);
    for (let i = 0; i < 25; i++) stats = addRun(stats, run({ id: String(i) }));
    expect(stats.recent).toHaveLength(20);
    expect(stats.recent[0].id).toBe('24');
  });

  it('a damaged record is read as far as it can be', () => {
    const cleaned = sanitizeStats({ modes: { custom: { games: 'many', bestScore: 42 } }, recent: [{ mode: 'nope' }, { mode: 'insane', score: 9 }] });
    expect(cleaned.modes.custom.games).toBe(0);
    expect(cleaned.modes.custom.bestScore).toBe(42);
    expect(cleaned.recent).toHaveLength(1);
    expect(cleaned.recent[0].mode).toBe('insane');
  });
});

describe('campaign progress', () => {
  it('starts at the first level with a best score for each', () => {
    const progress = defaultProgress();
    expect(progress.unlocked).toBe(0);
    expect(progress.completed).toBe(false);
    expect(progress.best).toHaveLength(CAMPAIGN.length);
  });

  it('reads back an unlocked level but not one past the last', () => {
    expect(sanitizeProgress({ unlocked: 4, completed: false, best: [900, 1500] }).unlocked).toBe(4);
    expect(sanitizeProgress({ unlocked: 99 }).unlocked).toBe(CAMPAIGN.length - 1);
    expect(sanitizeProgress({ best: [-5, 'x', 800] }).best.slice(0, 3)).toEqual([0, 0, 800]);
  });
});
