import 'package:shared_preferences/shared_preferences.dart';

import 'settings.dart';

/// Where the settings live between launches.
abstract class SettingsStore {
  Future<Settings> load();

  /// Returns whether the settings were actually written.
  Future<bool> save(Settings settings);
}

/// The device's own key-value storage.
class DeviceSettingsStore implements SettingsStore {
  static const _key = 'rotathree.settings.v1';

  @override
  Future<Settings> load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return Settings.decode(preferences.getString(_key));
    } on Exception {
      return const Settings();
    }
  }

  @override
  Future<bool> save(Settings settings) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.setString(_key, settings.encode());
    } on Exception {
      return false;
    }
  }
}

/// Keeps the settings only while the app runs (tests).
class MemorySettingsStore implements SettingsStore {
  MemorySettingsStore([this.settings = const Settings()]);

  Settings settings;

  @override
  Future<Settings> load() async => settings;

  @override
  Future<bool> save(Settings settings) async {
    this.settings = settings;
    return true;
  }
}
