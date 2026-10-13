import { useI18n } from '../i18n/context';
import { T } from '../i18n/Text';
import { useEffect, useRef, useState } from 'react';
import { ACTIONS } from '../input/bindings';
import { PAD_SLOTS, type PadAction, type PadLayout, type PadSlot } from '../input/pads';
import { TRIANGLE_POINTS, buttonRects, type PadShape, type PadTweaks } from '../input/padShape';

const ICONS: Record<PadAction, string> = {
  none: '',
  moveLeft: '←',
  moveRight: '→',
  rotateCW: '↻',
  rotateCCW: '↺',
  softDrop: '⇓',
  hardDrop: '⤓',
  glassLeft: '↶',
  glassRight: '↷',
  glassOpposite: '⇄',
  pause: 'Ⅱ',
  restart: '↺',
};
const CAPTIONS: Record<PadAction, string> = {
  none: '',
  moveLeft: 'Влево',
  moveRight: 'Вправо',
  rotateCW: 'Поворот',
  rotateCCW: 'Поворот',
  softDrop: 'Быстрее',
  hardDrop: 'Сброс',
  glassLeft: 'Стакан',
  glassRight: 'Стакан',
  glassOpposite: 'Напротив',
  pause: 'Пауза',
  restart: 'Заново',
};

export function DPad({
  layout,
  label,
  disabled = false,
  showLabels = true,
  shape = 'square',
  tweaks = {},
  highlight,
  onDown,
  onUp,
}: {
  layout: PadLayout;
  label: string;
  disabled?: boolean;
  showLabels?: boolean;
  shape?: PadShape;
  tweaks?: PadTweaks;
  /** The button to outline while the layout is being edited. */
  highlight?: PadSlot;
  onDown: (action: PadAction) => void;
  onUp: (action: PadAction) => void;
}) {
  const { t } = useI18n();
  const held = useRef(new Map<number, PadAction>());
  const callbacks = useRef({ onDown, onUp });
  callbacks.current = { onDown, onUp };
  const [pressed, setPressed] = useState<PadAction[]>([]);
  useEffect(() => {
    const pointers = held.current;
    if (disabled) {
      for (const action of pointers.values()) callbacks.current.onUp(action);
      pointers.clear();
      setPressed([]);
    }
    return () => {
      for (const action of pointers.values()) callbacks.current.onUp(action);
      pointers.clear();
    };
  }, [disabled]);
  const release = (pointer: number) => {
    const action = held.current.get(pointer);
    if (action === undefined) return;
    held.current.delete(pointer);
    callbacks.current.onUp(action);
    setPressed([...held.current.values()]);
  };
  const rects = buttonRects(tweaks);
  return (
    <div className={`dpad dpad--${shape}`} role="group" aria-label={t(label)}>
      {PAD_SLOTS.map((slot) => {
        const action = layout[slot];
        const rect = rects[slot];
        return (
          <button
            key={slot}
            type="button"
            className={`dpad__button dpad__button--${slot} ${pressed.includes(action) ? 'is-pressed' : ''} ${highlight === slot ? 'is-edited' : ''}`}
            style={{
              left: `${rect.x * 100}%`,
              top: `${rect.y * 100}%`,
              width: `${rect.size * 100}%`,
              height: `${rect.size * 100}%`,
            }}
            disabled={disabled || action === 'none'}
            aria-label={t(ACTIONS.find((a) => a.id === action)?.hint ?? 'Не назначено')}
            onPointerDown={(event) => {
              if (event.button !== 0 || disabled || action === 'none') return;
              event.preventDefault();
              event.currentTarget.setPointerCapture(event.pointerId);
              held.current.set(event.pointerId, action);
              callbacks.current.onDown(action);
              setPressed([...held.current.values()]);
            }}
            onPointerUp={(event) => release(event.pointerId)}
            onPointerCancel={(event) => release(event.pointerId)}
            onLostPointerCapture={(event) => release(event.pointerId)}
            onClick={(event) => {
              if (event.detail === 0 && !disabled) {
                callbacks.current.onDown(action);
                callbacks.current.onUp(action);
              }
            }}
          >
            {shape === 'triangle' && (
              <svg className="dpad__shape" viewBox="0 0 100 100" preserveAspectRatio="none" aria-hidden="true">
                <polygon points={TRIANGLE_POINTS[slot]} />
              </svg>
            )}
            <span aria-hidden="true" className="dpad__icon">
              {ICONS[action]}
            </span>
            {showLabels && <small aria-hidden="true"><T>{CAPTIONS[action]}</T></small>}
          </button>
        );
      })}
    </div>
  );
}
