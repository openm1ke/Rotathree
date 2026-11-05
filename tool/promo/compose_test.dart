// The store screenshots, made from the raw shots in the key art's light:
// `flutter test tool/promo/compose_test.dart`. See tool/promo/README.md.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'captions.dart';
import 'look.dart';
import 'studio.dart';

const raw = 'build/promo/raw';
const out = 'build/promo/store';
const keyart = 'docs/marketing/keyart/rotathree-keyart-9x16-none.png';

/// A store's screenshot: its size, and the raw shots it is made from.
class Store {
  const Store(this.name, this.width, this.height, this.from);

  final String name;
  final int width, height;
  final Device from;
}

const stores = [
  Store('appstore-iphone-6.9', 1320, 2868, iphone),
  Store('appstore-ipad-13', 2064, 2752, ipad),
  Store('rustore-phone', 1080, 1920, iphone),
  Store('rustore-tablet', 1080, 1920, ipad),
];

/// Shots whose field is not in the middle across, by device: the cube
/// looked into sits left of the middle on a phone.
const _centres = {
  'iphone-6.9': {'cube-volume': 0.45, 'cube-lean': 0.4},
  // The hint over a held tip is at the left: it stays whole.
  'ipad-13': {'cube-lean': 0.4},
};

/// Screens that are lists: shown from their top, as wide as the window.
const _lists = {'campaign', 'achievements', 'settings-controls'};

/// One screenshot: the key art, dimmed, the words at the top, and right
/// under them a window of neon down to the bottom with the game as large as
/// it fits: the field enlarged, the pads under it, the empty room cut out.
class StoreShot extends StatelessWidget {
  const StoreShot({
    super.key,
    required this.size,
    required this.background,
    required this.shot,
    required this.caption,
    required this.layout,
    this.list = false,
    this.centre = 0.5,
  });

  final Size size;
  final ui.Image background, shot;
  final Caption caption;
  final ScreenLayout layout;
  final bool list;
  final double centre;

  @override
  Widget build(BuildContext context) {
    final base = size.width < size.height * 0.6 ? size.width : size.height * 0.6;
    final side = size.width * 0.03;
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          KeyartBackground(image: background),
          Padding(
            padding: EdgeInsets.fromLTRB(side, size.height * 0.03, side, size.height * 0.018),
            child: Column(
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
                  child: CaptionBlock(caption: caption, base: base),
                ),
                SizedBox(height: size.height * 0.022),
                Expanded(
                  child: NeonFrame(
                    base: base,
                    radius: base * 0.05,
                    child: LayoutBuilder(builder: (context, box) => _window(box.biggest)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _window(Size window) => GameWindow(shot: shot, layout: layout, window: window, list: list, centre: centre);
}


void main() {
  setUpAll(loadFonts);

  testWidgets('store screenshots', (tester) async {
    final background = await loadImage(tester, keyart);
    for (final store in stores) {
      final size = Size(store.width.toDouble(), store.height.toDouble());
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      for (final language in ['ru', 'en']) {
        if (store.name.startsWith('rustore') && language == 'en') continue;
        var index = 0;
        for (final MapEntry(key: name, value: words) in shots.entries) {
          index++;
          final path = '$raw/${store.from.name}/$language/$name.png';
          if (!File(path).existsSync()) continue;
          final shot = await loadImage(tester, path);
          final key = GlobalKey();
          await tester.pumpWidget(
            Directionality(
              textDirection: TextDirection.ltr,
              child: RepaintBoundary(
                key: key,
                child: StoreShot(
                  size: size,
                  background: background,
                  shot: shot,
                  caption: words[language]!,
                  layout: layouts[store.from.name]!,
                  list: _lists.contains(name),
                  centre: _centres[store.from.name]?[name] ?? 0.5,
                ),
              ),
            ),
          );
          await tester.pump();
          final image = await capture(tester, key, 1);
          await savePng(tester, image, '$out/${store.name}/$language/${index.toString().padLeft(2, '0')}-$name.png');
        }
      }
    }
  });
}
