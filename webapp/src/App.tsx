import { useCallback, useState } from 'react';
import { GameScreen } from './components/GameScreen';
import type { GameMode } from './components/hudState';
import { MenuScreen } from './components/MenuScreen';
import { SettingsPanel } from './components/SettingsPanel';
import { loadSettings, saveSettings, type Settings } from './services/settingsStore';

export default function App() {
  const [settings, setSettings] = useState<Settings>(loadSettings);
  /** False once the browser has refused to store the settings. */
  const [stored, setStored] = useState(true);
  /** The game being played; null on the menu. */
  const [mode, setMode] = useState<GameMode | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);

  // Every change is written to the browser's storage at once, so the keys
  // and everything else are still there when the tab is opened again.
  const updateSettings = useCallback((next: Settings) => {
    setSettings(next);
    setStored(saveSettings(next));
  }, []);

  return (
    <div className="app">
      <div className="backdrop" aria-hidden="true">
        <div className="backdrop__glow backdrop__glow--a" />
        <div className="backdrop__glow backdrop__glow--b" />
        <div className="backdrop__grid" />
      </div>

      {mode === null ? (
        <MenuScreen
          bindings={settings.bindings}
          blocked={settingsOpen}
          onPlay={setMode}
          onOpenSettings={() => setSettingsOpen(true)}
        />
      ) : (
        <GameScreen
          // The rules cannot change under a running game: new options start
          // a new one.
          key={mode + JSON.stringify(settings.game)}
          mode={mode}
          settings={settings}
          blocked={settingsOpen}
          onOpenSettings={() => setSettingsOpen(true)}
          onExit={() => setMode(null)}
        />
      )}

      {settingsOpen && (
        <SettingsPanel
          settings={settings}
          stored={stored}
          inGame={mode !== null}
          onChange={updateSettings}
          onClose={() => setSettingsOpen(false)}
        />
      )}
    </div>
  );
}
