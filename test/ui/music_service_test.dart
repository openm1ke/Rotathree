import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rotathree/ui/audio/music_service.dart';
import 'package:rotathree/ui/data/settings.dart';

void main() {
  testWidgets(
    'pause ducks native music and restores the chosen volume without reloading',
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
        await music.setPaused(true);
        expect(calls.where((call) => call.method == 'pause'), isEmpty);
        expect(
          calls
              .lastWhere((call) => call.method == 'setVolume')
              .arguments['volume'],
          closeTo(0.01, 0.0001),
        );
        await music.update(const AudioOptions(music: false, musicVolume: 0.35));
        await music.update(const AudioOptions(music: true, musicVolume: 0.35));
        await music
            .start(); // Includes attempts after returning to the foreground.
        expect(calls.where((call) => call.method == 'resume'), hasLength(2));
        expect(
          calls
              .lastWhere((call) => call.method == 'setVolume')
              .arguments['volume'],
          closeTo(0.035, 0.0001),
        );
        await music.setPaused(false);
        expect(calls.where((call) => call.method == 'resume'), hasLength(3));
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
        await music.setPaused(true);
        await music.update(const AudioOptions(music: false));
        await music.setPaused(false);
        expect(calls.where((call) => call.method == 'resume'), hasLength(3));
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
  testWidgets(
    'foreground and volume changes recover an interrupted native player',
    (tester) async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      const commands = MethodChannel('xyz.luan/audioplayers');
      const global = MethodChannel('xyz.luan/audioplayers.global');
      const globalEvents = MethodChannel('xyz.luan/audioplayers.global/events');
      final calls = <MethodCall>[];
      final eventChannels = <MethodChannel>[];
      var nativePlaying = false;
      messenger.setMockMethodCallHandler(global, (_) async => null);
      messenger.setMockMethodCallHandler(globalEvents, (_) async => null);
      messenger.setMockMethodCallHandler(commands, (call) async {
        calls.add(call);
        final channel =
            'xyz.luan/audioplayers/events/${call.arguments['playerId']}';
        if (call.method == 'create') {
          final events = MethodChannel(channel);
          eventChannels.add(events);
          messenger.setMockMethodCallHandler(events, (_) async => null);
        } else if (call.method == 'setSourceUrl') {
          messenger.handlePlatformMessage(
            channel,
            const StandardMethodCodec().encodeSuccessEnvelope({
              'event': 'audio.onPrepared',
              'value': true,
            }),
            (_) {},
          );
        } else if (call.method == 'resume') {
          nativePlaying = true;
        } else if (call.method == 'pause') {
          nativePlaying = false;
        }
        return call.method == 'getCurrentPosition' ||
                call.method == 'getDuration'
            ? 0
            : null;
      });
      for (final track in MusicService.tracks) {
        AudioCache.instance.loadedFiles[track] = File(
          'assets/$track',
        ).absolute.uri;
      }
      final music = MusicService();
      try {
        await tester.runAsync(() async {
          await music.start();
          expect(nativePlaying, isTrue);
          // A system interruption can leave AudioPlayer.state as playing.
          nativePlaying = false;
          await music.start();
          expect(nativePlaying, isTrue);
          nativePlaying = false;
          await music.update(const AudioOptions(musicVolume: 0.25));
          expect(nativePlaying, isTrue);
          expect(
            calls.lastWhere((c) => c.method == 'setVolume').arguments['volume'],
            0.25,
          );
          expect(calls.where((c) => c.method == 'setSourceUrl'), hasLength(1));
          expect(calls.where((c) => c.method == 'seek'), isEmpty);
          await music.stop();
          final resumes = calls.where((c) => c.method == 'resume').length;
          await music.update(const AudioOptions(musicVolume: 0.4));
          expect(nativePlaying, isFalse);
          expect(calls.where((c) => c.method == 'resume'), hasLength(resumes));
          // Completion can arrive while a background/mute command is in flight.
          final id = calls
              .firstWhere((c) => c.method == 'create')
              .arguments['playerId'];
          messenger.handlePlatformMessage(
            'xyz.luan/audioplayers/events/$id',
            const StandardMethodCodec().encodeSuccessEnvelope({
              'event': 'audio.onComplete',
            }),
            (_) {},
          );
          await Future<void>.delayed(Duration.zero);
          expect(nativePlaying, isFalse);
          await music.start();
          expect(nativePlaying, isTrue);
          final sources = calls.where((c) => c.method == 'setSourceUrl');
          expect(sources, hasLength(2));
          expect(
            sources.last.arguments['url'],
            contains(MusicService.tracks[1]),
          );
          await music.update(const AudioOptions(music: false));
          await music.start();
          expect(nativePlaying, isFalse);
          await music.dispose();
        });
      } finally {
        for (final track in MusicService.tracks) {
          AudioCache.instance.loadedFiles.remove(track);
        }
        for (final channel in [
          commands,
          global,
          globalEvents,
          ...eventChannels,
        ]) {
          messenger.setMockMethodCallHandler(channel, null);
        }
      }
    },
  );
}
