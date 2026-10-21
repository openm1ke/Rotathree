import { installStorage, type KeyValue } from './storageBackend';
import { setAdShowing, setPlatformHidden, setPlatformMuted } from './lifecycle';
import { setPlatformLocale } from './runtime';

/**
 * Playgama Bridge, the SDK every game on Playgama and its partner sites has
 * to carry (https://wiki.playgama.com/playgama/bridge-sdk/api). The Playgama
 * build loads it with a plain script tag (vite.config.ts); it maps each call
 * onto the platform the game runs on, and outside any platform it answers
 * from a mock.
 *
 * The required steps of Playgama's game checklist, and where each one lives:
 *
 *  1. wait for `bridge.initialize()` ............ startPlaygama
 *  2. English fallback, `platform.language` ..... startPlaygama + i18n/context.ts
 *  4. saves only through `bridge.storage`,
 *  5. all keys in a single call ................. startPlaygama + PlaygamaStorage
 *  8. obey the pause and audio events ........... watchPauseAndAudio
 *  9. `game_ready` once the game can be played .. reportGameReady (main.tsx)
 * 10. an interstitial at a natural pause ........ showInterstitial (GameScreen)
 *
 * The recommended lifecycle messages and the analytics events go through
 * sendPlatformMessage and sendAnalytics (telemetry.ts).
 */

type EventName = 'PAUSE_STATE_CHANGED' | 'AUDIO_STATE_CHANGED' | 'INTERSTITIAL_STATE_CHANGED';

/** A flat record, as Bridge's analytics takes it. */
export type AnalyticsData = Record<string, string | number | boolean>;

export interface PlaygamaBridge {
  initialize(): Promise<void>;
  EVENT_NAME: Record<EventName, string>;
  platform: {
    language: string;
    isAudioEnabled: boolean;
    sendMessage(message: string, data?: Record<string, string>): unknown;
    on(event: string, callback: (value: boolean) => void): void;
  };
  storage: {
    get(keys: string[]): Promise<unknown[]>;
    set(keys: string[], values: string[]): Promise<void>;
  };
  advertisement: {
    isInterstitialSupported: boolean;
    interstitialState?: string;
    showInterstitial(placement?: string): unknown;
    on(event: string, callback: (state: string) => void): void;
  };
  /** Bridge 2.3.0 and newer. */
  analytics?: {
    send(name: string, data?: AnalyticsData): unknown;
  };
}

declare global {
  interface Window {
    bridge?: PlaygamaBridge;
  }
}

/** How long to wait for the SDK, and then for the saves, before starting
 * without them: a game that never starts is worse than one without ads. */
const TIMEOUT_MS = 10_000;
/** An ad that reports "loading" and then nothing more stops holding the game. */
const AD_LOADING_LIMIT_MS = 8_000;
/** A pause that arrives this soon after an ad closed is that ad's own,
 * delivered late, not the player leaving. */
const LATE_AD_PAUSE_MS = 1_500;
/** The host may move the focus once more as the ad goes away. */
const FOCUS_AGAIN_MS = 150;

let ready: PlaygamaBridge | null = null;

/** The in-memory copy of every save, read synchronously by the game. Writes
 * of one tick go to the platform together, in a single `storage.set`. */
export class PlaygamaStorage implements KeyValue {
  private readonly pending = new Map<string, string>();
  private queued = false;

  constructor(
    private readonly bridge: PlaygamaBridge,
    private readonly values: Map<string, string>,
  ) {}

  getItem(key: string): string | null {
    return this.values.get(key) ?? null;
  }

  setItem(key: string, value: string): void {
    if (this.values.get(key) === value) return;
    this.values.set(key, value);
    this.pending.set(key, value);
    if (this.queued) return;
    this.queued = true;
    setTimeout(() => this.flush(), 0);
  }

  flush(): void {
    this.queued = false;
    if (this.pending.size === 0) return;
    const keys = [...this.pending.keys()];
    const values = [...this.pending.values()];
    this.pending.clear();
    this.bridge.storage.set(keys, values).catch((error: unknown) => warn('storage.set', error));
  }
}

/**
 * Brings Bridge up and loads every save in one call before the game is drawn.
 * Resolves either way; without Bridge the game runs on the browser's storage,
 * which only happens outside Playgama (local runs of the build).
 */
