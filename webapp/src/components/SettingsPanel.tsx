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
import { MAX_COLORS } from '../game/piece';
import { defaultHandling } from '../input/keyboard';
import { BLOCK_TONES } from '../render/theme';
import {
  defaultGameOptions,
  defaultHudOptions,
  defaultTurnMs,
  type GameOptions,
  type HudOptions,
  type Settings,
} from '../services/settingsStore';

interface Props {
  settings: Settings;
  /** False when the browser refuses to keep the settings. */
  stored: boolean;
  /** True when opened over a running game: changing the rules restarts it. */
  inGame: boolean;
  onChange: (settings: Settings) => void;
  onClose: () => void;
}

type Tab = 'controls' | 'game' | 'view';

/** The key slot waiting for its new key. */
interface Capture {
  action: Action;
  slot: number;
}

const GROUPS: readonly ActionGroup[] = ['piece', 'glass', 'game'];

const TABS: readonly (readonly [Tab, string])[] = [
  ['controls', 'Управление'],
  ['game', 'Игра'],
  ['view', 'Интерфейс'],
];

const SHOWN: readonly (readonly [boolean, string])[] = [
  [true, 'показывать'],
  [false, 'скрыть'],
];

export function SettingsPanel({ settings, stored, inGame, onChange, onClose }: Props) {
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
  const setHud = (patch: Partial<HudOptions>) =>
    onChange({ ...settings, hud: { ...settings.hud, ...patch } });

  return (
    <div className="overlay overlay--top" onMouseDown={(event) => event.target === event.currentTarget && onClose()}>
      <div className="dialog dialog--settings" role="dialog" aria-label="Настройки">
        <header className="settings__header">
          <h2 className="dialog__title">Настройки</h2>
          <div className="tabs">
            {TABS.map(([id, title]) => (
              <button
                type="button"
                key={id}
                className={`tabs__tab ${tab === id ? 'is-active' : ''}`}
                onClick={() => setTab(id)}
              >
                {title}
              </button>
            ))}
          </div>
          <button type="button" className="button button--ghost settings__close" onClick={onClose}>
            Закрыть
          </button>
        </header>

        {tab === 'controls' && (
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
        )}

        {tab === 'game' && (
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
                label="Дополнительных стаканов"
                note="кроме вашего: меньше стаканов — спокойнее игра"
                value={settings.game.glassCount - 1}
                options={[[1, '1'], [2, '2'], [3, '3']]}
                onChange={(extra) => setGame({ glassCount: extra + 1 })}
              />
              <Choice
                label="Цветов"
                note={
                  <span className="swatches">
                    {BLOCK_TONES.slice(0, settings.game.numberOfColors).map((tones) => (
                      <i key={tones.base} style={{ background: tones.base }} />
                    ))}
                  </span>
                }
                value={settings.game.numberOfColors}
                options={Array.from({ length: MAX_COLORS - 2 }, (_, i) => [i + 3, String(i + 3)] as const)}
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
            <div className="settings__footer">
              <button type="button" className="button" onClick={() => setGame({ ...defaultGameOptions })}>
                Сбросить правила
              </button>
            </div>
          </div>
        )}

        {tab === 'view' && (
          <div className="settings__body">
            <section className="settings__group">
              <h3>Поворот поля</h3>
              <Slider
                label="Длительность поворота"
                value={settings.turnMs}
                min={0}
                max={600}
                step={20}
                unit="мс"
                note={settings.turnMs === 0 ? 'мгновенно' : undefined}
                onChange={(turnMs) => onChange({ ...settings, turnMs })}
              />
              <Choice
                label="Толчки и тряска поля"
                value={settings.screenShake}
                options={[[true, 'вкл'], [false, 'выкл']]}
                onChange={(screenShake) => onChange({ ...settings, screenShake })}
              />
            </section>
            <section className="settings__group">
              <h3>Надписи на поле</h3>
              <Choice
                label="Подсказки клавиш"
                value={settings.hud.keyHints}
                options={SHOWN}
                onChange={(keyHints) => setHud({ keyHints })}
              />
              <Choice
                label="Очки и комбо"
                note="слева сверху; в дзене — и уровень"
                value={settings.hud.score}
                options={SHOWN}
                onChange={(score) => setHud({ score })}
              />
              <Choice
                label="Время, фигуры, матчи"
                value={settings.hud.stats}
                options={SHOWN}
                onChange={(stats) => setHud({ stats })}
              />
              <Slider
                label="Непрозрачность надписей"
                value={Math.round(settings.hud.opacity * 100)}
                min={10}
                max={100}
                step={5}
                unit="%"
                onChange={(percent) => setHud({ opacity: percent / 100 })}
              />
            </section>
            <div className="settings__footer">
              <button
                type="button"
                className="button"
                onClick={() =>
                  onChange({
                    ...settings,
                    hud: { ...defaultHudOptions },
                    turnMs: defaultTurnMs,
                    screenShake: true,
                  })
                }
              >
                Сбросить интерфейс
              </button>
            </div>
          </div>
        )}

        <p className={`settings__saved ${stored ? '' : 'settings__saved--off'}`}>
          {stored
            ? 'Настройки сохраняются в этом браузере сразу и остаются после закрытия вкладки.'
            : 'Браузер не даёт сохранить настройки (приватный режим или запрет хранилища): после закрытия вкладки они сбросятся.'}
        </p>
      </div>
    </div>
  );
}

function Choice<T extends string | number | boolean>({
  label,
  note,
  value,
  options,
  onChange,
}: {
  label: string;
  /** A line of small print, or a little picture, under the label. */
  note?: React.ReactNode;
  value: T;
  options: readonly (readonly [T, string])[];
  onChange: (value: T) => void;
}) {
  return (
    <div className="choice">
      <span className="choice__label">
        {label}
        {note && <small>{note}</small>}
      </span>
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
