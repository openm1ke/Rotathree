import { defaultConfig, type GameConfig } from './config';

/** One level of the campaign: earn `target` points with `glasses` glasses in
 * play and `colours` colours in the pieces. The step times apply from the
 * moment the level starts. */
export interface CampaignLevel {
  colours: number;
  glasses: number;
  target: number;
  activeStep: number;
  inactiveStep: number;
}

/** Fifteen levels in four stages, one stage per number of colours. Each stage
 * starts again with one glass and adds glasses one by one. The points were
 * chosen from simulated bot games (tool/campaign_sim.dart): a level takes a
 * decent player about 30 seconds at the start, about three minutes at the
 * end. The last three levels step the falling up by about ten per cent.
 * Stages, from the top:
 *   3 colours — 1, 2, 3 glasses
 *   4 colours — 1, 2, 3, 4 glasses
 *   5 colours — 1, 2, 3, 4 glasses
 *   6 colours — 1, 2, 3, 4 glasses (the last level of the campaign) */
export const CAMPAIGN: readonly CampaignLevel[] = [
  { colours: 3, glasses: 1, target: 1200, activeStep: 1, inactiveStep: 3 },
  { colours: 3, glasses: 2, target: 1800, activeStep: 1, inactiveStep: 3 },
  { colours: 3, glasses: 3, target: 2400, activeStep: 1, inactiveStep: 3 },
  { colours: 4, glasses: 1, target: 2600, activeStep: 1, inactiveStep: 3 },
  { colours: 4, glasses: 2, target: 2800, activeStep: 1, inactiveStep: 3 },
  { colours: 4, glasses: 3, target: 3200, activeStep: 1, inactiveStep: 3 },
  { colours: 4, glasses: 4, target: 3800, activeStep: 1, inactiveStep: 3 },
  { colours: 5, glasses: 1, target: 4000, activeStep: 1, inactiveStep: 3 },
  { colours: 5, glasses: 2, target: 4400, activeStep: 1, inactiveStep: 3 },
  { colours: 5, glasses: 3, target: 4800, activeStep: 1, inactiveStep: 3 },
  { colours: 5, glasses: 4, target: 5200, activeStep: 1, inactiveStep: 3 },
  { colours: 6, glasses: 1, target: 5400, activeStep: 1, inactiveStep: 3 },
  { colours: 6, glasses: 2, target: 5800, activeStep: 0.95, inactiveStep: 2.8 },
  { colours: 6, glasses: 3, target: 6200, activeStep: 0.92, inactiveStep: 2.7 },
  { colours: 6, glasses: 4, target: 6600, activeStep: 0.9, inactiveStep: 2.6 },
];

export const CAMPAIGN_LAST = CAMPAIGN.length - 1;

/** The engine configuration of a campaign level. */
export const levelConfig = (level: CampaignLevel): GameConfig => ({
  ...defaultConfig,
  glassCount: level.glasses,
  numberOfColors: level.colours,
  activeStepSeconds: level.activeStep,
  inactiveStepSeconds: level.inactiveStep,
});

/** Whether a level starts a new stage: a new number of colours, so the board
 * is cleared and the cross starts again from one glass. */
export const startsStage = (index: number): boolean =>
  index === 0 || CAMPAIGN[index].colours !== CAMPAIGN[index - 1].colours;
