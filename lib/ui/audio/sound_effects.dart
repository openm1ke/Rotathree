import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../data/settings.dart';
import 'music_service.dart';

/// What the game makes a sound for.
enum SoundGroup { ui, move, rotate, turn, land, pop, level, over }

/// Short effects of play and of the interface: the takes of the web version,
/// copied into assets/sfx by tool/prepare_app_sfx.py.
class SoundEffects {
  SoundEffects._();

  static final instance = SoundEffects._();

  /// The take each group plays, as CHOSEN in webapp/src/services/sounds.ts.
  static const takes = {
    SoundGroup.ui: 'ui-blip',
    SoundGroup.move: 'move-select',
    SoundGroup.rotate: 'rotate-bloop',
    SoundGroup.turn: 'turn-sweep-deep',
    SoundGroup.land: 'land-soft',
    SoundGroup.pop: 'pop-plop',
    SoundGroup.level: 'level-up',
    SoundGroup.over: 'over-digital',
  };

  /// Steps of a major scale: a chain of matches climbs like a melody. The
  /// burst is rendered once per step, as `pop-plop-<step>`.
  static const comboSteps = [0, 2, 4, 5, 7, 9, 11, 12];

  /// How long the level jingle lasts: the music steps aside for it.
  static const levelSeconds = 1.25;

  /// Players per take, so that quick repeats overlap instead of cutting
  /// each other off: a held move repeats every few dozen milliseconds.
  static const _voices = {
    SoundGroup.ui: 2,
    SoundGroup.move: 4,
    SoundGroup.rotate: 3,
    SoundGroup.turn: 2,
    SoundGroup.land: 3,
    SoundGroup.pop: 1,
    SoundGroup.level: 1,
    SoundGroup.over: 1,
  };

  /// Effects mix into the music and never take the audio focus from it: on
  /// Android a player that took it would pause the music.
  static final _audioContext = AudioContext(
    iOS: MusicService.audioContextIOS,
    android: const AudioContextAndroid(
      contentType: AndroidContentType.sonification,
      usageType: AndroidUsageType.game,
      audioFocus: AndroidAudioFocus.none,
    ),
  );

  /// Whether the effects load at all: widget tests run without the audio
  /// plugin (test/flutter_test_config.dart).
  bool enabled = true;

  AudioOptions _options = const AudioOptions();
  bool _silenced = false;
  final Map<String, _Voices> _loaded = {};
  Future<void>? _loading;

  /// How the music steps aside while the level jingle plays.
  void Function(double seconds)? duckMusic;

  void setSettings(AudioOptions options) {
    _options = options;
    if (options.sounds && enabled) unawaited(load());
  }

  /// The app in the background: nothing plays.
  void setSilenced(bool silenced) => _silenced = silenced;

  /// Prepares every take once; a take still loading stays silent.
  Future<void> load() => _loading ??= _load();

  /// Lets every player go; the next [load] prepares them again.
  @visibleForTesting
  Future<void> unload() async {
    await _loading;
    final voices = [..._loaded.values];
    _loaded.clear();
    _loading = null;
    for (final take in voices) {
      await take.dispose();
    }
  }

  void play(SoundGroup group) {
    if (group == SoundGroup.pop) return pop(1);
    if (_fire(takes[group]!) && group == SoundGroup.level) duckMusic?.call(levelSeconds);
  }

  /// The burst of a cleared match, [combo] steps into its chain.
  void pop(int combo) => _fire('${takes[SoundGroup.pop]}-${comboSteps[combo.clamp(1, comboSteps.length) - 1]}');

  bool _fire(String take) {
    if (!_options.sounds || _silenced || _options.soundsVolume <= 0) return false;
    final voices = _loaded[take];
    if (voices == null) return false;
    voices.play(_options.soundsVolume);
    return true;
  }

  Future<void> _load() async {
    final names = <String, int>{
      for (final MapEntry(key: group, value: take) in takes.entries)
        if (group != SoundGroup.pop) take: _voices[group]!,
      for (final step in comboSteps) '${takes[SoundGroup.pop]}-$step': _voices[SoundGroup.pop]!,
    };
    for (final MapEntry(key: take, value: count) in names.entries) {
      try {
        final players = <AudioPlayer>[];
        for (var i = 0; i < count; i++) {
          final player = AudioPlayer();
          // Android's sound pool starts a short effect at once.
          if (defaultTargetPlatform == TargetPlatform.android) await player.setPlayerMode(PlayerMode.lowLatency);
          await player.setAudioContext(_audioContext);
          await player.setReleaseMode(ReleaseMode.stop);
          await player.setSource(AssetSource('sfx/$take.mp3'));
          players.add(player);
        }
        _loaded[take] = _Voices(players);
      } catch (error) {
        // A missing effect leaves the game silent there, nothing more.
        debugPrint('Sound effect $take: $error');
      }
    }
  }
}

/// The players of one take, used in turn.
class _Voices {
  _Voices(this._players)
      : _starting = List.filled(_players.length, false),
        _volumes = List.filled(_players.length, null);

  final List<AudioPlayer> _players;

  /// A player still being restarted takes no other play.
  final List<bool> _starting;

  /// The volume each player was last given, so it is set again only when it
  /// changes.
  final List<double?> _volumes;
  var _next = 0;

  /// Plays at once on the next free player. Quick repeats each get one; when
  /// every player is still starting, the repeat is left out rather than
  /// queued, so that no sound comes late after the move it belongs to.
  void play(double volume) {
    for (var tried = 0; tried < _players.length; tried++) {
      final index = _next;
      _next = (_next + 1) % _players.length;
      if (_starting[index]) continue;
      _starting[index] = true;
      unawaited(_start(index, volume));
      return;
    }
  }

  Future<void> dispose() async {
    for (final player in _players) {
      await player.dispose();
    }
  }

  Future<void> _start(int index, double volume) async {
    final player = _players[index];
    try {
      // A low-latency player plays a take once until it is stopped.
      await player.stop();
      if (_volumes[index] != volume) {
        await player.setVolume(volume);
        _volumes[index] = volume;
      }
      await player.resume();
    } catch (error) {
      debugPrint('Sound effect: $error');
    } finally {
      _starting[index] = false;
    }
  }
}

/// A button's press with its click: every button of the interface clicks,
/// except the pads, whose actions have the game's own sounds.
VoidCallback? clicking(VoidCallback? onPressed) => onPressed == null
    ? null
    : () {
        SoundEffects.instance.play(SoundGroup.ui);
        onPressed();
      };
