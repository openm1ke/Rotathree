import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { CampaignScreen } from './components/CampaignScreen';
import { CustomScreen } from './components/CustomScreen';
import { GameScreen } from './components/GameScreen';
import { MainMenu, type MenuTarget } from './components/MainMenu';
import { SettingsScreen } from './components/SettingsScreen';
import { StatisticsScreen } from './components/StatisticsScreen';
import { Overlay } from './components/ui';
import { DEFAULT_CUSTOM, type CustomSetup } from './game/modes';
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
  loadRun,
  saveRun,
  loadTutorial,
  saveTutorial,
  type Progress,
  type RunRecord,
  type Settings,
  type Stats,
} from './services/storage';
import { abandonedRun, type RunSave } from './services/runSave';

const routeOf = (target: MenuTarget): Route => ({ name: target }) as Route;

/** Where a game was opened from, so that leaving it goes back there. */
type From = 'home' | 'campaign' | 'custom';

type Route =
  | { name: 'home' }
  | { name: 'campaign' }
  | { name: 'custom' }
  | { name: 'statistics' }
  | { name: 'settings' }
  | { name: 'play'; session: Session; from: From; restore?: RunSave; tutorial?: boolean };

export default function App() {
  const [settings, setSettings] = useState<Settings>(() => loadSettings());
  const [progress, setProgress] = useState<Progress>(() => loadProgress());
  const [stats, setStats] = useState<Stats>(() => loadStats());
  const statsRef = useRef(stats);
  const [custom, setCustom] = useState<CustomSetup>(() => loadCustom());
  const [route, setRoute] = useState<Route>({ name: 'home' });
  const [settingsOpen, setSettingsOpen] = useState(false);
  /** Changes for every new game, so that each one starts from scratch. */
  const [nonce, setNonce] = useState(0);
  const [failedWrites, setFailedWrites] = useState<string[]>([]);
  const [savedRun, setSavedRun] = useState<RunSave | null>(() => {
    const save = loadRun();
    return save && !stats.recent.some((run) => run.id === save.id) ? save : null;
  });
  const savedRef = useRef(savedRun);
  const [tutorialDone, setTutorialDone] = useState(() => loadTutorial());
  const afterTutorial = useRef<{ session: Session; from: From } | null>(null);
  const stored = failedWrites.length === 0;
  const written = useCallback((key: string, ok: boolean) => {
    setFailedWrites((previous) => {
      if (ok === !previous.includes(key)) return previous;
      return ok ? previous.filter((item) => item !== key) : [...previous, key];
    });
  }, []);
  const checkpoint = useCallback(
    (save: RunSave | null) => {
      savedRef.current = save;
      setSavedRun(save);
      written('run', saveRun(save));
    },
    [written],
  );
  const recordRun = useCallback(
    (run: RunRecord) => {
      const next = addRun(statsRef.current, run);
      statsRef.current = next;
      // Persist before removing the resumable run, including when closing a tab.
      written('stats', saveStats(next));
      setStats(next);
    },
    [written],
  );

  const activeColours = useMemo(() => {
    const { palettes } = settings;
    return (palettes.sets.find((set) => set.id === palettes.active) ?? palettes.sets[0]).colours;
  }, [settings]);

  // Everything the player sets up is written at once, so it survives closing
  // the tab; the block colours follow the active set.
  useEffect(() => {
    setPalette(activeColours);
    written('settings', saveSettings(settings));
  }, [settings, activeColours, written]);
  useEffect(() => {
    written('progress', saveProgress(progress));
  }, [progress, written]);
  useEffect(() => {
    written('stats', saveStats(stats));
  }, [stats, written]);
  useEffect(() => {
    written('custom', saveCustom(custom));
  }, [custom, written]);

  const retryStorage = () => {
    written('settings', saveSettings(settings));
    written('progress', saveProgress(progress));
    written('stats', saveStats(stats));
    written('custom', saveCustom(custom));
    written('run', saveRun(savedRef.current));
    written('tutorial', saveTutorial(tutorialDone));
  };

  const openTutorial = useCallback((after: { session: Session; from: From } | null = null) => {
    afterTutorial.current = after;
    setNonce((n) => n + 1);
    setSettingsOpen(false);
    setRoute({
      name: 'play',
      session: { mode: 'custom', setup: { ...DEFAULT_CUSTOM, extraGlasses: 0 } },
      from: 'home',
      tutorial: true,
    });
  }, []);

  const openGame = useCallback(
    (session: Session, from: From, restore?: RunSave) => {
      if (!restore && savedRef.current) {
        const abandoned = abandonedRun(savedRef.current);
        recordRun(abandoned);
        checkpoint(null);
      }
      setNonce((n) => n + 1);
      setSettingsOpen(false);
      setRoute({ name: 'play', session, from, restore });
    },
    [checkpoint, recordRun],
  );

  const start = useCallback(
    (session: Session, from: From) => {
      if (!tutorialDone) openTutorial({ session, from });
      else openGame(session, from);
    },
    [tutorialDone, openTutorial, openGame],
  );

  const finishTutorial = useCallback(() => {
    setTutorialDone(true);
    written('tutorial', saveTutorial(true));
    const after = afterTutorial.current;
    afterTutorial.current = null;
    if (after) openGame(after.session, after.from);
    else {
      setSettingsOpen(false);
      setRoute({ name: 'home' });
    }
  }, [written, openGame]);

  const retry = useCallback((session: Session) => {
    setNonce((n) => n + 1);
    setRoute((r) => (r.name === 'play' ? { ...r, session, restore: undefined } : r));
  }, []);

  const exit = useCallback(() => {
    setSettingsOpen(false);
    setRoute({ name: 'home' });
  }, []);

  const levels = useCallback(() => {
    setSettingsOpen(false);
    setRoute({ name: 'campaign' });
  }, []);

  const updateProgress = useCallback(
    (next: Progress) => {
      written('progress', saveProgress(next));
      setProgress(next);
    },
    [written],
  );
  const home = useCallback(() => setRoute({ name: 'home' }), []);

  let screen: ReactNode;
  switch (route.name) {
    case 'home':
      screen = (
        <MainMenu
          progress={progress}
          savedRun={savedRun}
          tutorialDone={tutorialDone}
          onTutorial={() => openTutorial()}
          onResume={() => {
            if (savedRun) openGame(savedRun.session, 'home', savedRun);
          }}
          onOpen={(target: MenuTarget) => setRoute(routeOf(target))}
          active={!settingsOpen}
        />
      );
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
      screen = (
        <SettingsScreen
          settings={settings}
          stored={stored}
          active={!settingsOpen}
          onChange={setSettings}
          onBack={home}
        />
      );
      break;
    case 'play':
      screen = (
        <GameScreen
          key={nonce}
          session={route.session}
          settings={settings}
          progress={progress}
          blocked={settingsOpen}
          restore={route.restore}
          tutorial={route.tutorial}
          onCheckpoint={checkpoint}
          onTutorialDone={finishTutorial}
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

      <div className="app__content">{screen}</div>
      {!stored && (
        <div className="storage-notice" role="status">
          <span>Не удалось сохранить данные. Они пока доступны только в этой вкладке.</span>
          <button type="button" className="chip" onClick={retryStorage}>
            Повторить
          </button>
        </div>
      )}

      {settingsOpen && route.name === 'play' && (
        <Overlay label="Настройки" onDismiss={() => setSettingsOpen(false)}>
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
