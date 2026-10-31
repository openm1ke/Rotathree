import { defaultSettings, type AudioOptions } from './storage';

/** What the game makes a sound for. */
export type SoundGroup = 'ui' | 'move' | 'rotate' | 'turn' | 'land' | 'pop' | 'level' | 'over';

/** The take each group plays, from public/sfx; null keeps the group silent.
 * Every take there is, with its source, is in sfx-lab/ (see its README). */
const CHOSEN: Record<SoundGroup, string | null> = {
  ui: 'ui-blip',
  move: 'move-select',
  rotate: 'rotate-bloop',
  turn: 'turn-sweep-deep',
  land: 'land-soft',
  pop: 'pop-plop',
  level: 'level-up',
  over: 'over-digital',
};

/** Steps of a major scale: a chain of matches climbs like a melody. */
const COMBO_STEPS = [0, 2, 4, 5, 7, 9, 11, 12];

/** Short effects of play and of the interface. Browsers start audio only from
 * a gesture, so the files are decoded on the first one. */
export class SoundEffects {
  private options: AudioOptions = defaultSettings().audio;
  private context: AudioContext | undefined;
  private master: GainNode | undefined;
  private readonly buffers = new Map<SoundGroup, AudioBuffer>();
  private loading: Promise<void> | undefined;
  private silenced = false;
  private duckMusic: ((seconds: number) => void) | undefined;

  setSettings(options: AudioOptions): void {
    this.options = options;
    this.applyVolume();
  }

  /** A hidden page, a platform pause or mute, or an ad: silence, tails included. */
  setSilenced(silenced: boolean): void {
    this.silenced = silenced;
    this.applyVolume();
  }

  /** How the music steps aside while the victory jingle plays. */
  setDucker(duck: ((seconds: number) => void) | undefined): void {
    this.duckMusic = duck;
  }

  /** Called from a pointer or key gesture. */
  unlock(): void {
    if (!this.options.sounds) return;
    if (!this.context) {
      try {
        this.context = new AudioContext({ latencyHint: 'interactive' });
      } catch {
        return;
      }
      this.master = this.context.createGain();
      this.master.connect(this.context.destination);
      this.applyVolume();
    }
    if (this.context.state === 'suspended') void this.context.resume().catch(() => {});
    this.loading ??= this.load(this.context);
  }

  play(group: SoundGroup, rate = 1): void {
    const context = this.context;
    const buffer = this.buffers.get(group);
    if (!this.options.sounds || this.silenced || !context || !this.master || !buffer || context.state !== 'running') return;
    const source = context.createBufferSource();
    source.buffer = buffer;
    source.playbackRate.value = rate;
    source.connect(this.master);
    source.start();
    if (group === 'level') this.duckMusic?.(buffer.duration / rate);
  }

  /** The burst of a cleared match, `combo` steps into its chain. */
  pop(combo: number): void {
    const step = COMBO_STEPS[Math.min(Math.max(combo, 1), COMBO_STEPS.length) - 1];
    this.play('pop', 2 ** (step / 12));
  }

  private async load(context: AudioContext): Promise<void> {
    // On the dev server the comparison page (/sfx-lab/) can try other takes.
    let tried: Partial<Record<SoundGroup, string | null>> = {};
    if (import.meta.env.DEV) {
      try { tried = JSON.parse(localStorage.getItem('rotathree.dev.sfx') ?? '{}') as typeof tried; } catch { /* none */ }
    }
    await Promise.all((Object.keys(CHOSEN) as SoundGroup[]).map(async (group) => {
      const take = group in tried ? tried[group] : CHOSEN[group];
      if (!take) return;
      try {
        const from = group in tried ? 'sfx-lab/takes' : 'sfx';
        const response = await fetch(`${import.meta.env.BASE_URL}${from}/${take}.mp3`);
        this.buffers.set(group, await context.decodeAudioData(await response.arrayBuffer()));
      } catch {
        // A missing effect leaves the game silent there, nothing more.
      }
    }));
  }

  private applyVolume(): void {
    if (!this.context || !this.master) return;
    const volume = this.silenced ? 0 : Math.max(0, Math.min(1, this.options.soundsVolume));
    this.master.gain.setTargetAtTime(volume, this.context.currentTime, 0.02);
  }
}

export const sounds = new SoundEffects();
if (import.meta.env.DEV) Object.assign(window, { __sounds: sounds });
