type Listener = (value: boolean) => void;

let hidden = false;
let muted = false;
const visibilityListeners = new Set<Listener>();
const muteListeners = new Set<Listener>();

/** The platform has the game covered: a full-screen ad, its own overlay or
 * another tab. The game stops its clock and its music, as for a hidden page. */
export const isPlatformHidden = () => hidden;

export function setPlatformHidden(value: boolean): void {
  if (hidden === value) return;
  hidden = value;
  for (const listener of visibilityListeners) listener(value);
}

export function subscribeVisibility(listener: Listener): () => void {
  visibilityListeners.add(listener);
  return () => { visibilityListeners.delete(listener); };
}

/** The platform asks for silence while the game itself goes on. */
export const isPlatformMuted = () => muted;

export function setPlatformMuted(value: boolean): void {
  if (muted === value) return;
  muted = value;
  for (const listener of muteListeners) listener(value);
}

export function subscribeMute(listener: Listener): () => void {
  muteListeners.add(listener);
  return () => { muteListeners.delete(listener); };
}
