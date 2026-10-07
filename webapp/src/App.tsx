import { useCallback, useState } from 'react';
import { GameScreen } from './components/GameScreen';
import { MenuScreen } from './components/MenuScreen';
import { SettingsPanel } from './components/SettingsPanel';
import { loadSettings, saveSettings, type Settings } from './services/settingsStore';

type Screen = 'menu' | 'game';

export default function App() {
  const [settings, setSettings] = useState<Settings>(loadSettings);
  const [screen, setScreen] = useState<Screen>('menu');
  const [settingsOpen, setSettingsOpen] = useState(false);

  const updateSettings = useCallback((next: Settings) => {
    setSettings(next);
    saveSettings(next);
  }, []);

  return (
    <div className="app">
      <div className="backdrop" aria-hidden="true">
        <div className="backdrop__glow backdrop__glow--a" />
        <div className="backdrop__glow backdrop__glow--b" />
        <div className="backdrop__grid" />
      </div>

      {screen === 'menu' ? (
        <MenuScreen
          bindings={settings.bindings}
          blocked={settingsOpen}
          onPlay={() => setScreen('game')}
          onOpenSettings={() => setSettingsOpen(true)}
        />
      ) : (
        <GameScreen
          // The rules cannot change under a running game: new options start
          // a new one.
          key={JSON.stringify(settings.game)}
          settings={settings}
          blocked={settingsOpen}
          onOpenSettings={() => setSettingsOpen(true)}
          onExit={() => setScreen('menu')}
        />
      )}

      {settingsOpen && (
        <SettingsPanel
          settings={settings}
          inGame={screen === 'game'}
          onChange={updateSettings}
          onClose={() => setSettingsOpen(false)}
        />
      )}
    </div>
  );
}
