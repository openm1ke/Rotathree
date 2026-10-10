import { afterEach, beforeEach, expect, it, vi } from 'vitest';
import { initializeVK } from '../platform/vk';
import { getPlatformStorage, installStorage } from '../platform/storageBackend';
import { isPlatformHidden, setPlatformHidden } from '../platform/lifecycle';
import { platformNeedsTouch, setPlatformMobile } from '../platform/runtime';

const mock = vi.hoisted(() => ({ embedded: true, send: vi.fn(), subscribe: vi.fn() }));
vi.mock('@vkontakte/vk-bridge', () => ({ default: {
  isEmbedded: () => mock.embedded,
  send: mock.send,
  subscribe: mock.subscribe,
} }));

beforeEach(() => {
  mock.embedded = true;
  vi.stubEnv('VITE_VK_APP_ID', '54815388');
  mock.send.mockImplementation(async (method: string) => {
    if (method === 'VKWebAppInit') return { result: true };
    if (method === 'VKWebAppGetLaunchParams') return { vk_app_id: 54815388, vk_user_id: 1, vk_platform: 'mobile_web' };
    if (method === 'VKWebAppGetConfig') return { insets: { top: 20, right: 0, bottom: 10, left: 0 }, adaptivity: 'force_mobile' };
    if (method === 'VKWebAppStorageGet') return { keys: [] };
    if (method === 'VKWebAppStorageSet') return { result: true };
    throw new Error('Unexpected permission request');
  });
});
afterEach(() => {
  installStorage(undefined);
  setPlatformHidden(false);
  setPlatformMobile(false);
  mock.send.mockReset();
  mock.subscribe.mockReset();
  vi.unstubAllEnvs();
});

it('initializes before installing saves and applies mobile controls and safe areas', async () => {
  await initializeVK();
  expect(mock.send.mock.calls.map(([method]) => method)).toEqual(['VKWebAppInit', 'VKWebAppGetLaunchParams', 'VKWebAppGetConfig', 'VKWebAppStorageGet']);
  expect(getPlatformStorage()).toBeDefined();
  expect(platformNeedsTouch()).toBe(true);
  expect(document.documentElement.style.getPropertyValue('--vk-inset-top')).toBe('20px');
  const subscriber = mock.subscribe.mock.calls[0][0];
  subscriber({ detail: { type: 'VKWebAppViewHide', data: {} } });
  expect(isPlatformHidden()).toBe(true);
  subscriber({ detail: { type: 'VKWebAppViewRestore', data: {} } });
  expect(isPlatformHidden()).toBe(false);
});

it('fails safely without mounting an empty save when cloud loading fails', async () => {
  mock.send.mockImplementation(async (method: string) => {
    if (method === 'VKWebAppInit') return { result: true };
    if (method === 'VKWebAppGetLaunchParams') return { vk_app_id: 54815388, vk_user_id: 1, vk_platform: 'desktop_web' };
    throw new Error('offline');
  });
  await expect(initializeVK()).rejects.toThrow('offline');
  expect(getPlatformStorage()).toBeUndefined();
  expect(mock.subscribe).not.toHaveBeenCalled();
  expect(mock.send.mock.calls.some(([method]) => method === 'VKWebAppStorageSet')).toBe(false);
});

it('rejects standalone launch or a different application ID', async () => {
  mock.embedded = false;
  await expect(initializeVK()).rejects.toThrow('inside VK');
  expect(mock.send).not.toHaveBeenCalled();
  mock.embedded = true;
  vi.stubEnv('VITE_VK_APP_ID', 'different-app');
  await expect(initializeVK()).rejects.toThrow('Unexpected VK app ID');
  expect(getPlatformStorage()).toBeUndefined();
});
