import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { useEffect, useRef, useState } from 'react';
import { CAMPAIGN, CAMPAIGN_LAST, levelConfig, startsStage } from '../game/campaign';
import { GameEngine, type GameEvent } from '../game/engine';
import { sideAtSlot, slotOfSide } from '../game/glass';
import { planFor, type Session } from '../game/session';
import { MODE_NAMES, type RunPlan } from '../game/modes';
import type { Side } from '../game/side';
import { KeyboardController } from '../input/keyboard';
import { keyLabel, type Action } from '../input/bindings';
import { PadController, type PadAction } from '../input/pads';
import { useTouchControls } from '../input/touch';
import { makePiece } from '../game/piece';
import type { RunSave, RunTotals } from '../services/runSave';
import { TouchControls } from './TouchControls';
import { PAD_SLOTS } from '../input/pads';
import { TutorialPanel, TUTORIAL_LESSONS } from './TutorialPanel';
import { Effects } from '../render/effects';
import { AdaptiveQuality } from '../render/quality';
import { GameRenderer } from '../render/renderer';
import { paletteRevision } from '../render/theme';
import type { Palettes, Progress, RunRecord, Settings } from '../services/storage';
import { Hud } from './Hud';
import { LevelBanner, type BannerData } from './LevelBanner';
import { EMPTY_HUD, formatScore, type Callout, type HudState } from './hudState';
import { Button, Overlay } from './ui';
import { formatColours, formatDuration, formatNumber, formatPoints } from './format';

type Status = 'playing' | 'paused' | 'over' | 'done';

const NO_TOTALS: RunTotals = { score: 0, pieces: 0, matches: 0, bestCombo: 0, seconds: 0 };

interface Props {
  session: Session;
  settings: Settings;
  progress: Progress;
  /** True while the settings are open over the game: nothing moves. */
  blocked: boolean;
  onSettings: () => void;
  /** Back to the main menu. */
  onExit: () => void;
  /** Back to the campaign's levels. */
  onLevels: () => void;
  /** A new game of the given session: the campaign level, or the same run. */
  onRetry: (session: Session) => void;
  /** Opens Insane once the campaign is finished. */
  onInsane: () => void;
  /** Back to the custom setup. */
  onCustomise: () => void;
  onRecord: (run: RunRecord) => void;
  onProgress: (progress: Progress) => void;
  restore?: RunSave | null;
  onCheckpoint?: (save: RunSave | null) => void;
  tutorial?: boolean;
  onTutorialDone?: () => void;
}

/** Longest frame the game will simulate in one go (hitches, tab switches). */
const MAX_FRAME_SECONDS = 0.05;

/** Browsers refuse, or silently shrink, canvases much beyond this many
 * device pixels a side. */
const MAX_CANVAS_PIXELS = 4096;

/** The resolution the field is drawn at. Kept for the whole visit: a machine
 * that needed fewer pixels in one game needs them in the next. */
const quality = new AdaptiveQuality();

const SLOT_NAMES = ['Верхний', 'Правый', 'Нижний', 'Левый'] as const;

const paletteColours = (palettes: Palettes): string[] =>
  (palettes.sets.find((set) => set.id === palettes.active) ?? palettes.sets[0]).colours;

const newId = (): string => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;

/** The playable screen: owns the engine, runs it from the frame loop, drives
 * the campaign's levels and turns key presses into engine input. The parent
 * re-keys it for every new game, so a session never changes under it. */
