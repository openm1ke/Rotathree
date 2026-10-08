export function record(raw: unknown): Record<string, unknown> {
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) throw new Error('Invalid game save');
  return raw as Record<string, unknown>;
}

export function number(raw: unknown, min = 0, max = 1e12): number {
  if (typeof raw !== 'number' || !Number.isFinite(raw) || raw < min || raw > max)
    throw new Error('Invalid saved number');
  return raw;
}

export function integer(raw: unknown, min = 0, max = 1e12): number {
  const value = number(raw, min, max);
  if (!Number.isInteger(value)) throw new Error('Invalid saved integer');
  return value;
}

export function list(raw: unknown, max = 1000): unknown[] {
  if (!Array.isArray(raw) || raw.length > max) throw new Error('Invalid saved list');
  return raw;
}
