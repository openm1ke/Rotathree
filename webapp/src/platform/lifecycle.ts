type Listener = (hidden: boolean) => void;
let hidden = false;
const listeners = new Set<Listener>();

export const isPlatformHidden = () => hidden;

export function setPlatformHidden(value: boolean): void {
  if (hidden === value) return;
  hidden = value;
  for (const listener of listeners) listener(value);
}

export function subscribeVisibility(listener: Listener): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}
