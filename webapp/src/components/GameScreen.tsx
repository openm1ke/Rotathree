import { useCallback, useEffect, useRef, useState } from 'react';
import { gridSize } from '../game/config';
import { GameEngine } from '../game/engine';
import { sideAtSlot, slotOfSide } from '../game/glass';
import type { Side } from '../game/side';
import { zenLevelOf, zenLevelProgress, zenLevelTarget } from '../game/zen';
import { KeyboardController } from '../input/keyboard';
import { Effects } from '../render/effects';
import { GameRenderer } from '../render/renderer';
import { configFor, type Settings } from '../services/settingsStore';
import { Hud } from './Hud';
import { formatClock, formatScore, type Callout, type GameMode, type HudState } from './hudState';

type Status = 'playing' | 'paused' | 'levelUp' | 'over';

interface Result extends HudState {
  /** Screen slot of the glass that overflowed. */
  slot: Side;
}

/** A Zen level that has just been reached and is being celebrated. */
interface LevelUp {
  id: number;
  level: number;
}

interface Props {
  mode: GameMode;
  settings: Settings;
  /** True while the settings panel is on top: the game is frozen and the
   * keyboard belongs to the panel. */
  blocked: boolean;
  onOpenSettings: () => void;
  onExit: () => void;
}

const EMPTY_HUD: HudState = {
  score: 0,
  combo: 0,
  bestCombo: 0,
  matches: 0,
  pieces: 0,
  seconds: 0,
  level: 0,
  levelInto: 0,
  levelTarget: 0,
};

/** Longest frame the game will simulate in one go (hitches, tab switches). */
const MAX_FRAME_SECONDS = 0.05;

/** How long the game stands still while a new Zen level is announced. */
const LEVEL_UP_SECONDS = 2.4;

const SLOT_NAMES = ['Верхний', 'Правый', 'Нижний', 'Левый'] as const;

/** `level` is the Zen level being played, 0 outside Zen. */
const hudOf = (engine: GameEngine, level: number): HudState => {
  const progress = level > 0 ? zenLevelProgress(engine.state.score, level) : { into: 0, target: 0 };
  return {
    score: engine.state.score,
    combo: engine.state.combo,
    bestCombo: engine.state.bestCombo,
    matches: engine.state.matches,
    pieces: engine.state.piecesPlaced,
    seconds: Math.floor(engine.state.elapsedSeconds),
    level,
    levelInto: progress.into,
    levelTarget: progress.target,
  };
};

const sameHud = (a: HudState, b: HudState): boolean =>
  (Object.keys(a) as (keyof HudState)[]).every((key) => a[key] === b[key]);

/** The playable screen: owns the engine, runs it from the frame loop and
 * turns key presses into engine input. */
