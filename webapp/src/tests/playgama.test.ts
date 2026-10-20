import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { PlaygamaBridge } from '../platform/playgama';

const EVENT_NAME = {
  PAUSE_STATE_CHANGED: 'pause_state_changed',
  AUDIO_STATE_CHANGED: 'audio_state_changed',
  INTERSTITIAL_STATE_CHANGED: 'interstitial_state_changed',
};

function fakeBridge(stored: Record<string, unknown> = {}, language = 'ru', interstitialState = 'closed') {
  const handlers = new Map<string, (value: never) => void>();
  const on = (event: string, callback: (value: never) => void) => handlers.set(event, callback);
  const bridge = {
    initialize: vi.fn(async () => {}),
    EVENT_NAME,
    platform: { language, isAudioEnabled: true, sendMessage: vi.fn(), on },
    storage: {
      get: vi.fn(async (keys: string[]) => keys.map((key) => stored[key] ?? null)),
      set: vi.fn(async () => {}),
    },
    advertisement: { isInterstitialSupported: true, interstitialState, showInterstitial: vi.fn(), on },
    analytics: { send: vi.fn() },
  };
  const emit = (event: string, value: boolean | string) => (handlers.get(event) as ((value: unknown) => void) | undefined)?.(value);
  return { bridge, emit };
}

/** Fresh copies of the modules, so that each test starts from no platform. */
async function load() {
  return {
    playgama: await import('../platform/playgama'),
    backend: await import('../platform/storageBackend'),
    lifecycle: await import('../platform/lifecycle'),
    runtime: await import('../platform/runtime'),
    storage: await import('../services/storage'),
  };
}

beforeEach(() => vi.resetModules());
afterEach(() => {
  delete window.bridge;
  vi.useRealTimers();
});

