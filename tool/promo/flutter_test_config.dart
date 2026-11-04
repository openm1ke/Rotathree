import 'dart:async';

import 'package:rotathree/ui/audio/sound_effects.dart';

/// The studio films without sound: the audio plugin is not there in tests.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SoundEffects.instance.enabled = false;
  await testMain();
}
