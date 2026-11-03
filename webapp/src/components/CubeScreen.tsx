import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { useEffect, useRef, useState } from 'react';
import { CubeGame } from '../cube/rules';
import { CUBE_LESSONS, CUBE_LESSON_LAST, LESSON_KEYS, LESSON_PADS, lessonGame } from '../cube/tutorial';
import { CubeView, type LookAxis, type Steering } from '../cube/view';
import { CUBE_RAMP, MODE_NAMES } from '../game/modes';
import { KeyboardController } from '../input/keyboard';
import type { Action } from '../input/bindings';
import { CUBE_PADS, PadController, type PadAction } from '../input/pads';
import { useTouchControls } from '../input/touch';
import type { RunRecord, Settings } from '../services/storage';
import { sounds } from '../services/sounds';
import { isPlatformHidden, subscribeVisibility } from '../platform/lifecycle';
import { PLAYGAMA_BUILD } from '../platform/target';
import { showInterstitial } from '../platform/playgama';
import { reportAbandoned, reportLevel } from '../platform/telemetry';
import { Hud } from './Hud';
import { TouchControls } from './TouchControls';
import { EMPTY_HUD, type Callout, type HudState } from './hudState';
import { TutorialPanel } from './TutorialPanel';
import { BackButton, Button, GameIconButton, Overlay, SoundButton } from './ui';
import { formatDuration, formatNumber } from './format';

type Status = 'playing' | 'paused' | 'over';
type OneShot = Exclude<Action, 'moveLeft' | 'moveRight' | 'softDrop'>;

interface Props {
  settings: Settings;
  /** True while the settings are open over the game: nothing moves. */
  blocked: boolean;
  onSettings: () => void;
  onToggleMusic?: () => void;
  onPauseChanged?: (paused: boolean) => void;
  /** Back to the main menu. */
  onExit: () => void;
  /** Back to Cube's own screen. */
  onSetup: () => void;
  /** A new game. */
  onRetry: () => void;
  onRecord: (run: RunRecord) => void;
  /** The tutorial's lessons instead of a game. */
  tutorial?: boolean;
  /** `played`: Play on the last lesson; false when the player skipped. */
  onTutorialDone?: (played: boolean) => void;
}

/** Longest frame the game will simulate in one go (hitches, tab switches). */
const MAX_FRAME_SECONDS = 0.05;
/** Browsers refuse, or silently shrink, canvases much beyond this many
 * device pixels a side. */
const MAX_CANVAS_PIXELS = 4096;
/** How long a result screen ignores presses once it opens. */
const RESULT_ARM_MS = 700;
/** A turn of the cross takes this much longer than in the flat game: the
 * hub is a heavier thing to turn. */
const TURN_SLOWER = 1.4;

/** While the hub is turned to be looked at, the play keys turn it. */
const LOOK_TURNS: Partial<Record<OneShot, [LookAxis, -1 | 1]>> = {
  glassLeft: ['upright', 1],
  glassRight: ['upright', -1],
  tipBack: ['across', 1],
  tipFront: ['across', -1],
  rotateCW: ['sight', -1],
  rotateCCW: ['sight', 1],
};

/** A lesson done moves on once the board has been at rest this long. */
const TUTORIAL_NEXT_MS = 700;
/** A lesson still waiting after this long says again what to press. */
const TUTORIAL_IDLE_MS = 4000;
/** How long the volume has to be held open in its lesson. */
const PEEK_LESSON_SECONDS = 1.2;
/** The first lesson opens the cube and closes it again, from either side,
 * this many seconds at a time. */
const INTRO_BEAT_SECONDS = 2.4;
/** What the lessons let the player do (the last one: everything). In front
 * of the glass in front, only that glass; a tip, only back over the top. */
const PIECE_ACTIONS: readonly Action[] = ['moveLeft', 'moveRight', 'rotateCW', 'rotateCCW', 'softDrop', 'hardDrop'];
const DEPTH_ACTIONS: readonly Action[] = ['frontGlass', 'backGlass', 'depthGlass'];

/** The glass that filled up, by where the screen shows it. */
const PLACE_NAMES = { top: 'Верхний', right: 'Правый', bottom: 'Нижний', left: 'Левый', front: 'Передний', back: 'Задний' } as const;

const newId = (): string => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;

/** What the line under the cube says. */
interface Status3d {
  steering: Steering;
  tip: { up: boolean; popped: number; rounds: number } | null;
  look: { runs: number; blocks: number } | null;
}

