import { useRef } from 'react';
import { CUSTOM_LIMITS, DEFAULT_CUSTOM, type CustomSetup } from '../game/modes';
import { Button, Choice, Screen, Toggle } from './ui';
import { useScreenKeys } from './nav';

interface Props {
  setup: CustomSetup;
  colours: string[];
  onChange: (setup: CustomSetup) => void;
  onStart: () => void;
  onBack: () => void;
  active: boolean;
}

const range = (from: number, to: number): number[] => Array.from({ length: to - from + 1 }, (_, i) => from + i);

/** Everything the custom mode is made of, set before a game starts. These
 * values are not used by the campaign or by Insane. */
export function CustomScreen({ setup, colours, onChange, onStart, onBack, active }: Props) {
  const rootRef = useRef<HTMLElement>(null);
  useScreenKeys(rootRef, active, onBack);
  const set = (patch: Partial<CustomSetup>) => onChange({ ...setup, ...patch });
  const glasses = 1 + setup.extraGlasses;
  const percent = Math.round(setup.speedUpStep * 100);

  return (
    <Screen
      rootRef={rootRef}
      kicker="Режим"
      title="Кастом"
      onBack={onBack}
      actions={
        <Button ghost onClick={() => onChange({ ...DEFAULT_CUSTOM })}>
          Сбросить
        </Button>
      }
      footer={<span>Настройки этого режима действуют только в нём</span>}
    >
      <div className="form">
        <Choice
          label="Дополнительных стаканов"
          note="кроме стакана, с которого начинается игра"
          value={setup.extraGlasses}
          options={range(CUSTOM_LIMITS.extraGlasses[0], CUSTOM_LIMITS.extraGlasses[1]).map((n) => [n, String(n)] as const)}
          onChange={(extraGlasses) => set({ extraGlasses })}
        />
        <Choice
          label="Цветов"
          note={
            <span className="dots">
              {colours.slice(0, setup.colours).map((colour, i) => (
                <i key={i} style={{ background: colour }} />
              ))}
            </span>
          }
          value={setup.colours}
          options={range(CUSTOM_LIMITS.colours[0], CUSTOM_LIMITS.colours[1]).map((n) => [n, String(n)] as const)}
          onChange={(colours) => set({ colours })}
        />
        <Choice
          label="Длина рукава, клеток"
          value={setup.armLength}
          options={[6, 8, 9, 10].map((n) => [n, String(n)] as const)}
          onChange={(armLength) => set({ armLength })}
        />
        <Choice
          label="Старт: активный стакан"
          note="секунд на шаг фигуры"
          value={setup.activeStep}
          options={[
            [0.5, '0.5'],
            [0.75, '0.75'],
            [1, '1'],
            [1.5, '1.5'],
          ]}
          onChange={(activeStep) => set({ activeStep })}
        />
        <Choice
          label="Старт: остальные стаканы"
          note="секунд на шаг фигуры"
          value={setup.inactiveStep}
          options={[
            [1.5, '1.5'],
            [2, '2'],
            [3, '3'],
            [4, '4'],
            [6, '6'],
          ]}
          onChange={(inactiveStep) => set({ inactiveStep })}
        />
        <Toggle label="Ускорять падение" value={setup.speedUp} onChange={(speedUp) => set({ speedUp })} />
        {setup.speedUp && (
          <>
            <Choice
              label="Шаг ускорения"
              note="на сколько быстрее каждый раз"
              value={setup.speedUpStep}
              options={[
                [0.05, '5%'],
                [0.1, '10%'],
                [0.15, '15%'],
                [0.2, '20%'],
              ]}
              onChange={(speedUpStep) => set({ speedUpStep })}
            />
            <Choice
              label="Ускорять каждые"
              note="очков"
              value={setup.speedUpEvery}
              options={[
                [1000, '1000'],
                [2000, '2000'],
                [3000, '3000'],
              ]}
              onChange={(speedUpEvery) => set({ speedUpEvery })}
            />
          </>
        )}
        <Choice
          label="После хлопка падает"
          value={setup.gravityScope}
          options={[
            ['wholeGlass', 'всё без опоры'],
            ['aboveCleared', 'только над дырой'],
          ]}
          onChange={(gravityScope) => set({ gravityScope })}
        />
      </div>

      <div className="summary">
        <strong>
          {glasses} {glasses === 1 ? 'стакан' : 'стакана'} · {setup.colours} цв. · рукав {setup.armLength}
        </strong>
        <span>{setup.speedUp ? `ускорение на ${percent}% каждые ${setup.speedUpEvery} очков` : 'скорость не меняется'}</span>
      </div>
      <div className="form__start">
        <Button primary autoFocus onClick={onStart}>
          Начать
        </Button>
      </div>
    </Screen>
  );
}
