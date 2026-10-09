import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import '../data/settings.dart';

/// The playback assets have equal loudness and two-second fades baked into
/// both ends. One player runs them in order, without overlapping their volume.
class MusicService {
  static const tracks = <String>[
    'music/playback/deep-focus.m4a',
    'music/playback/deep-focus-1.m4a',
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
  var _disposed = false;

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
      await _player?.setVolume(_options.music ? _options.musicVolume : 0);
    });
  }

  Future<void> start() {
    if (!_options.music || _disposed) return Future.value();
    _wanted = true;
    return _enqueue(_playCurrent);
  }

  Future<void> _playCurrent() async {
    if (!_wanted || !_options.music || _disposed) return;
    if (_player == null) {
      final player = AudioPlayer();
      _player = player;
      _completeSubscription = player.onPlayerComplete.listen((_) {
        if (!_wanted || _disposed) return;
        _track = (_track + 1) % tracks.length;
        _loaded = false;
        unawaited(_enqueue(_playCurrent));
      });
    }
    final player = _player!;
    if (!_loaded) {
      await player.setSource(AssetSource(tracks[_track]));
      _loaded = true;
    }
    await player.setVolume(_options.music ? _options.musicVolume : 0);
    if (_wanted && _options.music && !_disposed) await player.resume();
  }

  Future<void> stop() {
    _wanted = false;
    return _enqueue(() async => _player?.pause());
  }

  Future<void> dispose() {
    _disposed = true;
    _wanted = false;
    return _enqueue(() async {
      await _completeSubscription?.cancel();
      await _player?.dispose();
    });
  }
}
