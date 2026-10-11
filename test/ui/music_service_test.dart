import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/audio/music_service.dart';
import 'package:rotathree/ui/data/settings.dart';

void main() {
  testWidgets(
    'pause blocks native resume and preserves the source and chosen volume',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const commands = MethodChannel('xyz.luan/audioplayers');
      const global = MethodChannel('xyz.luan/audioplayers.global');
      const globalEvents = MethodChannel('xyz.luan/audioplayers.global/events');
      const codec = StandardMethodCodec();
      final calls = <MethodCall>[];
      final eventChannels = <MethodChannel>[];
      messenger.setMockMethodCallHandler(global, (_) async => null);
      messenger.setMockMethodCallHandler(globalEvents, (_) async => null);
      messenger.setMockMethodCallHandler(commands, (call) async {
        calls.add(call);
        final arguments = call.arguments as Map;
        final channel = 'xyz.luan/audioplayers/events/${arguments['playerId']}';
        if (call.method == 'create') {
          final events = MethodChannel(channel);
          eventChannels.add(events);
          messenger.setMockMethodCallHandler(events, (_) async => null);
        } else if (call.method == 'setSourceUrl') {
          messenger.handlePlatformMessage(
            channel,
            codec.encodeSuccessEnvelope({
              'event': 'audio.onPrepared',
              'value': true,
            }),
            (_) {},
          );
        }
        return call.method == 'getCurrentPosition' ||
                call.method == 'getDuration'
            ? 0
            : null;
      });
      final source = File('assets/${MusicService.tracks.first}').absolute.uri;
      AudioCache.instance.loadedFiles[MusicService.tracks.first] = source;
      final music = MusicService();
      await tester.runAsync(() async {
        await music.start();
        expect(calls.where((call) => call.method == 'resume'), hasLength(1));
        expect(
          calls
              .lastWhere((call) => call.method == 'setVolume')
              .arguments['volume'],
          0.1,
        );
        await music.setSuspended(true);
        expect(calls.where((call) => call.method == 'pause'), hasLength(1));
        await music.update(const AudioOptions(music: false, musicVolume: 0.35));
        await music.update(const AudioOptions(music: true, musicVolume: 0.35));
        await music
            .start(); // Includes attempts after returning to the foreground.
        expect(calls.where((call) => call.method == 'resume'), hasLength(1));
        await music.setSuspended(false);
        expect(calls.where((call) => call.method == 'resume'), hasLength(2));
        expect(
          calls.where((call) => call.method == 'setSourceUrl'),
          hasLength(1),
        );
        expect(calls.where((call) => call.method == 'seek'), isEmpty);
        expect(
          calls
              .lastWhere((call) => call.method == 'setVolume')
              .arguments['volume'],
          0.35,
        );
        await music.setSuspended(true);
        await music.update(const AudioOptions(music: false));
        await music.setSuspended(false);
        expect(calls.where((call) => call.method == 'resume'), hasLength(2));
        await music.dispose();
      });
      AudioCache.instance.loadedFiles.remove(MusicService.tracks.first);
      for (final channel in [
        commands,
        global,
        globalEvents,
        ...eventChannels,
      ]) {
        messenger.setMockMethodCallHandler(channel, null);
      }
    },
  );
}
