import type { AudioOptions } from './storage';

/** Tracks bundled with the web build. The first two are the player's tracks;
 * the remaining files are CC0 loopable ambience in assets/music/downloaded. */
export const MUSIC_TRACKS = [
  'music/deep-focus.m4a',
  'music/deep-focus-1.m4a',
  'music/ambient-relaxing-loop.mp3',
  'music/project-utopia-loop.mp3',
  'music/chill-loopable.mp3',
  'music/insistent-background-loop.mp3',
  'music/claimed-by-the-void-loop.mp3',
] as const;

const CROSSFADE_MS = 3000;

/**
 * Two HTML audio elements are used because changing an element's volume while
 * it is playing cannot overlap the next source. A small timer ramps one down
 * and the other up during the last three seconds of every track.
 */
export class MusicPlayer {
  private readonly players = [new Audio(), new Audio()];
  private options: AudioOptions = { music: true, musicVolume: 0.6 };
  private active = 0;
  private track = 0;
  private timer: number | undefined;
  private started = false;
  private transitioning = false;
  private fadeStarted = 0;
  private sourceBase = import.meta.env.BASE_URL;

  constructor() {
    for (const player of this.players) {
      player.preload = 'auto';
      player.addEventListener('ended', () => this.advanceWithoutFade(player));
    }
  }

  setSettings(options: AudioOptions): void {
    const wasEnabled = this.options.music;
    this.options = options;
    for (const player of this.players) player.volume = options.music ? options.musicVolume : 0;
    if (!options.music) {
      this.stop();
    } else if (!wasEnabled) {
      this.ensurePlaying();
    }
  }

  /** Call from a pointer/key gesture so browsers that block autoplay can start. */
  ensurePlaying(): void {
    if (!this.options.music || this.started) return;
    void this.start();
  }

  async start(): Promise<void> {
    if (!this.options.music || this.started) return;
    this.started = true;
    const player = this.players[this.active];
    player.src = this.url(MUSIC_TRACKS[this.track]);
    player.currentTime = 0;
    player.volume = this.options.musicVolume;
    try {
      await player.play();
      this.timer ??= window.setInterval(() => void this.tick(), 80);
    } catch {
      // Autoplay policies reject the promise until the next user gesture.
      this.started = false;
    }
  }

  stop(): void {
    this.started = false;
    this.transitioning = false;
    if (this.timer !== undefined) window.clearInterval(this.timer);
    this.timer = undefined;
    for (const player of this.players) {
      player.pause();
      player.currentTime = 0;
    }
  }

  dispose(): void {
    this.stop();
    for (const player of this.players) {
      player.removeAttribute('src');
      player.load();
    }
  }

  private url(track: string): string {
    return `${this.sourceBase}${track}`;
  }

  private async tick(): Promise<void> {
    if (!this.started || this.transitioning) return;
    const player = this.players[this.active];
    if (!Number.isFinite(player.duration) || player.duration <= 0) return;
    if (player.duration - player.currentTime <= CROSSFADE_MS / 1000) await this.beginFade();
  }

  private async beginFade(): Promise<void> {
    if (this.transitioning || !this.started) return;
    this.transitioning = true;
    this.fadeStarted = performance.now();
    const next = 1 - this.active;
    this.track = (this.track + 1) % MUSIC_TRACKS.length;
    const player = this.players[next];
    player.pause();
    player.src = this.url(MUSIC_TRACKS[this.track]);
    player.currentTime = 0;
    player.volume = 0;
    try {
      await player.play();
      this.fade();
    } catch {
      this.transitioning = false;
    }
  }

  private fade(): void {
    if (!this.transitioning) return;
    const progress = Math.min(1, (performance.now() - this.fadeStarted) / CROSSFADE_MS);
    this.players[this.active].volume = this.options.musicVolume * (1 - progress);
    this.players[1 - this.active].volume = this.options.musicVolume * progress;
    if (progress < 1) {
      window.requestAnimationFrame(() => this.fade());
      return;
    }
    this.players[this.active].pause();
    this.players[this.active].currentTime = 0;
    this.active = 1 - this.active;
    this.transitioning = false;
  }

  private advanceWithoutFade(player: HTMLAudioElement): void {
    if (!this.started || this.transitioning || player !== this.players[this.active]) return;
    void this.beginFade();
  }
}
