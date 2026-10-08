import { useEffect, useRef, useState } from 'react';
import { COLOUR_NAMES } from '../render/theme';
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
import { defaultSettings, type Palettes, type Settings, type ExplosionStyle } from '../services/storage';
import { Button, Chip, Choice, Screen, Slider, Toggle } from './ui';
import { useScreenKeys } from './nav';
import { useTouchControls } from '../input/touch';
import { DEFAULT_PADS, PAD_SLOTS, SLOT_LABELS } from '../input/pads';

type Tab = 'controls' | 'colours' | 'effects' | 'interface';

const TABS: readonly (readonly [Tab, string])[] = [
  ['controls', 'Управление'],
  ['colours', 'Цвета'],
  ['effects', 'Эффекты'],
  ['interface', 'Интерфейс'],
];

const GROUPS: readonly ActionGroup[] = ['piece', 'glass', 'game'];

interface Props {
  settings: Settings;
  /** False when the browser refuses to keep the settings. */
  stored: boolean;
  /** Shown over a game rather than as a screen of its own. */
  overlay?: boolean;
  /** False while another layer takes the keyboard. */
  active: boolean;
  onChange: (next: Settings) => void;
  onBack: () => void;
}

const newId = (): string => `custom-${Date.now().toString(36)}${Math.random().toString(36).slice(2, 5)}`;

