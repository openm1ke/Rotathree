export type KeyValue = Pick<Storage, 'getItem' | 'setItem'>;

let platformStorage: KeyValue | undefined;

/** Installed before React mounts, after the platform has hydrated saves. */
export function installStorage(storage: KeyValue | undefined): void {
  platformStorage = storage;
}

export function getPlatformStorage(): KeyValue | undefined {
  return platformStorage;
}
