import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../game/config/modes.dart';
import 'progress.dart';
import 'settings.dart';
import 'stats.dart';

/// Everything the player sets up, kept on the device. Each value is written
/// as one JSON text; anything unreadable falls back to its default.
class AppStore {
  AppStore(this._prefs);

  static const _settingsKey = 'rotathree.settings.v2';
  static const _progressKey = 'rotathree.progress.v1';
  static const _statsKey = 'rotathree.stats.v1';
  static const _customKey = 'rotathree.custom.v1';

  static Future<AppStore> open() async => AppStore(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  T _read<T>(String key, T Function(Object? raw) parse) {
    try {
      final text = _prefs.getString(key);
      return parse(text == null ? null : jsonDecode(text));
    } catch (_) {
      return parse(null);
    }
  }

  /// Returns whether the value was actually written.
  Future<bool> _write(String key, Object value) async {
    try {
      return await _prefs.setString(key, jsonEncode(value));
    } catch (_) {
      return false;
    }
  }

  Settings loadSettings() => _read(_settingsKey, Settings.fromJson);
  Future<bool> saveSettings(Settings value) => _write(_settingsKey, value.toJson());

  Progress loadProgress() => _read(_progressKey, Progress.fromJson);
  Future<bool> saveProgress(Progress value) => _write(_progressKey, value.toJson());

  Stats loadStats() => _read(_statsKey, Stats.fromJson);
  Future<bool> saveStats(Stats value) => _write(_statsKey, value.toJson());

  CustomSetup loadCustom() => _read(
        _customKey,
        (raw) => raw == null ? defaultCustom : CustomSetup.fromJson(raw),
      );
  Future<bool> saveCustom(CustomSetup value) => _write(_customKey, value.toJson());
}
