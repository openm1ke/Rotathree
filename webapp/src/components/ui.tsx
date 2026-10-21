import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { useEffect, useRef, useState, type ReactNode, type RefObject } from 'react';
import { createPortal } from 'react-dom';
import { PlayerHands } from '../platform/hands';

/** The way back of every page: a small chevron, the same on every screen. The
 * label stays translated for keyboard users and screen readers. */
export function BackButton({ onClick, navigable = true }: { onClick: () => void; navigable?: boolean }) {
  const { t } = useI18n();
  return <button type="button" className="back" aria-label={t('Назад')} title={t('Назад')} data-nav={navigable || undefined} onClick={onClick}>
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round" aria-hidden="true">
      <path d="M15 5l-7 7 7 7" />
    </svg>
  </button>;
}

/** Compact game actions retain translated labels for keyboard and screen readers. */
export function GameIconButton({ icon, label, onClick }: {
  icon: 'pause' | 'settings' | 'sound-on' | 'sound-off'; label: string;
  onClick: (event: React.MouseEvent<HTMLButtonElement>) => void;
}) {
  const { t } = useI18n();
  return <button type="button" className="game-icon" aria-label={t(label)} title={t(label)} onClick={onClick}>
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
      {icon === 'pause' ? <><path d="M8 5v14M16 5v14" strokeWidth="3" strokeLinecap="round" /></>
      : icon === 'sound-on' || icon === 'sound-off' ? <g strokeLinecap="round" strokeLinejoin="round">
        <path d="M3.5 9.5h3.5L11.5 6v12L7 14.5H3.5z" />
        {icon === 'sound-on' ? <path d="M15 9.5a3.5 3.5 0 0 1 0 5M17.5 7a7 7 0 0 1 0 10" /> : <path d="m15 9.5 5 5m0-5-5 5" />}
      </g> : <>
        <path d="m9 3-.6 2.3-1.5.9-2.3-.6-3 5.2 1.7 1.7v1.8l-1.7 1.7 3 5.2 2.3-.6 1.5.9.6 2.3h6l.6-2.3 1.5-.9 2.3.6 3-5.2-1.7-1.7v-1.8l1.7-1.7-3-5.2-2.3.6-1.5-.9L15 3Z" transform="translate(1 0) scale(.9)" />
        <circle cx="12" cy="12" r="3" />
      </>}
    </svg>
  </button>;
}

const FOCUSABLE = 'button:not(:disabled), input, select, [tabindex="0"]';
/** After its delay, a layer that opened by itself waits until no key or finger
 * has pressed for this long: a player still hammering the drop key presses
 * nothing. */
const ARM_STILL_MS = 400;
/** It arms by this time whatever is held, so that a stuck key cannot lock it;
 * a press that began earlier still never counts. */
const ARM_LATEST_MS = 3000;

/** The music on or off at once, without opening the settings: on the main
 * menu beside the language switch and in a game beside the settings gear. A
 * tap or click leaves no focus behind, so the next Space drops a piece instead
 * of pressing the switch again. */
export function SoundButton({ on, onToggle }: { on: boolean; onToggle: () => void }) {
  return <GameIconButton icon={on ? 'sound-on' : 'sound-off'} label={on ? 'Выключить музыку' : 'Включить музыку'}
    onClick={(event) => {
      onToggle();
      if (event.detail > 0) event.currentTarget.blur();
    }} />;
}

/** A layer over the whole window, not just the field it was opened from.
 *
 * `armAfterMs` is for a layer that opens by itself, under keys and fingers
 * still busy with the game: for that long, and then until the player's hands
 * have been still for a moment, it presses nothing, and only then does its
 * first button take the focus. A press that began before that never counts,
 * so a key held through the opening, its auto-repeat or a finger lifted
 * afterwards cannot choose for the player. */