export function SettingsScreen({ settings, stored, overlay, active, onChange, onBack }: Props) {
  const touch = useTouchControls();
  const rootRef = useRef<HTMLElement>(null);
  const [tab, setTab] = useState<Tab>('controls');
  /** The key slot waiting for its new key. */
  const [capture, setCapture] = useState<{ action: Action; slot: number } | null>(null);
  useScreenKeys(rootRef, active && capture === null, onBack);

  // While a slot waits, the very next key is its new key.
  useEffect(() => {
    if (!capture || touch) return;
    const onKey = (event: KeyboardEvent) => {
      event.preventDefault();
      event.stopPropagation();
      if (event.code === 'Escape') {
        setCapture(null);
      } else if (event.code === 'Backspace' || event.code === 'Delete') {
        onChange({ ...settings, bindings: unbindKey(settings.bindings, capture.action, capture.slot) });
        setCapture(null);
      } else if (event.code) {
        onChange({ ...settings, bindings: bindKey(settings.bindings, capture.action, capture.slot, event.code) });
        setCapture(null);
      }
    };
    window.addEventListener('keydown', onKey, true);
    return () => window.removeEventListener('keydown', onKey, true);
  }, [capture, settings, onChange, touch]);

  const defaults = defaultSettings();
  let body: React.ReactNode;
  switch (tab) {
    case 'controls':
      body = (
        <>
          {touch ? (
            <>
              <p className="hint">
                Левая крестовина управляет фигурой, правая — поворотами и стаканами. Можно нажимать обе одновременно.
              </p>
              {(['left', 'right'] as const).map((side) => (
                <section className="group" key={side}>
                  <h3>{side === 'left' ? 'Левая крестовина' : 'Правая крестовина'}</h3>
                  {PAD_SLOTS.map((slot) => (
                    <label className="row" key={slot}>
                      <span className="row__label">{SLOT_LABELS[slot]}</span>
                      <select
                        className="pad-select"
                        value={settings.pads[side][slot]}
                        onChange={(event) =>
                          onChange({
                            ...settings,
                            pads: { ...settings.pads, [side]: { ...settings.pads[side], [slot]: event.target.value } },
                          })
                        }
                      >
                        <option value="none">Не назначено</option>
                        {ACTIONS.map((action) => (
                          <option key={action.id} value={action.id}>
                            {action.label}
                          </option>
                        ))}
                      </select>
                    </label>
                  ))}
                </section>
              ))}
            </>
          ) : (
            <>
              <p className="hint">
                Нажмите на действие, затем на новую клавишу. Esc — отмена, Backspace — очистить. Клавиша, занятая другим
                действием, переходит к новому. Клавиша поворота против часовой и мягкий сброс по умолчанию не назначены.
              </p>
              {GROUPS.map((group) => (
                <section className="group" key={group}>
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
                          // The second slot only shows once the first is taken.
                          if (code === undefined && slot > settings.bindings[action.id].length) return null;
                          const waiting = capture?.action === action.id && capture.slot === slot;
                          return (
                            <button
                              type="button"
                              key={slot}
                              data-nav
                              className={`bind__key ${waiting ? 'is-waiting' : ''} ${code ? '' : 'is-empty'}`}
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
            </>
          )}
          <section className="group">
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
          <div className="form__start">
            <Button
              ghost
              onClick={() =>
                onChange({
                  ...settings,
                  ...(touch
                    ? { pads: { left: { ...DEFAULT_PADS.left }, right: { ...DEFAULT_PADS.right } } }
                    : { bindings: cloneBindings(defaultBindings) }),
                  handling: { ...defaultHandling },
                })
              }
            >
              Сбросить управление
            </Button>
          </div>
        </>
      );
      break;
    case 'colours':
      body = <ColoursTab settings={settings} onChange={onChange} />;
      break;
    case 'effects':
      body = (
        <>
          <section className="group">
            <h3>Взрывы</h3>
            <Choice<ExplosionStyle>
              label="Анимация взрыва"
              note="как взрываются линии после исчезновения фигур"
              value={settings.effects.explosion}
              options={[
                ['varied', 'Разная для каждого типа'],
                ['unified', 'Одна для всех'],
              ]}
              onChange={(explosion) => onChange({ ...settings, effects: { ...settings.effects, explosion } })}
            />
            <p className="hint">
              Разная: тройки, четвёрки и пятёрки взрываются по-своему, шесть и больше — с золотой вспышкой.
              Одновременные линии добавляют волны, три линии сразу — вспышку поля. Одна: все взрывы одинаковые.
            </p>
          </section>
          <section className="group">
            <h3>Поле</h3>
            <Toggle
              label="Толчки и тряска поля"
              value={settings.effects.screenShake}
              onChange={(screenShake) => onChange({ ...settings, effects: { ...settings.effects, screenShake } })}
            />
            <Slider
              label="Поворот поля"
              value={settings.effects.turnMs}
              min={0}
              max={600}
              step={20}
              unit="мс"
              note={settings.effects.turnMs === 0 ? 'мгновенно' : undefined}
              onChange={(turnMs) => onChange({ ...settings, effects: { ...settings.effects, turnMs } })}
            />
          </section>
        </>
      );
      break;
    case 'interface':
      body = (
        <>
          <section className="group">
            <h3>Надписи на поле</h3>
            <Toggle
              label={touch ? 'Подписи экранных кнопок' : 'Подсказки клавиш'}
              value={settings.hud.keyHints}
              on="показывать"
              off="скрыть"
              onChange={(keyHints) => onChange({ ...settings, hud: { ...settings.hud, keyHints } })}
            />
            <Toggle
              label="Очки, уровень и комбо"
              value={settings.hud.score}
              on="показывать"
              off="скрыть"
              onChange={(score) => onChange({ ...settings, hud: { ...settings.hud, score } })}
            />
            <Toggle
              label="Время, фигуры, матчи"
              value={settings.hud.stats}
              on="показывать"
              off="скрыть"
              onChange={(stats) => onChange({ ...settings, hud: { ...settings.hud, stats } })}
            />
            <Slider
              label="Непрозрачность надписей"
              value={Math.round(settings.hud.opacity * 100)}
              min={10}
              max={100}
              step={5}
              unit="%"
              onChange={(percent) => onChange({ ...settings, hud: { ...settings.hud, opacity: percent / 100 } })}
            />
          </section>
          <div className="form__start">
            <Button ghost onClick={() => onChange({ ...settings, hud: defaults.hud, effects: defaults.effects })}>
              Сбросить интерфейс
            </Button>
          </div>
        </>
      );
      break;
  }

  return (
    <Screen
      rootRef={rootRef}
      className={overlay ? 'screen--overlay' : ''}
      kicker={overlay ? 'В игре' : 'Меню'}
      title="Настройки"
      onBack={onBack}
      footer={
        stored ? (
          <span>Всё сохраняется на этом устройстве сразу</span>
        ) : (
          <span className="warn">Браузер не даёт сохранить настройки: после перезагрузки они сбросятся</span>
        )
      }
    >
      <nav className="tabs" aria-label="Разделы настроек">
        {TABS.map(([id, title]) => (
          <Chip key={id} active={tab === id} onClick={() => setTab(id)}>
            {title}
          </Chip>
        ))}
      </nav>
      {body}
    </Screen>
  );
}

/** The palettes: pick one, copy it, delete a copy, and change its colours. A
 * built-in set is copied before it is changed. */
function ColoursTab({ settings, onChange }: { settings: Settings; onChange: (next: Settings) => void }) {
  const palettes: Palettes = settings.palettes;
  const active = palettes.sets.find((set) => set.id === palettes.active) ?? palettes.sets[0];

  const copy = () => {
    const set = {
      id: newId(),
      name: `Мой набор ${palettes.sets.length - 2}`,
      colours: [...active.colours],
      builtin: false,
    };
    onChange({ ...settings, palettes: { active: set.id, sets: [...palettes.sets, set] } });
  };

  const remove = () => {
    if (active.builtin) return;
    onChange({
      ...settings,
      palettes: { active: 'classic', sets: palettes.sets.filter((set) => set.id !== active.id) },
    });
  };

  const edit = (slot: number, hex: string) => {
    if (active.builtin) {
      const set = {
        id: newId(),
        name: `${active.name} · мой`.slice(0, 24),
        colours: active.colours.map((colour, i) => (i === slot ? hex : colour)),
        builtin: false,
      };
      onChange({ ...settings, palettes: { active: set.id, sets: [...palettes.sets, set] } });
      return;
    }
    const sets = palettes.sets.map((set) =>
      set.id === active.id ? { ...set, colours: set.colours.map((colour, i) => (i === slot ? hex : colour)) } : set,
    );
    onChange({ ...settings, palettes: { ...palettes, sets } });
  };

  return (
    <>
      <section className="group">
        <h3>Наборы</h3>
        <div className="chips">
          {palettes.sets.map((set) => (
            <Chip
              key={set.id}
              active={set.id === active.id}
              onClick={() => onChange({ ...settings, palettes: { ...palettes, active: set.id } })}
            >
              {set.name}
            </Chip>
          ))}
        </div>
        <div className="chips chips--spaced">
          <Button onClick={copy}>Новый набор из текущего</Button>
          {!active.builtin && (
            <Button ghost onClick={remove}>
              Удалить набор
            </Button>
          )}
        </div>
      </section>

      <section className="group">
        <h3>Цвета фигур · {active.name}</h3>
        <p className="hint">Стандартные наборы не меняются: изменяя цвет, вы получаете свою копию.</p>
        <div className="swatches">
          {COLOUR_NAMES.map((name, slot) => (
            <label className="swatch" key={slot}>
              <input
                type="color"
                value={active.colours[slot]}
                aria-label={name}
                onChange={(event) => edit(slot, event.target.value)}
              />
              <span className="swatch__text">
                <span className="swatch__name">{name}</span>
                <code>{active.colours[slot].toUpperCase()}</code>
              </span>
            </label>
          ))}
        </div>
      </section>

      <section className="group">
        <h3>Так это выглядит</h3>
        <div className="preview">
          {active.colours.map((colour, i) => (
            <div key={i} className="preview__block" style={{ background: colour }} />
          ))}
        </div>
      </section>
    </>
  );
}