export function GameScreen({ mode, settings, blocked, onOpenSettings, onExit }: Props) {
  const frameRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const engineRef = useRef<GameEngine | null>(null);
  const rendererRef = useRef<GameRenderer | null>(null);
  const restartRef = useRef<() => void>(() => {});

  const [size, setSize] = useState(0);
  const [hud, setHud] = useState<HudState>(EMPTY_HUD);
  const [callout, setCallout] = useState<Callout | null>(null);
  const [status, setStatus] = useState<Status>('playing');
  const [result, setResult] = useState<Result | null>(null);
  const [levelUp, setLevelUp] = useState<LevelUp | null>(null);

  // The frame loop and the key handlers are set up once; they read whatever
  // is current through this.
  const live = useRef({ settings, blocked, status });
  useEffect(() => {
    live.current = { settings, blocked, status };
  });

  const togglePause = useCallback(() => {
    setStatus((current) => (current === 'playing' ? 'paused' : current === 'paused' ? 'playing' : current));
  }, []);

  const restart = useCallback(() => restartRef.current(), []);

  // The square stage follows the window.
  useEffect(() => {
    const frame = frameRef.current!;
    const measure = () => {
      const next = Math.floor(Math.min(frame.clientWidth, frame.clientHeight));
      setSize(next);
      rendererRef.current?.resize(next, window.devicePixelRatio || 1);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(frame);
    return () => observer.disconnect();
  }, []);

  useEffect(() => {
    // The mode and the options are fixed for the life of this component:
    // the parent re-keys it when they change.
    const zen = mode === 'zen';
    const engine = new GameEngine(configFor(live.current.settings.game));
    const fx = new Effects();
    fx.reset(engine.activeSide);
    const renderer = new GameRenderer(canvasRef.current!);
    const frame = frameRef.current!;
    renderer.resize(
      Math.floor(Math.min(frame.clientWidth, frame.clientHeight)),
      window.devicePixelRatio || 1,
    );
    engineRef.current = engine;
    rendererRef.current = renderer;
    // A handle for poking at a running game from the console while developing.
    if (import.meta.env.DEV) Object.assign(window, { __rotathree: engine });

    let calloutId = 0;
    let shown = EMPTY_HUD;
    // Zen: the level being played, and the seconds left of the pause that
    // announces a new one.
    let level = zen ? 1 : 0;
    let levelUpLeft = 0;
    let levelUpId = 0;

    restartRef.current = () => {
      engine.restart();
      fx.reset(engine.activeSide);
      keyboard.releaseAll();
      level = zen ? 1 : 0;
      levelUpLeft = 0;
      setCallout(null);
      setResult(null);
      setLevelUp(null);
      setStatus('playing');
    };

    const playing = () => live.current.status === 'playing' && levelUpLeft <= 0;

    const keyboard = new KeyboardController(
      () => live.current.settings.bindings,
      () => live.current.settings.handling,
      {
        move: (direction, toWall) => {
          if (!playing()) return;
          engine.moveActive(toWall ? direction * engine.config.boardSize : direction);
        },
        softDrop: (held) => engine.setSoftDrop(held),
        press: (action) => {
          if (action === 'pause') return togglePause();
          if (action === 'restart') return restartRef.current();
          if (!playing()) {
            // On the result screen the drop key starts the next game.
            if (live.current.status === 'over' && action === 'hardDrop') restartRef.current();
            return;
          }
          switch (action) {
            case 'rotateCW':
              return engine.rotateActive(true);
            case 'rotateCCW':
              return engine.rotateActive(false);
            case 'hardDrop':
              return engine.dropActive();
            case 'glassLeft':
              return engine.switchSide(-1);
            case 'glassRight':
              return engine.switchSide(1);
            case 'glassOpposite':
              return engine.switchSide(2);
          }
        },
      },
    );

    const onKeyDown = (event: KeyboardEvent) => {
      if (live.current.blocked || event.ctrlKey || event.metaKey || event.altKey) return;
      if (keyboard.keyDown(event.code, event.repeat)) event.preventDefault();
    };
    const onKeyUp = (event: KeyboardEvent) => {
      keyboard.keyUp(event.code);
    };
    const onBlur = () => {
      keyboard.releaseAll();
      setStatus((current) => (current === 'playing' ? 'paused' : current));
    };
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', onBlur);

    let raf = 0;
    let last = performance.now();
    const tick = (now: number) => {
      const seconds = Math.min(MAX_FRAME_SECONDS, Math.max(0, (now - last) / 1000));
      last = now;
      const { status: current, blocked: frozen, settings: latest } = live.current;
      const running = current === 'playing' && !frozen && levelUpLeft <= 0;
      if (frozen) keyboard.releaseAll();
      fx.screenShake = latest.screenShake;
      fx.turnSeconds = latest.turnMs / 1000;

      if (running) {
        keyboard.update(seconds);
        engine.update(seconds);
      }
      const events = engine.drainEvents();
      fx.consume(events, engine);
      // Effects keep playing out on the result screen, but not under a pause.
      fx.update(current === 'paused' || frozen ? 0 : seconds, engine);

      for (const event of events) {
        if (event.type === 'matchScored') {
          setCallout({ id: ++calloutId, combo: event.combo, score: event.score });
        } else if (event.type === 'gameEnded') {
          setResult({ ...hudOf(engine, level), slot: slotOfSide(engine.activeSide, event.side) });
          setStatus('over');
        }
      }

      if (levelUpLeft > 0) {
        if (!frozen) levelUpLeft -= seconds;
        if (levelUpLeft <= 0) {
          levelUpLeft = 0;
          setLevelUp(null);
          setStatus((value) => (value === 'levelUp' ? 'playing' : value));
        }
      } else if (zen && running && engine.phase === 'playing') {
        // The board is at rest, so a cascade that carried the score over the
        // line has played out in full before the game stops to celebrate.
        const reached = zenLevelOf(engine.state.score);
        if (reached > level) {
          level = reached;
          levelUpLeft = LEVEL_UP_SECONDS;
          keyboard.releaseAll();
          fx.celebrate(engine.config.numberOfColors);
          setLevelUp({ id: ++levelUpId, level });
          setStatus('levelUp');
        }
      }

      renderer.draw(engine, fx);
      const next = hudOf(engine, level);
      if (!sameHud(next, shown)) {
        shown = next;
        setHud(next);
      }
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener('keydown', onKeyDown);
      window.removeEventListener('keyup', onKeyUp);
      window.removeEventListener('blur', onBlur);
    };
  }, [mode, togglePause]);

  /** Clicking a glass brings it to the top. */
  const onCanvasClick = (event: React.MouseEvent<HTMLCanvasElement>) => {
    const engine = engineRef.current;
    const renderer = rendererRef.current;
    if (!engine || !renderer || status !== 'playing' || blocked) return;
    const box = event.currentTarget.getBoundingClientRect();
    const zone = renderer.zoneAt(event.clientX - box.left, event.clientY - box.top, engine.config);
    if (zone === 1 || zone === 2 || zone === 3) {
      engine.activateSide(sideAtSlot(engine.activeSide, zone));
    }
  };

  const zen = mode === 'zen';
  const config = configFor(settings.game);
  const corner = `${(100 * config.armLength) / gridSize(config)}%`;

  return (
    <main className="game">
      {zen && (
        // A wash of colour behind the field that moves on with every level.
        <div
          className="game__aura"
          aria-hidden="true"
          style={{ filter: `hue-rotate(${(Math.max(1, hud.level) - 1) * 47}deg)` }}
        />
      )}
      <div className="game__frame" ref={frameRef}>
        <div
          className="stage"
          style={{
            width: size,
            height: size,
            fontSize: Math.max(9, size / 58),
            ['--corner' as string]: corner,
            ['--hud-opacity' as string]: settings.hud.opacity,
          }}
        >
          <canvas
            ref={canvasRef}
            className="stage__canvas"
            style={{ width: size, height: size }}
            onClick={onCanvasClick}
          />
          <Hud
            hud={hud}
            callout={callout}
            bindings={settings.bindings}
            options={settings.hud}
            onPause={togglePause}
            onOpenSettings={onOpenSettings}
          />

          {levelUp && (
            <div className="levelup" key={levelUp.id} role="status">
              <div className="levelup__sweep" />
              <div className="levelup__card">
                <span className="levelup__label">Уровень {levelUp.level - 1} пройден</span>
                <span className="levelup__title">
                  Уровень <b>{levelUp.level}</b>
                </span>
                <span className="levelup__goal">
                  Цель · {formatScore(zenLevelTarget(levelUp.level))} очков
                </span>
              </div>
            </div>
          )}

          {status === 'paused' && !blocked && (
            <div className="overlay">
              <div className="dialog">
                <h2 className="dialog__title">Пауза</h2>
                {zen && <p className="dialog__note">Дзен · уровень {hud.level}</p>}
                <div className="dialog__actions">
                  <button type="button" className="button button--primary" onClick={togglePause} autoFocus>
                    Продолжить
                  </button>
                  <button type="button" className="button" onClick={restart}>
                    {zen ? 'Начать заново' : 'Заново'}
                  </button>
                  <button type="button" className="button" onClick={onOpenSettings}>
                    Настройки
                  </button>
                  <button type="button" className="button button--ghost" onClick={onExit}>
                    В меню
                  </button>
                </div>
              </div>
            </div>
          )}

          {status === 'over' && result && !blocked && (
            <div className="overlay">
              <div className="dialog dialog--over">
                <h2 className="dialog__title dialog__title--danger">Игра окончена</h2>
                <p className="dialog__note">
                  {SLOT_NAMES[result.slot]} стакан заполнился до конца рукава.
                  {zen && ' Начнёте заново с первого уровня?'}
                </p>
                <dl className="stats">
                  {zen && (
                    <div className="stats__row stats__row--main">
                      <dt>Уровень</dt>
                      <dd>{result.level}</dd>
                    </div>
                  )}
                  <div className={`stats__row ${zen ? '' : 'stats__row--main'}`}>
                    <dt>Счёт</dt>
                    <dd>{formatScore(result.score)}</dd>
                  </div>
                  <div className="stats__row">
                    <dt>Лучшее комбо</dt>
                    <dd>×{result.bestCombo}</dd>
                  </div>
                  <div className="stats__row">
                    <dt>Матчи</dt>
                    <dd>{result.matches}</dd>
                  </div>
                  <div className="stats__row">
                    <dt>Фигуры</dt>
                    <dd>{result.pieces}</dd>
                  </div>
                  <div className="stats__row">
                    <dt>Время</dt>
                    <dd>{formatClock(result.seconds)}</dd>
                  </div>
                </dl>
                <div className="dialog__actions">
                  <button type="button" className="button button--primary" onClick={restart} autoFocus>
                    {zen ? 'Начать заново' : 'Заново'}
                  </button>
                  <button type="button" className="button" onClick={onOpenSettings}>
                    Настройки
                  </button>
                  <button type="button" className="button button--ghost" onClick={onExit}>
                    В меню
                  </button>
                </div>
              </div>
            </div>
          )}
        </div>
      </div>
    </main>
  );
}
