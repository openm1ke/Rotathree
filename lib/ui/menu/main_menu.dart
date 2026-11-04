import '../i18n/language_picker.dart';
import '../i18n/strings.dart';
import 'package:flutter/material.dart';

import '../../game/config/campaign.dart';
import '../data/progress.dart';
import '../layout.dart';
import '../style.dart';
import '../widgets/controls.dart';
import '../audio/sound_effects.dart';

/// The classic set's colours for the tiles' little pictures (MainMenu.tsx).
const _red = 0, _blue = 1, _yellow = 2, _green = 3, _violet = 4, _orange = 6;

/// How a block of a tile's picture is drawn: whole, see-through, or as a thin
/// line across its row, under the blocks.
enum _Look { solid, faint, track }

/// A picture made of the game's own blocks: column, row and colour on a
/// three-by-three grid.
typedef _Block = (double x, double y, int colour, _Look look);

const _pictures = <String, List<_Block>>{
  // A play sign, stacked.
  'resume': [(0, 0, _green, _Look.solid), (0, 1, _green, _Look.solid), (0, 2, _green, _Look.solid),
      (1, 0.5, _green, _Look.solid), (1, 1.5, _green, _Look.solid), (2, 1, _green, _Look.solid)],
  // Three in a row, the game in one picture.
  'campaign': [(0, 2, _red, _Look.solid), (1, 2, _red, _Look.solid), (2, 2, _red, _Look.solid), (1, 1, _blue, _Look.solid)],
  // A cube: its front, and its back showing behind.
  'cube': [(1, 0, _blue, _Look.faint), (2, 0, _blue, _Look.faint), (2, 1, _blue, _Look.faint),
      (0, 1, _blue, _Look.solid), (1, 1, _blue, _Look.solid), (0, 2, _blue, _Look.solid), (1, 2, _blue, _Look.solid)],
  // A stick of three colours, as the player sets them.
  'custom': [(1, 0, _yellow, _Look.solid), (1, 1, _green, _Look.solid), (1, 2, _violet, _Look.solid)],
  // A stick coming down into the gap that makes the line.
  'tutorial': [(1, 0, _green, _Look.solid), (0, 2, _green, _Look.solid), (2, 2, _green, _Look.solid), (1, 2, _green, _Look.faint)],
  // Columns growing: the records.
  'statistics': [(0, 2, _violet, _Look.solid), (1, 2, _violet, _Look.solid), (1, 1, _violet, _Look.solid),
      (2, 2, _violet, _Look.solid), (2, 1, _violet, _Look.solid), (2, 0, _violet, _Look.solid)],
  // Three sliders, each set somewhere else.
  'settings': [(0, 0, _orange, _Look.track), (0, 1, _orange, _Look.track), (0, 2, _orange, _Look.track),
      (2, 0, _orange, _Look.solid), (0, 1, _orange, _Look.solid), (1, 2, _orange, _Look.solid)],
};

/// The first screen, as on the web: a tile for each way to play, with a
/// picture made of the game's blocks and a line that says where the player
/// is; the records and the settings side by side under them.
class MainMenu extends StatelessWidget {
  const MainMenu({
    super.key,
    required this.progress,
    required this.onCampaign,
    required this.onCustom,
    required this.onStatistics,
    required this.onSettings,
    this.hasSavedGames = false,
    this.onResume,
    this.onTutorial,
    this.tutorialDone = false,
    this.music = true,
    this.onToggleMusic,
    this.onLanguage,
  });