describe('Playgama Bridge', () => {
  it('loads every save in one call and sends the changes of one tick together', async () => {
    const { bridge } = fakeBridge({
      'rotathree.progress.v1': JSON.stringify({ unlocked: 3, completed: false, best: [] }),
      // Some platforms hand back the parsed value instead of the stored text.
      'rotathree.tutorial.v1': true,
    });
    window.bridge = bridge as unknown as PlaygamaBridge;
    const { playgama, storage } = await load();
    await playgama.startPlaygama(Object.values(storage.STORAGE_KEYS));

    expect(bridge.storage.get).toHaveBeenCalledTimes(1);
    expect(bridge.storage.get).toHaveBeenCalledWith(Object.values(storage.STORAGE_KEYS));
    expect(storage.loadProgress().unlocked).toBe(3);
    expect(storage.loadTutorial()).toBe(true);

    vi.useFakeTimers();
    const progress = { ...storage.loadProgress(), unlocked: 4 };
    expect(storage.saveProgress(progress)).toBe(true);
    expect(storage.saveStats(storage.defaultStats())).toBe(true);
    expect(storage.loadProgress().unlocked).toBe(4);
    expect(bridge.storage.set).not.toHaveBeenCalled();
    vi.runAllTimers();
    expect(bridge.storage.set).toHaveBeenCalledTimes(1);
    const [keys, values] = bridge.storage.set.mock.calls[0] as unknown as [string[], string[]];
    expect(keys).toEqual(['rotathree.progress.v1', 'rotathree.stats.v1']);
    expect(JSON.parse(values[0]).unlocked).toBe(4);
  });

  it('takes the language from the platform', async () => {
    window.bridge = fakeBridge({}, 'ES-es').bridge as unknown as PlaygamaBridge;
    const { playgama, runtime } = await load();
    await playgama.startPlaygama([]);
    expect(runtime.platformLocale()).toBe('es');
  });

  it('stops the game and its music under a pause or an ad, and mutes on request', async () => {
    const { bridge, emit } = fakeBridge();
    window.bridge = bridge as unknown as PlaygamaBridge;
    const { playgama, lifecycle } = await load();
    await playgama.startPlaygama([]);

    emit(EVENT_NAME.PAUSE_STATE_CHANGED, true);
    expect(lifecycle.isPlatformHidden()).toBe(true);
    emit(EVENT_NAME.PAUSE_STATE_CHANGED, false);
    expect(lifecycle.isPlatformHidden()).toBe(false);

    emit(EVENT_NAME.INTERSTITIAL_STATE_CHANGED, 'opened');
    expect(lifecycle.isPlatformHidden()).toBe(true);
    // A pause that the ad brought and the platform never lifted ends with it.
    emit(EVENT_NAME.PAUSE_STATE_CHANGED, true);
    emit(EVENT_NAME.INTERSTITIAL_STATE_CHANGED, 'closed');
    expect(lifecycle.isPlatformHidden()).toBe(false);

    emit(EVENT_NAME.AUDIO_STATE_CHANGED, false);
    expect(lifecycle.isPlatformMuted()).toBe(true);
    emit(EVENT_NAME.AUDIO_STATE_CHANGED, true);
    expect(lifecycle.isPlatformMuted()).toBe(false);
  });

  it('lets go of an ad that never gets past loading', async () => {
    const { bridge, emit } = fakeBridge();
    window.bridge = bridge as unknown as PlaygamaBridge;
    const { playgama, lifecycle } = await load();
    await playgama.startPlaygama([]);
    vi.useFakeTimers();
    emit(EVENT_NAME.INTERSTITIAL_STATE_CHANGED, 'loading');
    expect(lifecycle.isPlatformHidden()).toBe(true);
    vi.advanceTimersByTime(8_000);
    expect(lifecycle.isPlatformHidden()).toBe(false);
  });

  it('reports game_ready once and asks Bridge for interstitials', async () => {
    const { bridge } = fakeBridge();
    window.bridge = bridge as unknown as PlaygamaBridge;
    const { playgama } = await load();
    playgama.showInterstitial('game_over');
    playgama.reportGameReady();
    expect(bridge.advertisement.showInterstitial).not.toHaveBeenCalled();
    expect(bridge.platform.sendMessage).not.toHaveBeenCalled();

    await playgama.startPlaygama([]);
    playgama.reportGameReady();
    playgama.reportGameReady();
    expect(bridge.platform.sendMessage).toHaveBeenCalledTimes(1);
    expect(bridge.platform.sendMessage).toHaveBeenCalledWith('game_ready');
    playgama.showInterstitial('game_over');
    expect(bridge.advertisement.showInterstitial).toHaveBeenCalledWith('game_over');
  });

  it('stops the game for an ad that is already open when it starts', async () => {
    const { bridge, emit } = fakeBridge({}, 'ru', 'opened');
    window.bridge = bridge as unknown as PlaygamaBridge;
    const { playgama, lifecycle } = await load();
    await playgama.startPlaygama([]);
    expect(lifecycle.isPlatformHidden()).toBe(true);
    emit(EVENT_NAME.INTERSTITIAL_STATE_CHANGED, 'closed');
    expect(lifecycle.isPlatformHidden()).toBe(false);
  });

  it('sends lifecycle messages and analytics only once Bridge is up', async () => {
    const { bridge } = fakeBridge();
    window.bridge = bridge as unknown as PlaygamaBridge;
    const { playgama } = await load();
    const telemetry = await import('../platform/telemetry');
    telemetry.reportLevel('level_started', { world: 'campaign', level: 3 });
    telemetry.reportTutorial('tutorial_step', 1);
    expect(bridge.platform.sendMessage).not.toHaveBeenCalled();
    expect(bridge.analytics.send).not.toHaveBeenCalled();

    await playgama.startPlaygama([]);
    telemetry.reportLevel('level_started', { world: 'campaign', level: 3 });
    telemetry.reportLevel('level_failed', { world: 'custom' });
    telemetry.reportAbandoned({ world: 'insane' });
    telemetry.reportTutorial('tutorial_skipped', 2);
    expect(bridge.platform.sendMessage).toHaveBeenNthCalledWith(1, 'level_started', { world: 'campaign', level: '3' });
    expect(bridge.platform.sendMessage).toHaveBeenNthCalledWith(2, 'level_failed', { world: 'custom' });
    expect(bridge.analytics.send).toHaveBeenNthCalledWith(1, 'level_abandoned', { world: 'insane' });
    expect(bridge.analytics.send).toHaveBeenNthCalledWith(2, 'tutorial_skipped', { step_index: 2 });
  });

  it('keeps the browser storage when Bridge is not there', async () => {
    const { playgama, backend } = await load();
    expect(await playgama.startPlaygama(['rotathree.settings.v2'])).toBeNull();
    expect(backend.getPlatformStorage()).toBeUndefined();
  });
});

