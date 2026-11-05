// The video's frames, cut from the reel's raw frames in the key art's light:
// `flutter test tool/promo/video_test.dart`, then tool/promo/encode.sh.
// See tool/promo/README.md.
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'captions.dart';
import 'look.dart';
import 'studio.dart';

const reel = 'build/promo/reel';
const out = 'build/promo/video';
const plainArt = 'docs/marketing/keyart/rotathree-keyart-9x16-none.png';

/// What the footage says, in turn, in frames: the cross says two things,
/// and each change of game takes [_fade] frames from the one before.
const _words = <String, List<(int, Caption)>>{
  'ru': [
    (150, Caption('Головоломка', 'Поверни стакан', 'Четыре стакана вокруг одного центра')),
    (110, Caption('Каскады', 'Собери три', 'Линии лопаются — всё сверху осыпается')),
    (95, Caption('Испытание', 'Кошмар', 'Шесть цветов, и скорость растёт')),
    (90, Caption('Новый режим', 'Куб · 3D', 'Шесть стаканов вокруг куба')),
    (75, Caption('Куб', 'Опрокинь куб', 'Глубина станет новой картинкой')),
    (75, Caption('Куб', 'Загляни в объём', 'Видно всё, что лежит внутри')),
  ],
  'en': [
    (150, Caption('Puzzle', 'Turn the glass', 'Four glasses around one centre')),
    (110, Caption('Cascades', 'Match three', 'Lines pop, everything above falls')),
    (95, Caption('Challenge', 'Nightmare', 'Six colours and rising speed')),
    (90, Caption('New mode', 'Cube · 3D', 'Six glasses around a cube')),
    (75, Caption('Cube', 'Tip the cube', 'Its depth becomes the new picture')),
    (75, Caption('Cube', 'Look inside', 'See everything that lies in its depth')),
  ],
};

/// The games filmed, each a run of scenes, in turn.
const _games = [
  ['cross'],
  ['nightmare'],
  ['cube', 'tip', 'volume'],
];

/// Frames a cross-fade takes, from one game to the next.
const _fade = 10;

/// A frame of the reel: which raw frame, and what to blend into it.
class _Shot {
  _Shot(this.path, {this.under, this.mix = 1});

  final String path;
  final String? under;
  final double mix;
}

/// The reel's raw frames in order, each game cross-fading into the next.
List<_Shot> _footage(String language) {
  List<String> frames(String scene) =>
      (Directory('$reel/$language/$scene').listSync().map((f) => f.path).toList()..sort());
  final shots = <_Shot>[];
  List<String>? last;
  for (final game in _games) {
    final now = [for (final scene in game) ...frames(scene)];
    if (last != null) {
      shots.removeRange(shots.length - _fade, shots.length);
      for (var i = 0; i < _fade; i++) {
        shots.add(_Shot(now[i], under: last[last.length - _fade + i], mix: (i + 1) / (_fade + 1)));
      }
      shots.addAll(now.skip(_fade).map(_Shot.new));
    } else {
      shots.addAll(now.map(_Shot.new));
    }
    last = now;
  }
  return shots;
}

/// The caption on frame [i] of the footage, and how far it has faded in.
(Caption, double) _captionAt(String language, int i) {
  var start = 0;
  final parts = _words[language]!;
  for (final (length, caption) in parts) {
    if (i < start + length || identical(caption, parts.last.$2)) {
      final into = i - start;
      final left = start + length - i;
      return (caption, math.min(1.0, math.min((into + 1) / 8, left / 6)).clamp(0.0, 1.0));
    }
    start += length;
  }
  return (parts.last.$2, 1);
}

class _Caption extends StatelessWidget {
  const _Caption({required this.caption, required this.shown, required this.base});

  final Caption caption;
  final double shown, base;

  @override
  Widget build(BuildContext context) => Opacity(
    opacity: shown,
    child: Transform.translate(offset: Offset(0, (1 - shown) * base * 0.03), child: CaptionBlock(caption: caption, base: base)),
  );
}

