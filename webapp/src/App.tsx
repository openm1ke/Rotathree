import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { CampaignScreen } from './components/CampaignScreen';
import { CustomScreen } from './components/CustomScreen';
import { GameScreen } from './components/GameScreen';
import { MainMenu, type MenuTarget } from './components/MainMenu';
import { SettingsScreen } from './components/SettingsScreen';
import { StatisticsScreen } from './components/StatisticsScreen';
import { Overlay } from './components/ui';
import type { CustomSetup } from './game/modes';
import type { Session } from './game/session';
import { setPalette } from './render/theme';
import {
  addRun,
  loadCustom,
  loadProgress,
  loadSettings,
  loadStats,
  saveCustom,
  saveProgress,
  saveSettings,
  saveStats,
  type Progress,
  type RunRecord,
  type Settings,
  type Stats,
} from './services/storage';

const routeOf = (target: MenuTarget): Route => ({ name: target }) as Route;

/** Where a game was opened from, so that leaving it goes back there. */
type From = 'home' | 'campaign' | 'custom';

type Route =
  | { name: 'home' }
  | { name: 'campaign' }
  | { name: 'custom' }
  | { name: 'statistics' }
  | { name: 'settings' }
  | { name: 'play'; session: Session; from: From };

export default function App() {
  const [settings, setSettings] = useState<Settings>(() => loadSettings());
  const [progress, setProgress] = useState<Progress>(() => loadProgress());
  const [stats, setStats] = useState<Stats>(() => loadStats());
  const [custom, setCustom] = useState<CustomSetup>(() => loadCustom());
  const [route, setRoute] = useState<Route>({ name: 'home' });
  const [settingsOpen, setSettingsOpen] = useState(false);
  /** Changes for every new game, so that each one starts from scratch. */
  const [nonce, setNonce] = useState(0);
  const [stored, setStored] = useState(true);

  const activeColours = useMemo(() => {
    const { palettes } = settings;
    return (palettes.sets.find((set) => set.id === palettes.active) ?? palettes.sets[0]).colours;
  }, [settings]);

  // Everything the player sets up is written at once, so it survives closing
  // the tab; the block colours follow the active set.
  useEffect(() => {
    setPalette(activeColours);
    setStored(saveSettings(settings));
  }, [settings, activeColours]);
  useEffect(() => {
    saveProgress(progress);
  }, [progress]);
  useEffect(() => {
    saveStats(stats);
  }, [stats]);
  useEffect(() => {
    saveCustom(custom);
  }, [custom]);

  const start = useCallback((session: Session, from: From) => {
    setNonce((n) => n + 1);
    setSettingsOpen(false);
    setRoute({ name: 'play', session, from });
  }, []);

  const retry = useCallback((session: Session) => {
    setNonce((n) => n + 1);
    setRoute((r) => (r.name === 'play' ? { ...r, session } : r));
  }, []);

  const exit = useCallback(() => {
    setSettingsOpen(false);
    setRoute({ name: 'home' });
  }, []);

  const levels = useCallback(() => {
    setSettingsOpen(false);
    setRoute({ name: 'campaign' });
  }, []);

  const recordRun = useCallback((run: RunRecord) => setStats((prev) => addRun(prev, run)), []);
  const updateProgress = useCallback((next: Progress) => setProgress(next), []);
  const home = useCallback(() => setRoute({ name: 'home' }), []);

  let screen: ReactNode;
  switch (route.name) {
    case 'home':
      screen = <MainMenu progress={progress} onOpen={(target: MenuTarget) => setRoute(routeOf(target))} active={!settingsOpen} />;
      break;
    case 'campaign':
      screen = (
        <CampaignScreen
          progress={progress}
          colours={activeColours}
          onStart={(level) => start({ mode: 'campaign', level }, 'campaign')}
          onInsane={() => start({ mode: 'insane' }, 'campaign')}
          onBack={home}
          active={!settingsOpen}
        />
      );
      break;
    case 'custom':
      screen = (
        <CustomScreen
          setup={custom}
          colours={activeColours}
          onChange={setCustom}
          onStart={() => start({ mode: 'custom', setup: custom }, 'custom')}
          onBack={home}
          active={!settingsOpen}
        />
      );
      break;
    case 'statistics':
      screen = <StatisticsScreen stats={stats} progress={progress} onBack={home} active={!settingsOpen} />;
      break;
    case 'settings':
      screen = <SettingsScreen settings={settings} stored={stored} active={!settingsOpen} onChange={setSettings} onBack={home} />;
      break;
    case 'play':
      screen = (
        <GameScreen
          key={nonce}
          session={route.session}
          settings={settings}
          progress={progress}
          blocked={settingsOpen}
          onSettings={() => setSettingsOpen(true)}
          onExit={exit}
          onLevels={levels}
          onRetry={retry}
          onInsane={() => start({ mode: 'insane' }, 'campaign')}
          onCustomise={() => {
            setSettingsOpen(false);
            setRoute({ name: 'custom' });
          }}
          onRecord={recordRun}
          onProgress={updateProgress}
        />
      );
      break;
  }

  return (
    <div className="app">
      <div className="backdrop" aria-hidden="true">
        <div className="backdrop__glow backdrop__glow--a" />
        <div className="backdrop__glow backdrop__glow--b" />
        <div className="backdrop__grid" />
      </div>

      {screen}

      {settingsOpen && route.name === 'play' && (
        <Overlay>
          <SettingsScreen
            overlay
            settings={settings}
            stored={stored}
            active
            onChange={setSettings}
            onBack={() => setSettingsOpen(false)}
          />
        </Overlay>
      )}
    </div>
  );
}