  final Progress progress;
  final VoidCallback onCampaign;
  final VoidCallback onCustom;
  final VoidCallback onStatistics;
  final VoidCallback onSettings;
  final bool hasSavedGames;
  final VoidCallback? onResume, onTutorial;
  final bool tutorialDone;
  final bool music;
  final VoidCallback? onToggleMusic;
  final ValueChanged<LanguageChoice>? onLanguage;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final s = tabletScale(size);
    // The music and the other language stay in the corner.
    final corner = Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (onToggleMusic != null)
            SoundButton(on: music, onToggle: onToggleMusic!, size: 38, background: Palette.panelStrong),
          if (onToggleMusic != null && onLanguage != null) const SizedBox(width: 8),
          if (onLanguage != null) LanguageSwitch(onChanged: onLanguage!),
        ],
      ),
    );
    final corners = onToggleMusic != null || onLanguage != null;
    return SafeArea(
      child: Column(
        children: [
          if (corners)
            SizedBox(
              height: 50 * s,
              child: Align(
                alignment: Alignment.topRight,
                child: Transform.scale(scale: s, alignment: Alignment.topRight, child: corner),
              ),
            ),
          Expanded(
            child: TabletScale(
              child: LayoutBuilder(
                builder: (context, box) {
                  // One column on an upright phone, two where there is room
                  // or too little height for one.
                  final columns = size.width / s <= 520 && size.height / s >= 560 ? 1 : 2;
                  final rows = _rows(columns);
                  final squeeze = _squeeze(box.maxHeight / s, rows.length);
                  return SingleChildScrollView(
                    padding: EdgeInsets.symmetric(horizontal: 18 * s, vertical: _lerp(14, 8, squeeze) * s),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minHeight: box.maxHeight - 2 * _lerp(14, 8, squeeze) * s),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: 680 * s),
                          child: _menu(rows, squeeze, s),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool get _continues => hasSavedGames && onResume != null;

  /// The tiles, row by row: Continue across the whole width, the ways to
  /// play one or two to a row (an odd last one across), then the records
  /// and the settings side by side.
  List<List<Widget>> _rows(int columns) {
    final levels = campaignLevels.length;
    final campaign = progress.completed
        ? 'пройдена · Кошмар открыт'
        : 'уровень ${progress.unlocked + 1} из $levels';
    final ways = <Widget>[
      _Tile(
        key: const ValueKey('menu-campaign'),
        title: 'Кампания',
        caption: campaign,
        picture: 'campaign',
        done: progress.completed ? 1 : progress.unlocked / levels,
        onTap: onCampaign,
      ),
      _Tile(key: const ValueKey('menu-custom'), title: 'Кастом', caption: 'Ваши правила', picture: 'custom', onTap: onCustom),
      if (onTutorial != null)
        _Tile(
          key: const ValueKey('menu-tutorial'),
          title: 'Обучение',
          caption: tutorialDone ? 'Повторить основы' : 'Правила на практике',
          picture: 'tutorial',
          onTap: onTutorial!,
        ),
    ];
    return [
      if (_continues)
        [_Tile(key: const ValueKey('menu-resume'), title: 'Продолжить', caption: 'Сохранённые игры', picture: 'resume', accent: true, onTap: onResume!)],
      for (var i = 0; i < ways.length; i += columns) ways.sublist(i, (i + columns).clamp(0, ways.length)),
      [
        _Tile(key: const ValueKey('menu-statistics'), title: 'Статистика', picture: 'statistics', small: true, onTap: onStatistics),
        _Tile(key: const ValueKey('menu-settings'), title: 'Настройки', picture: 'settings', small: true, onTap: onSettings),
      ],
    ];
  }

  /// How much a low screen tightens the menu, from 0 (as drawn) to 1, so that
  /// all of it, Continue included, fits without scrolling. A menu taller
  /// still scrolls.
  double _squeeze(double height, int rows) {
    double total(double squeeze) =>
        2 * _lerp(14, 8, squeeze) + _MenuHeights.logo(squeeze) + rows * _MenuHeights.tile(squeeze) + (rows - 1) * _MenuHeights.gap(squeeze);
    final full = total(0), tight = total(1);
    return ((full - height) / (full - tight)).clamp(0.0, 1.0);
  }

  Widget _menu(List<List<Widget>> rows, double squeeze, double s) {
    final gap = _MenuHeights.gap(squeeze) * s;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: _MenuHeights.logo(squeeze) * s,
          child: Center(
            child: Text.rich(
              TextSpan(
                style: Type.display(_lerp(46, 36, squeeze), spacing: 1),
                children: const [
                  TextSpan(text: 'ROTA'),
                  TextSpan(text: 'T', style: TextStyle(color: Palette.brandRed)),
                  TextSpan(text: 'H', style: TextStyle(color: Palette.brandBlue)),
                  TextSpan(text: 'R', style: TextStyle(color: Palette.brandYellow)),
                  TextSpan(text: 'E', style: TextStyle(color: Palette.brandGreen)),
                  TextSpan(text: 'E', style: TextStyle(color: Palette.brandViolet)),
                ],
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        for (final (index, row) in rows.indexed) ...[
          if (index > 0) SizedBox(height: gap),
          SizedBox(
            height: _MenuHeights.tile(squeeze) * s,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, tile) in row.indexed) ...[
                  if (i > 0) SizedBox(width: gap),
                  Expanded(child: _Squeezed(squeeze: squeeze, child: tile)),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}

double _lerp(double full, double tight, double squeeze) => full + (tight - full) * squeeze;

/// Heights of the menu's parts on a phone, as drawn and at their tightest;
/// a tablet scales them by its factor.
abstract final class _MenuHeights {
  static double logo(double squeeze) => _lerp(86, 56, squeeze);
  static double tile(double squeeze) => _lerp(76, 54, squeeze);
  static double gap(double squeeze) => _lerp(10, 6, squeeze);
}

/// Hands the menu's squeeze down to its tiles.
class _Squeezed extends InheritedWidget {
  const _Squeezed({required this.squeeze, required super.child});
  final double squeeze;

  static double of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_Squeezed>()?.squeeze ?? 0;

  @override
  bool updateShouldNotify(_Squeezed old) => old.squeeze != squeeze;
}

/// One way into the game. `done`: how much of its campaign is played, as a
/// thin bar under the line.
class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.title,
    this.caption,
    required this.picture,
    this.done,
    this.small = false,
    this.accent = false,
    required this.onTap,
  });

  final String title;
  final String? caption;
  final String picture;
  final double? done;
  final bool small, accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = tabletScale(MediaQuery.sizeOf(context));
    final squeeze = _Squeezed.of(context);
    final narrow = MediaQuery.sizeOf(context).width / s < 360;
    final title = Text(
      context.tr(this.title).toUpperCase(),
      maxLines: 1,
      softWrap: false,
      style: Type.display(small ? _lerp(18, 15, squeeze) : _lerp(22, 18, squeeze), color: Palette.accent),
    );
    return Semantics(
      button: true,
      label: [context.tr(this.title), if (caption != null) context.tr(caption!)].join(', '),
      excludeSemantics: true,
      child: Material(
        color: accent ? const Color(0x1478CDFF) : const Color(0x09FFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14 * s),
          side: const BorderSide(color: Palette.lineStrong),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14 * s),
          onTap: clicking(onTap),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: (small ? 12 : 16) * s, vertical: 6 * s),
            child: Row(
              children: [
                // A small tile on the narrowest phones gives its picture's room to the name.
                if (!(small && narrow)) ...[
                  _BlockPicture(
                    blocks: _pictures[picture]!,
                    size: (small ? _lerp(30, 26, squeeze) : _lerp(44, 32, squeeze)) * s,
                  ),
                  SizedBox(width: (small ? 10 : 14) * s),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: title),
                      if (caption != null) ...[
                        SizedBox(height: _lerp(4, 2, squeeze)),
                        LText(caption!, maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: Type.body(_lerp(13, 11.5, squeeze), color: Palette.textDim, height: 1.15)),
                      ],
                      if (done != null) ...[
                        SizedBox(height: _lerp(6, 3, squeeze)),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(3),
                          child: Stack(children: [
                            Container(height: 3 * s, color: const Color(0x1AFFFFFF)),
                            FractionallySizedBox(
                              widthFactor: done!.clamp(0.0, 1.0),
                              child: Container(height: 3 * s, color: Palette.accent),
                            ),
                          ]),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A tile's picture: blocks with the bevel of the game's own, on a
/// three-by-three grid.
class _BlockPicture extends StatelessWidget {
  const _BlockPicture({required this.blocks, required this.size});

  final List<_Block> blocks;
  final double size;

  @override
  Widget build(BuildContext context) =>
      SizedBox.square(dimension: size, child: CustomPaint(painter: _BlocksPainter(blocks)));
}

class _BlocksPainter extends CustomPainter {
  _BlocksPainter(this.blocks);

  final List<_Block> blocks;

  @override
  void paint(Canvas canvas, Size size) {
    final unit = size.width;
    final side = unit * 0.31;
    // Tracks first: the blocks sit on them.
    for (final (x, y, colour, _) in blocks.where((b) => b.$4 == _Look.track)) {
      final rect = Rect.fromLTWH(x * unit * 0.34, y * unit * 0.34 + unit * 0.11, unit, unit * 0.09);
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(rect.height / 2)),
        Paint()..color = classicColours[colour].withValues(alpha: 0.35),
      );
    }
    for (final (x, y, colour, look) in blocks.where((b) => b.$4 != _Look.track)) {
      final rect = Rect.fromLTWH(x * unit * 0.34, y * unit * 0.34, side, side);
      final shape = RRect.fromRectAndRadius(rect, Radius.circular(side * 0.22));
      final tones = BlockTones.fromBase(classicColours[colour]);
      final alpha = look == _Look.faint ? 0.32 : 1.0;
      final bevel = (side * 0.1).clamp(1.0, 2.0);
      canvas.save();
      canvas.clipRRect(shape);
      canvas.drawRect(rect, Paint()..color = tones.base.withValues(alpha: alpha));
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.top, rect.width, bevel), Paint()..color = tones.light.withValues(alpha: alpha));
      canvas.drawRect(Rect.fromLTWH(rect.left, rect.bottom - bevel, rect.width, bevel), Paint()..color = tones.dark.withValues(alpha: alpha));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_BlocksPainter old) => old.blocks != blocks;
}
