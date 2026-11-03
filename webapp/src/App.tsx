import { T } from './i18n/Text';
import { I18nContext, useLanguage } from './i18n/context';
import { lazy, Suspense, useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react';
import { CampaignScreen } from './components/CampaignScreen';
import { CustomScreen } from './components/CustomScreen';
import { CubeSetupScreen } from './components/CubeSetupScreen';
import { GameScreen } from './components/GameScreen';
import { ResumeScreen } from './components/ResumeScreen';
import { MainMenu, type MenuTarget } from './components/MainMenu';
import { SettingsScreen } from './components/SettingsScreen';
import { StatisticsScreen } from './components/StatisticsScreen';
import { Overlay, SoundButton } from './components/ui';
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
  loadRuns,
  saveRuns,
  loadTutorial,
  saveTutorial,
  loadCubeTutorial,
  saveCubeTutorial,
  type Progress,
  type RunRecord,
  type Settings,
  type Stats,
} from './services/storage';
import { abandonedRun, type SavedRuns, type RunSave } from './services/runSave';
import { MusicPlayer } from './services/music';
import { sounds } from './services/sounds';
import { isPlatformHidden, isPlatformMuted, subscribeMute, subscribeVisibility } from './platform/lifecycle';
import { LanguageSwitch } from './platform/LanguageSwitch';

/** Cube draws with three.js: loaded only when it is played. */
const CubeScreen = lazy(() => import('./components/CubeScreen').then((module) => ({ default: module.CubeScreen })));

/** The page is hidden, or the platform has covered or muted the game. */
const silent = () => document.hidden || isPlatformHidden() || isPlatformMuted();

const routeOf = (target: MenuTarget): Route => ({ name: target }) as Route;

/** Where a game was opened from, so that leaving it goes back there. */
type From = 'home' | 'campaign' | 'custom';

type Route =
  | { name: 'home' }
  | { name: 'resume' }
  | { name: 'campaign' }
  | { name: 'custom' }
  | { name: 'cube' }
  /** `then`: where the tutorial leads when it is skipped — into a game, when
   * it came before the first one, or back to Cube's screen. */
  | { name: 'cubePlay'; tutorial?: boolean; then?: 'game' | 'setup' }
  | { name: 'statistics' }
  | { name: 'settings' }
  | { name: 'play'; session: Session; from: From; restore?: RunSave; resumeImmediately?: boolean; tutorial?: boolean };

