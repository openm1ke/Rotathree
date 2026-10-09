import { useEffect, type RefObject } from 'react';

const NAV_ITEMS = 'button:not(:disabled):not([tabindex="-1"]), input[type="range"], input[type="checkbox"], input[type="color"]';

/** Keyboard use of the menus. Arrows and W/S move between the controls of the
 * screen, Enter and Space press them, Esc and Backspace go back. Inside a text
 * field the keys are left alone. */
export function useScreenKeys(root: RefObject<HTMLElement | null>, active: boolean, onBack: () => void): void {
  useEffect(() => {
    if (!active) return;
    const onKey = (event: KeyboardEvent) => {
      if (event.defaultPrevented) return;
      const target = event.target as HTMLElement | null;
      if (target?.closest('select, textarea')) return;
      if (target instanceof HTMLInputElement && (target.type === 'text' || target.type === 'color')) {
        if (event.code === 'Escape') target.blur();
        return;
      }
      if (event.code === 'Escape' || event.code === 'Backspace') {
        event.preventDefault();
        onBack();
        return;
      }
      const step = event.code === 'ArrowDown' || event.code === 'KeyS' ? 1 : event.code === 'ArrowUp' || event.code === 'KeyW' ? -1 : 0;
      if (step === 0) return;
      const items = [...(root.current?.querySelectorAll<HTMLElement>(NAV_ITEMS) ?? [])];
      if (items.length === 0) return;
      const at = items.indexOf(document.activeElement as HTMLElement);
      const next = at === -1 ? (step > 0 ? 0 : items.length - 1) : (at + step + items.length) % items.length;
      event.preventDefault();
      items[next].focus();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [root, active, onBack]);
}
