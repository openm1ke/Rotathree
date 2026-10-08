import { CAMPAIGN, levelConfig } from './campaign';
import { customPlan, insanePlan, type CustomSetup, type RunPlan } from './modes';

/** A game being played: one campaign level, Insane, or a custom setup. The
 * setup is copied when the game starts, so changing it later does not touch
 * a game in progress. */
export type Session =
  | { mode: 'campaign'; level: number }
  | { mode: 'insane' }
  | { mode: 'custom'; setup: CustomSetup };

/** The engine configuration and speed ramp of a session. */
export function planFor(session: Session): RunPlan {
  switch (session.mode) {
    case 'campaign':
      return { config: levelConfig(CAMPAIGN[session.level]), ramp: null };
    case 'insane':
      return insanePlan();
    case 'custom':
      return customPlan(session.setup);
  }
}
