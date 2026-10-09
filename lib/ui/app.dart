import 'package:flutter/material.dart';

import '../game/config/modes.dart';
import '../game/session.dart';
import 'data/progress.dart';
import 'data/settings.dart';
import 'data/stats.dart';
import 'data/store.dart';
import 'data/run_save.dart';
import 'game/game_screen.dart';
import 'menu/campaign_screen.dart';
import 'menu/custom_screen.dart';
import 'menu/main_menu.dart';
import 'menu/resume_screen.dart';
import 'menu/settings_screen.dart';
import 'menu/statistics_screen.dart';
import 'style.dart';
import 'widgets/backdrop.dart';

class RotathreeApp extends StatelessWidget {
  const RotathreeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rotathree',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Palette.bg,
        colorScheme: const ColorScheme.dark(primary: Palette.accent, surface: Palette.panelStrong),
        fontFamily: Type.family,
        fontFamilyFallback: Type.fallback,
      ),
      home: const _AppRoot(),
    );
  }
}

enum _Screen { home, resume, campaign, custom, statistics, settings, play }

/// The app: the screens, the route between them, and everything the player
/// sets up, kept on the device.
class _AppRoot extends StatefulWidget {
  const _AppRoot();

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> {
  AppStore? _store;
  Settings _settings = Settings.defaults();
  Progress _progress = Progress.initial();
  Stats _stats = Stats.empty();
  CustomSetup _custom = defaultCustom;

  _Screen _screen = _Screen.home;
  Session? _session;
  bool _settingsOpen = false;

  bool _stored = true;
  final Set<String> _failedWrites = {};
  Map<ModeId, RunSave> _savedRuns = {};
  RunSave? _restore;
  bool _tutorialDone = false;
  bool _tutorial = false;
  Session? _afterTutorial;

  /// A fresh key for each run; system Back talks to the current game.
  GlobalKey<GameScreenState> _gameKey = GlobalKey<GameScreenState>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final store = await AppStore.open();
    if (!mounted) return;
    setState(() {
      _store = store;
      _settings = store.loadSettings();
      _progress = store.loadProgress();
      _stats = store.loadStats();
      _custom = store.loadCustom();
      _savedRuns = store.loadRuns();
      _tutorialDone = store.loadTutorial();
      _savedRuns.removeWhere((_, save) => _stats.recent.any((run) => run.id == save.id));
      _saved('run', store.saveRuns(_savedRuns));
      if (!store.available) _failedWrites.add('storage');
      _stored = _failedWrites.isEmpty;
    });
    BlockTones.setColours(_settings.palettes.activeSet.colours);
  }

  void _saved(String key, Future<bool> write) {
    write.then((ok) {
      if (!mounted) return;
      if (ok) {
        _failedWrites.remove(key);
      } else {
        _failedWrites.add(key);
      }
      final stored = _failedWrites.isEmpty;
      if (stored != _stored) setState(() => _stored = stored);
    });
  }

  Future<void> _retryStorage() async {
    final store = await AppStore.open();
    if (!mounted) return;
    _store = store;
    if (store.available) _failedWrites.remove('storage');
    _saved('settings', store.saveSettings(_settings));
    _saved('progress', store.saveProgress(_progress));
    _saved('stats', store.saveStats(_stats));
    _saved('custom', store.saveCustom(_custom));
    _saved('run', store.saveRuns(_savedRuns));
    _saved('tutorial', store.saveTutorial(_tutorialDone));
  }

  void _checkpoint(ModeId mode, RunSave? save) {
    if (save == null) {
      _savedRuns.remove(mode);
    } else {
      _savedRuns[mode] = save;
    }
    _saved('run', _store!.saveRuns(_savedRuns));
  }

  void _changeSettings(Settings next) {
    setState(() => _settings = next);
    BlockTones.setColours(next.palettes.activeSet.colours);
    _saved('settings', _store!.saveSettings(next));
  }

  void _changeProgress(Progress next) {
    setState(() => _progress = next);
    _saved('progress', _store!.saveProgress(next));
  }

  void _recordRun(RunRecord run) {
    final next = _stats.withRun(run);
    setState(() => _stats = next);
    _saved('stats', _store!.saveStats(next));
  }

  void _changeCustom(CustomSetup next) {
    setState(() => _custom = next);
    _saved('custom', _store!.saveCustom(next));
  }

  void _show(_Screen screen) => setState(() {
    _screen = screen;
    _settingsOpen = false;
  });

