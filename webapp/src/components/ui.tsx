import type { ReactNode, RefObject } from 'react';
import { createPortal } from 'react-dom';

/** A layer over the whole window, not just the field it was opened from. */
export function Overlay({ children, onDismiss }: { children: ReactNode; onDismiss?: () => void }) {
  return createPortal(
    <div
      className="overlay"
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
        <button type="button" className="back" data-nav onClick={onBack}>
          ← Назад
        </button>
        <div className="screen__title">
          {kicker && <span className="kicker">{kicker}</span>}
          <h1>{title}</h1>
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
}: {
  active: boolean;
  onClick: () => void;
  children: ReactNode;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      data-nav
      className={`chip ${active ? 'is-active' : ''}`}
      aria-pressed={active}
      disabled={disabled}
      onClick={onClick}
    >
      {children}
    </button>
  );
}

/** A setting with a label, an optional note and its control. */
export function Row({ label, note, children }: { label: string; note?: ReactNode; children: ReactNode }) {
  return (
    <div className="row">
      <div className="row__label">
        <span>{label}</span>
        {note && <small>{note}</small>}
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
          <Chip key={String(option)} active={option === value} onClick={() => onChange(option)}>
            {text}
          </Chip>
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
  return (
    <Row label={label} note={note}>
      <div className="slider">
        <input type="range" min={min} max={max} step={step} value={value} onChange={(event) => onChange(Number(event.target.value))} />
        <output>
          {Number.isInteger(value) ? value : value.toFixed(2)} {unit}
        </output>
      </div>
    </Row>
  );
}

/** A two-state switch, shown as on or off words. */
export function Toggle({ label, value, onChange, on = 'вкл', off = 'выкл' }: { label: string; value: boolean; onChange: (value: boolean) => void; on?: string; off?: string }) {
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
      {children}
    </button>
  );
}

