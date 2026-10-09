import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../game/config/modes.dart';
import 'progress.dart';
import 'settings.dart';
import 'stats.dart';
import 'run_save.dart';

/// Everything the player sets up, kept on the device. Each value is written
/// as one JSON text; anything unreadable falls back to its default.
class AppStore {
  AppStore(this._prefs);

  static const _settingsKey = 'rotathree.settings.v2';
  static const _progressKey = 'rotathree.progress.v1';
  static const _statsKey = 'rotathree.stats.v1';
  static const _customKey = 'rotathree.custom.v1';
  static const _runKey = 'rotathree.run.mobile.v1';
  static const _tutorialKey = 'rotathree.tutorial.v1';

  static Future<AppStore> open() async {
    try {
      return AppStore(await SharedPreferences.getInstance());
    } catch (_) {
      return AppStore(null);
    }
  }

  final SharedPreferences? _prefs;
  bool get available => _prefs != null;
  final Map<String, String?> _memory = {};
  Future<void> _writes = Future.value();

  T _read<T>(String key, T Function(Object? raw) parse) {
    try {
      final text = _memory.containsKey(key) ? _memory[key] : _prefs?.getString(key);
      return parse(text == null ? null : jsonDecode(text));
    } catch (_) {
      return parse(null);
    }
  }

  /// Returns whether the value was actually written.
  Future<bool> _write(String key, Object? value) {
    final text = value == null ? null : jsonEncode(value);
    _memory[key] = text;
    final result = _writes.then((_) async {
      try {
        final prefs = _prefs;
        if (prefs == null) return false;
        return text == null ? await prefs.remove(key) : await prefs.setString(key, text);
      } catch (_) {
        return false;
      }
    });
    _writes = result.then((_) {});
    return result;
  }

  Settings loadSettings() => _read(_settingsKey, Settings.fromJson);
  Future<bool> saveSettings(Settings value) => _write(_settingsKey, value.toJson());

  Progress loadProgress() => _read(_progressKey, Progress.fromJson);
  Future<bool> saveProgress(Progress value) => _write(_progressKey, value.toJson());

  Stats loadStats() => _read(_statsKey, Stats.fromJson);
  Future<bool> saveStats(Stats value) => _write(_statsKey, value.toJson());

  CustomSetup loadCustom() => _read(_customKey, (raw) => raw == null ? defaultCustom : CustomSetup.fromJson(raw));
  Future<bool> saveCustom(CustomSetup value) => _write(_customKey, value.toJson());
  RunSave? loadRun() => _read(_runKey, RunSave.read);
  Future<bool> saveRun(RunSave? value) => _write(_runKey, value?.toJson());
  Map<ModeId, RunSave> loadRuns() => _read(_runKey, readSavedRuns);
  Future<bool> saveRuns(Map<ModeId, RunSave> runs) => _write(_runKey, {
    'version': 2,
    'runs': {for (final entry in runs.entries) entry.key.name: entry.value.toJson()},
  });
  bool loadTutorial() => _read(_tutorialKey, (raw) => raw == true);
  Future<bool> saveTutorial(bool done) => _write(_tutorialKey, done);
}