  void _start(Session session, {RunSave? restore}) {
    if (restore == null && !_tutorialDone) {
      _openTutorial(after: session);
      return;
    }
    final mode = modeOf(session);
    if (restore == null && _savedRuns[mode] != null) {
      _recordRun(_savedRuns[mode]!.abandoned());
      _checkpoint(mode, null);
    }
    setState(() {
      _gameKey = GlobalKey<GameScreenState>();
      _restore = restore;
      _tutorial = false;
      _settingsOpen = false;
      _session = session;
      _screen = _Screen.play;
    });
  }

  void _openTutorial({Session? after}) => setState(() {
    _gameKey = GlobalKey<GameScreenState>();
    _restore = null;
    _afterTutorial = after;
    _tutorial = true;
    _settingsOpen = false;
    _session = CustomSession(defaultCustom.copyWith(extraGlasses: 0));
    _screen = _Screen.play;
  });

  void _finishTutorial() {
    _tutorialDone = true;
    _saved('tutorial', _store!.saveTutorial(true));
    final next = _afterTutorial;
    _afterTutorial = null;
    if (next == null) {
      _show(_Screen.home);
    } else {
      _start(next);
    }
  }

  void _retry(Session session) => setState(() {
    _gameKey = GlobalKey<GameScreenState>();
    _restore = null;
    _session = session;
  });

  void _back() {
    if (_settingsOpen) {
      setState(() => _settingsOpen = false);
      return;
    }
    if (_screen == _Screen.play) {
      _gameKey.currentState?.handleBack();
      return;
    }
    if (_screen != _Screen.home) _show(_Screen.home);
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final colours = _settings.palettes.activeSet.colours;
    final body = switch (store) {
      null => const Center(child: CircularProgressIndicator()),
      _ => switch (_screen) {
        _Screen.home => MainMenu(
          progress: _progress,
          hasSavedGames: _savedRuns.isNotEmpty,
          onResume: () => _show(_Screen.resume),
          onTutorial: () => _openTutorial(),
          tutorialDone: _tutorialDone,
          onCampaign: () => _show(_Screen.campaign),
          onCustom: () => _show(_Screen.custom),
          onStatistics: () => _show(_Screen.statistics),
          onSettings: () => _show(_Screen.settings),
        ),
        _Screen.resume => ResumeScreen(
          runs: _savedRuns,
          onResume: (save) => _start(save.session, restore: save),
          onBack: () => _show(_Screen.home),
        ),
        _Screen.campaign => CampaignScreen(
          progress: _progress,
          colours: colours,
          onStart: (level) => _start(CampaignSession(level)),
          onInsane: () => _start(const InsaneSession()),
          onBack: () => _show(_Screen.home),
        ),
        _Screen.custom => CustomScreen(
          setup: _custom,
          colours: colours,
          onChange: _changeCustom,
          onStart: () => _start(CustomSession(_custom)),
          onBack: () => _show(_Screen.home),
        ),
        _Screen.statistics => StatisticsScreen(stats: _stats, progress: _progress, onBack: () => _show(_Screen.home)),
        _Screen.settings => SettingsScreen(
          settings: _settings,
          stored: _stored,
          onChange: _changeSettings,
          onBack: () => _show(_Screen.home),
        ),
        _Screen.play => GameScreen(
          key: _gameKey,
          restore: _restore,
          onCheckpoint: (save) => _checkpoint(modeOf(_session!), save),
          tutorial: _tutorial,
          onTutorialDone: _finishTutorial,
          session: _session!,
          settings: _settings,
          progress: _progress,
          blocked: _settingsOpen,
          onSettings: () => setState(() => _settingsOpen = true),
          onExit: () => _show(_Screen.home),
          onLevels: () => _show(_Screen.campaign),
          onRetry: _retry,
          onInsane: () => _start(const InsaneSession()),
          onCustomise: () => _show(_Screen.custom),
          onRecord: _recordRun,
          onProgress: _changeProgress,
        ),
      },
    };

    return PopScope(
      canPop: _screen == _Screen.home && !_settingsOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      // Material gives every control its ink and its switches an ancestor.
      child: Material(
        type: MaterialType.transparency,
        child: Stack(
          children: [
            Positioned.fill(
              child: Backdrop(menu: _screen != _Screen.play, paused: _settingsOpen),
            ),
            Positioned.fill(
              child: Column(
                children: [
                  Expanded(child: body),
                  if (!_stored)
                    SafeArea(
                      top: false,
                      child: Container(
                        color: Palette.panelStrong,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Не удалось сохранить данные. Они пока доступны только в этой сессии.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton(onPressed: _retryStorage, child: const Text('Повторить')),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_settingsOpen && _screen == _Screen.play && store != null)
              Positioned.fill(
                child: SettingsScreen(
                  overlay: true,
                  settings: _settings,
                  stored: _stored,
                  onChange: _changeSettings,
                  onBack: () => setState(() => _settingsOpen = false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
