/** A small seeded generator (mulberry32). Returns numbers in [0, 1). */
export function createRandom(seed?: number | null): () => number {
  let state = (seed ?? Math.floor(Math.random() * 0xffffffff)) >>> 0;
  return () => {
    state = (state + 0x6d2b79f5) >>> 0;
    let t = state;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
