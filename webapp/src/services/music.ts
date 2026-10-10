import { defaultSettings, type AudioOptions } from './storage';
import { VK_BUILD } from '../platform/runtime';

/** These playback copies have matched loudness and baked-in 2s fades at both
 * ends. Keep the originals and licensing records in assets/music. */
export const MUSIC_TRACKS = [
  ...(VK_BUILD ? [] : ['music/deep-focus.m4a', 'music/deep-focus-1.m4a']),
  'music/ambient-relaxing-loop.m4a',
  'music/project-utopia-loop.m4a',
  'music/chill-loopable.m4a',
  'music/insistent-background-loop.m4a',
  'music/claimed-by-the-void-loop.m4a',
] as const;

/** One player advances only after a track finishes, so the faded ends never
 * overlap or add their loudness. Web Audio also controls volume on iOS Safari,
 * where setting HTMLMediaElement.volume alone has no effect. */
export class MusicPlayer {
  private readonly player = new Audio();
  private options: AudioOptions = defaultSettings().audio;
  private context: AudioContext | undefined;
  private gain: GainNode | undefined;
  private track = 0;
  private loaded = false;
  private wanted = false;
  private disposed = false;
  private pending: Promise<void> | undefined;
  private failures = 0;

  constructor() {
    this.player.preload = 'auto';
    this.player.addEventListener('ended', this.onEnded);
    this.player.addEventListener('error', this.onError);
    this.applyVolume();
  }

  setSettings(options: AudioOptions): void {
    const wasEnabled = this.options.music;
    this.options = { ...options, musicVolume: Math.max(0, Math.min(1, options.musicVolume)) };
    this.applyVolume();
    if (!options.music) this.stop();
    else if (!wasEnabled) this.ensurePlaying();
  }

  /** Called from a pointer/key gesture to unlock browser audio. */
  ensurePlaying(): void {
    if (!this.options.music || this.disposed) return;
    if (!this.player.paused && this.wanted) return;
    void this.start();
  }

  async start(): Promise<void> {
    if (!this.options.music || this.disposed) return;
    this.wanted = true;
    if (this.pending) return this.pending;
    this.pending = this.playCurrent();
    try {
      await this.pending;
    } finally {
      this.pending = undefined;
    }
  }

  stop(): void {
    this.wanted = false;
    this.player.pause();
  }

  dispose(): void {
    if (this.disposed) return;
    this.disposed = true;
    this.stop();
    this.player.removeEventListener('ended', this.onEnded);
    this.player.removeEventListener('error', this.onError);
    this.player.removeAttribute('src');
    this.player.load();
    void this.context?.close().catch(() => {});
  }

  private applyVolume(): void {
    const volume = this.options.music ? this.options.musicVolume : 0;
    if (this.gain) this.gain.gain.value = volume;
    else this.player.volume = volume;
  }

  private createAudioGraph(): void {
    if (this.context || typeof AudioContext === 'undefined') return;
    const context = new AudioContext();
    const gain = context.createGain();
    context.createMediaElementSource(this.player).connect(gain);
    gain.connect(context.destination);
    this.context = context;
    this.gain = gain;
    this.applyVolume();
    this.player.volume = 1;
  }

  private async playCurrent(): Promise<void> {
    if (!this.loaded) {
      this.player.src = `${import.meta.env.BASE_URL}${MUSIC_TRACKS[this.track]}`;
      this.loaded = true;
    }
    try {
      this.createAudioGraph();
      if (this.context?.state === 'suspended') await this.context.resume();
      if (!this.wanted || this.disposed) return;
      await this.player.play();
      if (!this.wanted || this.disposed) this.player.pause();
    } catch {
      // A rejected autoplay attempt is retried on the next user gesture.
      // Media errors instead advance once this pending play has settled.
      if (!this.player.error) this.wanted = false;
    }
  }

  private advance(): void {
    if (!this.wanted || !this.options.music || this.disposed) return;
    this.track = (this.track + 1) % MUSIC_TRACKS.length;
    this.loaded = false;
    void this.start();
  }

  private onEnded = (): void => {
    this.failures = 0;
    this.advance();
  };

  private onError = (): void => {
    // Skip an unavailable file, but stop if the entire playlist is unavailable.
    if (++this.failures >= MUSIC_TRACKS.length) this.stop();
    else if (this.pending) void this.pending.then(() => this.advance());
    else this.advance();
  };
}
