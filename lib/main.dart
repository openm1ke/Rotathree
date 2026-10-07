import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/game_screen.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const RotathreeApp());
}

class RotathreeApp extends StatelessWidget {
  const RotathreeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Rotathree',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: NeonPalette.background,
        colorScheme: const ColorScheme.dark(
          primary: NeonPalette.outline,
          surface: NeonPalette.background,
        ),
      ),
      home: const GameScreen(),
    );
  }
}
