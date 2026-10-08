import { useEffect, useRef, useState } from 'react';
import { CAMPAIGN, CAMPAIGN_LAST, levelConfig, startsStage } from '../game/campaign';
import { gridSize } from '../game/config';
import { GameEngine, type GameEvent } from '../game/engine';
import { sideAtSlot, slotOfSide } from '../game/glass';
import { planFor, type Session } from '../game/session';
import { MODE_NAMES, type RunPlan } from '../game/modes';
import type { Side } from '../game/side';
import { KeyboardController } from '../input/keyboard';
import type { Action } from '../input/bindings';
import { Effects } from '../render/effects';
import { GameRenderer } from '../render/renderer';
import type { Palettes, Progress, RunRecord, Settings } from '../services/storage';
import { Hud } from './Hud';
import { LevelBanner, type BannerData } from './LevelBanner';
import { EMPTY_HUD, formatScore, sameHud, type Callout, type HudState } from './hudState';
import { Button, Overlay } from './ui';
import { formatDuration, formatNumber } from './format';

type Status = 'playing' | 'paused' | 'over' | 'done';

/** Points, pieces and so on, summed over the engines of one run. */
interface Totals {
  score: number;
  pieces: number;
  matches: number;
  bestCombo: number;
  seconds: number;
}

const NO_TOTALS: Totals = { score: 0, pieces: 0, matches: 0, bestCombo: 0, seconds: 0 };

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
}

/** Longest frame the game will simulate in one go (hitches, tab switches). */
const MAX_FRAME_SECONDS = 0.05;

const SLOT_NAMES = ['Верхний', 'Правый', 'Нижний', 'Левый'] as const;

const paletteColours = (palettes: Palettes): string[] =>
  (palettes.sets.find((set) => set.id === palettes.active) ?? palettes.sets[0]).colours;

const newId = (): string => `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 7)}`;

/** The playable screen: owns the engine, runs it from the frame loop, drives
 * the campaign's levels and turns key presses into engine input. The parent
 * re-keys it for every new game, so a session never changes under it. */