/// A frame of footage as the screenshots show the game: the key art, the
/// words at the top, under them the game large in a window of neon.
Widget _framed(Size size, Caption caption, double shown, Widget Function(Size window) game, ui.Image art) {
  final base = math.min(size.width, size.height * 0.6);
  final side = size.width * 0.03;
  return Stack(
    fit: StackFit.expand,
    children: [
      KeyartBackground(image: art),
      Padding(
        padding: EdgeInsets.fromLTRB(side, size.height * 0.03, side, size.height * 0.018),
        child: Column(
          children: [
            Padding(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
              child: _Caption(caption: caption, shown: shown, base: base),
            ),
            SizedBox(height: size.height * 0.022),
            Expanded(
              child: NeonFrame(
                base: base,
                radius: base * 0.05,
                child: LayoutBuilder(builder: (context, box) => game(box.biggest)),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

void main() {
  setUpAll(loadFonts);

  Future<ui.Image> raw(WidgetTester tester, String path) => loadImage(tester, path);

  Future<void> render(WidgetTester tester, Size size, String name, int count, Future<Widget> Function(int i) frameAt) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    final dir = Directory('$out/$name');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    for (var i = 0; i < count; i++) {
      final key = GlobalKey();
      await tester.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(key: key, child: SizedBox.fromSize(size: size, child: await frameAt(i))),
      ));
      await savePng(tester, await capture(tester, key, 1), '${dir.path}/${i.toString().padLeft(4, '0')}.png');
    }
  }

  /// The footage frame [shot] in the game window, its under-frame blended in.
  Future<Widget Function(Size window)> footage(WidgetTester tester, _Shot shot) async {
    final top = await raw(tester, shot.path);
    final under = shot.under == null ? null : await raw(tester, shot.under!);
    Widget show(ui.Image image, Size window) => GameWindow(shot: image, layout: layouts['iphone-6.9']!, window: window);
    return (window) => under == null
        ? show(top, window)
        : Stack(fit: StackFit.expand, children: [show(under, window), Opacity(opacity: shot.mix, child: show(top, window))]);
  }

  // App Store's preview: the game as the screenshots show it, large.
  for (final language in ['ru', 'en']) {
    testWidgets('preview $language', (tester) async {
      final shots = _footage(language);
      final art = await loadImage(tester, plainArt);
      const size = Size(886, 1920);
      await render(tester, size, 'preview-$language', shots.length, (i) async {
        final (caption, shown) = _captionAt(language, i);
        return _framed(size, caption, shown, await footage(tester, shots[i]), art);
      });
    });
  }

  // The promo for RuStore and the feeds: the footage as the preview shows
  // it, a title before and the key art after.
  testWidgets('promo ru', (tester) async {
    const size = Size(1080, 1920);
    final shots = _footage('ru');
    final art = await loadImage(tester, plainArt);
    const title = 54, ending = 78;
    await render(tester, size, 'promo-ru', title + shots.length + ending, (i) async {
      if (i < title) {
        final shown = math.min(1.0, (i + 1) / 10);
        return Stack(fit: StackFit.expand, children: [
          KeyartBackground(image: art, zoom: 1 + i * 0.0008),
          Opacity(
            opacity: shown,
            child: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Wordmark(size: 150),
                const SizedBox(height: 34),
                Text.rich(
                  TextSpan(children: [
                    TextSpan(text: 'Поверни', style: exo(60, FontWeight.w900, italic: true, color: cyan)),
                    TextSpan(text: ' стакан. ', style: exo(60, FontWeight.w800, italic: true)),
                    TextSpan(text: 'Собери', style: exo(60, FontWeight.w900, italic: true, color: cyan)),
                    TextSpan(text: ' три.', style: exo(60, FontWeight.w800, italic: true)),
                  ]),
                ),
                const SizedBox(height: 70),
                Text('НОВОЕ: КУБ · 3D', style: exo(40, FontWeight.w800, color: pink, spacing: 6, glow: [
                  Shadow(color: pink.withValues(alpha: 0.7), blurRadius: 24),
                ])),
              ]),
            ),
          ),
        ]);
      }
      final f = i - title;
      if (f >= shots.length) {
        final e = f - shots.length;
        return Stack(fit: StackFit.expand, children: [
          KeyartBackground(image: art, zoom: 1.04 - e * 0.0005, dim: false),
          // Darker at the bottom, under the words, as the key art has it.
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [navy.withValues(alpha: 0), navy.withValues(alpha: 0.85)],
                stops: const [0.5, 0.95],
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 230,
            child: Column(children: [
              const Wordmark(size: 132),
              const SizedBox(height: 22),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: 'Поверни', style: exo(52, FontWeight.w900, italic: true, color: cyan)),
                  TextSpan(text: ' стакан. ', style: exo(52, FontWeight.w800, italic: true)),
                  TextSpan(text: 'Собери', style: exo(52, FontWeight.w900, italic: true, color: cyan)),
                  TextSpan(text: ' три.', style: exo(52, FontWeight.w800, italic: true)),
                ]),
              ),
            ]),
          ),
          Opacity(opacity: (1 - math.min(1.0, (e + 1) / 12)).clamp(0.0, 1.0).toDouble(), child: const ColoredBox(color: navy)),
          if (e > ending - 12) Opacity(opacity: ((e - (ending - 12)) / 12).clamp(0.0, 1.0).toDouble(), child: const ColoredBox(color: Colors.black)),
        ]);
      }
      final (caption, shown) = _captionAt('ru', f);
      return Stack(fit: StackFit.expand, children: [
        _framed(size, caption, shown, await footage(tester, shots[f]), art),
        if (f < 8) Opacity(opacity: 1 - (f + 1) / 9, child: const ColoredBox(color: navy)),
      ]);
    });
  });
}
