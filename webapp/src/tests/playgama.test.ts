import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import type { PlaygamaBridge } from '../platform/playgama';

const EVENT_NAME = {
  PAUSE_STATE_CHANGED: 'pause_state_changed',
  AUDIO_STATE_CHANGED: 'audio_state_changed',
  INTERSTITIAL_STATE_CHANGED: 'interstitial_state_changed',
};

function fakeBridge(stored: Record<string, unknown> = {}, language = 'ru') {
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
    advertisement: { isInterstitialSupported: true, showInterstitial: vi.fn(), on },
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

  it('keeps the browser storage when Bridge is not there', async () => {
    const { playgama, backend } = await load();
    expect(await playgama.startPlaygama(['rotathree.settings.v2'])).toBeNull();
    expect(backend.getPlatformStorage()).toBeUndefined();
  });
});
