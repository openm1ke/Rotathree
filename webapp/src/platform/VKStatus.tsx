import { useSyncExternalStore } from 'react';
import { T } from '../i18n/Text';
import { vkStorage } from './runtime';

export function VKStatus() {
  const storage = vkStorage!;
  const status = useSyncExternalStore(storage.subscribe, storage.getStatus);
  if (status !== 'error' && status !== 'local') return null;
  return <div className="storage-notice" role="status">
    <span><T>{status === 'local'
      ? 'Синхронизация VK отключена. Прогресс остаётся на этом устройстве.'
      : 'Не удалось сохранить прогресс в VK. Повторите попытку перед выходом.'}</T></span>
    {status === 'error' && <button type="button" className="chip" onClick={() => { void storage.flush().catch(() => {}); }}><T>Повторить</T></button>}
  </div>;
}
