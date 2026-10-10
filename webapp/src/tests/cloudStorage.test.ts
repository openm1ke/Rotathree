import { CloudStorage, CHUNK_SIZE, type CloudTransport } from '../platform/cloudStorage';
import { afterEach, expect, it, vi } from 'vitest';

function fixture() {
  const data: Record<string, string> = {};
  const localData: Record<string, string> = {};
  const local = { getItem: (key: string) => localData[key] ?? null, setItem: (key: string, value: string) => { localData[key] = value; } };
  const transport: CloudTransport = {
    get: vi.fn(async (keys: string[]) => Object.fromEntries(keys.map((key) => [key, data[key] ?? '']))),
    set: vi.fn(async (key: string, value: string) => { data[key] = value; }),
  };
  const create = (cache = 'account-1', enabled = true) => new CloudStorage(transport, ['run', 'settings'], local, cache, enabled);
  return { data, localData, local, transport, create };
}

afterEach(() => vi.useRealTimers());

it('round trips large Unicode saves and commits the manifest after every chunk', async () => {
  const { create, transport } = fixture();
  const store = create();
  await store.hydrate();
  const value = 'Кошмар 🎮'.repeat(1400);
  store.setItem('run', value);
  store.setItem('settings', '{"volume":0.1}');
  await store.flush();
  const writes = vi.mocked(transport.set).mock.calls;
  expect(writes.length).toBeGreaterThan(10);
  expect(writes.at(-1)?.[0]).toBe('rt_v1_manifest');
  for (const [key, value] of writes) if (key !== 'rt_v1_manifest') expect(value.length).toBeLessThanOrEqual(CHUNK_SIZE);
  const restored = create('another-device');
  await restored.hydrate();
  expect(restored.getItem('run')).toBe(value);
  expect(restored.getItem('settings')).toBe('{"volume":0.1}');
  expect(vi.mocked(transport.get).mock.calls.every(([keys]) => keys.length <= 10)).toBe(true);
});

it('keeps the previous complete save when a chunk write fails, then retries', async () => {
  const { create, transport, data } = fixture();
  const store = create();
  store.setItem('run', 'old');
  await store.flush();
  const manifest = data.rt_v1_manifest;
  vi.mocked(transport.set).mockRejectedValueOnce(new Error('offline'));
  store.setItem('run', 'new');
  await expect(store.flush()).rejects.toThrow('offline');
  expect(store.getStatus()).toBe('error');
  expect(data.rt_v1_manifest).toBe(manifest);
  const restored = create('another-device');
  await restored.hydrate();
  expect(restored.getItem('run')).toBe('old');
  await store.flush();
  await restored.hydrate();
  expect(restored.getItem('run')).toBe('new');
  expect(store.getStatus()).toBe('saved');
});

it('recovers unconfirmed local progress when the cloud has not changed', async () => {
  const { create, transport } = fixture();
  const store = create();
  store.setItem('run', 'confirmed');
  await store.flush();
  store.setItem('run', 'unconfirmed');
  vi.mocked(transport.set).mockRejectedValueOnce(new Error('offline'));
  await expect(store.flush()).rejects.toThrow();
  const recovered = create();
  await recovered.hydrate();
  expect(recovered.getItem('run')).toBe('unconfirmed');
  const other = create('another-device');
  await other.hydrate();
  expect(other.getItem('run')).toBe('unconfirmed');
});

it('requires an explicit choice when another device and the backup both changed', async () => {
  const { create, transport, data, localData } = fixture();
  const store = create();
  store.setItem('run', 'original');
  await store.flush();
  store.setItem('run', 'device-one');
  vi.mocked(transport.set).mockRejectedValueOnce(new Error('offline'));
  await expect(store.flush()).rejects.toThrow();
  const backup = localData['account-1'];
  const other = create('device-two');
  await other.hydrate();
  other.setItem('run', 'device-two');
  await other.flush();
  const manifest = data.rt_v1_manifest;
  await expect(create().hydrate()).rejects.toThrow('changed independently');
  expect(data.rt_v1_manifest).toBe(manifest);
  const preferCloud = create();
  await preferCloud.hydrate('cloud');
  expect(preferCloud.getItem('run')).toBe('device-two');
  localData['account-1'] = backup;
  const preferDevice = create();
  await preferDevice.hydrate('backup');
  expect(preferDevice.getItem('run')).toBe('device-one');
  await other.hydrate();
  expect(other.getItem('run')).toBe('device-one');
});

it('serializes an update that arrives while a save is in flight', async () => {
  const { create, transport } = fixture();
  const store = create();
  const data: Record<string, string> = {};
  transport.get = async (keys) => Object.fromEntries(keys.map((key) => [key, data[key] ?? '']));
  let first = true;
  transport.set = async (key, value) => {
    if (first) { first = false; store.setItem('run', 'newer'); }
    data[key] = value;
  };
  store.setItem('run', 'first');
  const pending = store.flush();
  expect(store.flush()).toBe(pending);
  await pending;
  const restored = create();
  await restored.hydrate();
  expect(restored.getItem('run')).toBe('newer');
});

it('does not overwrite a damaged or unavailable cloud save with defaults', async () => {
  const { create, data, transport } = fixture();
  data.rt_v1_manifest = '{"version":1,"bank":0,"count":1,"checksum":"wrong"}';
  data.rt_v1_0_0 = 'AAAA';
  await expect(create().hydrate()).rejects.toThrow('Damaged cloud save');
  expect(transport.set).not.toHaveBeenCalled();
  vi.mocked(transport.get).mockRejectedValueOnce(new Error('offline'));
  await expect(create().hydrate()).rejects.toThrow('offline');
  expect(transport.set).not.toHaveBeenCalled();
});

it('isolates accounts and only uses local backups in explicit local mode', async () => {
  const { create, transport } = fixture();
  const store = create('account-1', false);
  await store.hydrate();
  store.setItem('run', 'local');
  await store.flush();
  const same = create('account-1', false);
  await same.hydrate();
  expect(same.getItem('run')).toBe('local');
  const other = create('account-2', false);
  await other.hydrate();
  expect(other.getItem('run')).toBeNull();
  expect(transport.get).not.toHaveBeenCalled();
  expect(transport.set).not.toHaveBeenCalled();
  const cloud = create('account-new');
  await cloud.hydrate();
  expect(cloud.getItem('run')).toBeNull();
});

it('reports failure consistently when local-only storage cannot persist', async () => {
  const { transport } = fixture();
  const store = new CloudStorage(transport, ['run'], { getItem: () => null, setItem: () => { throw new Error('blocked'); } }, 'account', false);
  await store.hydrate();
  expect(() => store.setItem('run', 'new')).toThrow('Local backup is unavailable');
  expect(() => store.setItem('run', 'new')).toThrow('Local backup is unavailable');
  expect(store.getItem('run')).toBeNull();
});

it('batches continuous checkpoints without postponing cloud writes indefinitely', async () => {
  vi.useFakeTimers();
  const { create, transport } = fixture();
  const store = create();
  store.setItem('run', '1');
  await vi.advanceTimersByTimeAsync(4000);
  store.setItem('run', '2');
  await vi.advanceTimersByTimeAsync(1000);
  expect(transport.set).toHaveBeenCalled();
  const restored = create();
  await restored.hydrate();
  expect(restored.getItem('run')).toBe('2');
});