export function Overlay({
  children,
  onDismiss,
  label = 'Меню игры',
  className = '',
  armAfterMs = 0,
}: {
  children: ReactNode;
  onDismiss?: () => void;
  label?: string;
  className?: string;
  armAfterMs?: number;
}) {
  const { t } = useI18n();
  const root = useRef<HTMLDivElement>(null);
  const returnFocus = useRef(document.activeElement as HTMLElement | null);
  const armed = useRef(armAfterMs <= 0);
  const [ready, setReady] = useState(armAfterMs <= 0);
  /** Whether the pointer now pressing went down after arming. */
  const freshPointer = useRef(false);
  useEffect(() => {
    const dialog = root.current!;
    const previous = returnFocus.current;
    const background = [...document.body.children].filter(
      (node): node is HTMLElement => node instanceof HTMLElement && !node.contains(dialog),
    );
    const original = background.map((node) => node.inert);
    background.forEach((node) => {
      node.inert = true;
    });
    // Until it is armed the layer holds the focus itself: Enter and Space
    // find no button to press.
    if (!dialog.contains(document.activeElement))
      ((armed.current && dialog.querySelector<HTMLElement>(FOCUSABLE)) || dialog).focus();
    return () => {
      background.forEach((node, i) => {
        node.inert = original[i];
      });
      if (previous?.isConnected && !previous.closest('[inert]')) previous.focus();
    };
  }, []);
  useEffect(() => {
    if (armAfterMs <= 0) return;
    const dialog = root.current!;
    // Enter and Space press the focused button. They count only from a key
    // that went down after arming; otherwise its repeats and its release
    // (Space presses on release) do nothing.
    const fresh = new Set<string>();
    const presses = (event: KeyboardEvent) => event.key === 'Enter' || event.key === ' ';
    const onKeyDown = (event: KeyboardEvent) => {
      if (!presses(event)) return;
      if (armed.current && !event.repeat) fresh.add(event.code);
      else if (!fresh.has(event.code)) event.preventDefault();
    };
    const onKeyUp = (event: KeyboardEvent) => {
      if (presses(event) && !fresh.delete(event.code)) event.preventDefault();
    };
    const opened = performance.now();
    const hands = new PlayerHands();
    const unwatchHands = hands.watch();
    let timer: ReturnType<typeof setTimeout>;
    const arm = () => {
      const now = performance.now();
      if (now - opened < ARM_LATEST_MS && !hands.stillFor(ARM_STILL_MS, now)) {
        timer = setTimeout(arm, 100);
        return;
      }
      armed.current = true;
      setReady(true);
      if (document.activeElement === dialog) dialog.querySelector<HTMLElement>(FOCUSABLE)?.focus();
    };
    timer = setTimeout(arm, armAfterMs);
    window.addEventListener('keydown', onKeyDown, true);
    window.addEventListener('keyup', onKeyUp, true);
    return () => {
      clearTimeout(timer);
      unwatchHands();
      window.removeEventListener('keydown', onKeyDown, true);
      window.removeEventListener('keyup', onKeyUp, true);
    };
  }, [armAfterMs]);
  return createPortal(
    <div
      ref={root}
      className={`overlay ${className}`}
      role="dialog"
      aria-modal="true"
      aria-label={t(label)}
      tabIndex={-1}
      data-armed={armAfterMs > 0 ? ready : undefined}
      onPointerDownCapture={() => {
        freshPointer.current = armed.current;
      }}
      onClickCapture={(event) => {
        // Once armed, a click counts from a pointer that went down since, or
        // from the keyboard: a click with no pointer behind it (detail 0).
        if (armAfterMs <= 0 || (armed.current && (event.detail === 0 || freshPointer.current))) return;
        event.preventDefault();
        event.stopPropagation();
      }}
      onKeyDown={(event) => {
        if (event.defaultPrevented) return;
        if (event.key === 'Escape' && onDismiss) {
          event.preventDefault();
          event.stopPropagation();
          onDismiss();
        }
        if (event.key !== 'Tab') return;
        const items = [
          ...(root.current?.querySelectorAll<HTMLElement>(
            'button:not(:disabled), input:not(:disabled), select:not(:disabled), textarea, [tabindex="0"]',
          ) ?? []),
        ].filter((el) => el.getClientRects().length > 0);
        const first = items[0],
          last = items.at(-1);
        if (!first) {
          event.preventDefault();
          root.current?.focus();
        } else if (event.shiftKey && (document.activeElement === first || document.activeElement === root.current)) {
          event.preventDefault();
          last?.focus();
        } else if (!event.shiftKey && document.activeElement === last) {
          event.preventDefault();
          first.focus();
        }
      }}
      onMouseDown={(event) => {
        if (event.target === event.currentTarget && onDismiss) onDismiss();
      }}
    >
      {children}
    </div>,
    document.body,
  );
}

