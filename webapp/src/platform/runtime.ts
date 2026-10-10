import type { CloudStorage } from './cloudStorage';

export const VK_BUILD = import.meta.env.VITE_PLATFORM === 'vk';
export let vkStorage: CloudStorage | undefined;
export function setVKStorage(storage: CloudStorage): void { vkStorage = storage; }

let mobile = false;
let locale: string | undefined;
export const platformLocale = () => locale;
export function setPlatformLocale(value: string): void { locale = value; }
export const platformNeedsTouch = () => mobile;
export function setPlatformMobile(value: boolean): void {
  if (mobile === value) return;
  mobile = value;
  window.dispatchEvent(new Event('resize'));
}
