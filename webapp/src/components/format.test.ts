import { expect, it } from 'vitest';
import { formatCells, formatColours, formatGlasses, formatNumber, formatPoints, formatTimes } from './format';

it('Russian quantities handle the teens, endings and grouped numbers', () => {
  const cases = new Map([
    [0, 'очков'], [1, 'очко'], [2, 'очка'], [4, 'очка'], [5, 'очков'],
    [11, 'очков'], [12, 'очков'], [14, 'очков'], [20, 'очков'],
    [21, 'очко'], [22, 'очка'], [25, 'очков'], [101, 'очко'],
    [111, 'очков'], [1001, 'очко'], [1012, 'очков'],
  ]);
  for (const [value, noun] of cases) expect(formatPoints(value)).toBe(`${formatNumber(value)} ${noun}`);
  expect(formatPoints(-22)).toBe(`${formatNumber(-22)} очка`);
  expect(formatPoints(1001)).toBe('1 001 очко');
});

it('UI quantities use the noun appropriate to their number', () => {
  expect(formatGlasses(1)).toBe('1 стакан');
  expect(formatGlasses(3)).toBe('3 стакана');
  expect(formatGlasses(5)).toBe('5 стаканов');
  expect(formatColours(3)).toBe('3 цвета');
  expect(formatColours(5)).toBe('5 цветов');
  expect(formatCells(4)).toBe('4 клетки');
  expect(formatCells(12)).toBe('12 клеток');
  expect(formatTimes(1)).toBe('1 раз');
  expect(formatTimes(2)).toBe('2 раза');
  expect(formatTimes(11)).toBe('11 раз');
  expect(formatTimes(22)).toBe('22 раза');
});
