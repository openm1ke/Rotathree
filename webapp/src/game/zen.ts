/** Zen mode: the same game played through levels. Each level asks for a few
 * more points than the one before; nothing gets faster. */

/** Points needed to finish `level` (the first level is 1). */
export const zenLevelTarget = (level: number): number => 1000 + 500 * (level - 1);

/** Total score at which `level` begins. */
export function zenLevelStart(level: number): number {
  let total = 0;
  for (let l = 1; l < level; l++) total += zenLevelTarget(l);
  return total;
}

/** The level a total score has reached. */
export function zenLevelOf(score: number): number {
  let level = 1;
  while (score >= zenLevelStart(level + 1)) level++;
  return level;
}

/** How far into `level` a total score is, capped at the level's target: the
 * score may run past it while a cascade is still resolving. */
export function zenLevelProgress(score: number, level: number): { into: number; target: number } {
  const target = zenLevelTarget(level);
  return { into: Math.max(0, Math.min(target, score - zenLevelStart(level))), target };
}
