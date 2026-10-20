import { StrictMode } from 'react';
import { createRoot } from 'react-dom/client';
import '@fontsource/exo-2/400.css';
import '@fontsource/exo-2/600.css';
import '@fontsource/exo-2/800.css';
import '@fontsource/exo-2/800-italic.css';
import '@fontsource/exo-2/900-italic.css';
import App from './App';
import './styles/global.css';
import { PLAYGAMA_BUILD } from './platform/target';
import { reportGameReady, startPlaygama } from './platform/playgama';
import { watchErrors } from './platform/telemetry';
import { STORAGE_KEYS } from './services/storage';

const mount = () => createRoot(document.getElementById('root')!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);

if (PLAYGAMA_BUILD) {
  watchErrors();
  // Bridge first, then the saves it holds, then the game: the app reads them
  // synchronously as it mounts. `game_ready` goes out once the first frame has
  // been painted, not merely scheduled.
  void startPlaygama(Object.values(STORAGE_KEYS)).then(() => {
    mount();
    requestAnimationFrame(() => requestAnimationFrame(reportGameReady));
  });
} else {
  mount();
}
