import { useI18n } from '../i18n/context';
import { useEffect, useRef, useState, type PointerEvent } from 'react';
import type { Settings } from '../services/storage';
import { movePad, padAreaHeight, padGeometry, type PadPositions, type PadSide } from '../input/padPlacement';
import type { PadAction } from '../input/pads';
import { DPad } from './DPad';

export function TouchControls({
  settings,
  disabled = false,
  onDown,
  onUp,
  onEdit,
}: {
  settings: Settings;
  disabled?: boolean;
  onDown: (action: PadAction) => void;
  onUp: (action: PadAction) => void;
  onEdit?: (positions: PadPositions) => void;
}) {
  const { t } = useI18n();
  const root = useRef<HTMLDivElement>(null);
  const [bounds, setBounds] = useState({
    width: Math.max(280, window.innerWidth - 16),
    viewport: window.innerHeight,
    virtual: window.innerWidth - 16,
  });
  useEffect(() => {
    const measure = () =>
      setBounds({
        width: root.current?.clientWidth ?? 280,
        viewport: window.innerHeight,
        virtual: window.innerWidth - 16,
      });
    const observer = new ResizeObserver(measure);
    observer.observe(root.current!);
    window.addEventListener('resize', measure);
    measure();
    return () => {
      observer.disconnect();
      window.removeEventListener('resize', measure);
    };
  }, []);
  const width = onEdit ? bounds.virtual : bounds.width;
  const height = padAreaHeight(bounds.viewport, settings.padPositions, width);
  const scale = onEdit ? bounds.width / width : 1;
  const geometry = padGeometry(width, height, settings.padPositions);
  const drag = useRef<{
    pointer: number;
    side: PadSide;
    clientX: number;
    clientY: number;
    x: number;
    y: number;
    positions: PadPositions;
  } | null>(null);
  const move = (event: PointerEvent<HTMLDivElement>) => {
    const start = drag.current;
    if (!start || start.pointer !== event.pointerId) return;
    onEdit?.(
      movePad(
        start.positions,
        start.side,
        start.x + (event.clientX - start.clientX) / scale,
        start.y + (event.clientY - start.clientY) / scale,
        width,
        height,
      ),
    );
  };
  return (
    <div className={`pad-surface ${onEdit ? 'pad-surface--editor' : ''}`} ref={root} style={{ height: height * scale }}>
      <div className="pad-surface__space" style={{ width, height, transform: `scale(${scale})` }}>
        {(['left', 'right'] as const).map((side) => {
          const r = geometry[side],
            label = side === 'left' ? 'Левая крестовина' : 'Правая крестовина';
          return (
            <div
              key={side}
              data-pad={side}
              className="pad-surface__pad"
              style={{ left: r.x, top: r.y, width: r.size, height: r.size }}
              role={onEdit ? 'button' : undefined}
              tabIndex={onEdit ? 0 : undefined}
              aria-label={onEdit ? t(`Переместить: ${label}`) : undefined}
              onPointerDown={
                onEdit
                  ? (event) => {
                      if (event.button !== 0) return;
                      event.preventDefault();
                      event.currentTarget.setPointerCapture(event.pointerId);
                      drag.current = {
                        pointer: event.pointerId,
                        side,
                        clientX: event.clientX,
                        clientY: event.clientY,
                        x: r.x,
                        y: r.y,
                        positions: settings.padPositions,
                      };
                    }
                  : undefined
              }
              onPointerMove={onEdit ? move : undefined}
              onPointerUp={() => {
                drag.current = null;
              }}
              onPointerCancel={() => {
                drag.current = null;
              }}
              onLostPointerCapture={() => {
                drag.current = null;
              }}
              onKeyDown={
                onEdit
                  ? (event) => {
                      const delta = { ArrowLeft: [-8, 0], ArrowRight: [8, 0], ArrowUp: [0, -8], ArrowDown: [0, 8] }[
                        event.key
                      ];
                      if (!delta) return;
                      event.preventDefault();
                      event.stopPropagation();
                      onEdit(movePad(settings.padPositions, side, r.x + delta[0], r.y + delta[1], width, height));
                    }
                  : undefined
              }
            >
              <div inert={onEdit ? true : undefined}>
                <DPad
                  label={label}
                  layout={settings.pads[side]}
                  disabled={disabled}
                  showLabels={settings.hud.keyHints || !!onEdit}
                  onDown={onDown}
                  onUp={onUp}
                />
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}
