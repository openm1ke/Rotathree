import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'i18n/strings.dart';

import '../game/config/modes.dart';
import '../game/session.dart';
import 'data/achievements.dart';
import 'data/progress.dart';
import 'data/settings.dart';
import 'data/stats.dart';
import 'data/store.dart';
import 'data/run_save.dart';
import 'audio/music_service.dart';
import 'audio/sound_effects.dart';
import 'game/game_screen.dart';
import 'layout.dart';
import 'menu/achievements_screen.dart';
import 'menu/campaign_screen.dart';
import 'menu/custom_screen.dart';
import 'cube/cube_screen.dart';
import 'cube/cube_setup_screen.dart';
import '../cube/campaign.dart';
import '../cube/save.dart';
import 'menu/main_menu.dart';
import 'menu/resume_screen.dart';
import 'menu/settings_screen.dart';
import 'menu/statistics_screen.dart';
import 'style.dart';
import 'widgets/achievement_toast.dart';
import 'widgets/backdrop.dart';

class RotathreeApp extends StatefulWidget {
  const RotathreeApp({super.key});

  @override
  State<RotathreeApp> createState() => _RotathreeAppState();
}

class _RotathreeAppState extends State<RotathreeApp> {
  LanguageChoice _language = LanguageChoice.auto;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RotaThree',
      locale: _language == LanguageChoice.auto ? null : Locale(_language.name),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        AppStrings.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      localeListResolutionCallback: (preferred, _) => resolveLanguage(_language, preferred ?? const []),
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        scaffoldBackgroundColor: Palette.bg,
        colorScheme: const ColorScheme.dark(primary: Palette.accent, surface: Palette.panelStrong),
        fontFamily: Type.family,
        fontFamilyFallback: Type.fallback,
      ),
      home: _AppRoot(
        onLanguageChanged: (language) {
          if (_language != language) setState(() => _language = language);
        },
      ),
    );
  }
}

enum _Screen { home, resume, campaign, custom, statistics, achievements, settings, play, cube, cubePlay }

/// The app: the screens, the route between them, and everything the player
/// sets up, kept on the device.
class _AppRoot extends StatefulWidget {
  const _AppRoot({required this.onLanguageChanged});
  final ValueChanged<LanguageChoice> onLanguageChanged;

