import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '@fontsource/exo-2/400.css';
import '@fontsource/exo-2/600.css';
import '@fontsource/exo-2/800.css';
import '@fontsource/exo-2/800-italic.css';
import '@fontsource/exo-2/900-italic.css';
import App from './App';
import './styles/global.css';
import { VK_BUILD } from './platform/runtime';
import { LocalSaveConflict } from './platform/cloudStorage';

const root = createRoot(document.getElementById('root')!);
const mount = () => root.render(
  <StrictMode>
    <App />
  </StrictMode>,
);

async function start(localOnly = false, preference?: 'cloud' | 'backup'): Promise<void> {
  const en = !navigator.language.toLowerCase().startsWith('ru');
  root.render(<main className="vk-start" role="status"><h1>ROTATHREE</h1><p>{en ? 'Loading your progress…' : 'Загружаем ваш прогресс…'}</p></main>);
  try {
    const { initializeVK } = await import('./platform/vk');
    await initializeVK(localOnly, preference);
    mount();
  } catch (error) {
    if (error instanceof LocalSaveConflict) {
      root.render(<main className="vk-start"><h1>ROTATHREE</h1>
        <p>{en ? 'Your device and VK have different progress. Choose which save to keep; it will replace the other.' : 'На этом устройстве и в VK разный прогресс. Выберите сохранение: оно заменит другую копию.'}</p>
        <button className="button button--primary" type="button" onClick={() => { void start(false, 'backup'); }}>{en ? 'Keep device progress' : 'Оставить прогресс устройства'}</button>
        <button className="chip" type="button" onClick={() => { void start(false, 'cloud'); }}>{en ? 'Keep VK progress' : 'Оставить прогресс VK'}</button>
      </main>);
      return;
    }
    root.render(<main className="vk-start"><h1>ROTATHREE</h1>
      <p>{en ? 'Could not connect to VK or load progress. Open the game inside VK, retry, or use this device’s backup.' : 'Не удалось подключиться к VK или загрузить прогресс. Откройте игру внутри VK, повторите попытку или используйте копию на этом устройстве.'}</p>
      <button className="button button--primary" type="button" onClick={() => { void start(); }}>{en ? 'Retry' : 'Повторить'}</button>
      <button className="chip" type="button" onClick={() => { void start(true); }}>{en ? 'Play on this device' : 'Играть на этом устройстве'}</button>
    </main>);
  }
}

if (VK_BUILD) void start();
else mount();
