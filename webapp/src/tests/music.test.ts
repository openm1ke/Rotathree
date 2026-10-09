import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { MUSIC_TRACKS, MusicPlayer } from '../services/music';

class TestAudio extends EventTarget {
  static instances: TestAudio[] = [];
  private source = '';
  error: { code: number } | null = null;
  get src(): string { return this.source; }
  set src(value: string) {
    this.source = value;
    this.error = null;
    this.currentTime = 0;
  }
  preload = '';
  volume = 1;
  currentTime = 0;
  paused = true;
  play = vi.fn(async () => { this.paused = false; });
  pause = vi.fn(() => { this.paused = true; });
  load = vi.fn();
  removeAttribute = vi.fn();
  constructor() {
    super();
    TestAudio.instances.push(this);
  }
}

class TestContext {
  static instances: TestContext[] = [];
  state = 'suspended';
  destination = {};
  output = { gain: { value: 1 }, connect: vi.fn() };
  resume = vi.fn(async () => { this.state = 'running'; });
  close = vi.fn(async () => {});
  createGain = vi.fn(() => this.output);
  createMediaElementSource = vi.fn(() => ({ connect: vi.fn() }));
  constructor() { TestContext.instances.push(this); }
}

describe('background music playback', () => {
  let music: MusicPlayer;
  beforeEach(() => {
    TestAudio.instances = [];
    TestContext.instances = [];
    vi.stubGlobal('Audio', TestAudio);
    vi.stubGlobal('AudioContext', TestContext);
    music = new MusicPlayer();
  });
  afterEach(() => {
    music.dispose();
    vi.unstubAllGlobals();
  });

  it('starts at 10% and changes the output gain without restarting the track', async () => {
    await music.start();
    const player = TestAudio.instances[0];
    const output = TestContext.instances[0].output;
    expect(output.gain.value).toBe(0.1);
    expect(player.src).toBe(`/${MUSIC_TRACKS[0]}`);
    player.currentTime = 25;
    music.setSettings({ music: true, musicVolume: 0.35 });
    expect(output.gain.value).toBe(0.35);
    expect(player.currentTime).toBe(25);
    expect(player.play).toHaveBeenCalledTimes(1);
    expect(TestAudio.instances).toHaveLength(1);
  });

  it('plays tracks sequentially and returns to the first after the last', async () => {
    await music.start();
    const player = TestAudio.instances[0];
    for (let index = 1; index <= MUSIC_TRACKS.length; index++) {
      player.dispatchEvent(new Event('ended'));
      await music.start();
      expect(player.src).toBe(`/${MUSIC_TRACKS[index % MUSIC_TRACKS.length]}`);
    }
    expect(TestAudio.instances).toHaveLength(1);
  });

  it('mutes, ignores further gestures while disabled, and resumes at the chosen volume', async () => {
    await music.start();
    const player = TestAudio.instances[0];
    music.setSettings({ music: false, musicVolume: 0.2 });
    expect(player.paused).toBe(true);
    expect(TestContext.instances[0].output.gain.value).toBe(0);
    music.ensurePlaying();
    await music.start();
    expect(player.play).toHaveBeenCalledTimes(1);
    music.setSettings({ music: true, musicVolume: 0.2 });
    await music.start();
    expect(player.paused).toBe(false);
    expect(TestContext.instances[0].output.gain.value).toBe(0.2);
  });

  it('does not resume after being disabled while autoplay is still pending', async () => {
    const player = TestAudio.instances[0];
    let finish!: () => void;
    player.play.mockImplementationOnce(() => new Promise<void>((resolve) => {
      finish = () => { player.paused = false; resolve(); };
    }));
    const starting = music.start();
    await Promise.resolve();
    music.setSettings({ music: false, musicVolume: 0.1 });
    finish();
    await starting;
    expect(player.paused).toBe(true);
    expect(TestContext.instances[0].output.gain.value).toBe(0);
  });

  it('retries blocked autoplay on a later gesture and stops after disposal', async () => {
    const player = TestAudio.instances[0];
    player.play.mockRejectedValueOnce(new Error('autoplay blocked'));
    await music.start();
    expect(player.paused).toBe(true);
    await music.start();
    expect(player.paused).toBe(false);
    music.dispose();
    player.dispatchEvent(new Event('ended'));
    await music.start();
    expect(player.play).toHaveBeenCalledTimes(2);
    expect(player.paused).toBe(true);
  });

  it('uses the media volume as fallback when Web Audio is unavailable', async () => {
    vi.stubGlobal('AudioContext', undefined);
    music.setSettings({ music: true, musicVolume: 0.05 });
    await music.start();
    expect(TestAudio.instances[0].volume).toBe(0.05);
  });

  it('skips an unavailable track even when its play promise is still pending', async () => {
    const player = TestAudio.instances[0];
    player.play.mockImplementationOnce(async () => {
      player.error = { code: 4 };
      player.dispatchEvent(new Event('error'));
      throw new Error('unsupported source');
    });
    await music.start();
    await music.start();
    expect(player.src).toBe(`/${MUSIC_TRACKS[1]}`);
    expect(player.paused).toBe(false);
  });
});
