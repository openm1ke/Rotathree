/** One of the four glasses of the cross, named by where it sits in the
 * fixed world frame (the orientation the game starts in). */
export type Side = 0 | 1 | 2 | 3;

export const TOP: Side = 0;
export const RIGHT: Side = 1;
export const BOTTOM: Side = 2;
export const LEFT: Side = 3;

export const SIDES: readonly Side[] = [TOP, RIGHT, BOTTOM, LEFT];
export const SIDE_NAMES = ['top', 'right', 'bottom', 'left'] as const;

/** The side reached after `quarterTurns` steps of TOP → RIGHT → BOTTOM →
 * LEFT (negative steps go backwards). */
export const turned = (side: Side, quarterTurns: number): Side =>
  ((((side + quarterTurns) % 4) + 4) % 4) as Side;

/** Signed number of steps from `from` to `to`, the short way round:
 * -1, 0, 1 or 2. */
export function stepsTo(from: Side, to: Side): number {
  const diff = (((to - from) % 4) + 4) % 4;
  return diff === 3 ? -1 : diff;
}