  @override
  State<_AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<_AppRoot> with WidgetsBindingObserver {
  final MusicService _music = MusicService();
  AppStore? _store;
  Settings _settings = Settings.defaults();
  Progress _progress = Progress.initial();
  Stats _stats = Stats.empty();
  CustomSetup _custom = defaultCustom;
  AchievementLog _achievements = const AchievementLog({});
  final AchievementToasts _toasts = AchievementToasts();

  _Screen _screen = _Screen.home;
  Session? _session;
  bool _settingsOpen = false;

  bool _stored = true;
  final Set<String> _failedWrites = {};
  Map<ModeId, RunSave> _savedRuns = {};
  RunSave? _restore;
  bool _resumeImmediately = false;
  bool _tutorialDone = false;
  bool _tutorial = false;
  Session? _afterTutorial;

  /// A fresh key for each run; system Back talks to the current game.
  GlobalKey<GameScreenState> _gameKey = GlobalKey<GameScreenState>();

  // Cube: the two games kept (endless, a level), its campaign, and the game
  // on now — a level, or the endless one, maybe a kept one.
  Map<CubeKind, CubeSave> _cubeRuns = {};
  Progress _cubeProgress = defaultCubeProgress();
  int? _cubeLevel;
  CubeSave? _cubeRestore;

  /// Cube's lessons: seen once, on now, and what they lead to when skipped
  /// or played through — the endless game, a level, or Cube's screen.
  bool _cubeTutorialDone = false;

  /// The campaign opened from a level of Cube: its part is shown first.
  bool _campaignCube = false;
  bool _cubeTutorial = false;
  ({bool game, int? level}) _cubeThen = (game: false, level: null);
  GlobalKey<CubeScreenState> _cubeKey = GlobalKey<CubeScreenState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SoundEffects.instance.duckMusic = _music.duck;
    _load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    SoundEffects.instance.setSilenced(state != AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed && _store != null) {
      unawaited(_music.start());
    } else if (state != AppLifecycleState.resumed) {
      unawaited(_music.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SoundEffects.instance.duckMusic = null;
    unawaited(_music.dispose());
    _toasts.dispose();
    super.dispose();
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
      _cubeRuns = store.loadCubeRuns()..removeWhere((_, save) => _stats.recent.any((run) => run.id == save.id));
      _cubeProgress = store.loadCubeProgress();
      _cubeTutorialDone = store.loadCubeTutorial();
      _achievements = store.loadAchievements();
      if (!store.available) _failedWrites.add('storage');
      _stored = _failedWrites.isEmpty;
    });
    // What was earned before the achievements were kept is given quietly.
    _grantAchievements(announce: false);
    widget.onLanguageChanged(_settings.language);
    BlockTones.setLook(_settings.palettes.activeSet.colours, _settings.skin);
    unawaited(_music.update(_settings.audio));
    SoundEffects.instance.setSettings(_settings.audio);
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      unawaited(_music.start());
    }
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
    _saved('cubeRun', store.saveCubeRuns(_cubeRuns));
    _saved('cubeProgress', store.saveCubeProgress(_cubeProgress));
    _saved('cubeTutorial', store.saveCubeTutorial(_cubeTutorialDone));
    _saved('achievements', store.saveAchievements(_achievements));
  }

  AchievementFacts get _facts => AchievementFacts(stats: _stats, progress: _progress, cubeProgress: _cubeProgress);

  /// Gives the achievements the kept results now earn, and [also], earned by
  /// what just happened; each announced unless [announce] is false.
  void _grantAchievements({Iterable<String> also = const [], bool announce = true}) {
    final store = _store;
    if (store == null) return;
    final earned = [
      for (final id in also)
        if (!_achievements.has(id)) ?achievementById(id),
      ..._achievements.newlyEarned(_facts),
    ];
    if (earned.isEmpty) return;
    final next = _achievements.withUnlocked(earned.map((a) => a.id), DateTime.now().millisecondsSinceEpoch);
    setState(() => _achievements = next);
    _saved('achievements', store.saveAchievements(next));
    if (announce) _toasts.add(earned);
  }

  void _cubeCheckpoint(CubeKind kind, CubeSave? save) {
    if (save == null) {
      _cubeRuns.remove(kind);
    } else {
      _cubeRuns[kind] = save;
    }
    _saved('cubeRun', _store!.saveCubeRuns(_cubeRuns));
  }

  void _changeCubeProgress(Progress next) {
    setState(() => _cubeProgress = next);
    _saved('cubeProgress', _store!.saveCubeProgress(next));
    _grantAchievements();
  }

  /// A new game of Cube, endless or a campaign level: one of the same kind
  /// left unfinished is given up, and recorded.
  void _playCube([int? level]) {
    final kind = kindOf(level);
    final kept = _cubeRuns[kind];
    if (kept != null) {
      _recordRun(kept.abandoned());
      _cubeCheckpoint(kind, null);
    }
    _setMusicPaused(false);
    setState(() {
      _cubeKey = GlobalKey<CubeScreenState>();
      _cubeLevel = level;
      _cubeRestore = null;
      _cubeTutorial = false;
      _settingsOpen = false;
      _screen = _Screen.cubePlay;
    });
  }

  /// Cube's first game, endless or a level, begins with its lessons.
  void _startCube([int? level]) {
    if (_cubeTutorialDone) {
      _playCube(level);
    } else {
      _openCubeTutorial((game: true, level: level));
    }
  }

  void _openCubeTutorial(({bool game, int? level}) then) {
    _setMusicPaused(false);
    setState(() {
      _cubeKey = GlobalKey<CubeScreenState>();
      _cubeLevel = null;
      _cubeRestore = null;
      _cubeTutorial = true;
      _cubeThen = then;
      _settingsOpen = false;
      _screen = _Screen.cubePlay;
    });
  }

  /// [played]: Play on the last lesson rather than Skip: it goes into the
  /// game, as a skip does when the lessons came before a game.
  void _finishCubeTutorial(bool played) {
    _cubeTutorialDone = true;
    _saved('cubeTutorial', _store!.saveCubeTutorial(true));
    if (played) _grantAchievements(also: const [cubeLessonsPlayed]);
    final then = _cubeThen;
    if (then.level != null) {
      _playCube(then.level);
    } else if (played || then.game) {
      _playCube();
    } else {
      _show(_Screen.cube);
    }
  }

  /// A kept game of Cube: it opens paused.
  void _resumeCube(CubeKind kind) {
    final save = _cubeRuns[kind];
    if (save == null) return;
    _setMusicPaused(true);
    setState(() {
      _cubeKey = GlobalKey<CubeScreenState>();
      _cubeLevel = save.level;
      _cubeRestore = save;
      _cubeTutorial = false;
      _settingsOpen = false;
      _screen = _Screen.cubePlay;
    });
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
    final wasMusicEnabled = _settings.audio.music;
    setState(() => _settings = next);
    widget.onLanguageChanged(next.language);
    BlockTones.setLook(next.palettes.activeSet.colours, next.skin);
    unawaited(_music.update(next.audio));
    SoundEffects.instance.setSettings(next.audio);
    if (!wasMusicEnabled && next.audio.music &&
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
      unawaited(_music.start());
    }
    _saved('settings', _store!.saveSettings(next));
  }

  /// The quick sound button mutes music and effects together, and brings
  /// both back.
  void _toggleMusic() {
    final on = !(_settings.audio.music || _settings.audio.sounds);
    _changeSettings(_settings.copyWith(audio: _settings.audio.copyWith(music: on, sounds: on)));
  }

  void _changeProgress(Progress next) {
    setState(() => _progress = next);
    _saved('progress', _store!.saveProgress(next));
    _grantAchievements();
  }

  void _recordRun(RunRecord run) {
    final next = _stats.withRun(run);
    setState(() => _stats = next);
    _saved('stats', _store!.saveStats(next));
    _grantAchievements();
  }

  void _changeCustom(CustomSetup next) {
    setState(() => _custom = next);
    _saved('custom', _store!.saveCustom(next));
  }

  bool _gamePaused = false;

  void _setMusicPaused(bool paused) {
    if (_gamePaused != paused) setState(() => _gamePaused = paused);
    unawaited(_music.setPaused(paused));
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      unawaited(_music.stop());
    }
  }

  void _show(_Screen screen) {
    _setMusicPaused(false);
    _campaignCube = false;
    setState(() {
      _screen = screen;
      _settingsOpen = false;
    });
  }

  void _playCampaign() {
    final save = _savedRuns[ModeId.campaign];
    if (save != null) {
      _start(save.session, restore: save, resumeImmediately: true);
    } else {
      _start(CampaignSession(_progress.unlocked));
    }
  }

  void _start(Session session, {RunSave? restore, bool resumeImmediately = false}) {
    if (restore == null && !_tutorialDone) {
      _openTutorial(after: session);
      return;
    }
    final mode = modeOf(session);
    if (restore == null && _savedRuns[mode] != null) {
      _recordRun(_savedRuns[mode]!.abandoned());
      _checkpoint(mode, null);
    }
    _setMusicPaused(restore != null && !resumeImmediately);
    setState(() {
      _gameKey = GlobalKey<GameScreenState>();
      _restore = restore;
      _resumeImmediately = resumeImmediately;
      _tutorial = false;
      _settingsOpen = false;
      _session = session;
      _screen = _Screen.play;
    });
  }

  void _openTutorial({Session? after}) {
    _setMusicPaused(false);
    setState(() {
      _gameKey = GlobalKey<GameScreenState>();
      _restore = null;
      _afterTutorial = after;
      _tutorial = true;
      _settingsOpen = false;
      _session = CustomSession(defaultCustom.copyWith(extraGlasses: 0));
      _screen = _Screen.play;
    });
  }

  /// [played]: the player pressed Play on the last lesson rather than Skip.
  /// A tutorial opened from the menu then goes on into the campaign.
  void _finishTutorial(bool played) {
    _tutorialDone = true;
    _saved('tutorial', _store!.saveTutorial(true));
    if (played) _grantAchievements(also: const [lessonsPlayed]);
    final next = _afterTutorial;
    _afterTutorial = null;
    if (next != null) {
      _start(next);
    } else if (played) {
      _playCampaign();
    } else {
      _show(_Screen.home);
    }
  }

  void _retry(Session session) {
    _setMusicPaused(false);
    setState(() {
      _gameKey = GlobalKey<GameScreenState>();
      _restore = null;
      _session = session;
    });
  }

  /// A game is on the screen, flat or Cube.
  bool get _inGame => _screen == _Screen.play || _screen == _Screen.cubePlay;

  void _back() {
    if (_settingsOpen) {
      setState(() => _settingsOpen = false);
      return;
    }
    if (_screen == _Screen.play) {
      _gameKey.currentState?.handleBack();
      return;
    }
    if (_screen == _Screen.cubePlay) {
      _cubeKey.currentState?.handleBack();
      return;
    }
    if (_screen == _Screen.achievements) {
      _show(_Screen.statistics);
    } else if (_screen != _Screen.home) {
      _show(_Screen.home);
    }
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
          cubeProgress: _cubeProgress,
          hasSavedGames: _savedRuns.isNotEmpty || _cubeRuns.isNotEmpty,
          onResume: () => _show(_Screen.resume),
          onTutorial: () => _openTutorial(),
          tutorialDone: _tutorialDone,
          onCampaign: () => _show(_Screen.campaign),
          onCube: () => _show(_Screen.cube),
          onCustom: () => _show(_Screen.custom),
          onStatistics: () => _show(_Screen.statistics),
          onSettings: () => _show(_Screen.settings),
          music: _settings.audio.music || _settings.audio.sounds,
          onToggleMusic: _toggleMusic,
          onLanguage: (language) => _changeSettings(_settings.copyWith(language: language)),
        ),
        _Screen.resume => ResumeScreen(
          runs: _savedRuns,
          cubeRuns: _cubeRuns,
          onResumeCube: _resumeCube,
          onResume: (save) => _start(save.session, restore: save),
          onBack: () => _show(_Screen.home),
        ),
        _Screen.campaign => CampaignScreen(
          progress: _progress,
          cubeProgress: _cubeProgress,
          cubeSaved: _cubeRuns[CubeKind.campaign],
          onCubeStart: _startCube,
          onCubeResume: () => _resumeCube(CubeKind.campaign),
          cube: _campaignCube,
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
        _Screen.cube => CubeSetupScreen(
          settings: _settings,
          stats: _stats,
          colours: colours,
          onChange: (cube) => _changeSettings(_settings.copyWith(cube: cube)),
          onStart: () => _startCube(),
          saved: _cubeRuns[CubeKind.endless],
          onResume: () => _resumeCube(CubeKind.endless),
          onTutorial: () => _openCubeTutorial((game: false, level: null)),
          onBack: () => _show(_Screen.home),
        ),
        _Screen.cubePlay => CubeScreen(
          key: _cubeKey,
          settings: _settings,
          blocked: _settingsOpen,
          onSettings: () => setState(() => _settingsOpen = true),
          onToggleMusic: _toggleMusic,
          onPauseChanged: _setMusicPaused,
          onExit: () => _show(_Screen.home),
          onSetup: () => _show(_Screen.cube),
          onRetry: () => _playCube(_cubeLevel),
          onRecord: _recordRun,
          level: _cubeLevel,
          progress: _cubeProgress,
          onProgress: _changeCubeProgress,
          onLevels: () {
            _show(_Screen.campaign);
            _campaignCube = true;
          },
          onNextLevel: _playCube,
          restore: _cubeRestore,
          onCheckpoint: (save) => _cubeCheckpoint(kindOf(_cubeLevel), save),
          tutorial: _cubeTutorial,
          onTutorialDone: _finishCubeTutorial,
        ),
        _Screen.statistics => StatisticsScreen(
          stats: _stats,
          progress: _progress,
          cubeProgress: _cubeProgress,
          achievements: (earned: _achievements.count, total: achievements.length),
          onAchievements: () => _show(_Screen.achievements),
          onBack: () => _show(_Screen.home),
        ),
        _Screen.achievements => AchievementsScreen(
          log: _achievements,
          facts: _facts,
          onBack: () => _show(_Screen.statistics),
        ),
        _Screen.settings => SettingsScreen(
          settings: _settings,
          stored: _stored,
          onChange: _changeSettings,
          onBack: () => _show(_Screen.home),
        ),
        _Screen.play => GameScreen(
          key: _gameKey,
          restore: _restore,
          resumeImmediately: _resumeImmediately,
          onCheckpoint: (save) => _checkpoint(modeOf(_session!), save),
          tutorial: _tutorial,
          onTutorialDone: _finishTutorial,
          session: _session!,
          settings: _settings,
          progress: _progress,
          blocked: _settingsOpen,
          onPauseChanged: _setMusicPaused,
          onSettings: () => setState(() => _settingsOpen = true),
          onToggleMusic: _toggleMusic,
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

    final page = _inGame ? body : MenuWidth(child: body);
    final shell = PopScope(
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
              child: Backdrop(
                menu: !_inGame,
                paused: _settingsOpen || _gamePaused,
                animated: !_inGame || _settings.effects.fieldBackground,
              ),
            ),
            Positioned.fill(
              child: Column(
                children: [
                  // The game lays out its own column, so its dialogs still cover the whole window.
                  Expanded(
                    child: usesDesktopKeyboard
                        ? FocusScope(
                            key: ValueKey(_screen),
                            child: ExcludeFocus(excluding: _settingsOpen, child: page),
                          )
                        : page,
                  ),
                  if (!_stored)
                    SafeArea(
                      top: false,
                      child: Container(
                        color: Palette.panelStrong,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        child: Row(
                          children: [
                            const Expanded(
                              child: LText(
                                'Не удалось сохранить данные. Они пока доступны только в этой сессии.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            TextButton(onPressed: clicking(_retryStorage), child: const LText('Повторить')),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (_settingsOpen && _inGame && store != null)
              Positioned.fill(
                child: SettingsScreen(
                  overlay: true,
                  cube: _screen == _Screen.cubePlay,
                  settings: _settings,
                  stored: _stored,
                  onChange: _changeSettings,
                  onBack: () => setState(() => _settingsOpen = false),
                ),
              ),
            Positioned.fill(child: AchievementToast(toasts: _toasts)),
          ],
        ),
      ),
    );
    if (!usesDesktopKeyboard) return shell;
    return CallbackShortcuts(
      bindings: {
        if (_settingsOpen || (!_inGame && _screen != _Screen.home))
          const SingleActivator(LogicalKeyboardKey.escape): _back,
      },
      child: shell,
    );
  }
}
