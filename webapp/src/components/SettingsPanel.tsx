import { useEffect, useState } from 'react';
import {
  ACTIONS,
  GROUP_TITLES,
  SLOTS_PER_ACTION,
  bindKey,
  cloneBindings,
  defaultBindings,
  keyLabel,
  unbindKey,
  type Action,
  type ActionGroup,
} from '../input/bindings';
import { defaultHandling } from '../input/keyboard';
import { defaultGameOptions, type GameOptions, type Settings } from '../services/settingsStore';

interface Props {
  settings: Settings;
  /** True when opened over a running game: changing the rules restarts it. */
  inGame: boolean;
  onChange: (settings: Settings) => void;
  onClose: () => void;
}

type Tab = 'controls' | 'game';

/** The key slot waiting for its new key. */
interface Capture {
  action: Action;
  slot: number;
}

const GROUPS: readonly ActionGroup[] = ['piece', 'glass', 'game'];

export function SettingsPanel({ settings, inGame, onChange, onClose }: Props) {
  const [tab, setTab] = useState<Tab>('controls');
  const [capture, setCapture] = useState<Capture | null>(null);

  // While a slot is waiting, the very next key press is its new key.
  useEffect(() => {
    const onKey = (event: KeyboardEvent) => {
      if (capture) {
        event.preventDefault();
        event.stopPropagation();
        if (event.code === 'Escape') {
          setCapture(null);
        } else if (event.code === 'Backspace' || event.code === 'Delete') {
          onChange({ ...settings, bindings: unbindKey(settings.bindings, capture.action, capture.slot) });
          setCapture(null);
        } else if (event.code) {
          onChange({
            ...settings,
            bindings: bindKey(settings.bindings, capture.action, capture.slot, event.code),
          });
          setCapture(null);
        }
      } else if (event.code === 'Escape') {
        event.preventDefault();
        onClose();
      }
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [capture, settings, onChange, onClose]);

  const setGame = (patch: Partial<GameOptions>) =>
    onChange({ ...settings, game: { ...settings.game, ...patch } });

  return (
    <div className="overlay overlay--top" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <div className="dialog dialog--settings" role="dialog" aria-label="Настройки">
        <header className="settings__header">
          <h2 className="dialog__title">Настройки</h2>
          <div className="tabs">
            <button
              type="button"
              className={`tabs__tab ${tab === 'controls' ? 'is-active' : ''}`}
              onClick={() => setTab('controls')}
            >
              Управление
            </button>
            <button
              type="button"
              className={`tabs__tab ${tab === 'game' ? 'is-active' : ''}`}
              onClick={() => setTab('game')}
            >
              Игра
            </button>
          </div>
          <button type="button" className="button button--ghost settings__close" onClick={onClose}>
            Закрыть
          </button>
        </header>

        {tab === 'controls' ? (
          <div className="settings__body">
            <p className="settings__hint">
              Нажмите на клавишу, затем на новую. <kbd className="keycap">Esc</kbd> — отмена,{' '}
              <kbd className="keycap">Backspace</kbd> — очистить. Клавиша, занятая другим действием,
              переходит к новому.
            </p>

            {GROUPS.map((group) => (
              <section className="settings__group" key={group}>
                <h3>{GROUP_TITLES[group]}</h3>
                {ACTIONS.filter((action) => action.group === group).map((action) => (
                  <div className="bind" key={action.id}>
                    <div className="bind__name">
                      <span>{action.label}</span>
                      <small>{action.hint}</small>
                    </div>
                    <div className="bind__keys">
                      {Array.from({ length: SLOTS_PER_ACTION }, (_, slot) => {
                        const code = settings.bindings[action.id][slot];
                        // The second slot only appears once the first is taken.
                        if (code === undefined && slot > settings.bindings[action.id].length) return null;
                        const waiting = capture?.action === action.id && capture.slot === slot;
                        return (
                          <button
                            type="button"
                            key={slot}
                            className={`bind__key ${waiting ? 'is-waiting' : ''} ${code ? '' : 'is-empty'}`}
                            data-testid={`bind-${action.id}-${slot}`}
                            onClick={() => setCapture(waiting ? null : { action: action.id, slot })}
                          >
                            {waiting ? 'нажмите…' : code ? keyLabel(code) : '+'}
                          </button>
                        );
                      })}
                    </div>
                  </div>
                ))}
              </section>
            ))}

            <section className="settings__group">
              <h3>Автоповтор движения</h3>
              <Slider
                label="Задержка перед повтором (DAS)"
                value={settings.handling.dasMs}
                min={0}
                max={300}
                step={5}
                unit="мс"
                onChange={(dasMs) => onChange({ ...settings, handling: { ...settings.handling, dasMs } })}
              />
              <Slider
                label="Интервал повтора (ARR)"
                value={settings.handling.arrMs}
                min={0}
                max={100}
                step={5}
                unit="мс"
                note={settings.handling.arrMs === 0 ? 'сразу до стенки' : undefined}
                onChange={(arrMs) => onChange({ ...settings, handling: { ...settings.handling, arrMs } })}
              />
            </section>

            <div className="settings__footer">
              <button
                type="button"
                className="button"
                onClick={() =>
                  onChange({
                    ...settings,
                    bindings: cloneBindings(defaultBindings),
                    handling: { ...defaultHandling },
                  })
                }
              >
                Сбросить управление
              </button>
            </div>
          </div>
        ) : (
          <div className="settings__body">
            {inGame && (
              <p className="settings__hint settings__hint--warn">
                Изменение правил начнёт новую партию.
              </p>
            )}
            <section className="settings__group">
              <h3>Скорость падения</h3>
              <Choice
                label="Шаг в активном стакане"
                value={settings.game.activeStepSeconds}
                options={[[0.5, '0.5 с'], [0.75, '0.75 с'], [1, '1 с'], [1.5, '1.5 с']]}
                onChange={(activeStepSeconds) => setGame({ activeStepSeconds })}
              />
              <Choice
                label="Шаг в остальных стаканах"
                value={settings.game.inactiveStepSeconds}
                options={[[1.5, '1.5 с'], [2, '2 с'], [3, '3 с'], [4, '4 с'], [6, '6 с']]}
                onChange={(inactiveStepSeconds) => setGame({ inactiveStepSeconds })}
              />
            </section>
            <section className="settings__group">
              <h3>Поле</h3>
              <Choice
                label="Длина рукава, клеток"
                value={settings.game.armLength}
                options={[[6, '6'], [8, '8'], [9, '9'], [10, '10']]}
                onChange={(armLength) => setGame({ armLength })}
              />
              <Choice
                label="Цветов"
                value={settings.game.numberOfColors}
                options={[[3, '3'], [4, '4']]}
                onChange={(numberOfColors) => setGame({ numberOfColors })}
              />
            </section>
            <section className="settings__group">
              <h3>Правила</h3>
              <Choice
                label="После хлопка падает"
                value={settings.game.gravityScope}
                options={[['wholeGlass', 'всё без опоры'], ['aboveCleared', 'только над дырой']]}
                onChange={(gravityScope) => setGame({ gravityScope })}
              />
              <Choice
                label="Стакан оседает при повороте"
                value={settings.game.settleAfterBoardRotation}
                options={[[false, 'нет'], [true, 'да']]}
                onChange={(settleAfterBoardRotation) => setGame({ settleAfterBoardRotation })}
              />
            </section>
            <section className="settings__group">
              <h3>Эффекты</h3>
              <Choice
                label="Толчки и тряска поля"
                value={settings.screenShake}
                options={[[true, 'вкл'], [false, 'выкл']]}
                onChange={(screenShake) => onChange({ ...settings, screenShake })}
              />
            </section>
            <div className="settings__footer">
              <button type="button" className="button" onClick={() => setGame({ ...defaultGameOptions })}>
                Сбросить правила
              </button>
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function Choice<T extends string | number | boolean>({
  label,
  value,
  options,
  onChange,
}: {
  label: string;
  value: T;
  options: readonly (readonly [T, string])[];
  onChange: (value: T) => void;
}) {
  return (
    <div className="choice">
      <span className="choice__label">{label}</span>
      <div className="choice__options">
        {options.map(([option, text]) => (
          <button
            type="button"
            key={String(option)}
            className={`chip ${option === value ? 'is-active' : ''}`}
            onClick={() => onChange(option)}
          >
            {text}
          </button>
        ))}
      </div>
    </div>
  );
}

function Slider({
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
    <label className="slider">
      <span className="slider__label">{label}</span>
      <input
        type="range"
        min={min}
        max={max}
        step={step}
        value={value}
        onChange={(event) => onChange(Number(event.target.value))}
      />
      <span className="slider__value">
        {value} {unit}
        {note && <small> · {note}</small>}
      </span>
    </label>
  );
}
