import 'dart:async';

import 'package:audioplayers/audioplayers.dart';

import '../data/settings.dart';

/// Plays the background playlist on two alternating players. Starting the
/// next player before the current one ends keeps the hand-off gapless while
/// the short volume ramp makes every transition a gentle crossfade.
class MusicService {
  MusicService({this.crossfade = const Duration(seconds: 3)});

  static const tracks = <String>[
    'music/Deep Focus.m4a',
    'music/Deep Focus(1).m4a',
    'music/downloaded/ambient_relaxing_loop.mp3',
    'music/downloaded/project_utopia_loop.mp3',
    'music/downloaded/chill_loopable.mp3',
    'music/downloaded/insistent_background_loop.mp3',
    'music/downloaded/claimed_by_the_void_loop.mp3',
  ];

  final Duration crossfade;
  final _players = <AudioPlayer>[];
  final _completeSubscriptions = <StreamSubscription<void>>[];
  Timer? _timer;
  AudioOptions _options = const AudioOptions();
  var _active = 0;
  var _track = 0;
  var _started = false;
  var _transitioning = false;
  var _tickBusy = false;
  DateTime? _fadeStarted;

  List<AudioPlayer> get players {
    if (_players.isEmpty) {
      for (var i = 0; i < 2; i++) {
        final player = AudioPlayer();
        final index = i;
        _players.add(player);
        _completeSubscriptions.add(player.onPlayerComplete.listen((_) => _onComplete(index)));
      }
    }
    return _players;
  }

  Future<void> update(AudioOptions options) async {
    _options = options;
    if (!options.music) {
      _timer?.cancel();
      _timer = null;
      if (_players.isNotEmpty) await Future.wait([for (final player in _players) player.pause()]);
      _started = false;
      _transitioning = false;
      return;
    }
    if (_players.isNotEmpty) {
      for (final player in _players) {
        await player.setVolume(options.musicVolume);
      }
    }
  }

  Future<void> start() async {
    if (!_options.music || _started || tracks.isEmpty) return;
    _started = true;
    final player = players[_active];
    await player.setSource(AssetSource(tracks[_track]));
    await player.setVolume(_options.musicVolume);
    await player.resume();
    _timer ??= Timer.periodic(const Duration(milliseconds: 80), (_) => _tick());
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    _started = false;
    _transitioning = false;
    if (_players.isNotEmpty) await Future.wait([for (final player in _players) player.stop()]);
  }

  Future<void> dispose() async {
    await stop();
    await Future.wait(_completeSubscriptions.map((subscription) => subscription.cancel()));
    await Future.wait([for (final player in _players) player.dispose()]);
  }

  Future<void> _tick() async {
    if (_tickBusy || !_started || !_options.music) return;
    _tickBusy = true;
    try {
      if (_transitioning) {
        await _fadeTick();
        return;
      }
      final player = players[_active];
      final duration = await player.getDuration();
      final position = await player.getCurrentPosition();
      if (duration == null || position == null) return;
      if (duration - position <= crossfade) await _beginFade();
    } finally {
      _tickBusy = false;
    }
  }

  Future<void> _beginFade() async {
    if (_transitioning || !_started) return;
    _transitioning = true;
    _fadeStarted = DateTime.now();
    final next = 1 - _active;
    _track = (_track + 1) % tracks.length;
    final player = players[next];
    await player.stop();
    await player.setSource(AssetSource(tracks[_track]));
    await player.setVolume(0);
    await player.resume();
  }

  Future<void> _fadeTick() async {
    final started = _fadeStarted;
    if (started == null) return;
    final progress = (DateTime.now().difference(started).inMilliseconds / crossfade.inMilliseconds).clamp(0.0, 1.0);
    final next = 1 - _active;
    await players[_active].setVolume(_options.musicVolume * (1 - progress));
    await players[next].setVolume(_options.musicVolume * progress);
    if (progress < 1) return;
    await players[_active].stop();
    _active = next;
    _transitioning = false;
    _fadeStarted = null;
  }

  void _onComplete(int index) {
    if (!_started || index != _active || _transitioning) return;
    // Very short or metadata-less files still advance if a duration could not
    // be read in time for the normal crossfade timer.
    unawaited(_beginFade());
  }
}
