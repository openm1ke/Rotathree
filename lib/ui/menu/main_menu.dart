import '../i18n/language_picker.dart';
import '../i18n/strings.dart';
import 'package:flutter/material.dart';

import '../../game/config/campaign.dart';
import '../data/progress.dart';
import '../layout.dart';
import '../style.dart';
import '../widgets/controls.dart';
import '../widgets/completed_badge.dart';

/// The first screen: a column of large entries, the progress on the side.
class MainMenu extends StatelessWidget {
  const MainMenu({
    super.key,
    required this.progress,
    required this.onCampaign,
    required this.onPlayCampaign,
    this.campaignLevel,
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
  final VoidCallback onCampaign, onPlayCampaign;
  final int? campaignLevel;
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
    // The music and the other language stay in the corner; the menu scrolls under them.
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
    // A phone starts the menu at the top; a tablet centres it on the screen.
    if (!isTablet(size)) {
      return SafeArea(
        child: Column(
          children: [
            if (corners) corner,
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final squeeze = _squeeze(box.maxHeight);
                  return ListView(
                    padding: EdgeInsets.fromLTRB(18, corners ? 4 : 16, 18, _lerp(24, 12, squeeze)),
                    children: _items(context, squeeze),
                  );
                },
              ),
            ),
          ],
        ),
      );
    }
    return TabletScale(
      child: SafeArea(
        child: Column(
          children: [
            if (corners) corner,
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: box.maxHeight - 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _items(context, 0),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  bool get _continues => hasSavedGames && onResume != null;

  /// How much a low phone tightens the menu, from 0 (as drawn) to 1, so that
  /// all of it, "Continue" and the campaign card included, fits without
  /// scrolling, as on the web. The heights are those of the menu at 0 and at
  /// 1 with the system font size; a menu taller still scrolls.
  double _squeeze(double height) {
    var full = _MenuHeights.nav * (onTutorial != null ? 5 : 4) + _MenuHeights.logo + _MenuHeights.padding;
    var tight = _MenuHeights.navTight * (onTutorial != null ? 5 : 4) + _MenuHeights.logoTight + _MenuHeights.paddingTight;
    if (_continues) {
      full += _MenuHeights.resume;
      tight += _MenuHeights.resumeTight;
    }
    if (!progress.completed) {
      full += _MenuHeights.shortcut;
      tight += _MenuHeights.shortcutTight;
    }
    // Text lines do not shrink quite in step with their font: keep a few pixels spare.
    return ((full + 6 - height) / (full - tight)).clamp(0.0, 1.0);
  }

  List<Widget> _items(BuildContext context, double squeeze) {
    final level = campaignLevel ?? progress.unlocked;
    final s = tabletScale(MediaQuery.sizeOf(context));
    return [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final colour in classicColours)
            Container(
              width: _lerp(12, 10, squeeze) * s,
              height: _lerp(12, 10, squeeze) * s,
              margin: EdgeInsets.symmetric(horizontal: 3 * s),
              decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(3 * s)),
            ),
        ],
      ),
      SizedBox(height: _lerp(14, 8, squeeze)),
      Text.rich(
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
      SizedBox(height: _lerp(24, 14, squeeze)),
      if (_continues) ...[
        GoButton(label: 'Продолжить', expand: true, onPressed: onResume),
        SizedBox(height: _lerp(12, 8, squeeze)),
      ],
      if (onTutorial != null)
        _NavItem(
          title: 'Обучение',
          caption: tutorialDone ? 'Повторить основы' : 'Правила на практике',
          onTap: onTutorial!,
          squeeze: squeeze,
        ),
      _NavItem(title: 'Кампания', caption: '16 уровней', onTap: onCampaign, completed: progress.completed, squeeze: squeeze),
      _NavItem(title: 'Кастом', caption: 'Ваши правила', onTap: onCustom, squeeze: squeeze),
      _NavItem(title: 'Статистика', caption: 'Результаты и рекорды', onTap: onStatistics, squeeze: squeeze),
      _NavItem(title: 'Настройки', caption: 'Управление и оформление', onTap: onSettings, squeeze: squeeze),
      if (!progress.completed) ...[
        SizedBox(height: _lerp(16, 6, squeeze)),
        _CampaignShortcut(
          key: const ValueKey('campaign-shortcut'),
          level: level,
          onTap: onPlayCampaign,
          squeeze: squeeze,
        ),
      ],
    ];
  }
}

double _lerp(double full, double tight, double squeeze) => full + (tight - full) * squeeze;

/// Heights of the phone menu's parts, gaps included, with Exo 2 at the
/// system font size: as drawn, and at their tightest. test/ui/main_menu_test.dart
/// checks them against the menu itself.
abstract final class _MenuHeights {
  static const logo = 96.0, logoTight = 68.0;
  static const nav = 76.0, navTight = 58.0;
  static const resume = 55.0, resumeTight = 51.0;
  static const shortcut = 96.0, shortcutTight = 74.0;
  static const padding = 28.0, paddingTight = 16.0;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.title,
    required this.caption,
    required this.onTap,
    this.completed = false,
    this.squeeze = 0,
  });

  final String title;
  final String caption;
  final VoidCallback onTap;
  final bool completed;
  final double squeeze;

  @override
  Widget build(BuildContext context) {
    final s = tabletScale(MediaQuery.sizeOf(context));
    return Padding(
      padding: EdgeInsets.only(bottom: _lerp(10, 6, squeeze) * s),
      child: Material(
        color: Palette.panel,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14 * s),
          side: const BorderSide(color: Palette.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(14 * s),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: _lerp(14, 8, squeeze) * s),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: completed
                            ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                                child: LText(title, style: Type.display(_lerp(22, 20, squeeze))))
                            : LText(title, style: Type.display(_lerp(22, 20, squeeze)))),
                        if (completed) ...[
                          const SizedBox(width: 12),
                          const CompletedBadge(),
                        ],
                      ]),
                      LText(caption, style: Type.body(12, color: Palette.textDim)),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: Palette.textDim, size: 24 * s),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CampaignShortcut extends StatelessWidget {
  const _CampaignShortcut({super.key, required this.level, required this.onTap, this.squeeze = 0});
  final int level;
  final VoidCallback onTap;
  final double squeeze;

  @override
  Widget build(BuildContext context) {
    final s = tabletScale(MediaQuery.sizeOf(context));
    return Semantics(
      button: true,
      label: context.tr('Продолжить кампанию'),
      child: Material(
        color: Palette.panel,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14 * s), side: const BorderSide(color: Palette.line)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14 * s),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 14 * s, vertical: _lerp(14, 10, squeeze) * s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LText('КАМПАНИЯ', style: Type.label(11, color: Palette.accent)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: LText('уровень ${level + 1} из ${campaignLevels.length}', style: Type.body(15, weight: FontWeight.w800))),
                Icon(Icons.chevron_right_rounded, color: Palette.accent, size: 20 * s),
              ]),
              SizedBox(height: _lerp(10, 6, squeeze) * s),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: Stack(children: [
                  Container(height: 6 * s, color: Palette.line),
                  FractionallySizedBox(widthFactor: (level / campaignLevels.length).clamp(0.0, 1.0),
                    child: Container(height: 6 * s, color: Palette.accent)),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
