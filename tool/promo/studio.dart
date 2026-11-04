// The promo studio: the real app, drawn by its own code at a device's size
// inside a widget test, its games played by a script, its frames saved as
// PNG. See tool/promo/README.md.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// A screen the shots are made for, in physical pixels.
class Device {
  const Device(this.name, this.width, this.height, this.ratio);

  final String name;
  final int width, height;
  final double ratio;

  Size get physical => Size(width.toDouble(), height.toDouble());
}

/// App Store's 6.9-inch iPhone and 13-inch iPad, the sizes it asks for.
const iphone = Device('iphone-6.9', 1320, 2868, 3);
const ipad = Device('ipad-13', 2064, 2752, 2);

/// The app at the App Store preview's 886 × 1920.
const preview = Device('preview', 886, 1920, 2);

/// Exo 2 as the app bundles it, and the Material icons: tests draw boxes
/// for every letter until real fonts are loaded.
Future<void> loadFonts() async {
  const files = {
    'Exo2': ['Latin-400', 'Latin-600', 'Latin-800', 'Latin-800Italic', 'Latin-900Italic'],
    'Exo2Cyrillic': ['Cyrillic-400', 'Cyrillic-600', 'Cyrillic-800', 'Cyrillic-800Italic', 'Cyrillic-900Italic'],
  };
  for (final MapEntry(key: family, value: names) in files.entries) {
    final loader = FontLoader(family);
    for (final name in names) {
      loader.addFont(rootBundle.load('assets/fonts/Exo2-$name.ttf'));
    }
    await loader.load();
  }
  final flutter = File(Platform.resolvedExecutable).parent.parent.parent.parent.parent.parent.path;
  final icons = File('$flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final fallback = File('/opt/homebrew/share/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  final bytes = await (icons.existsSync() ? icons : fallback).readAsBytes();
  await (FontLoader('MaterialIcons')..addFont(Future.value(ByteData.sublistView(bytes)))).load();
}

/// Sets the test's screen to [device].
void useDevice(WidgetTester tester, Device device) {
  tester.view.physicalSize = device.physical;
  tester.view.devicePixelRatio = device.ratio;
}

/// The picture under [key], at [ratio] pixels to a logical pixel.
Future<ui.Image> capture(WidgetTester tester, GlobalKey key, double ratio) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  return (await tester.runAsync(() => boundary.toImage(pixelRatio: ratio)))!;
}

/// Writes [image] as a PNG, making its folder.
Future<void> savePng(WidgetTester tester, ui.Image image, String path) async {
  final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.png));
  File(path)
    ..parent.createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

/// Reads a picture from a file, for the backgrounds.
Future<ui.Image> loadImage(WidgetTester tester, String path) async {
  final bytes = File(path).readAsBytesSync();
  return (await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(bytes);
    return (await codec.getNextFrame()).image;
  }))!;
}

/// Lets real time pass for what the app reads from its store, then frames.
Future<void> settle(WidgetTester tester, {int frames = 20}) async {
  for (var i = 0; i < frames; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump(const Duration(milliseconds: 100));
  }
}
