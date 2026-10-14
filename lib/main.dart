import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/app.dart';
import 'ui/layout.dart';
import 'ui/menu/licenses.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerAssetLicenses();
  SystemChrome.setPreferredOrientations(_orientations());
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const RotathreeApp());
}

/// Phones stay upright; tablets turn with the device.
List<DeviceOrientation> _orientations() {
  final view = PlatformDispatcher.instance.views.first;
  final size = view.physicalSize / view.devicePixelRatio;
  return isTablet(size) ? DeviceOrientation.values : const [DeviceOrientation.portraitUp];
}
