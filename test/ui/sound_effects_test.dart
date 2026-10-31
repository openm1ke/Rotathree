import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/audio/sound_effects.dart';
import 'package:rotathree/ui/data/settings.dart';

/// Every take the app plays, as the names of its files in assets/sfx.
List<String> takeNames() => [
  for (final MapEntry(key: group, value: take) in SoundEffects.takes.entries)
    if (group != SoundGroup.pop) take,
  for (final step in SoundEffects.comboSteps) '${SoundEffects.takes[SoundGroup.pop]}-$step',
];

void main() {
  test('every take the app plays ships, long enough for Android to load', () {
    for (final name in takeNames()) {
      final file = File('assets/sfx/$name.mp3');
      expect(file.existsSync(), isTrue, reason: name);
      // Android's sound pool loads nothing from a take of three MP3 frames,
      // as the 40 ms move was: tool/prepare_app_sfx.py pads the short ones to
      // 0.15 s, about 3.3 KB at 128 kbit/s.
      expect(file.lengthSync(), greaterThan(3000), reason: name);
    }
  });

  testWidgets('quick moves each make their sound, none of them late', (tester) async {
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const commands = MethodChannel('xyz.luan/audioplayers');
    const global = MethodChannel('xyz.luan/audioplayers.global');
    const globalEvents = MethodChannel('xyz.luan/audioplayers.global/events');
    const codec = StandardMethodCodec();
    final sources = <String, String>{};
    final resumed = <String>[];
    final eventChannels = <MethodChannel>[];
    messenger.setMockMethodCallHandler(global, (_) async => null);
    messenger.setMockMethodCallHandler(globalEvents, (_) async => null);
    messenger.setMockMethodCallHandler(commands, (call) async {
      final arguments = call.arguments as Map;
      final id = arguments['playerId'] as String;
      final channel = 'xyz.luan/audioplayers/events/$id';
      if (call.method == 'create') {
        final events = MethodChannel(channel);
        eventChannels.add(events);
        messenger.setMockMethodCallHandler(events, (_) async => null);
      } else if (call.method == 'setSourceUrl') {
        sources[id] = arguments['url'] as String;
        messenger.handlePlatformMessage(
          channel,
          codec.encodeSuccessEnvelope({'event': 'audio.onPrepared', 'value': true}),
          (_) {},
        );
      } else if (call.method == 'resume') {
        resumed.add(sources[id]!);
      }
      return null;
    });
    for (final name in takeNames()) {
      AudioCache.instance.loadedFiles['sfx/$name.mp3'] = File('assets/sfx/$name.mp3').absolute.uri;
    }
    final sounds = SoundEffects.instance..enabled = true;
    await tester.runAsync(() async {
      sounds.setSettings(const AudioOptions());
      await sounds.load();
      // A held move repeats every 35 ms by default; these come faster still.
      for (var i = 0; i < 10; i++) {
        sounds.play(SoundGroup.move);
        await Future<void>.delayed(const Duration(milliseconds: 15));
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(resumed.where((url) => url.contains('move-select')), hasLength(10));
      // Played as the moves come: a burst faster than the players can start
      // leaves the extra repeats out instead of queueing them up.
      resumed.clear();
      for (var i = 0; i < 10; i++) {
        sounds.play(SoundGroup.move);
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(resumed.where((url) => url.contains('move-select')), hasLength(4));
      await sounds.unload();
    });
    sounds.enabled = false;
    for (final name in takeNames()) {
      AudioCache.instance.loadedFiles.remove('sfx/$name.mp3');
    }
    for (final channel in [commands, global, globalEvents, ...eventChannels]) {
      messenger.setMockMethodCallHandler(channel, null);
    }
  });
}
