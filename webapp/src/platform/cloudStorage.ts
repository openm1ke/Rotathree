import type { KeyValue } from './storageBackend';

export interface CloudTransport {
  get(keys: string[]): Promise<Record<string, string>>;
  set(key: string, value: string): Promise<void>;
}
export type SyncStatus = 'saved' | 'pending' | 'error' | 'local';

// Conservative ASCII payloads. Verify current VK quotas during live testing.
export const CHUNK_SIZE = 1800;
const MAX_CHUNKS = 32;
const MANIFEST_KEY = 'rt_v1_manifest';
const chunkKey = (bank: number, index: number) => `rt_v1_${bank}_${index}`;
type Values = Record<string, string>;
export class LocalSaveConflict extends Error {}
interface Manifest { version: 1; bank: 0 | 1; count: number; checksum: string }

function checksum(text: string): string {
  let hash = 2166136261;
  for (let i = 0; i < text.length; i++) hash = Math.imul(hash ^ text.charCodeAt(i), 16777619);
  return (hash >>> 0).toString(16);
}

function encode(values: Values): string {
  let binary = '';
  for (const byte of new TextEncoder().encode(JSON.stringify(values))) binary += String.fromCharCode(byte);
  return btoa(binary);
}

function decode(text: string, allowed: readonly string[]): Values {
  const binary = atob(text);
  const raw: unknown = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(Uint8Array.from(binary, (c) => c.charCodeAt(0))));
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) throw new Error('Invalid cloud save');
  const values: Values = {};
  for (const key of allowed) {
    const value = (raw as Values)[key];
    if (value !== undefined && typeof value !== 'string') throw new Error('Invalid cloud value');
    if (value !== undefined) values[key] = value;
  }
  return values;
}

/** A synchronous mirror for the game, with serialized asynchronous cloud
 * writes. The active manifest switches only after every chunk is confirmed. */
export class CloudStorage implements KeyValue {
  private values: Values = {};
  private bank: 0 | 1 = 1;
  private revision = 0;
  private persisted = 0;
  private cloudBase = '';
  private timer: ReturnType<typeof setTimeout> | undefined;
  private pending: Promise<void> | undefined;
  private listeners = new Set<() => void>();
  status: SyncStatus = 'saved';

  constructor(
    private transport: CloudTransport,
    private allowed: readonly string[],
    private local: KeyValue | null,
    private cacheKey: string,
    private cloudEnabled = true,
  ) {}

  async hydrate(preference?: 'cloud' | 'backup'): Promise<void> {
    let cached: Values | undefined;
    try {
      const text = this.local?.getItem(this.cacheKey);
      if (text) cached = decode(text, [...this.allowed, '__rt_base', '__rt_pending']);
    } catch { /* A damaged local backup cannot replace a valid cloud save. */ }
    if (!this.cloudEnabled) {
      if (cached) this.values = this.pickValues(cached);
      this.cloudBase = cached?.__rt_base ?? '';
      this.status = 'local';
      return;
    }
    const response = await this.transport.get([MANIFEST_KEY]);
    const raw = response[MANIFEST_KEY];
    if (!raw) {
      await this.recoverBackup(cached, preference);
      this.backup();
      return;
    }
    const manifest = JSON.parse(raw) as Manifest;
    if (manifest.version !== 1 || ![0, 1].includes(manifest.bank) ||
      !Number.isInteger(manifest.count) || manifest.count < 1 || manifest.count > MAX_CHUNKS ||
      typeof manifest.checksum !== 'string') throw new Error('Invalid cloud manifest');
    const keys = Array.from({ length: manifest.count }, (_, i) => chunkKey(manifest.bank, i));
    const chunks: Record<string, string> = {};
    for (let offset = 0; offset < keys.length; offset += 10) {
      Object.assign(chunks, await this.transport.get(keys.slice(offset, offset + 10)));
    }
    if (keys.some((key) => !chunks[key] || chunks[key].length > CHUNK_SIZE)) throw new Error('Incomplete cloud save');
    const data = keys.map((key) => chunks[key]).join('');
    if (checksum(data) !== manifest.checksum) throw new Error('Damaged cloud save');
    this.values = decode(data, this.allowed);
    this.bank = manifest.bank;
    this.cloudBase = manifest.checksum;
    await this.recoverBackup(cached, preference);
    this.backup();
  }

  getItem(key: string): string | null {
    return this.values[key] ?? null;
  }

  setItem(key: string, value: string): void {
    if (!this.allowed.includes(key)) throw new Error('Unknown save key');
    if (this.values[key] === value) return;
    const previous = this.values[key];
    this.values[key] = value;
    this.revision++;
    const backedUp = this.backup();
    if (!this.cloudEnabled && !backedUp) {
      if (previous === undefined) delete this.values[key];
      else this.values[key] = previous;
      this.revision--;
      throw new Error('Local backup is unavailable');
    }
    if (!this.cloudEnabled) return;
    this.setStatus('pending');
    // Batch changing gameplay checkpoints; lifecycle events flush immediately.
    if (!this.timer) this.timer = setTimeout(() => { void this.flush().catch(() => {}); }, 5000);
  }

  subscribe = (listener: () => void): (() => void) => {
    this.listeners.add(listener);
    return () => { this.listeners.delete(listener); };
  };

  getStatus = (): SyncStatus => this.status;

  flush(): Promise<void> {
    clearTimeout(this.timer);
    this.timer = undefined;
    if (!this.cloudEnabled) return Promise.resolve();
    if (this.pending) return this.pending;
    this.pending = this.persist().finally(() => { this.pending = undefined; });
    return this.pending;
  }

  private async persist(): Promise<void> {
    try {
      while (this.persisted < this.revision) {
        const revision = this.revision;
        const data = encode(this.values);
        const count = Math.ceil(data.length / CHUNK_SIZE);
        if (count > MAX_CHUNKS) throw new Error('Cloud save exceeds configured capacity');
        const bank = this.bank === 0 ? 1 : 0;
        for (let i = 0; i < count; i++) {
          await this.transport.set(chunkKey(bank, i), data.slice(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE));
        }
        const manifest: Manifest = { version: 1, bank, count, checksum: checksum(data) };
        await this.transport.set(MANIFEST_KEY, JSON.stringify(manifest));
        this.bank = bank;
        this.cloudBase = manifest.checksum;
        this.persisted = revision;
        this.backup();
      }
      this.setStatus('saved');
    } catch (error) {
      this.setStatus('error');
      throw error;
    }
  }

  private backup(): boolean {
    try {
      if (!this.local) return false;
      this.local.setItem(this.cacheKey, encode({ ...this.values,
        __rt_base: this.cloudBase, __rt_pending: !this.cloudEnabled || this.persisted < this.revision ? '1' : '0' }));
      return true;
    } catch { return false; /* Cloud remains usable without localStorage. */ }
  }

  private pickValues(cached: Values): Values {
    return Object.fromEntries(this.allowed.filter((key) => cached[key] !== undefined).map((key) => [key, cached[key]]));
  }

  private async recoverBackup(cached: Values | undefined, preference?: 'cloud' | 'backup'): Promise<void> {
    if (cached?.__rt_pending !== '1' || preference === 'cloud') return;
    if (cached.__rt_base !== this.cloudBase && preference !== 'backup') throw new LocalSaveConflict('Local and cloud saves changed independently');
    this.values = this.pickValues(cached);
    this.revision++;
    await this.flush();
  }

  private setStatus(status: SyncStatus): void {
    this.status = status;
    for (const listener of this.listeners) listener();
  }
}