export function GameScreen(props: Props) {
  const { session, settings, blocked } = props;
  const frameRef = useRef<HTMLDivElement>(null);
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const rendererRef = useRef<GameRenderer | null>(null);
  const actions = useRef({ togglePause: () => {}, retry: () => {}, activeGlass: (_side: number) => {} });

  const [size, setSize] = useState(0);
  const [hud, setHud] = useState<HudState>(EMPTY_HUD);
  const [callout, setCallout] = useState<Callout | null>(null);
  const [banner, setBanner] = useState<BannerData | null>(null);
  const [status, setStatus] = useState<Status>('playing');
  const [result, setResult] = useState<RunRecord | null>(null);
  const [level, setLevel] = useState(session.mode === 'campaign' ? session.level : -1);
  const [overSlot, setOverSlot] = useState(0);

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
    // Development only: lets the browser checks drive a running game.
    if (import.meta.env.DEV) Object.assign(window, { __rotathree: engine });
    const fx = new Effects();
    fx.reset(engine.activeSide);
    const renderer = new GameRenderer(canvas);
    rendererRef.current = renderer;
    const measure = () => {
      const next = Math.floor(Math.min(frame.clientWidth, frame.clientHeight));
      setSize(next);
      renderer.resize(next, window.devicePixelRatio || 1);
    };
    measure();
    const observer = new ResizeObserver(measure);
    observer.observe(frame);

    let current: Status = 'playing';
    const setRunStatus = (next: Status) => {
      current = next;
      setStatus(next);
    };

    let campaignLevel = campaign ? session.level : -1;
    let levelBase = 0;
    let carry: Totals = NO_TOTALS;
    let completing = false;
    let finished = false;
    let calloutId = 0;
    let bannerId = 0;
    let banner: { left: number; blocking: boolean; then: (() => void) | null } | null = null;
    let shown = EMPTY_HUD;
    let progressNow = live.current.progress;

    const totals = (): Totals => ({
      score: carry.score + engine.state.score,
      pieces: carry.pieces + engine.state.piecesPlaced,
      matches: carry.matches + engine.state.matches,
      bestCombo: Math.max(carry.bestCombo, engine.state.bestCombo),
      seconds: carry.seconds + engine.state.elapsedSeconds,
    });

    const swapEngine = (next: GameEngine) => {
      carry = totals();
      engine = next;
      if (import.meta.env.DEV) Object.assign(window, { __rotathree: engine });
      fx.reset(engine.activeSide);
    };

    const showBanner = (data: Omit<BannerData, 'id' | 'seconds'>, seconds: number, blocking: boolean, then?: () => void) => {
      bannerId++;
      setBanner({ ...data, id: bannerId, seconds });
      banner = { left: seconds, blocking, then: then ?? null };
    };

    const stageColours = (count: number) => paletteColours(live.current.settings.palettes).slice(0, count);

    const recordRun = (completed: boolean) => {
      const t = totals();
      const record: RunRecord = {
        id: newId(),
        mode: session.mode,
        at: Date.now(),
        score: t.score,
        pieces: t.pieces,
        matches: t.matches,
        bestCombo: t.bestCombo,
        seconds: t.seconds,
        level: campaign ? (completed ? CAMPAIGN_LAST + 1 : campaignLevel + 1) : engine.state.speedLevel + 1,
        completed,
      };
      live.current.onRecord(record);
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
      const to = CAMPAIGN[next];
      showBanner(
        {
          kicker: `Уровень ${index + 1} пройден`,
          title: `${formatScore(levelScore)} очков`,
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
      const from = CAMPAIGN[campaignLevel];
      const to = CAMPAIGN[next];
      campaignLevel = next;
      setLevel(next);
      if (startsStage(next)) {
        swapEngine(newEngine({ config: levelConfig(to), ramp: null }));
        levelBase = 0;
        showBanner(
          { kicker: 'Новый этап', title: `${to.colours} цвета`, sub: 'стаканы снова по одному', colours: stageColours(to.colours) },
          2.2,
          true,
        );
      } else {
        engine.setSteps(to.activeStep, to.inactiveStep);
        if (to.glasses > from.glasses) {
          engine.addGlass();
          showBanner({ kicker: 'Новый стакан', title: `${to.glasses} стакана`, sub: 'первая фигура уже в пути' }, 1.6, false);
        } else {
          showBanner({ kicker: `Уровень ${next + 1}`, title: `цель ${formatScore(to.target)}`, sub: `${to.glasses} ст. · ${to.colours} цв.` }, 1.6, false);
        }
        levelBase = engine.state.score;
      }
    };

    const togglePause = () => {
      if (current === 'playing') {
        keyboard.releaseAll();
        setRunStatus('paused');
      } else if (current === 'paused') {
        setRunStatus('playing');
      }
    };

    const retry = () => {
      finished = true;
      live.current.onRetry(campaign ? { mode: 'campaign', level: campaignLevel } : session);
    };
    actions.current = {
      togglePause,
      retry,
      activeGlass: (slot: number) => {
        if (current !== 'playing') return;
        engine.activateSide(sideAtSlot(engine.activeSide, slot as 0 | 1 | 2 | 3));
      },
    };

    const acceptsInput = () => current === 'playing' && !(banner?.blocking ?? false);

    const sink = {
      move: (direction: -1 | 1, toWall: boolean) => {
        if (!acceptsInput()) return;
        engine.moveActive(toWall ? direction * engine.config.boardSize : direction);
      },
      softDrop: (held: boolean) => engine.setSoftDrop(held),
      press: (action: Exclude<Action, 'moveLeft' | 'moveRight' | 'softDrop'>) => {
        if (action === 'pause') return togglePause();
        if (action === 'restart') return retry();
        if (!acceptsInput()) {
          // On the result screens the drop key starts the next game.
          if ((current === 'over' || current === 'done') && action === 'hardDrop') retry();
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
    };
    const keyboard = new KeyboardController(
      () => live.current.settings.bindings,
      () => live.current.settings.handling,
      sink,
    );

    const onKeyDown = (event: KeyboardEvent) => {
      if (live.current.blocked || event.ctrlKey || event.metaKey || event.altKey) return;
      if (keyboard.keyDown(event.code, event.repeat)) event.preventDefault();
    };
    const onKeyUp = (event: KeyboardEvent) => keyboard.keyUp(event.code);
    const onBlur = () => {
      keyboard.releaseAll();
      if (current === 'playing') setRunStatus('paused');
    };
    window.addEventListener('keydown', onKeyDown);
    window.addEventListener('keyup', onKeyUp);
    window.addEventListener('blur', onBlur);

    let raf = 0;
    let last = performance.now();
    const tick = (now: number) => {
      const seconds = Math.min(MAX_FRAME_SECONDS, Math.max(0, (now - last) / 1000));
      last = now;
      const s = live.current.settings;
      const frozen = live.current.blocked;
      const holding = frozen || (banner?.blocking ?? false);
      if (frozen) keyboard.releaseAll();
      fx.screenShake = s.effects.screenShake;
      fx.turnSeconds = s.effects.turnMs / 1000;
      fx.explosion = s.effects.explosion;

      if (current === 'playing' && !holding) {
        keyboard.update(seconds);
        engine.update(seconds);
      }

      // Banners count down on their own clock.
      if (banner) {
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
          setCallout({ id: ++calloutId, kind: 'score', score: event.score, combo: event.combo });
        } else if (event.type === 'speedUp') {
          setCallout({ id: ++calloutId, kind: 'speed', speed: event.level + 1 });
        } else if (event.type === 'gameEnded' && !finished) {
          gameOver(event.side);
        }
      }

      if (campaign && !finished && !completing && acceptsInput() && engine.phase === 'playing') {
        if (engine.state.score - levelBase >= CAMPAIGN[campaignLevel].target) completeLevel();
      }

      renderer.draw(engine, fx);

      const t = totals();
      const next: HudState = {
        score: t.score,
        combo: engine.state.combo,
        bestCombo: t.bestCombo,
        matches: t.matches,
        pieces: t.pieces,
        seconds: Math.floor(t.seconds),
        level: campaign ? campaignLevel + 1 : 0,
        into: campaign ? engine.state.score - levelBase : 0,
        target: campaign ? CAMPAIGN[campaignLevel].target : 0,
        colours: campaign ? CAMPAIGN[campaignLevel].colours : engine.config.numberOfColors,
        glasses: engine.sides.length,
        speed: plan.ramp ? engine.state.speedLevel + 1 : 0,
      };
      if (!sameHud(next, shown)) {
        shown = next;
        setHud(next);
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

  const config = planFor(session).config;
  const corner = `${(100 * config.armLength) / gridSize(config)}%`;
  const campaign = session.mode === 'campaign';
  const retryLabel = campaign ? 'Повторить уровень' : 'Заново';
  const mode = MODE_NAMES[session.mode];
  const playingLevel = campaign ? CAMPAIGN[level] : undefined;

  return (
    <main className="game">
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
          <canvas ref={canvasRef} className="stage__canvas" style={{ width: size, height: size }} onClick={onCanvasClick} />
          <Hud
            hud={hud}
            callout={callout}
            bindings={settings.bindings}
            options={settings.hud}
            onPause={() => actions.current.togglePause()}
            onOpenSettings={props.onSettings}
          />
          {banner && <LevelBanner banner={banner} />}
        </div>
      </div>

      {status === 'paused' && !blocked && (
        <Overlay>
          <div className="dialog dialog--narrow">
            <span className="kicker">{mode}{playingLevel ? ` · уровень ${level + 1} из ${CAMPAIGN_LAST + 1}` : ''}</span>
            <h2 className="dialog__title">Пауза</h2>
            {playingLevel && (
              <p className="dialog__note">
                Цель {formatScore(playingLevel.target)} очков · {playingLevel.colours} цв. · {playingLevel.glasses} ст.
              </p>
            )}
            <div className="dialog__actions">
              <Button primary autoFocus onClick={() => actions.current.togglePause()}>
                Продолжить
              </Button>
              <Button onClick={() => actions.current.retry()}>{retryLabel}</Button>
              <Button onClick={props.onSettings}>Настройки</Button>
              {session.mode === 'custom' && <Button onClick={props.onCustomise}>Изменить режим</Button>}
              {session.mode !== 'custom' && <Button onClick={props.onLevels}>К уровням</Button>}
              <Button ghost onClick={props.onExit}>
                В меню
              </Button>
            </div>
          </div>
        </Overlay>
      )}

      {status === 'over' && result && !blocked && (
        <Overlay>
          <div className="dialog dialog--narrow">
            <span className="kicker">{mode}</span>
            <h2 className="dialog__title dialog__title--danger">Игра окончена</h2>
            <p className="dialog__note">
              {SLOT_NAMES[overSlot]} стакан заполнился до конца рукава.
              {campaign && ' Уровень не пройден: начнём его заново или выберем другой.'}
            </p>
            <Stats record={result} campaign={campaign} />
            <div className="dialog__actions">
              <Button primary autoFocus onClick={() => actions.current.retry()}>
                {retryLabel}
              </Button>
              {session.mode === 'custom' && <Button onClick={props.onCustomise}>Изменить режим</Button>}
              {campaign && <Button onClick={props.onLevels}>К уровням</Button>}
              <Button ghost onClick={props.onExit}>
                В меню
              </Button>
            </div>
          </div>
        </Overlay>
      )}

      {status === 'done' && result && !blocked && (
        <Overlay>
          <div className="dialog dialog--narrow">
            <span className="kicker">Кампания</span>
            <h2 className="dialog__title">Кампания пройдена</h2>
            <p className="dialog__note">Все {CAMPAIGN_LAST + 1} уровней позади. Безумие открыто.</p>
            <Stats record={result} campaign />
            <div className="dialog__actions">
              <Button primary autoFocus onClick={props.onInsane}>
                Безумие
              </Button>
              <Button onClick={props.onLevels}>К уровням</Button>
              <Button ghost onClick={props.onExit}>
                В меню
              </Button>
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
          <dt>Уровень</dt>
          <dd>{record.completed ? CAMPAIGN_LAST + 1 : record.level}</dd>
        </div>
      )}
      <div className={`stats__row ${campaign ? '' : 'stats__row--main'}`}>
        <dt>Очки</dt>
        <dd>{formatNumber(record.score)}</dd>
      </div>
      <div className="stats__row">
        <dt>Фигуры</dt>
        <dd>{record.pieces}</dd>
      </div>
      <div className="stats__row">
        <dt>Матчи</dt>
        <dd>{record.matches}</dd>
      </div>
      <div className="stats__row">
        <dt>Лучшее комбо</dt>
        <dd>×{record.bestCombo}</dd>
      </div>
      <div className="stats__row">
        <dt>Время</dt>
        <dd>{formatDuration(record.seconds)}</dd>
      </div>
    </dl>
  );
}