export async function startPlaygama(keys: readonly string[]): Promise<PlaygamaBridge | null> {
  const bridge = window.bridge;
  if (!bridge) return null;
  try {
    await withTimeout(bridge.initialize(), TIMEOUT_MS);
  } catch (error) {
    warn('initialize', error);
    return null;
  }
  ready = bridge;
  setPlatformLocale(bridge.platform.language?.slice(0, 2).toLowerCase());
  try {
    const stored = await withTimeout(bridge.storage.get([...keys]), TIMEOUT_MS);
    const values = new Map<string, string>();
    keys.forEach((key, i) => {
      const value = stored[i];
      if (value == null) return;
      // Some platforms hand back what they parsed rather than what was stored.
      values.set(key, typeof value === 'string' ? value : JSON.stringify(value));
    });
    const storage = new PlaygamaStorage(bridge, values);
    installStorage(storage);
    window.addEventListener('pagehide', () => storage.flush());
  } catch (error) {
    warn('storage.get', error);
  }
  watchPauseAndAudio(bridge);
  document.documentElement.dataset.platform = 'playgama';
  // A long press on the field must not open the browser's menu.
  document.addEventListener('contextmenu', (event) => {
    if (!(event.target instanceof Element && event.target.closest('input, textarea, [contenteditable]'))) {
      event.preventDefault();
    }
  });
  return bridge;
}

/** A pause from the platform and a full-screen ad both cover the game: its
 * clock and its music stop until both are gone. A muted platform silences
 * the music while the game goes on. */
function watchPauseAndAudio(bridge: PlaygamaBridge): void {
  let paused = false;
  let pausedByAd = false;
  let adShowing = false;
  let adEndedAt = 0;
  let loadingTimer: ReturnType<typeof setTimeout> | undefined;
  const update = () => {
    setAdShowing(adShowing);
    setPlatformHidden(paused || adShowing);
  };

  bridge.platform.on(bridge.EVENT_NAME.PAUSE_STATE_CHANGED, (isPaused) => {
    if (isPaused && !adShowing && Date.now() - adEndedAt < LATE_AD_PAUSE_MS) return;
    paused = isPaused;
    pausedByAd = isPaused && adShowing;
    update();
  });
  const onInterstitial = (state: string | undefined) => {
    clearTimeout(loadingTimer);
    const showing = state === 'loading' || state === 'opened';
    if (state === 'loading') {
      loadingTimer = setTimeout(() => {
        adShowing = false;
        update();
      }, AD_LOADING_LIMIT_MS);
    }
    if (showing === adShowing) return;
    adShowing = showing;
    if (!showing) {
      adEndedAt = Date.now();
      // Some platforms pause for the ad and never resume after it.
      if (pausedByAd) paused = pausedByAd = false;
      takeKeyboardBack();
    }
    update();
  };
  bridge.advertisement.on(bridge.EVENT_NAME.INTERSTITIAL_STATE_CHANGED, onInterstitial);
  // Some hosts open an ad together with the game, and Bridge reports only the
  // changes that follow: an ad already up stops the game from the start.
  onInterstitial(bridge.advertisement.interstitialState);
  bridge.platform.on(bridge.EVENT_NAME.AUDIO_STATE_CHANGED, (isEnabled) => setPlatformMuted(!isEnabled));
  setPlatformMuted(!bridge.platform.isAudioEnabled);
}

/** Closing an ad with a click leaves the keyboard on the host page, where the
 * game cannot hear it: the game takes it back. */
function takeKeyboardBack(): void {
  const take = () => {
    if (!document.hidden && !document.hasFocus()) window.focus();
  };
  take();
  setTimeout(take, FOCUS_AGAIN_MS);
}

let gameReadySent = false;

/** Tells the platform, once, that the first playable frame is on screen. */
export function reportGameReady(): void {
  if (gameReadySent || !ready) return;
  gameReadySent = true;
  ready.platform.sendMessage('game_ready');
}

/** A lifecycle message for the host (level_started, level_paused and the
 * like); Bridge also records it in Playgama's analytics. */
export function sendPlatformMessage(message: string, data?: Record<string, string>): void {
  if (!ready) return;
  try {
    ready.platform.sendMessage(message, data);
  } catch (error) {
    warn(`sendMessage ${message}`, error);
  }
}

/** An event only the game knows about, for Playgama's analytics. */
export function sendAnalytics(name: string, data?: AnalyticsData): void {
  const analytics = ready?.analytics;
  if (!analytics) return;
  try {
    analytics.send(name, data);
  } catch (error) {
    warn(`analytics ${name}`, error);
  }
}

/** An interstitial at a natural pause. Bridge keeps the minimum gap between
 * two of them (playgama-bridge-config.json), so most calls are declined. */
export function showInterstitial(placement: string): void {
  const bridge = ready;
  if (!bridge?.advertisement.isInterstitialSupported) return;
  try {
    bridge.advertisement.showInterstitial(placement);
  } catch (error) {
    warn('showInterstitial', error);
  }
}

function withTimeout<T>(promise: Promise<T>, ms: number): Promise<T> {
  return new Promise<T>((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('timeout')), ms);
    promise.then(
      (value) => { clearTimeout(timer); resolve(value); },
      (error: unknown) => { clearTimeout(timer); reject(error); },
    );
  });
}

function warn(action: string, error: unknown): void {
  console.warn(`Playgama: ${action} failed`, error);
}
