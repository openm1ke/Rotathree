import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game_screen.dart';
import 'hud.dart';
import 'menu_screen.dart';
import 'settings/settings.dart';
import 'settings/settings_store.dart';
import 'settings_panel.dart';
import 'style.dart';
import 'widgets/backdrop.dart';

/// The whole app: the menu, the game it starts and the settings over either.
class RotathreeApp extends StatefulWidget {
  const RotathreeApp({super.key, this.store, this.seed});

  /// Where the settings are kept; the device's own storage by default.
  final SettingsStore? store;

  /// Fixes the order of the pieces (tests).
  final int? seed;

  @override
  State<RotathreeApp> createState() => _RotathreeAppState();
}

class _RotathreeAppState extends State<RotathreeApp> {
  late final SettingsStore _store = widget.store ?? DeviceSettingsStore();

  /// Null until the stored settings have been read.
  Settings? _settings;

  /// False once the device has refused to store the settings.
  bool _stored = true;

  /// The game being played; null on the menu.
  GameMode? _mode;
  bool _settingsOpen = false;

  // The rules cannot change under a running game: new options start a new
  // one, which is what a new key does.
  String? _gameId;
  GlobalKey<GameScreenState> _gameKey = GlobalKey<GameScreenState>();

  @override
  void initState() {
    super.initState();
    _store.load().then((settings) {
      if (mounted) setState(() => _settings = settings);
    });
  }

  /// Every change is written to the device at once.
  void _update(Settings next) {
    setState(() => _settings = next);
    _store.save(next).then((ok) {
      if (mounted && ok != _stored) setState(() => _stored = ok);
    });
  }

  /// The system "back": close what is on top, pause a running game, and only
  /// leave the app from the menu.
  void _back() {
    if (_settingsOpen) {
      setState(() => _settingsOpen = false);
    } else if (_mode != null) {
      final game = _gameKey.currentState;
      if (game != null && game.status == GameStatus.playing) {
        game.pause();
      } else {
        setState(() => _mode = null);
      }
    } else {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rotathree',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        fontFamily: Type.family,
        fontFamilyFallback: Type.fallback,
        scaffoldBackgroundColor: Palette.bg,
        colorScheme: const ColorScheme.dark(
          primary: Palette.accent,
          surface: Palette.bg,
        ),
        splashFactory: NoSplash.splashFactory,
      ),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.15,
        child: child!,
      ),
      home: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _back();
        },
        child: Scaffold(
          backgroundColor: Palette.bg,
          body: Stack(
            fit: StackFit.expand,
            children: [
              const Backdrop(),
              if (_settings != null) ..._buildScreens(_settings!),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildScreens(Settings settings) {
    final mode = _mode;
    final Widget screen;
    if (mode == null) {
      screen = MenuScreen(
        key: const ValueKey('menu'),
        onPlay: (mode) => setState(() => _mode = mode),
        onOpenSettings: () => setState(() => _settingsOpen = true),
      );
    } else {
      final id = '${mode.name}:${settings.game.key}';
      if (id != _gameId) {
        _gameId = id;
        _gameKey = GlobalKey<GameScreenState>();
      }
      screen = GameScreen(
        key: _gameKey,
        mode: mode,
        settings: settings,
        seed: widget.seed,
        blocked: _settingsOpen,
        onOpenSettings: () => setState(() => _settingsOpen = true),
        onExit: () => setState(() => _mode = null),
      );
    }
    return [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 380),
        switchInCurve: Motion.snap,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween(begin: 0.95, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        child: screen,
      ),
      if (_settingsOpen)
        SettingsPanel(
          settings: settings,
          stored: _stored,
          inGame: mode != null,
          onChanged: _update,
          onClose: () => setState(() => _settingsOpen = false),
        ),
    ];
  }
}