export default function App() {
  const [settings, setSettings] = useState<Settings>(() => loadSettings());
  const music = useRef<MusicPlayer | null>(null);
  const musicPaused = useRef(false);
  const [gamePaused, setGamePaused] = useState(false);
  const onPauseChanged = useCallback((paused: boolean) => {
    musicPaused.current = paused;
    setGamePaused(paused);
    music.current?.setPaused(paused);
    if (silent()) music.current?.stop();
  }, []);
  const i18n = useLanguage(settings.language);
  const [progress, setProgress] = useState<Progress>(() => loadProgress());
  const [stats, setStats] = useState<Stats>(() => loadStats());
  const statsRef = useRef(stats);
  const [custom, setCustom] = useState<CustomSetup>(() => loadCustom());
  const [route, setRoute] = useState<Route>({ name: 'home' });
  const [settingsOpen, setSettingsOpen] = useState(false);
  /** Changes for every new game, so that each one starts from scratch. */
  const [nonce, setNonce] = useState(0);
  const [failedWrites, setFailedWrites] = useState<string[]>([]);
  const [savedRuns, setSavedRuns] = useState<SavedRuns>(() =>
    Object.fromEntries(
      Object.entries(loadRuns()).filter(([, save]) => !stats.recent.some((run) => run.id === save.id)),
    ),
  );
  const savedRef = useRef(savedRuns);
  const [tutorialDone, setTutorialDone] = useState(() => loadTutorial());
  const [cubeTutorialDone, setCubeTutorialDone] = useState(() => loadCubeTutorial());
  const afterTutorial = useRef<{ session: Session; from: From } | null>(null);
  const stored = failedWrites.length === 0;
  const written = useCallback((key: string, ok: boolean) => {
    setFailedWrites((previous) => {
      if (ok === !previous.includes(key)) return previous;
      return ok ? previous.filter((item) => item !== key) : [...previous, key];
    });
  }, []);
  const checkpoint = useCallback(
    (mode: Session['mode'], save: RunSave | null) => {
      const next = { ...savedRef.current };
      if (save) next[mode] = save;
      else delete next[mode];
      savedRef.current = next;
      setSavedRuns(next);
      written('run', saveRuns(next));
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

  useEffect(() => {
    const player = new MusicPlayer();
    music.current = player;
    player.setPaused(musicPaused.current);
    sounds.setDucker((seconds) => player.duck(seconds));
    const unlock = () => {
      sounds.unlock();
      if (!silent()) player.ensurePlaying();
    };
    const onVisibility = () => {
      sounds.setSilenced(silent());
      if (silent()) player.stop();
      else player.ensurePlaying();
    };
    const onPageHide = () => player.stop();
    // Every button clicks, except the on-screen pads: their actions have the game's own sounds.
    const onButton = (event: MouseEvent) => {
      const button = event.target instanceof Element ? event.target.closest('button') : null;
      if (button && !button.closest('.touch-controls, .pad-surface, .dpad')) sounds.play('ui');
    };
    const unsubscribeVisibility = subscribeVisibility(onVisibility);
    const unsubscribeMute = subscribeMute(onVisibility);
    sounds.setSilenced(silent());
    if (silent()) player.stop();
    document.addEventListener('visibilitychange', onVisibility);
    document.addEventListener('click', onButton);
    window.addEventListener('pagehide', onPageHide);
    window.addEventListener('pointerdown', unlock);
    window.addEventListener('click', unlock);
    window.addEventListener('keydown', unlock);
    return () => {
      window.removeEventListener('pointerdown', unlock);
      window.removeEventListener('click', unlock);
      window.removeEventListener('keydown', unlock);
      document.removeEventListener('visibilitychange', onVisibility);
      document.removeEventListener('click', onButton);
      window.removeEventListener('pagehide', onPageHide);
      unsubscribeVisibility();
      unsubscribeMute();
      sounds.setDucker(undefined);
      player.dispose();
      music.current = null;
    };
  }, []);
  useEffect(() => {
    music.current?.setSettings(settings.audio);
    sounds.setSettings(settings.audio);
    if (silent()) music.current?.stop();
  }, [settings.audio]);

  /** A game is on the screen, flat or Cube. */
  const inGame = route.name === 'play' || route.name === 'cubePlay';
  useEffect(() => {
    if (!inGame) onPauseChanged(false);
  }, [inGame, onPauseChanged]);

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
    written('run', saveRuns(savedRef.current));
    written('tutorial', saveTutorial(tutorialDone));
    written('cubeTutorial', saveCubeTutorial(cubeTutorialDone));
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
    (session: Session, from: From, restore?: RunSave, resumeImmediately = false) => {
      if (!restore && savedRef.current[session.mode]) {
        const abandoned = abandonedRun(savedRef.current[session.mode]!);
        recordRun(abandoned);
        checkpoint(session.mode, null);
      }
      setNonce((n) => n + 1);
      setSettingsOpen(false);
      setRoute({ name: 'play', session, from, restore, resumeImmediately });
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

  /** The campaign where the player left it: the saved run, else the furthest
   * open level, started through `fresh`. */
  const playCampaign = useCallback(
    (fresh: (session: Session, from: From) => void) => {
      const save = savedRef.current.campaign;
      if (save) openGame(save.session, 'home', save, true);
      else fresh({ mode: 'campaign', level: progress.unlocked }, 'home');
    },
    [openGame, progress.unlocked],
  );

  /** `played`: the player pressed Play on the last lesson rather than Skip.
   * A tutorial opened from the menu then goes on into the campaign. */
  const finishTutorial = useCallback(
    (played: boolean) => {
      setTutorialDone(true);
      written('tutorial', saveTutorial(true));
      const after = afterTutorial.current;
      afterTutorial.current = null;
      if (after) openGame(after.session, after.from);
      else if (played) playCampaign(openGame);
      else {
        setSettingsOpen(false);
        setRoute({ name: 'home' });
      }
    },
    [written, openGame, playCampaign],
  );

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
  const playCube = useCallback(() => {
    setNonce((n) => n + 1);
    setSettingsOpen(false);
    setRoute({ name: 'cubePlay' });
  }, []);
  const openCubeTutorial = useCallback((then: 'game' | 'setup') => {
    setNonce((n) => n + 1);
    setSettingsOpen(false);
    setRoute({ name: 'cubePlay', tutorial: true, then });
  }, []);
  /** Cube's first game begins with its lessons. */
  const startCube = useCallback(() => {
    if (cubeTutorialDone) playCube();
    else openCubeTutorial('game');
  }, [cubeTutorialDone, playCube, openCubeTutorial]);
  const finishCubeTutorial = useCallback(
    (played: boolean, then: 'game' | 'setup' = 'setup') => {
      setCubeTutorialDone(true);
      written('cubeTutorial', saveCubeTutorial(true));
      if (played || then === 'game') playCube();
      else {
        setSettingsOpen(false);
        setRoute({ name: 'cube' });
      }
    },
    [written, playCube],
  );
  /** The quick sound switch mutes music and effects together, and turns both
   * back on. */
  const toggleMusic = useCallback(
    () => setSettings((current) => {
      const on = !(current.audio.music || current.audio.sounds);
      return { ...current, audio: { ...current.audio, music: on, sounds: on } };
    }),
    [],
  );

  let screen: ReactNode;
  switch (route.name) {
    case 'home':
      screen = (
        <MainMenu
          progress={progress}
          savedRuns={savedRuns}
          tutorialDone={tutorialDone}
          onTutorial={() => openTutorial()}
          onResume={() => setRoute({ name: 'resume' })}
          onPlayCampaign={() => playCampaign(start)}
          onOpen={(target: MenuTarget) => setRoute(routeOf(target))}
          active={!settingsOpen}
        />
      );
      break;
    case 'resume':
      screen = (
        <ResumeScreen runs={savedRuns} onResume={(save) => openGame(save.session, 'home', save)} onBack={home} />
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
    case 'cube':
      screen = (
        <CubeSetupScreen
          settings={settings}
          stats={stats}
          colours={activeColours}
          onChange={(cube) => setSettings((current) => ({ ...current, cube }))}
          onStart={startCube}
          onTutorial={() => openCubeTutorial('setup')}
          onBack={home}
          active={!settingsOpen}
        />
      );
      break;
    case 'cubePlay':
      screen = (
        <Suspense fallback={null}>
          <CubeScreen
            key={nonce}
            settings={settings}
            blocked={settingsOpen}
            onSettings={() => setSettingsOpen(true)}
            onToggleMusic={toggleMusic}
            onPauseChanged={onPauseChanged}
            onExit={exit}
            onSetup={() => {
              setSettingsOpen(false);
              setRoute({ name: 'cube' });
            }}
            onRetry={playCube}
            tutorial={route.tutorial}
            onTutorialDone={(played) => finishCubeTutorial(played, route.then)}
            onRecord={recordRun}
          />
        </Suspense>
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
          resumeImmediately={route.resumeImmediately}
          tutorial={route.tutorial}
          onCheckpoint={(save) => checkpoint(route.session.mode, save)}
          onTutorialDone={finishTutorial}
          onSettings={() => setSettingsOpen(true)}
          onToggleMusic={toggleMusic}
          onPauseChanged={onPauseChanged}
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
    <I18nContext.Provider value={i18n}>
    <div className="app">
      <div className={`backdrop${inGame && !settings.effects.fieldBackground ? ' backdrop--static' : ''}`} data-paused={inGame && gamePaused} aria-hidden="true">
        <div className="backdrop__glow backdrop__glow--a" />
        <div className="backdrop__glow backdrop__glow--b" />
        <div className="backdrop__grid" />
      </div>

      <div className="app__content">{screen}</div>
      {route.name === 'home' && (
        <div className="corner-controls">
          <SoundButton on={settings.audio.music || settings.audio.sounds} onToggle={toggleMusic} />
          <LanguageSwitch
            language={i18n.language}
            onChange={(language) => setSettings((current) => ({ ...current, language }))}
          />
        </div>
      )}
      {!stored && (
        <div className="storage-notice" role="status">
          <span><T>Не удалось сохранить данные. Они пока доступны только в этой вкладке.</T></span>
          <button type="button" className="chip" onClick={retryStorage}><T>
            Повторить
          </T></button>
        </div>
      )}

      {settingsOpen && inGame && (
        <Overlay label="Настройки" className="overlay--settings" onDismiss={() => setSettingsOpen(false)}>
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
    </I18nContext.Provider>
  );
}