export function GameScreen(props: Props) {
  const { t } = useI18n();
  const { session, settings, blocked, tutorial = false } = props;
  const touch = useTouchControls();
  const runId = useRef(props.restore?.id ?? newId());
  const frameRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rendererRef = useRef<GameRenderer | null>(null);
  const actions = useRef({
    togglePause: () => {},
    retry: () => {},
    activeGlass: (_side: number) => {},
    down: (_action: PadAction) => {},
    up: (_action: PadAction) => {},
    nextLesson: () => {},
    practice: (_action: Action) => {},
    leave: (_destination: () => void, _save = true) => {},
  });

  const [size, setSize] = useState(0);
  const [hud, setHud] = useState<HudState>(EMPTY_HUD);
  const [callout, setCallout] = useState<Callout | null>(null);
  const [banner, setBanner] = useState<BannerData | null>(null);
  const [status, setStatus] = useState<Status>('playing');
  const [result, setResult] = useState<RunRecord | null>(null);
  const [level, setLevel] = useState(session.mode === 'campaign' ? session.level : -1);
  const [overSlot, setOverSlot] = useState(0);
  const [tutorialStep, setTutorialStep] = useState(0);
  const [performed, setPerformed] = useState(false);

  // The loop reads the latest settings and callbacks through this.
  const live = useRef(props);
  useEffect(() => {
    live.current = props;
  });

  useEffect(() => {
    const frame = frameRef.current!;
    const canvas = canvasRef.current!;
    const campaign = session.mode === 'campaign';
    const plan: RunPlan = planFor(session);
    const newEngine = (p: RunPlan): GameEngine => {
      const engine = new GameEngine(p.config);
      engine.setRamp(p.ramp);
      return engine;
    };

    let engine = newEngine(plan);
    if (props.restore) engine.restoreSnapshot(props.restore.engine);
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
    // Development only: lets the browser checks drive a running game.
    const exposeEngine = () => {
      if (import.meta.env.DEV) Object.assign(window, { __rotathree: engine });
    };
    exposeEngine();
    const fx = new Effects();
    fx.reset(engine.activeSide);
    const renderer = new GameRenderer(canvas);
    rendererRef.current = renderer;
    // Development only: lets a benchmark draw frames on demand.
    if (import.meta.env.DEV) Object.assign(window, { __rotathreeView: { renderer, fx } });
    /** Set when the picture has to be drawn even though nothing moved. */
    let dirty = true;
    const measure = () => {
      const style = getComputedStyle(frame);
      const width = frame.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      const height = frame.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
      const next = Math.floor(Math.max(0, Math.min(width, height)));
      setSize(next);
      const dpr = Math.min(window.devicePixelRatio || 1, MAX_CANVAS_PIXELS / Math.max(1, next));
      renderer.resize(next, dpr * quality.scale);
      quality.restart();
      dirty = true;
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(frame);

    let current: Status = props.restore ? 'paused' : 'playing';
    setStatus(current);
    const setRunStatus = (next: Status) => {
      current = next;
      setStatus(next);
    };

    let campaignLevel = campaign ? session.level : -1;
    let levelBase = props.restore?.levelBase ?? 0;
    let carry: RunTotals = props.restore?.carry ?? NO_TOTALS;
    let completing = false;
    let finished = false;
    let pendingLevel: number | null = props.restore?.banner?.pendingLevel ?? null;
    let saveCharge = 0;
    let wasFrozen = false;
    let lesson = 0;
    let lessonPerformed = false;
    let tutorialMatch = false;
    let calloutId = 0;
    let bannerId = 0;
    let banner: {
      data: Omit<BannerData, 'id' | 'seconds'>;
      left: number;
      blocking: boolean;
      then: (() => void) | null;
    } | null = null;
    let shown = EMPTY_HUD;
    let progressNow = live.current.progress;

    const totals = (): RunTotals => ({
      score: carry.score + engine.state.score,
      pieces: carry.pieces + engine.state.piecesPlaced,
      matches: carry.matches + engine.state.matches,
      bestCombo: Math.max(carry.bestCombo, engine.state.bestCombo),
      seconds: carry.seconds + engine.state.elapsedSeconds,
    });

    const swapEngine = (next: GameEngine) => {
      carry = totals();
      engine = next;
      exposeEngine();
      fx.reset(engine.activeSide);
    };

    const showBanner = (
      data: Omit<BannerData, 'id' | 'seconds'>,
      seconds: number,
      blocking: boolean,
      then?: () => void,
    ) => {
      bannerId++;
      setBanner({ ...data, id: bannerId, seconds });
      banner = { data, left: seconds, blocking, then: then ?? null };
    };

    const stageColours = (count: number) => paletteColours(live.current.settings.palettes).slice(0, count);

    const recordRun = (completed: boolean, interrupted = false) => {
      if (tutorial) return;
      const t = totals();
      const record: RunRecord = {
        id: runId.current,
        mode: session.mode,
        at: Date.now(),
        score: t.score,
        pieces: t.pieces,
        matches: t.matches,
        bestCombo: t.bestCombo,
        seconds: t.seconds,
        level: campaign ? (completed ? CAMPAIGN_LAST + 1 : campaignLevel + 1) : engine.state.speedLevel + 1,
        completed,
        interrupted,
      };
      live.current.onRecord(record);
      live.current.onCheckpoint?.(null);
      setResult(record);
    };

    const gameOver = (side: Side) => {
      finished = true;
      setOverSlot(slotOfSide(engine.activeSide, side));
      recordRun(false);
      setRunStatus('over');
    };

    const campaignDone = () => {
      finished = true;
      recordRun(true);
      setRunStatus('done');
    };

    /** A campaign level is finished: keep its best score, open the next one,
     * and announce it. The game stands still while the banner shows. */
    const completeLevel = () => {
      completing = true;
      const index = campaignLevel;
      const levelScore = engine.state.score - levelBase;
      const best = progressNow.best.map((value, i) => (i === index ? Math.max(value, levelScore) : value));
      const next = Math.min(index + 1, CAMPAIGN_LAST);
      progressNow = {
        unlocked: Math.max(progressNow.unlocked, next),
        completed: progressNow.completed || index === CAMPAIGN_LAST,
        best,
      };
      live.current.onProgress(progressNow);
      if (index === CAMPAIGN_LAST) {
        campaignDone();
        return;
      }
      pendingLevel = next;
      const to = CAMPAIGN[next];
      showBanner(
        {
          kicker: `Уровень ${index + 1} пройден`,
          title: formatPoints(levelScore),
          sub: `Дальше: ${to.colours} цв. · ${to.glasses} ст. · цель ${formatScore(to.target)}`,
        },
        2.2,
        true,
        () => advanceTo(next),
      );
    };

    /** Moves to the next campaign level. A new number of colours starts a
     * fresh board with one glass; a new glass grows out of the cross while the
     * falling goes on. */
    const advanceTo = (next: number) => {
      completing = false;
      pendingLevel = null;
      const from = CAMPAIGN[campaignLevel];
      const to = CAMPAIGN[next];
      campaignLevel = next;
      setLevel(next);
      if (startsStage(next)) {
        swapEngine(newEngine({ config: levelConfig(to), ramp: null }));
        levelBase = 0;
        showBanner(
          {
            kicker: 'Новый этап',
            title: formatColours(to.colours),
            sub: 'стаканы снова по одному',
            colours: stageColours(to.colours),
          },
          2.2,
          true,
        );
      } else {
        engine.setSteps(to.activeStep, to.inactiveStep);
        if (to.glasses > from.glasses) {
          engine.addGlass();
          showBanner(
            { kicker: 'Новый стакан', title: `${to.glasses}-й стакан`, sub: 'первая фигура уже в пути' },
            1.6,
            false,
          );
        } else {
          showBanner(
            {
              kicker: `Уровень ${next + 1}`,
              title: `цель ${formatScore(to.target)}`,
              sub: `${to.glasses} ст. · ${to.colours} цв.`,
            },
            1.6,
            false,
          );
        }
        levelBase = engine.state.score;
      }
    };

    const savedBanner = props.restore?.banner;
    if (savedBanner) {
      completing = savedBanner.pendingLevel !== null;
      showBanner(
        {
          kicker: savedBanner.kicker,
          title: savedBanner.title,
          sub: savedBanner.sub,
          colours: stageColours(savedBanner.colours),
        },
        savedBanner.left,
        savedBanner.blocking,
        savedBanner.pendingLevel === null ? undefined : () => advanceTo(savedBanner.pendingLevel!),
      );
    }
    const checkpoint = () => {
      if (tutorial || finished || engine.isGameOver || !live.current.onCheckpoint) return;
      live.current.onCheckpoint({
        version: 1,
        id: runId.current,
        session: campaign ? { mode: 'campaign', level: campaignLevel } : session,
        engine: engine.snapshot(),
        carry: { ...carry },
        levelBase,
        savedAt: Date.now(),
        banner:
          banner === null
            ? null
            : {
                kicker: banner.data.kicker,
                title: banner.data.title,
                sub: banner.data.sub,
                left: banner.left,
                blocking: banner.blocking,
                pendingLevel,
                colours: banner.data.colours?.length ?? 0,
              },
      });
      saveCharge = 0;
    };
    const allowsTutorial = (action: Action) =>
      !tutorial ||
      (engine.phase === 'playing' &&
        (lesson === 1
          ? action === 'moveLeft' || action === 'moveRight'
          : lesson === 2
            ? action === 'rotateCW' || action === 'rotateCCW'
            : lesson === 3
              ? action === 'hardDrop'
              : lesson === 4
                ? ['glassLeft', 'glassRight', 'glassOpposite'].includes(action)
                : false));
    const didLesson = () => {
      if (tutorial && !lessonPerformed) {
        lessonPerformed = true;
        setPerformed(true);
      }
    };

    const togglePause = () => {
      if (tutorial) {
        live.current.onExit();
        return;
      }
      if (current === 'playing') {
        keyboard.releaseAll();
        pads.releaseAll();
        setRunStatus('paused');
        checkpoint();
      } else if (current === 'paused') {
        setRunStatus('playing');
      }
    };

    const retry = () => {
      if (tutorial) {
        keyboard.releaseAll();
        pads.releaseAll();
        engine = newEngine(plan);
        fx.reset(engine.activeSide);
        exposeEngine();
        lesson = 0;
        lessonPerformed = false;
        tutorialMatch = false;
        setTutorialStep(0);
        setPerformed(false);
        setRunStatus('playing');
        return;
      }
      if (!finished) recordRun(false, true);
      finished = true;
      live.current.onRetry(campaign ? { mode: 'campaign', level: campaignLevel } : session);
    };
    actions.current = {
      togglePause,
      retry,
      practice: (action) => {
        pads.down(action);
        pads.up(action);
      },
      down: (action) => pads.down(action),
      up: (action) => pads.up(action),
      leave: (destination, save = true) => {
        keyboard.releaseAll();
        pads.releaseAll();
        if (save) checkpoint();
        else if (!finished) recordRun(false, true);
        finished = true;
        destination();
      },
      nextLesson: () => {
        if (current !== 'playing' || live.current.blocked || (lesson > 0 && lesson < TUTORIAL_LESSONS.length - 1 && !lessonPerformed)) return;
        if (lesson === TUTORIAL_LESSONS.length - 1) {
          live.current.onTutorialDone?.();
          return;
        }
        keyboard.releaseAll();
        pads.releaseAll();
        lesson++;
        lessonPerformed = false;
        setTutorialStep(lesson);
        setPerformed(false);
        if (lesson === 3) {
          engine = newEngine(plan);
          fx.reset(engine.activeSide);
          exposeEngine();
          engine.board.paintCenter(['. Y . . . . . . . .', 'B . . . . . . . . .', 'R R . . . . . . . .']);
          engine.incoming.put(0, makePiece([0, 1, 2]), { column: 2 });
        } else if (lesson === 4) engine.addGlass();
        if (!live.current.blocked) canvas.focus({ preventScroll: true });
      },
      activeGlass: (slot: number) => {
        if (current !== 'playing' || live.current.blocked || !allowsTutorial('glassRight') || banner?.blocking) return;
        const before = engine.activeSide;
        engine.activateSide(sideAtSlot(engine.activeSide, slot as 0 | 1 | 2 | 3));
        if (engine.activeSide !== before) didLesson();
      },
    };

    const acceptsInput = () => current === 'playing' && !live.current.blocked && !(banner?.blocking ?? false);

    const sink = {
      move: (direction: -1 | 1, toWall: boolean) => {
        if (!acceptsInput() || !allowsTutorial(direction < 0 ? 'moveLeft' : 'moveRight')) return;
        const before = engine.activePiece?.column;
        engine.moveActive(toWall ? direction * engine.config.boardSize : direction);
        if (engine.activePiece?.column !== before) didLesson();
      },
      softDrop: (held: boolean) => engine.setSoftDrop(held && acceptsInput() && allowsTutorial('softDrop')),
      press: (action: Exclude<Action, 'moveLeft' | 'moveRight' | 'softDrop'>) => {
        if (action === 'pause') return togglePause();
        if (action === 'restart') return retry();
        if (!acceptsInput()) {
          // On the result screens the drop key starts the next game.
          if ((current === 'over' || current === 'done') && action === 'hardDrop') retry();
          return;
        }
        if (!allowsTutorial(action)) return;
        const beforePiece = engine.activePiece?.piece,
          beforeSide = engine.activeSide;
        switch (action) {
          case 'rotateCW':
            engine.rotateActive(true);
            break;
          case 'rotateCCW':
            engine.rotateActive(false);
            break;
          case 'hardDrop':
            engine.dropActive();
            break;
          case 'glassLeft':
            engine.switchSide(-1);
            break;
          case 'glassRight':
            engine.switchSide(1);
            break;
          case 'glassOpposite':
            engine.switchSide(2);
            break;
        }
        if (['rotateCW', 'rotateCCW'].includes(action) && engine.activePiece?.piece !== beforePiece) didLesson();
        if (engine.activeSide !== beforeSide) didLesson();
      },
    };
    const keyboard = new KeyboardController(
      () => live.current.settings.bindings,
      () => live.current.settings.handling,
      sink,
    );

    const pads = new PadController(sink, () => live.current.settings.handling);

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || live.current.blocked || event.ctrlKey || event.metaKey || event.altKey) return;
      if (current === 'paused') {
        if (live.current.settings.bindings.pause.includes(event.code)) {
          event.preventDefault();
          togglePause();
        }
        return;
      }
      if (current !== 'playing') return;
      const target = event.target as HTMLElement | null;
      if (target?.closest('input, select, textarea, [contenteditable], [role="dialog"]')) return;
      if (tutorial && ['Enter', 'NumpadEnter', 'Backspace'].includes(event.code)) {
        // Focused header/practice/skip buttons retain their normal Enter action.
        if (event.code !== 'Backspace' && target?.closest('button:not(.tutorial__next)')) return;
        event.preventDefault();
        if (event.repeat) return;
        if (event.code === 'Backspace') live.current.onTutorialDone?.();
        else if (lesson > 0 && lesson < TUTORIAL_LESSONS.length - 1 && !lessonPerformed) {
          // A custom Enter binding can still perform the lesson's required action.
          keyboard.keyDown(event.code, false);
        } else actions.current.nextLesson();
        return;
      }
      if (target?.closest('button') && ['Space', 'Enter', 'NumpadEnter'].includes(event.code)) return;
      if (keyboard.keyDown(event.code, event.repeat)) event.preventDefault();
    };
    const onKeyUp = (event: KeyboardEvent) => keyboard.keyUp(event.code);
    const onBlur = () => {
      keyboard.releaseAll();
      pads.releaseAll();
      if (!tutorial && current === 'playing') setRunStatus('paused');
      checkpoint();
    };
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', onBlur);
    const onVisibility = () => {
      if (document.hidden) onBlur();
    };
    document.addEventListener('visibilitychange', onVisibility);
    window.addEventListener('pagehide', onBlur);
    checkpoint();

    let raf = 0;
    let last = performance.now();
    /** Frames in a row whose picture could not have changed. */
    let still = 0;
    let drawnPalette = -1;
    const tick = (now: number) => {
      const frameMs = now - last;
      const seconds = Math.min(MAX_FRAME_SECONDS, Math.max(0, frameMs / 1000));
      last = now;
      const s = live.current.settings;
      const frozen = live.current.blocked || document.hidden;
      const holding = frozen || (banner?.blocking ?? false);
      if (frozen) {
        keyboard.releaseAll();
        pads.releaseAll();
        if (!wasFrozen) checkpoint();
      }
      wasFrozen = frozen;
      fx.screenShake = s.effects.screenShake && !reduceMotion.matches;
      // The explicit game setting controls glass navigation; the system
      // preference still reduces decorative motion and screen shake.
      fx.turnSeconds = s.effects.turnMs / 1000;
      fx.explosion = s.effects.explosion;

      if (current === 'playing' && !holding) {
        keyboard.update(seconds);
        pads.update(seconds);
        if (!tutorial || engine.phase !== 'playing') engine.update(seconds);
      }

      // Banners share the pause/settings gate with gameplay.
      if (banner && current === 'playing' && !frozen) {
        banner.left -= seconds;
        if (banner.left <= 0) {
          const done = banner;
          banner = null;
          setBanner(null);
          done.then?.();
        }
      }

      const events: GameEvent[] = engine.drainEvents();
      fx.consume(events, engine);
      // Effects keep playing out on the result screens, but not under a pause.
      fx.update(current === 'paused' || frozen ? 0 : seconds, engine);

      for (const event of events) {
        if (event.type === 'matchScored') {
          if (tutorial && lesson === 3) tutorialMatch = true;
          setCallout({ id: ++calloutId, kind: 'score', score: event.score, combo: event.combo });
        } else if (event.type === 'speedUp') {
          setCallout({ id: ++calloutId, kind: 'speed', speed: event.level + 1 });
        } else if (event.type === 'gameEnded' && !finished) {
          gameOver(event.side);
        }
      }

      if (tutorial && tutorialMatch && lesson === 3 && engine.phase === 'playing') didLesson();
      if (current === 'playing' && !frozen) saveCharge += seconds;
      if (
        saveCharge >= 2 ||
        events.some((event) => ['pieceLanded', 'matchScored', 'glassAdded', 'speedUp'].includes(event.type))
      )
        checkpoint();

      if (campaign && !finished && !completing && acceptsInput() && engine.phase === 'playing') {
        if (engine.state.score - levelBase >= CAMPAIGN[campaignLevel].target) completeLevel();
      }

      // A picture that cannot have changed is not drawn again: under a pause,
      // or once a game that stands still has played out its effects. The
      // browser then has nothing to composite either.
      const engineRunning = current === 'playing' && !holding;
      const effectsRunning = current !== 'paused' && !frozen;
      still = !engineRunning && (!effectsRunning || fx.settled) ? still + 1 : 0;
      if (still <= 2 || dirty || drawnPalette !== paletteRevision()) {
        renderer.draw(engine, fx, reduceMotion.matches, tutorial);
        dirty = false;
        drawnPalette = paletteRevision();
      }
      // On a machine that cannot keep up, fewer pixels are drawn.
      if (engineRunning && quality.sample(frameMs)) measure();

      // The numbers in the corners, compared one by one so that a frame in
      // which none of them changed creates nothing.
      const state = engine.state;
      const playing = campaign ? CAMPAIGN[campaignLevel] : undefined;
      const score = carry.score + state.score;
      const bestCombo = Math.max(carry.bestCombo, state.bestCombo);
      const matches = carry.matches + state.matches;
      const pieces = carry.pieces + state.piecesPlaced;
      const clock = Math.floor(carry.seconds + state.elapsedSeconds);
      const level = campaign ? campaignLevel + 1 : 0;
      const into = campaign ? state.score - levelBase : 0;
      const target = playing?.target ?? 0;
      const colours = playing?.colours ?? engine.config.numberOfColors;
      const glasses = engine.sides.length;
      const speed = plan.ramp ? state.speedLevel + 1 : 0;
      if (
        score !== shown.score ||
        state.combo !== shown.combo ||
        bestCombo !== shown.bestCombo ||
        matches !== shown.matches ||
        pieces !== shown.pieces ||
        clock !== shown.seconds ||
        level !== shown.level ||
        into !== shown.into ||
        target !== shown.target ||
        colours !== shown.colours ||
        glasses !== shown.glasses ||
        speed !== shown.speed
      ) {
        shown = {
          score,
          combo: state.combo,
          bestCombo,
          matches,
          pieces,
          seconds: clock,
          level,
          into,
          target,
          colours,
          glasses,
          speed,
        };
        setHud(shown);
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(raf);
      observer.disconnect();
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      window.removeEventListener('blur', onBlur);
      document.removeEventListener('visibilitychange', onVisibility);
      window.removeEventListener('pagehide', onBlur);
      keyboard.releaseAll();
      pads.releaseAll();
      rendererRef.current = null;
    };
    // The session is fixed for the life of this component; the parent re-keys
    // it for every new game.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  /** Clicking a glass brings it to the top. */
  const onCanvasClick = (event: React.MouseEvent<HTMLCanvasElement>) => {
    const renderer = rendererRef.current;
    if (!renderer || status !== 'playing' || blocked) return;
    const box = event.currentTarget.getBoundingClientRect();
    const zone = renderer.zoneAt(event.clientX - box.left, event.clientY - box.top, planFor(session).config);
    if (zone === 1 || zone === 2 || zone === 3) actions.current.activeGlass(zone);
  };

  const campaign = session.mode === 'campaign';
  const retryLabel = campaign ? 'Повторить уровень' : 'Заново';
  const mode = tutorial ? 'Обучение' : MODE_NAMES[session.mode];
  const playingLevel = campaign ? CAMPAIGN[level] : undefined;
  const lessonActions: Action[] =
    tutorialStep === 1
      ? ['moveLeft', 'moveRight']
      : tutorialStep === 2
        ? ['rotateCW', 'rotateCCW']
        : tutorialStep === 3
          ? ['hardDrop']
          : tutorialStep === 4
            ? ['glassLeft', 'glassRight', 'glassOpposite']
            : [];
  const tutorialControls = touch
    ? (['left', 'right'] as const).flatMap((side) => {
        const slots = PAD_SLOTS.filter((slot) => lessonActions.includes(settings.pads[side][slot] as Action));
        const symbols = { up: '↑', left: '←', right: '→', down: '↓', center: '●' };
        return slots.length ? [`${side === 'left' ? 'Левая' : 'Правая'}: ${slots.map((slot) => symbols[slot]).join(' ')}`] : [];
      })
    : lessonActions.flatMap((action) => settings.bindings[action].map(keyLabel));
  const missingControl = lessonActions.length > 0 && tutorialControls.length === 0;

  return (
    <main
      className={`game ${touch ? 'game--touch' : ''} ${tutorial ? 'game--tutorial' : ''}`}
      data-frozen={status === 'paused' || blocked}
    >
      {(touch || tutorial) && (
        <header className={`touch-hud ${tutorial ? 'tutorial-hud' : ''}`}>
          {tutorial ? (
            <button type="button" className="chip" onClick={props.onExit}><T>← Назад</T></button>
          ) : (
            <>
              <div>
                <strong><T>{formatPoints(hud.score)}</T></strong>
                <small><T>
                  {campaign
                    ? `Уровень ${level + 1} · ${formatScore(hud.into)} / ${formatScore(hud.target)}`
                    : `${hud.pieces} фиг. · ${formatDuration(hud.seconds)}`}
                </T></small>
              </div>
              <button type="button" className="chip" onClick={() => actions.current.togglePause()}><T>
                Пауза
              </T></button>
            </>
          )}
          <button type="button" className="chip" onClick={props.onSettings}><T>
            Настройки
          </T></button>
        </header>
      )}
      {!touch && !tutorial && <div className="game__readout" style={{ ['--hud-opacity' as string]: settings.hud.opacity }}>
        <Hud hud={hud} callout={callout} bindings={settings.bindings} options={settings.hud}
          onPause={() => actions.current.togglePause()} onOpenSettings={props.onSettings} />
      </div>}
      <div className="game__frame" ref={frameRef}>
        <div
          className="stage"
          style={{
            width: size,
            height: size,
            fontSize: Math.max(9, size / 58),
            ['--hud-opacity' as string]: settings.hud.opacity,
          }}
        >
          <canvas
            ref={canvasRef}
            className="stage__canvas"
            tabIndex={0}
            aria-label={t("Игровое поле")}
            style={{ width: size, height: size }}
            onClick={onCanvasClick}
          />

          {banner && <LevelBanner banner={banner} />}
        </div>
      </div>

      {tutorial && (
        <TutorialPanel
          step={tutorialStep}
          performed={performed}
          keyboard={!touch}
          controls={
            missingControl
              ? 'Нет кнопки. Нажмите «Попробовать» или назначьте в настройках.'
              : tutorialControls.join(' · ')
          }
          onPractice={missingControl ? () => actions.current.practice(lessonActions[0]) : undefined}
          onNext={() => actions.current.nextLesson()}
          onSkip={() => props.onTutorialDone?.()}
        />
      )}
      {touch && (
        <div className="touch-controls">
          <TouchControls
            settings={settings}
            disabled={status !== 'playing' || blocked}
            onDown={(action) => actions.current.down(action)}
            onUp={(action) => actions.current.up(action)}
          />
        </div>
      )}

      {!tutorial && status === 'paused' && !blocked && (
        <Overlay label="Пауза" onDismiss={() => actions.current.togglePause()}>
          <div className="dialog dialog--narrow">
            <span className="kicker"><T>
              {mode}
              {playingLevel ? ` · уровень ${level + 1} из ${CAMPAIGN_LAST + 1}` : ''}
            </T></span>
            <h2 className="dialog__title"><T>Пауза</T></h2>
            {playingLevel && (
              <p className="dialog__note"><T>
                Цель {formatPoints(playingLevel.target)} · {playingLevel.colours} цв. · {playingLevel.glasses} ст.
              </T></p>
            )}
            <div className="dialog__actions">
              <Button primary autoFocus onClick={() => actions.current.togglePause()}><T>
                Продолжить
              </T></Button>
              <Button onClick={() => actions.current.retry()}><T>{retryLabel}</T></Button>
              <Button onClick={props.onSettings}><T>Настройки</T></Button>
              {session.mode === 'custom' && !tutorial && (
                <Button onClick={() => actions.current.leave(props.onCustomise)}><T>Изменить режим</T></Button>
              )}
              {session.mode !== 'custom' && (
                <Button onClick={() => actions.current.leave(props.onLevels)}><T>К уровням</T></Button>
              )}
              {!tutorial && <Button onClick={() => actions.current.leave(props.onExit, true)}><T>В меню</T></Button>}
              <Button ghost onClick={() => actions.current.leave(props.onExit, false)}><T>
                {tutorial ? 'В меню' : 'Завершить партию'}
              </T></Button>
            </div>
          </div>
        </Overlay>
      )}

      {status === 'over' && result && !blocked && (
        <Overlay>
          <div className="dialog dialog--narrow">
            <span className="kicker"><T>{mode}</T></span>
            <h2 className="dialog__title dialog__title--danger"><T>Игра окончена</T></h2>
            <p className="dialog__note"><T>
              {SLOT_NAMES[overSlot]} стакан заполнился до конца рукава.
              {campaign && ' Уровень не пройден: начнём его заново или выберем другой.'}
            </T></p>
            <Stats record={result} campaign={campaign} />
            <div className="dialog__actions">
              <Button primary autoFocus onClick={() => actions.current.retry()}><T>
                {retryLabel}
              </T></Button>
              {session.mode === 'custom' && !tutorial && (
                <Button onClick={() => actions.current.leave(props.onCustomise)}><T>Изменить режим</T></Button>
              )}
              {campaign && <Button onClick={props.onLevels}><T>К уровням</T></Button>}
              <Button ghost onClick={props.onExit}><T>
                В меню
              </T></Button>
            </div>
          </div>
        </Overlay>
      )}

      {status === 'done' && result && !blocked && (
        <Overlay>
          <div className="dialog dialog--narrow">
            <span className="kicker"><T>Кампания</T></span>
            <h2 className="dialog__title"><T>Кампания пройдена</T></h2>
            <p className="dialog__note"><T>Все {CAMPAIGN_LAST + 1} уровней позади. Кошмар открыт.</T></p>
            <Stats record={result} campaign />
            <div className="dialog__actions">
              <Button primary autoFocus onClick={props.onInsane}><T>
                Кошмар
              </T></Button>
              <Button onClick={props.onLevels}><T>К уровням</T></Button>
              <Button ghost onClick={props.onExit}><T>
                В меню
              </T></Button>
            </div>
          </div>
        </Overlay>
      )}
    </main>
  );
}

/** The summary of a finished run. */
function Stats({ record, campaign }: { record: RunRecord; campaign: boolean }) {
  return (
    <dl className="stats">
      {campaign && (
        <div className="stats__row stats__row--main">
          <dt><T>Уровень</T></dt>
          <dd><T>{record.completed ? CAMPAIGN_LAST + 1 : record.level}</T></dd>
        </div>
      )}
      <div className={`stats__row ${campaign ? '' : 'stats__row--main'}`}>
        <dt><T>Очки</T></dt>
        <dd><T>{formatNumber(record.score)}</T></dd>
      </div>
      <div className="stats__row">
        <dt><T>Фигуры</T></dt>
        <dd><T>{record.pieces}</T></dd>
      </div>
      <div className="stats__row">
        <dt><T>Матчи</T></dt>
        <dd><T>{record.matches}</T></dd>
      </div>
      <div className="stats__row">
        <dt><T>Лучшее комбо</T></dt>
        <dd><T>×{record.bestCombo}</T></dd>
      </div>
      <div className="stats__row">
        <dt><T>Время</T></dt>
        <dd><T>{formatDuration(record.seconds)}</T></dd>
      </div>
    </dl>
  );
}