/** The frame of a menu screen: a header with the way back, the body, and an
 * optional footer with the keys. */
export function Screen({
  kicker,
  title,
  onBack,
  actions,
  footer,
  children,
  rootRef,
  className = '',
}: {
  kicker?: string;
  title: string;
  onBack: () => void;
  actions?: ReactNode;
  footer?: ReactNode;
  children: ReactNode;
  rootRef?: RefObject<HTMLElement | null>;
  className?: string;
}) {
  return (
    <main className={`screen ${className}`} ref={rootRef as RefObject<HTMLElement>}>
      <header className="screen__head">
        <BackButton onClick={onBack} />
        <div className="screen__title">
          {kicker && <span className="kicker"><T>{kicker}</T></span>}
          <h1><T>{title}</T></h1>
        </div>
        <div className="screen__actions">{actions}</div>
      </header>
      <div className="screen__body">{children}</div>
      {footer && <footer className="screen__foot">{footer}</footer>}
    </main>
  );
}

/** One option of a choice: a chip that is lit when it is the current value. */
export function Chip({
  active,
  onClick,
  children,
  disabled,
  numeric = false,
}: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
  disabled?: boolean;
  numeric?: boolean;
}) {
  return (
    <button
      type="button"
      data-nav
      className={`chip ${active ? 'is-active' : ''} ${numeric ? 'chip--number' : ''}`}
      aria-pressed={active}
      disabled={disabled}
      onClick={onClick}
    >
      <T>{children}</T>
    </button>
  );
}

/** A setting with a label, an optional note and its control. */
export function Row({ label, note, children }: { label: string; note?: ReactNode; children: ReactNode }) {
  return (
    <div className="row">
      <div className="row__label">
        <span><T>{label}</T></span>
        {note && <small><T>{note}</T></small>}
      </div>
      <div className="row__control">{children}</div>
    </div>
  );
}

/** A group of choices for one setting. */
export function Choice<T extends string | number | boolean>({
  label,
  note,
  value,
  options,
  onChange,
}: {
  label: string;
  note?: ReactNode;
  value: T;
  options: readonly (readonly [T, ReactNode])[];
  onChange: (value: T) => void;
}) {
  return (
    <Row label={label} note={note}>
      <div className="chips">
        {options.map(([option, text]) => (
          <Chip key={String(option)} numeric={typeof option === 'number'} active={option === value} onClick={() => onChange(option)}><T>
            {text}
          </T></Chip>
        ))}
      </div>
    </Row>
  );
}

/** A slider with its current value written beside it. */
export function Slider({
  label,
  value,
  min,
  max,
  step,
  unit,
  note,
  onChange,
}: {
  label: string;
  value: number;
  min: number;
  max: number;
  step: number;
  unit: string;
  note?: string;
  onChange: (value: number) => void;
}) {
  const { t } = useI18n();
  return (
    <Row label={label} note={note}>
      <div className="slider">
        <input
          aria-label={t(label)}
          type="range"
          min={min}
          max={max}
          step={step}
          value={value}
          onChange={(event) => onChange(Number(event.target.value))}
        />
        <output><T>
          {Number.isInteger(value) ? value : value.toFixed(2)} {unit}
        </T></output>
      </div>
    </Row>
  );
}

/** A two-state switch, shown as on or off words. */
export function Toggle({
  label,
  value,
  onChange,
  on = 'вкл',
  off = 'выкл',
}: {
  label: string;
  value: boolean;
  onChange: (value: boolean) => void;
  on?: string;
  off?: string;
}) {
  return (
    <Choice<boolean>
      label={label}
      value={value}
      options={[
        [true, on],
        [false, off],
      ]}
      onChange={onChange}
    />
  );
}

/** A big action at the foot of a menu. */
export function Button({
  children,
  onClick,
  primary,
  ghost,
  autoFocus,
  disabled,
}: {
  children: ReactNode;
  onClick: () => void;
  primary?: boolean;
  ghost?: boolean;
  autoFocus?: boolean;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      data-nav
      autoFocus={autoFocus}
      disabled={disabled}
      className={`button ${primary ? 'button--primary' : ''} ${ghost ? 'button--ghost' : ''}`}
      onClick={onClick}
    >
      <T>{children}</T>
    </button>
  );
}
