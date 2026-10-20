import type { ModeId } from '../game/modes';
import { sendAnalytics, sendPlatformMessage, type AnalyticsData } from './playgama';

/**
 * What the game tells Playgama about play, after Playgama's telemetry guide
 * (get_game_telemetry_guide) and Bridge's platform and analytics pages. Every
 * call does nothing without Bridge, so the site and the tests send nothing.
 *
 * - A run, and each campaign level in it, goes out as Bridge's own lifecycle
 *   messages: level_started, level_paused, level_resumed, level_completed,
 *   level_failed. CrazyGames, Poki and Yandex take them, and Bridge records
 *   each one in Playgama's analytics, so they are not sent there twice.
 * - Analytics gets only what the game alone knows: a run the player gave up
 *   (level_abandoned), the tutorial's steps and how it ended, and
 *   performance_sample.
 *
 * Names stay fixed and the changing part goes into the data, from bounded
 * sets: the mode, and the campaign level from 1 to 16.
 */

/** Where in the game a run is: its mode, and in the campaign its level. */
export interface Place {
  world: ModeId;
  level?: number;
}

type LevelMessage = 'level_started' | 'level_paused' | 'level_resumed' | 'level_completed' | 'level_failed';

const placeData = ({ world, level }: Place): Record<string, string> =>
  level === undefined ? { world } : { world, level: String(level) };

export const reportLevel = (message: LevelMessage, place: Place) => sendPlatformMessage(message, placeData(place));

/** The player ended the run, or started it over, before it was decided. */
export const reportAbandoned = (place: Place) => sendAnalytics('level_abandoned', placeData(place));

/** A tutorial step done (its index), or how the tutorial ended and where. */
export const reportTutorial = (
  event: 'tutorial_step' | 'tutorial_completed' | 'tutorial_skipped' | 'tutorial_left',
  step: number,
) => sendAnalytics(event, { step_index: step });

export const reportPerformance = (sample: AnalyticsData | null) => {
  if (sample) sendAnalytics('performance_sample', sample);
};

/** Active play gathered into one performance sample, as the guide asks. */
export const SAMPLE_ACTIVE_MS = 30_000;
/** At the end of a run, a shorter stretch is still worth sending. */
export const SAMPLE_MIN_ACTIVE_MS = 5_000;
/** The game draws on every display frame and is built for 60 of them. */
const TARGET_FPS = 60;
const SLOW_FRAMES = [50, 100, 250, 500, 1000] as const;

let errors = 0;
let rejections = 0;

/** Counts uncaught errors and rejected promises for the samples. */
export function watchErrors(target: Window = window): void {
  target.addEventListener('error', () => errors++);
  target.addEventListener('unhandledrejection', () => rejections++);
}

const round = (value: number) => Math.round(value * 10) / 10;

/**
 * Frame times of visible, running play: not menus, pauses, ads or a hidden
 * page. The caller hands over only frames whose previous frame was play too,
 * so a gap in the background never counts as one long frame.
 */
export class PerformanceSampler {
  private frames: number[] = [];
  private activeMs = 0;
  private startedAt = 0;

  constructor(private readonly buildVersion = __BUILD_VERSION__) {}

  /** One frame, `frameMs` after the last. Answers a sample once enough play
   * has gathered, and starts the next one. */
  frame(frameMs: number, now: number): AnalyticsData | null {
    if (this.frames.length === 0) this.startedAt = now - frameMs;
    this.frames.push(frameMs);
    this.activeMs += frameMs;
    return this.activeMs >= SAMPLE_ACTIVE_MS ? this.take(now) : null;
  }

  /** What has gathered, at the end of a run, when there is enough of it. */
  flush(now: number): AnalyticsData | null {
    if (this.activeMs >= SAMPLE_MIN_ACTIVE_MS) return this.take(now);
    this.frames = [];
    this.activeMs = 0;
    return null;
  }

  private take(now: number): AnalyticsData {
    const sorted = [...this.frames].sort((a, b) => a - b);
    const count = sorted.length;
    const at = (share: number) => sorted[Math.min(count - 1, Math.max(0, Math.ceil(share * count) - 1))];
    const sample: AnalyticsData = {
      target_fps: TARGET_FPS,
      window_ms: Math.round(now - this.startedAt),
      active_ms: Math.round(this.activeMs),
      frame_count: count,
      fps_avg: round((count * 1000) / this.activeMs),
      // The slowest tenth of frames sets the 10th percentile of FPS.
      fps_p10: round(1000 / at(0.9)),
      frame_time_p50_ms: round(at(0.5)),
      frame_time_p95_ms: round(at(0.95)),
      frame_time_p99_ms: round(at(0.99)),
      frame_time_max_ms: round(sorted[count - 1]),
      js_error_count: errors,
      unhandled_rejection_count: rejections,
      build_version: this.buildVersion,
    };
    for (const limit of SLOW_FRAMES) sample[`frames_over_${limit}ms`] = sorted.filter((ms) => ms > limit).length;
    this.frames = [];
    this.activeMs = 0;
    errors = 0;
    rejections = 0;
    return sample;
  }
}
