import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../data/settings.dart';

/// The playback assets have equal loudness and two-second fades baked into
/// both ends. One player runs them in order, without overlapping their volume.
class MusicService {
  /// On iOS the music mixes with audio that is already playing (a podcast or
  /// another app) instead of stopping it. Android keeps the default audio
  /// focus, so a phone call still takes over the sound.
  /// The audio session is one for the whole app on iOS: the sound effects
  /// set the same one.
  static final audioContextIOS = AudioContextIOS(options: const {AVAudioSessionOptions.mixWithOthers});

  static final _audioContext = AudioContext(
    iOS: audioContextIOS,
    android: const AudioContextAndroid(),
  );

  static const tracks = <String>[
    'music/playback/ambient-relaxing-loop.m4a',
    'music/playback/project-utopia-loop.m4a',
    'music/playback/chill-loopable.m4a',
    'music/playback/insistent-background-loop.m4a',
    'music/playback/claimed-by-the-void-loop.m4a',
  ];

  AudioPlayer? _player;
  StreamSubscription<void>? _completeSubscription;
  AudioOptions _options = const AudioOptions();
  Future<void> _queue = Future.value();
  var _track = 0;
  var _loaded = false;
  var _wanted = false;
  var _paused = false;
  var _ducked = false;
  Timer? _duckTimer;
  var _disposed = false;

  double get _volume =>
      _options.music ? _options.musicVolume * (_paused || _ducked ? 0.1 : 1) : 0;

  /// Serialize native commands so a slow source load cannot undo mute/volume.
  Future<void> _enqueue(Future<void> Function() command) {
    _queue = _queue.then((_) => command()).catchError((Object error) {
      debugPrint('Background music: $error');
    });
    return _queue;
  }

  Future<void> update(AudioOptions options) {
    _options = options;
    if (!options.music) return stop();
    return _enqueue(() async {
      await _player?.setVolume(_volume);
      if (_wanted) await _playCurrent();
    });
  }

  Future<void> start() {
    if (!_options.music || _disposed) return Future.value();
    _wanted = true;
    return _enqueue(_playCurrent);
  }

  /// Duck music on pause without overwriting the player's volume preference.
  Future<void> setPaused(bool paused) {
    _paused = paused;
    return _enqueue(() async {
      await _player?.setVolume(_volume);
      if (!paused && _wanted) await _playCurrent();
    });
  }

  /// Steps aside for a musical effect, such as the level jingle: as quiet as
  /// under a pause for [seconds], so that two tunes do not clash.
  void duck(double seconds) {
    _duckTimer?.cancel();
    _ducked = true;
    unawaited(_enqueue(() async => _player?.setVolume(_volume)));
    _duckTimer = Timer(Duration(milliseconds: (seconds * 1000).round()), () {
      _ducked = false;
      unawaited(_enqueue(() async => _player?.setVolume(_volume)));
    });
  }

  Future<void> _playCurrent() async {
    if (!_wanted || !_options.music || _disposed) return;
    if (_player == null) {
      final player = AudioPlayer();
      _player = player;
      await player.setAudioContext(_audioContext);
      _completeSubscription = player.onPlayerComplete.listen((_) {
        if (_disposed) return;
        _track = (_track + 1) % tracks.length;
        _loaded = false;
        if (_wanted) unawaited(_enqueue(_playCurrent));
      });
    }
    final player = _player!;
    if (!_loaded || player.source == null) {
      await player.setSource(AssetSource(tracks[_track]));
      _loaded = true;
    }
    await player.setVolume(_volume);
    // Native interruptions can pause playback without changing the Dart state.
    // Resume is idempotent and also reacquires audio focus without seeking.
    if (_wanted && _options.music && !_disposed) await player.resume();
  }

  Future<void> stop() {
    _wanted = false;
    return _enqueue(() async => _player?.pause());
  }

  Future<void> dispose() {
    _disposed = true;
    _duckTimer?.cancel();
    _wanted = false;
    return _enqueue(() async {
      await _completeSubscription?.cancel();
      await _player?.dispose();
    });
  }
}