/** The playable screen of Cube: owns the game and its picture, runs them
 * from the frame loop and turns key presses into moves. The parent re-keys
 * it for every new game. */
export function CubeScreen(props: Props) {
  const { t } = useI18n();
  const { settings, blocked, tutorial = false } = props;
  const touch = useTouchControls();
  const touchMode = useRef(touch);
  const runId = useRef(newId());
  const frameRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const actions = useRef({
    togglePause: () => {},
    retry: () => {},
    look: (_on: boolean) => {},
    leave: (_destination: () => void) => {},
    down: (_action: PadAction) => {},
    up: (_action: PadAction) => {},
    nextLesson: () => {},
  });

  const [size, setSize] = useState(0);
  const [hud, setHud] = useState<HudState>(EMPTY_HUD);
  const [callout, setCallout] = useState<Callout | null>(null);
  const [status, setStatus] = useState<Status>('playing');
  /** Paused, or over, with the hub turned to be looked at: no dialog. */
  const [looking, setLooking] = useState(false);
  const [result, setResult] = useState<RunRecord | null>(null);
  const [overGlass, setOverGlass] = useState('');
  const [line, setLine] = useState<Status3d>({ steering: 'top', tip: null, look: null });
  /** The browser could not draw in 3D. */
  const [failed, setFailed] = useState(false);
  const [tutorialStep, setTutorialStep] = useState(0);
  const [performed, setPerformed] = useState(false);
  /** What to press, said again after a wrong key or a miss. */
  const [tutorialHint, setTutorialHint] = useState<string | null>(null);
  const [urging, setUrging] = useState(false);
  /** Counts the player's presses that a lesson takes: each one starts the
   * wait for the reminder again. */
  const [tried, setTried] = useState(0);

  // The loop reads the latest settings and callbacks through this.
  const live = useRef(props);
  useEffect(() => {
    live.current = props;
    touchMode.current = touch;
  });

  useEffect(() => {
    const frame = frameRef.current!;
    const canvas = canvasRef.current!;
    /** The lesson shown, or −1 in a game. */
    let lesson = tutorial ? 0 : -1;
    let game = tutorial
      ? lessonGame(0)
      : new CubeGame({
          numberOfColors: live.current.settings.cube.colours,
          depthFalls: live.current.settings.cube.depthFalls,
          ramp: CUBE_RAMP,
        });
    let view: CubeView;
    try {
      view = new CubeView(canvas, game);
    } catch {
      setFailed(true);
      return;
    }
    // Development only: lets the browser checks drive a running game.
    if (import.meta.env.DEV) {
      Object.assign(window, {
        __rotathreeCube: {
          get game() {
            return game;
          },
          view,
        },
      });
    }

    const measure = () => {
      const style = getComputedStyle(frame);
      const width = frame.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      const height = frame.clientHeight - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom);
      const next = Math.floor(Math.max(0, Math.min(width, height)));
      setSize(next);
      const dpr = Math.min(window.devicePixelRatio || 1, 2, MAX_CANVAS_PIXELS / Math.max(1, next));
      view.resize(next, next, dpr);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(frame);

    const place = { world: 'cube' as const };
    let current: Status = 'playing';
    let isLooking = false;
    let finished = false;
    const setRunStatus = (next: Status) => {
      const before = current;
      current = next;
      setStatus(next);
      live.current.onPauseChanged?.(next === 'paused');
      view.paused = next !== 'playing';
      if (next === 'playing' && before === 'paused') reportLevel('level_resumed', place);
      else if (next === 'paused' && before === 'playing') reportLevel('level_paused', place);
    };
    const setLook = (on: boolean) => {
      isLooking = on;
      setLooking(on);
      if (!on) view.endInspect();
    };
    if (!tutorial) reportLevel('level_started', place);
    live.current.onPauseChanged?.(false);

    const recordRun = (interrupted: boolean) => {
      if (interrupted) reportAbandoned(place);
      const record: RunRecord = {
        id: runId.current,
        mode: 'cube',
        at: Date.now(),
        score: game.score,
        pieces: game.placed,
        matches: game.matches,
        bestCombo: game.bestCombo,
        seconds: game.seconds,
        level: game.speedLevel + 1,
        completed: false,
        interrupted,
      };
      live.current.onRecord(record);
      setResult(record);
    };

    /** Lets go of everything held: a tip being looked at, the volume. */
    const letGo = () => {
      keyboard.releaseAll();
      pads.releaseAll();
      view.cancelTip();
      view.peeking = false;
    };
    const togglePause = () => {
      if (current === 'over' || tutorial) return;
      letGo();
      if (isLooking) setLook(false);
      setRunStatus(current === 'playing' ? 'paused' : 'playing');
    };
    const retry = () => {
      if (tutorial) return;
      if (!finished) recordRun(true);
      finished = true;
      live.current.onRetry();
    };
    actions.current = {
      togglePause,
      retry,
      look: (on) => {
        letGo();
        setLook(on);
      },
      leave: (destination) => {
        letGo();
        if (!finished && (game.placed > 0 || game.seconds > 5)) recordRun(true);
        finished = true;
        destination();
      },
      down: (action) => pads.down(action),
      up: (action) => pads.up(action),
      nextLesson: () => nextLesson(),
    };

    // ------------------------------------------------------- the tutorial
    let lessonDone = false;
    let landed = false;
    let matched = false;
    let peekSeconds = 0;
    /** Since when a lesson done has been at rest; 0 while it is not. */
    let restSince = 0;
    const enterLesson = (next: number) => {
      letGo();
      lesson = next;
      game = lessonGame(next);
      view.reset(game);
      lessonDone = landed = matched = false;
      peekSeconds = restSince = 0;
      setTutorialStep(next);
      setPerformed(false);
      setTutorialHint(null);
      setUrging(false);
    };
    const didLesson = () => {
      if (lessonDone) return;
      lessonDone = true;
      setPerformed(true);
      setTutorialHint(null);
      setUrging(false);
    };
    /** The first lesson and the last wait for their button. */
    const nextLesson = () => {
      if (!tutorial || live.current.blocked || (lesson > 0 && lesson < CUBE_LESSON_LAST)) return;
      if (lesson === CUBE_LESSON_LAST) live.current.onTutorialDone?.(true);
      else enterLesson(lesson + 1);
    };
    /** Whether the lesson lets the player do this now. */
    const allows = (action: Action): boolean => {
      if (lesson < 0 || lesson === CUBE_LESSON_LAST) return true;
      if (lessonDone || lesson === 0) return false;
      if (lesson === 1) return PIECE_ACTIONS.includes(action);
      if (lesson === 2) {
        return DEPTH_ACTIONS.includes(action)
          || (view.steering !== 'top' && (PIECE_ACTIONS.includes(action) || action === 'tipBack' || action === 'tipFront'));
      }
      if (lesson === 3) return action === 'tipBack';
      return action === 'peek' || (view.peeking && PIECE_ACTIONS.includes(action));
    };
    const wrongInput = (action: Action) => {
      if (lesson === 2 && view.steering === 'top' && PIECE_ACTIONS.includes(action)) setTutorialHint('Сначала возьми стакан спереди');
      else setTutorialHint(touchMode.current ? 'Нажми подсвеченную кнопку' : 'Нажми подсвеченную клавишу');
    };
    /** The lessons with a piece to drop: a miss lays the board out again. */
    const checkLesson = (seconds: number, now: number) => {
      if (lesson === 1 || lesson === 2) {
        if (matched) didLesson();
        else if (landed && game.phase === 'playing') {
          enterLesson(lesson);
          setTutorialHint('Мимо — попробуй ещё раз');
        }
      } else if (lesson === 4 && view.peeking) {
        peekSeconds += seconds;
        if (peekSeconds >= PEEK_LESSON_SECONDS) didLesson();
      } else if (lesson === 0 && !live.current.blocked) {
        // The cross opens into the cube and closes again.
        const beat = Math.floor(now / 1000 / INTRO_BEAT_SECONDS) % 3;
        view.peeking = beat > 0;
        if (beat > 0) view.peekYaw = beat === 1 ? 1 : -1;
      }
      const atRest = game.phase === 'playing' && !view.tilting;
      restSince = lessonDone && atRest ? restSince || now : 0;
      if (restSince > 0 && now - restSince >= TUTORIAL_NEXT_MS && lesson < CUBE_LESSON_LAST) enterLesson(lesson + 1);
    };

    const playing = () => current === 'playing' && !live.current.blocked;
    /** False, and a word of what to press, when the lesson asks for
     * something else. */
    const lets = (action: Action): boolean => {
      if (!tutorial) return true;
      if (!allows(action)) {
        wrongInput(action);
        return false;
      }
      // On the right track: the reminder goes, and waits again.
      setTutorialHint(null);
      setUrging(false);
      setTried((n) => n + 1);
      return true;
    };
    const sink = {
      move: (direction: -1 | 1, toWall: boolean) => {
        if (!lets(direction < 0 ? 'moveLeft' : 'moveRight')) return;
        if (view.peeking) {
          view.peekYaw = direction;
          return;
        }
        if (!playing()) return;
        for (let i = toWall ? game.hub.size : 1; i > 0; i--) view.move(direction);
      },
      softDrop: (held: boolean) => {
        if (held && !lets('softDrop')) return;
        if (held && view.peeking) view.peekPitch = -1;
        else view.softDrop(held && playing());
      },
      press: (action: OneShot) => {
        if (action === 'pause') return togglePause();
        if (action === 'restart') return retry();
        if (!lets(action)) return;
        if (action === 'peek') {
          view.peeking = playing() || isLooking;
          return;
        }
        if (view.peeking && (action === 'rotateCW' || action === 'hardDrop')) {
          view.peekPitch = action === 'rotateCW' ? 1 : -1;
          return;
        }
        if (isLooking) {
          const turn = LOOK_TURNS[action];
          if (turn) view.inspectTurn(...turn);
          return;
        }
        if (current === 'over' && action === 'hardDrop') return retry();
        if (!playing()) return;
        const top = view.steering === 'top';
        switch (action) {
          case 'rotateCW':
          case 'rotateCCW':
            view.rotate(action === 'rotateCW');
            break;
          case 'hardDrop':
            view.drop();
            break;
          case 'glassLeft':
          case 'glassRight':
            view.turnCross(action === 'glassLeft' ? -1 : 1);
            break;
          case 'tipBack':
          case 'tipFront':
            // A stick in front or behind moves up and down the screen; the
            // one on top tips the hub over.
            if (top) view.startTip(action === 'tipBack');
            else view.shift(action === 'tipBack' ? 1 : -1);
            break;
          case 'frontGlass':
            view.steer('front');
            break;
          case 'backGlass':
            view.steer('back');
            break;
          case 'depthGlass':
            view.steer('cycle');
            break;
        }
      },
      release: (action: OneShot) => {
        if (action === 'peek') view.peeking = false;
        else if (action === 'tipBack' || action === 'tipFront') {
          if (!playing()) view.cancelTip();
          else if (view.commitTip(action === 'tipBack') && lesson === 3) didLesson();
        }
      },
    };
    const keyboard = new KeyboardController(
      () => live.current.settings.bindings,
      () => live.current.settings.handling,
      sink,
      'cube',
    );
    const pads = new PadController(sink, () => live.current.settings.handling);

    const onKeyDown = (event: KeyboardEvent) => {
      if (event.defaultPrevented || live.current.blocked || event.ctrlKey || event.metaKey || event.altKey) return;
      const target = event.target as HTMLElement | null;
      if (event.code === 'Tab') return;
      if (tutorial && !target?.closest?.('input, select, textarea')) {
        if (event.code === 'Backspace') {
          event.preventDefault();
          live.current.onTutorialDone?.(false);
          return;
        }
        // Enter goes on from the first lesson and the last; so does Space
        // from the first. In the last one Space drops, as in the game, even
        // while the Play button has the focus.
        const onNext = target?.closest?.('.tutorial__next');
        if (event.code === 'Space' && onNext && lesson > 0) {
          event.preventDefault();
          keyboard.keyDown(event.code, event.repeat);
          return;
        }
        if (['Enter', 'NumpadEnter'].includes(event.code) || (event.code === 'Space' && lesson === 0)) {
          if (target?.closest?.('button')) return;
          if (lesson === 0 || lesson === CUBE_LESSON_LAST) {
            event.preventDefault();
            if (!event.repeat) nextLesson();
            return;
          }
        }
      }
      if (current === 'paused' && !isLooking) {
        if (live.current.settings.bindings.pause.includes(event.code)) {
          event.preventDefault();
          togglePause();
        }
        return;
      }
      if (current === 'over' && !isLooking) return;
      if (target?.closest('input, select, textarea, [contenteditable], [role="dialog"]')) return;
      if (target?.closest('button') && ['Space', 'Enter', 'NumpadEnter'].includes(event.code)) return;
      // Looking around: Esc, or the pause key, brings the dialog back.
      if (isLooking && (event.code === 'Escape' || live.current.settings.bindings.pause.includes(event.code))) {
        event.preventDefault();
        if (current === 'paused') togglePause();
        else setLook(false);
        return;
      }
      if (keyboard.keyDown(event.code, event.repeat)) event.preventDefault();
    };
    const onKeyUp = (event: KeyboardEvent) => {
      // A Space let go on the focused Play button drops, and presses nothing.
      if (tutorial && event.code === 'Space' && (event.target as HTMLElement | null)?.closest?.('.tutorial__next')) event.preventDefault();
      keyboard.keyUp(event.code);
    };
    const onBlur = () => {
      letGo();
      if (current === 'playing' && !tutorial) setRunStatus('paused');
    };
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', onBlur);
    const unsubscribeVisibility = subscribeVisibility((hidden) => {
      if (hidden) onBlur();
    });
    const onVisibility = () => {
      if (document.hidden) onBlur();
    };
    document.addEventListener('visibilitychange', onVisibility);

    let raf = 0;
    let last = performance.now();
    let calloutId = 0;
    /** The combo of the match flashing now: it bursts that many steps up. */
    let poppingCombo = 0;
    let shown = EMPTY_HUD;
    let said = '';
    let wasFrozen = false;
    const tick = (now: number) => {
      const seconds = Math.min(MAX_FRAME_SECONDS, Math.max(0, (now - last) / 1000));
      last = now;
      const s = live.current.settings;
      const frozen = live.current.blocked || document.hidden || isPlatformHidden();
      if (frozen && !wasFrozen) letGo();
      wasFrozen = frozen;
      view.look = s.cube;
      view.turnSeconds = (s.effects.turnMs / 1000) * TURN_SLOWER;
      game.config.depthFalls = s.cube.depthFalls;
      const play = current === 'playing' && !frozen;
      if (play) {
        keyboard.update(seconds);
        pads.update(seconds);
      }
      // Under the settings the picture holds still; looking around, it turns.
      const events = frozen ? [] : view.frame(seconds, play);

      for (const event of events) {
        if (event.type === 'landed') landed = true;
        if (event.type === 'matched') matched = true;
        if (event.type === 'matched') {
          setCallout({ id: ++calloutId, kind: 'score', score: event.score, combo: event.combo });
          poppingCombo = event.combo;
        } else if (event.type === 'popped') {
          sounds.pop(poppingCombo);
        } else if (event.type === 'moved') {
          if (!event.blocked) sounds.play('move');
        } else if (event.type === 'rotated') {
          if (!event.blocked) sounds.play('rotate');
        } else if (event.type === 'switched') {
          sounds.play('turn');
        } else if (event.type === 'landed') {
          sounds.play('land');
        } else if (event.type === 'speedUp') {
          setCallout({ id: ++calloutId, kind: 'speed', speed: event.level + 1 });
          sounds.play('level');
        } else if (event.type === 'gameEnded' && tutorial) {
          // The tutorial's free play has no lost game: the cube empties.
          game = lessonGame(CUBE_LESSON_LAST);
          view.reset(game);
        } else if (event.type === 'gameEnded' && !finished) {
          finished = true;
          letGo();
          reportLevel('level_failed', place);
          setOverGlass(PLACE_NAMES[view.placeOf(event.side)]);
          recordRun(false);
          setRunStatus('over');
          sounds.play('over');
        }
      }

      if (tutorial && !frozen) checkLesson(seconds, now);

      // The readout: only when a number changed.
      const next: HudState = {
        ...EMPTY_HUD,
        score: game.score,
        combo: game.combo,
        bestCombo: game.bestCombo,
        matches: game.matches,
        pieces: game.placed,
        seconds: Math.floor(game.seconds),
        speed: game.speedLevel + 1,
      };
      if ((Object.keys(next) as (keyof HudState)[]).some((key) => next[key] !== shown[key])) {
        shown = next;
        setHud(next);
      }
      const status3d: Status3d = { steering: view.steering, tip: view.tipPreview, look: view.inspecting };
      const key = JSON.stringify(status3d);
      if (key !== said) {
        said = key;
        setLine(status3d);
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
      unsubscribeVisibility();
      document.removeEventListener('visibilitychange', onVisibility);
      keyboard.releaseAll();
      pads.releaseAll();
      view.dispose();
    };
    // The game, or the tutorial, is fixed for the life of this component;
    // the parent re-keys it for every new one.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // A lesson still waiting says again what to press, and the keys pulse harder.
  useEffect(() => {
    if (!tutorial || !LESSON_KEYS[tutorialStep] || performed || blocked) return;
    const timer = setTimeout(() => {
      setUrging(true);
      setTutorialHint((said) => said ?? (touch ? 'Нажми подсвеченную кнопку' : 'Нажми подсвеченную клавишу'));
    }, TUTORIAL_IDLE_MS);
    return () => clearTimeout(timer);
  }, [tutorial, tutorialStep, performed, blocked, touch, tried]);

  /** Leaving a finished run is the natural pause for Playgama's
   * interstitial, as in the flat game. */
  const afterRun = (go: () => void) => () => {
    if (PLAYGAMA_BUILD) showInterstitial('game_over');
    go();
  };
  const mode = MODE_NAMES.cube;
  const keyboard = !touch;
  // A done lesson keeps its keys, dimmed: the panel keeps its size.
  const lessonKeys = tutorial ? LESSON_KEYS[tutorialStep] ?? [] : [];
  const field = (
    <div className="game__frame" ref={frameRef}>
      <div className="stage" style={{ width: size, height: size, fontSize: Math.max(9, size / 58) }}>
        <canvas ref={canvasRef} className="stage__canvas" tabIndex={-1} aria-label={t('Игровое поле')}
          style={{ width: size, height: size }} />
        <div className="cube-bar">
          <CubeLine line={line} looking={looking} keyboard={keyboard} />
          {looking && !blocked && (
            <Button primary onClick={() => (status === 'paused' ? actions.current.togglePause() : actions.current.look(false))}><T>
              {status === 'paused' ? 'Продолжить' : 'К итогам'}
            </T></Button>
          )}
        </div>
      </div>
    </div>
  );

  return (
    <main
      className={`game game--cube ${touch ? 'game--touch' : ''} ${tutorial ? 'game--tutorial' : ''}`}
      style={{
        ['--field-size' as string]: size > 0 ? `${size}px` : '100%',
        ['--pad-size' as string]: `${Math.max(settings.padPositions.left.size, settings.padPositions.right.size)}px`,
      }}
      data-frozen={status === 'paused' || blocked}
    >
      {tutorial ? (
        <div className="tutorial-layout">
          <div className="tutorial-play">
            <header className="touch-hud tutorial-hud">
              <BackButton onClick={props.onSetup} navigable={false} />
              <div className="hud__buttons">
                {props.onToggleMusic && <SoundButton on={settings.audio.music || settings.audio.sounds} onToggle={props.onToggleMusic} />}
                <GameIconButton icon="settings" label="Настройки" onClick={props.onSettings} />
              </div>
            </header>
            <TutorialPanel
              lessons={CUBE_LESSONS}
              step={tutorialStep}
              performed={performed}
              keyboard={keyboard}
              active={!blocked}
              hint={tutorialHint}
              urging={urging}
              controls={lessonKeys.flatMap((action) => settings.bindings[action].length
                // Letters first, as in the flat game's lessons.
                ? [{ label: action, keys: [...settings.bindings[action]].sort((a, b) => Number(a.startsWith('Arrow')) - Number(b.startsWith('Arrow'))) }]
                : [])}
              onNext={() => actions.current.nextLesson()}
              onSkip={() => props.onTutorialDone?.(false)}
            />
            {field}
          </div>
        </div>
      ) : (
        <>
          <header className="game__readout" style={{ ['--hud-opacity' as string]: settings.hud.opacity }}>
            <Hud hud={hud} callout={callout} options={settings.hud}
              compact={touch} onPause={() => actions.current.togglePause()} onOpenSettings={props.onSettings}
              sound={props.onToggleMusic && { on: settings.audio.music || settings.audio.sounds, toggle: props.onToggleMusic }} />
          </header>
          {field}
        </>
      )}
      {touch && (
        <div className="touch-controls">
          <TouchControls
            settings={settings}
            layouts={CUBE_PADS}
            disabled={(status !== 'playing' && !looking) || blocked}
            hint={tutorial && !performed ? LESSON_PADS[tutorialStep] : undefined}
            onDown={(action) => actions.current.down(action)}
            onUp={(action) => actions.current.up(action)}
          />
        </div>
      )}

      {failed && (
        <Overlay>
          <div className="dialog dialog--narrow">
            <span className="kicker"><T>{mode}</T></span>
            <h2 className="dialog__title"><T>Куб не запустился</T></h2>
            <p className="dialog__note"><T>Браузеру не хватает WebGL — 3D-графики, которой нарисован куб.</T></p>
            <div className="dialog__actions">
              <Button primary autoFocus onClick={props.onSetup}><T>К режиму</T></Button>
              <Button ghost onClick={props.onExit}><T>В меню</T></Button>
            </div>
          </div>
        </Overlay>
      )}

      {status === 'paused' && !looking && !blocked && (
        <Overlay label="Пауза" onDismiss={() => actions.current.togglePause()}>
          <div className="dialog dialog--narrow">
            <span className="kicker"><T>{mode}</T></span>
            <h2 className="dialog__title"><T>Пауза</T></h2>
            <div className="dialog__actions">
              <Button primary autoFocus onClick={() => actions.current.togglePause()}><T>
                Продолжить
              </T></Button>
              <Button onClick={() => actions.current.look(true)}><T>Осмотреть куб</T></Button>
              <Button onClick={() => actions.current.retry()}><T>Заново</T></Button>
              <Button onClick={props.onSettings}><T>Настройки</T></Button>
              <Button onClick={() => actions.current.leave(props.onSetup)}><T>К режиму</T></Button>
              <Button ghost onClick={() => actions.current.leave(props.onExit)}><T>Завершить партию</T></Button>
            </div>
          </div>
        </Overlay>
      )}

      {status === 'over' && result && !looking && !blocked && (
        <Overlay armAfterMs={RESULT_ARM_MS}>
          <div className="dialog dialog--narrow">
            <span className="kicker"><T>{mode}</T></span>
            <h2 className="dialog__title dialog__title--danger"><T>Игра окончена</T></h2>
            <p className="dialog__note"><T>{overGlass} стакан заполнился до конца рукава.</T></p>
            <dl className="stats">
              <div className="stats__row stats__row--main">
                <dt><T>Очки</T></dt>
                <dd><T>{formatNumber(result.score)}</T></dd>
              </div>
              <div className="stats__row">
                <dt><T>Фигуры</T></dt>
                <dd><T>{result.pieces}</T></dd>
              </div>
              <div className="stats__row">
                <dt><T>Лучшее комбо</T></dt>
                <dd><T>×{result.bestCombo}</T></dd>
              </div>
              <div className="stats__row">
                <dt><T>Скорость</T></dt>
                <dd><T>{result.level}</T></dd>
              </div>
              <div className="stats__row">
                <dt><T>Время</T></dt>
                <dd><T>{formatDuration(result.seconds)}</T></dd>
              </div>
            </dl>
            <div className="dialog__actions">
              <Button primary onClick={afterRun(() => actions.current.retry())}><T>Заново</T></Button>
              <Button onClick={() => actions.current.look(true)}><T>Осмотреть куб</T></Button>
              <Button onClick={afterRun(props.onSetup)}><T>К режиму</T></Button>
              <Button ghost onClick={afterRun(props.onExit)}><T>В меню</T></Button>
            </div>
          </div>
        </Overlay>
      )}
    </main>
  );
}

/** The one line of words over the bottom of the field: which glass is
 * steered when it is not the one on top, what a tip held would pop, what
 * shows from where the hub is looked at. Nothing while plain play goes on. */
function CubeLine({ line, looking, keyboard }: { line: Status3d; looking: boolean; keyboard: boolean }) {
  let text: string | null = null;
  if (looking) {
    const lines = !line.look || line.look.runs === 0 ? 'линий отсюда нет' : `линий отсюда: ${line.look.runs}, блоков ${line.look.blocks}`;
    text = keyboard ? `Осмотр · ${lines} · стрелки и W — повернуть · Esc — назад` : `Осмотр · ${lines}`;
  } else if (line.tip) {
    const { popped, rounds } = line.tip;
    const pops = popped === 0 ? 'ничего не лопнет' : rounds > 1 ? `лопнет ${popped}, каскад ×${rounds}` : `лопнет ${popped}`;
    text = `Отпустите — опрокинуть · ${pops}`;
  } else if (line.steering !== 'top') {
    text = line.steering === 'front' ? 'Передний стакан' : 'Задний стакан';
  }
  if (!text) return null;
  return <div className="cube-line" role="status"><T>{text}</T></div>;
}
