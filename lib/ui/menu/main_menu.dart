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

  @override
  Widget build(BuildContext context) {
    final level = campaignLevel ?? progress.unlocked;
    final size = MediaQuery.sizeOf(context);
    final s = tabletScale(size);
    final items = <Widget>[
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final colour in classicColours)
            Container(
              width: 12 * s,
              height: 12 * s,
              margin: EdgeInsets.symmetric(horizontal: 3 * s),
              decoration: BoxDecoration(color: colour, borderRadius: BorderRadius.circular(3 * s)),
            ),
        ],
      ),
      const SizedBox(height: 14),
      Text.rich(
        TextSpan(
          style: Type.display(46, spacing: 1),
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
      const SizedBox(height: 24),
      if (hasSavedGames && onResume != null) ...[
        GoButton(label: 'Продолжить', expand: true, onPressed: onResume),
        const SizedBox(height: 12),
      ],
      if (onTutorial != null)
        _NavItem(
          title: 'Обучение',
          caption: tutorialDone ? 'Повторить основы' : 'Правила на практике',
          onTap: onTutorial!,
        ),
      _NavItem(title: 'Кампания', caption: '16 уровней', onTap: onCampaign, completed: progress.completed),
      _NavItem(title: 'Кастом', caption: 'Ваши правила', onTap: onCustom),
      _NavItem(title: 'Статистика', caption: 'Результаты и рекорды', onTap: onStatistics),
      _NavItem(title: 'Настройки', caption: 'Управление и оформление', onTap: onSettings),
      if (!progress.completed) ...[
        const SizedBox(height: 16),
        _CampaignShortcut(
          key: const ValueKey('campaign-shortcut'),
          level: level,
          onTap: onPlayCampaign,
        ),
      ],
    ];
    // A phone starts the menu at the top; a tablet centres it on the screen.
    if (!isTablet(size)) {
      return SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
          children: items,
        ),
      );
    }
    return TabletScale(
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, box) => SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight - 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: items,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.title, required this.caption, required this.onTap, this.completed = false});

  final String title;
  final String caption;
  final VoidCallback onTap;
  final bool completed;

  @override
  Widget build(BuildContext context) {
    final s = tabletScale(MediaQuery.sizeOf(context));
    return Padding(
      padding: EdgeInsets.only(bottom: 10 * s),
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
            padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 14 * s),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(child: completed
                            ? FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
                                child: LText(title, style: Type.display(22)))
                            : LText(title, style: Type.display(22))),
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
  const _CampaignShortcut({super.key, required this.level, required this.onTap});
  final int level;
  final VoidCallback onTap;

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
            padding: EdgeInsets.all(14 * s),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              LText('КАМПАНИЯ', style: Type.label(11, color: Palette.accent)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: LText('уровень ${level + 1} из ${campaignLevels.length}', style: Type.body(15, weight: FontWeight.w800))),
                Icon(Icons.chevron_right_rounded, color: Palette.accent, size: 20 * s),
              ]),
              SizedBox(height: 10 * s),
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
