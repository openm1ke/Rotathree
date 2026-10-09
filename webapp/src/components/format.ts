/** Durations as m:ss, or h:mm:ss from an hour on. */
export function formatDuration(seconds: number): string {
  const total = Math.floor(seconds);
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

export const formatNumber = (value: number): string => value.toLocaleString('ru-RU');

/** Russian cardinal forms depend on both the last digit and the last two. */
export function counted(value: number, one: string, few: string, many: string): string {
  const lastTwo = Math.abs(value) % 100, last = Math.abs(value) % 10;
  const noun = lastTwo >= 11 && lastTwo <= 14 ? many : last === 1 ? one : last >= 2 && last <= 4 ? few : many;
  return `${formatNumber(value)} ${noun}`;
}

export const formatPoints = (value: number) => counted(value, 'очко', 'очка', 'очков');
export const formatColours = (value: number) => counted(value, 'цвет', 'цвета', 'цветов');
export const formatGlasses = (value: number) => counted(value, 'стакан', 'стакана', 'стаканов');
export const formatCells = (value: number) => counted(value, 'клетка', 'клетки', 'клеток');
export const formatTimes = (value: number) => counted(value, 'раз', 'раза', 'раз');
