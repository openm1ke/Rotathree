import 'dart:async';

import 'package:rotathree/ui/audio/sound_effects.dart';

/// Widget tests run without the audio plugin: the sound effects stay
/// unloaded, and so silent.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SoundEffects.instance.enabled = false;
  await testMain();
}
