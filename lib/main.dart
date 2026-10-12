import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ui/app.dart';
import 'ui/menu/licenses.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  registerAssetLicenses();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle.light);
  runApp(const RotathreeApp());
}
