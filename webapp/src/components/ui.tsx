import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { useEffect, useRef, type ReactNode, type RefObject } from 'react';
import { createPortal } from 'react-dom';

/** Compact game actions retain translated labels for keyboard and screen readers. */
export function GameIconButton({ icon, label, onClick }: {
  icon: 'pause' | 'settings'; label: string; onClick: () => void;
}) {
  const { t } = useI18n();
  return <button type="button" className="game-icon" aria-label={t(label)} title={t(label)} onClick={onClick}>
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
      {icon === 'pause' ? <><path d="M8 5v14M16 5v14" strokeWidth="3" strokeLinecap="round" /></> : <>
        <path d="m9 3-.6 2.3-1.5.9-2.3-.6-3 5.2 1.7 1.7v1.8l-1.7 1.7 3 5.2 2.3-.6 1.5.9.6 2.3h6l.6-2.3 1.5-.9 2.3.6 3-5.2-1.7-1.7v-1.8l1.7-1.7-3-5.2-2.3.6-1.5-.9L15 3Z" transform="translate(1 0) scale(.9)" />
        <circle cx="12" cy="12" r="3" />
      </>}
    </svg>
  </button>;
}

/** A layer over the whole window, not just the field it was opened from. */
export function Overlay({
  children,
  onDismiss,
  label = 'Меню игры',
  className = '',
}: {
  children: ReactNode;
  onDismiss?: () => void;
  label?: string;
  className?: string;
}) {
  const { t } = useI18n();
  const root = useRef<HTMLDivElement>(null);
  const returnFocus = useRef(document.activeElement as HTMLElement | null);
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
    if (!dialog.contains(document.activeElement))
      (dialog.querySelector<HTMLElement>('button:not(:disabled), input, select, [tabindex="0"]') ?? dialog).focus();
    return () => {
      background.forEach((node, i) => {
        node.inert = original[i];
      });
      if (previous?.isConnected && !previous.closest('[inert]')) previous.focus();
    };
  }, []);
  return createPortal(
    <div
      ref={root}
      className={`overlay ${className}`}
      role="dialog"
      aria-modal="true"
      aria-label={t(label)}
      tabIndex={-1}
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
        <button type="button" className="back" data-nav onClick={onBack}><T>
          ← Назад
        </T></button>
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
