import { useEffect } from 'react';
import type { Bindings } from '../input/bindings';
import type { GameMode } from './hudState';
import { Keys } from './Keycap';

interface Props {
  bindings: Bindings;
  /** True while the settings panel is on top and owns the keyboard. */
  blocked: boolean;
  onPlay: (mode: GameMode) => void;
  onOpenSettings: () => void;
}

export function MenuScreen({ bindings, blocked, onPlay, onOpenSettings }: Props) {
  useEffect(() => {
    if (blocked) return;
    const onKey = (event: KeyboardEvent) => {
      // On a focused button Enter already presses that button.
      if (event.target instanceof HTMLButtonElement) return;
      if (event.code === 'Enter' || event.code === 'NumpadEnter') onPlay('classic');
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [blocked, onPlay]);

  return (
    <main className="menu">
      <header className="menu__brand">
        <h1 className="logo">
          ROTA<span>THREE</span>
        </h1>
        <p className="menu__tagline">Четыре стакана. Один центр. Три в ряд.</p>
        <ul className="menu__rules">
          <li>В каждом стакане падает своя фигура — во всех одновременно.</li>
          <li>Поворачивайте поле: стакан сверху — ваш, в нём фигура шагает быстрее.</li>
          <li>Три и больше одного цвета в ряд лопаются, блоки сверху падают.</li>
          <li>Стакан, заполненный до края рукава, заканчивает игру.</li>
        </ul>
      </header>

      <nav className="menu__buttons">
        <button type="button" className="mega mega--play" onClick={() => onPlay('classic')} autoFocus>
          <span className="mega__badge">GO</span>
          <span className="mega__text">
            <span className="mega__title">Играть</span>
            <span className="mega__sub">Одиночная партия на выживание · Enter</span>
          </span>
        </button>
        <button type="button" className="mega mega--zen" onClick={() => onPlay('zen')}>
          <span className="mega__badge">ZEN</span>
          <span className="mega__text">
            <span className="mega__title">Дзен</span>
            <span className="mega__sub">Спокойная игра по уровням</span>
          </span>
        </button>
        <button type="button" className="mega mega--config" onClick={onOpenSettings}>
          <span className="mega__badge">CFG</span>
          <span className="mega__text">
            <span className="mega__title">Настройки</span>
            <span className="mega__sub">Клавиши, поле, интерфейс</span>
          </span>
        </button>
      </nav>

      <footer className="menu__keys">
        <span>
          <Keys codes={[...bindings.moveLeft.slice(0, 1), ...bindings.moveRight.slice(0, 1)]} /> движение
        </span>
        <span>
          <Keys codes={bindings.rotateCW.slice(0, 1)} /> поворот
        </span>
        <span>
          <Keys codes={bindings.hardDrop.slice(0, 1)} /> сброс
        </span>
        <span>
          <Keys codes={[...bindings.glassLeft.slice(0, 1), ...bindings.glassRight.slice(0, 1)]} /> стаканы
        </span>
      </footer>
    </main>
  );
}
