import 'package:flutter/material.dart';

import '../game/config/modes.dart';
import '../game/session.dart';
import 'data/progress.dart';
import 'data/settings.dart';
import 'data/stats.dart';
import 'data/store.dart';
import 'game/game_screen.dart';
import 'menu/campaign_screen.dart';
import 'menu/custom_screen.dart';
import 'menu/main_menu.dart';
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

enum _Screen { home, campaign, custom, statistics, settings, play }

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

  /// Changes for every new game, so that each one starts from scratch.
  int _nonce = 0;
  bool _stored = true;

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
    });
    BlockTones.setColours(_settings.palettes.activeSet.colours);
  }

  void _saved(Future<bool> write) {
    write.then((ok) {
      if (mounted && ok != _stored) setState(() => _stored = ok);
    });
  }

  void _changeSettings(Settings next) {
    setState(() => _settings = next);
    BlockTones.setColours(next.palettes.activeSet.colours);
    _saved(_store!.saveSettings(next));
  }

  void _changeProgress(Progress next) {
    setState(() => _progress = next);
    _saved(_store!.saveProgress(next));
  }

  void _recordRun(RunRecord run) {
    final next = _stats.withRun(run);
    setState(() => _stats = next);
    _saved(_store!.saveStats(next));
  }

  void _changeCustom(CustomSetup next) {
    setState(() => _custom = next);
    _saved(_store!.saveCustom(next));
  }

  void _show(_Screen screen) => setState(() {
        _screen = screen;
        _settingsOpen = false;
      });

  void _start(Session session) => setState(() {
        _nonce++;
        _settingsOpen = false;
        _session = session;
        _screen = _Screen.play;
      });

  void _retry(Session session) => setState(() {
        _nonce++;
        _session = session;
      });

  void _back() {
    if (_settingsOpen) {
      setState(() => _settingsOpen = false);
      return;
    }
    if (_screen != _Screen.home) _show(_Screen.home);
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    final colours = _settings.palettes.activeSet.colours;
    final body = switch (store) {
      null => const SizedBox.shrink(),
      _ => switch (_screen) {
          _Screen.home => MainMenu(
              progress: _progress,
              onCampaign: () => _show(_Screen.campaign),
              onCustom: () => _show(_Screen.custom),
              onStatistics: () => _show(_Screen.statistics),
              onSettings: () => _show(_Screen.settings),
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
          _Screen.statistics => StatisticsScreen(
              stats: _stats,
              progress: _progress,
              onBack: () => _show(_Screen.home),
            ),
          _Screen.settings => SettingsScreen(
              settings: _settings,
              stored: _stored,
              onChange: _changeSettings,
              onBack: () => _show(_Screen.home),
            ),
          _Screen.play => GameScreen(
              key: ValueKey(_nonce),
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
            const Positioned.fill(child: Backdrop()),
            Positioned.fill(child: body),
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