describe('PlayerHands', () => {
  it('is still only once nothing is held and nothing was pressed for a while', async () => {
    const { PlayerHands } = await import('../platform/hands');
    const hands = new PlayerHands();
    expect(hands.stillFor(700, 0)).toBe(true);

    hands.keyDown('Space', 1_000);
    expect(hands.stillFor(700, 5_000)).toBe(false);
    hands.keyUp('Space');
    expect(hands.stillFor(700, 1_500)).toBe(false);
    expect(hands.stillFor(700, 1_700)).toBe(true);

    hands.pointerDown(3, 2_000);
    hands.pointerDown(4, 2_100);
    hands.pointerUp(3);
    expect(hands.stillFor(700, 9_000)).toBe(false);
    hands.pointerUp(4);
    expect(hands.stillFor(700, 9_000)).toBe(true);
  });

  it('follows the window and forgets what was held when it loses the focus', async () => {
    const { PlayerHands } = await import('../platform/hands');
    const hands = new PlayerHands();
    const stop = hands.watch(window);
    window.dispatchEvent(new KeyboardEvent('keydown', { code: 'KeyS' }));
    expect(hands.stillFor(0, performance.now())).toBe(false);
    window.dispatchEvent(new Event('blur'));
    expect(hands.stillFor(0, performance.now())).toBe(true);

    stop();
    window.dispatchEvent(new KeyboardEvent('keydown', { code: 'KeyS' }));
    expect(hands.stillFor(0, performance.now())).toBe(true);
  });
});

describe('PerformanceSampler', () => {
  it('answers one sample per 30 s of play, with the slow frames counted', async () => {
    const { PerformanceSampler } = await import('../platform/telemetry');
    const sampler = new PerformanceSampler('0.1.0+11');
    let now = 1_000;
    let sample = null;
    // 1600 smooth frames, then two slow ones each of 60, 120, 300, 600 and
    // 1200 ms: 30.16 s of play, which the last frame completes.
    const frames = [...Array(1600).fill(16), 60, 60, 120, 120, 300, 300, 600, 600, 1200, 1200];
    for (const ms of frames) {
      now += ms;
      sample = sampler.frame(ms, now) ?? sample;
    }
    expect(sample).not.toBeNull();
    expect(sample).toMatchObject({
      target_fps: 60,
      frame_count: 1610,
      frame_time_p50_ms: 16,
      frame_time_max_ms: 1200,
      frames_over_50ms: 10,
      frames_over_100ms: 8,
      frames_over_250ms: 6,
      frames_over_500ms: 4,
      frames_over_1000ms: 2,
      build_version: '0.1.0+11',
    });
    expect(sample!.window_ms).toBe(sample!.active_ms);
    expect(sample!.active_ms).toBe(30_160);
    expect(sample!.fps_avg).toBe(53.4);
    expect(sample!.fps_p10).toBe(62.5);
  });

  it('sends a short run only when there is enough of it', async () => {
    const { PerformanceSampler } = await import('../platform/telemetry');
    const sampler = new PerformanceSampler('dev');
    for (let i = 1; i <= 120; i++) sampler.frame(16, i * 16);
    expect(sampler.flush(2_000)).toBeNull();
    for (let i = 1; i <= 400; i++) sampler.frame(16, 10_000 + i * 16);
    expect(sampler.flush(20_000)).toMatchObject({ frame_count: 400, active_ms: 6400 });
  });
});
