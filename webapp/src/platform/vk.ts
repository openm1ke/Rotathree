import bridge, { type ParentConfigData } from '@vkontakte/vk-bridge';
import { STORAGE_KEYS } from '../services/storage';
import { CloudStorage, type CloudTransport } from './cloudStorage';
import { installStorage } from './storageBackend';
import { setPlatformHidden } from './lifecycle';
import { setPlatformLocale, setPlatformMobile, setVKStorage } from './runtime';

export function timeout<T>(promise: Promise<T>, ms = 10000): Promise<T> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('VK request timed out')), ms);
    promise.then((value) => { clearTimeout(timer); resolve(value); }, (error) => { clearTimeout(timer); reject(error); });
  });
}

function applyConfig(config: ParentConfigData): void {
  if ('insets' in config && config.insets) applyInsets(config.insets);
  if ('adaptivity' in config && config.adaptivity?.startsWith('force_mobile')) setPlatformMobile(true);
}

function applyInsets(insets: { top: number; right: number; bottom: number; left: number }): void {
  for (const edge of ['top', 'right', 'bottom', 'left'] as const) {
    const value = Number.isFinite(insets[edge]) ? Math.max(0, Math.min(200, insets[edge])) : 0;
    document.documentElement.style.setProperty(`--vk-inset-${edge}`, `${value}px`);
  }
}

/** No profile, OAuth token, contact or notification permissions are requested. */
export async function initializeVK(localOnly = false, preference?: 'cloud' | 'backup'): Promise<void> {
  if (!bridge.isEmbedded()) throw new Error('Open this build inside VK');
  await timeout(bridge.send('VKWebAppInit'));
  const params = await timeout(bridge.send('VKWebAppGetLaunchParams'));
  const expectedId = import.meta.env.VITE_VK_APP_ID;
  if (expectedId && String(params.vk_app_id) !== expectedId) throw new Error('Unexpected VK app ID');
  if (!params.vk_app_id || !params.vk_user_id) throw new Error('Missing VK launch parameters');
  setPlatformLocale(params.vk_language);
  setPlatformMobile(/android|iphone|ipad|mobile/i.test(params.vk_platform));
  try {
    applyConfig(await timeout(bridge.send('VKWebAppGetConfig'), 3000));
  } catch { /* DOM dimensions and browser safe-area remain a fallback. */ }
  let local: Storage | null = null;
  try { local = window.localStorage; } catch { /* Embedded browser may deny local storage. */ }
  if (localOnly && !local) throw new Error('Local storage is unavailable');
  const transport: CloudTransport = {
    async get(keys) {
      const result = await timeout(bridge.send('VKWebAppStorageGet', { keys }));
      return Object.fromEntries(result.keys.map((item) => [item.key, item.value]));
    },
    async set(key, value) {
      const response = await timeout(bridge.send('VKWebAppStorageSet', { key, value }));
      if (!response.result) throw new Error('VK did not confirm the save');
    },
  };
  const storage = new CloudStorage(transport, Object.values(STORAGE_KEYS), local,
    `rotathree.vk.${params.vk_app_id}.${params.vk_user_id}`, !localOnly);
  await storage.hydrate(preference);
  installStorage(storage);
  setVKStorage(storage);
  bridge.subscribe((event) => {
    const { type, data } = event.detail;
    if (type === 'VKWebAppViewHide') {
      setPlatformHidden(true);
      void storage.flush().catch(() => {});
    } else if (type === 'VKWebAppViewRestore') setPlatformHidden(false);
    else if (type === 'VKWebAppUpdateConfig') applyConfig(data);
    else if (type === 'VKWebAppUpdateInsets') applyInsets(data.insets);
  });
  window.addEventListener('pagehide', () => { void storage.flush().catch(() => {}); });
  document.addEventListener('visibilitychange', () => {
    if (document.hidden) void storage.flush().catch(() => {});
  });
  document.documentElement.dataset.platform = 'vk';
}
