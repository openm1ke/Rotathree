import 'package:flutter/material.dart';
import '../../game/config/modes.dart';
import '../../game/session.dart';
import '../data/run_save.dart';
import '../format.dart';
import '../widgets/controls.dart';

class ResumeScreen extends StatelessWidget {
  const ResumeScreen({super.key, required this.runs, required this.onResume, required this.onBack});
  final Map<ModeId, RunSave> runs;
  final ValueChanged<RunSave> onResume;
  final VoidCallback onBack;
  @override
  Widget build(BuildContext context) => ScreenFrame(
    kicker: 'Сохранённые игры',
    title: 'Продолжить',
    onBack: onBack,
    footer: 'Каждый режим сохраняется автоматически. Другие партии остаются на месте.',
    children: [
      for (final mode in [ModeId.campaign, ModeId.custom, ModeId.insane])
        if (runs[mode] case final RunSave save)
          Section(
            title: modeTitle(mode),
            note:
                '${save.session is CampaignSession ? 'Уровень ${(save.session as CampaignSession).level + 1} · ' : ''}${formatPoints(save.abandoned().score)} · ${formatDuration(save.abandoned().seconds)}',
            children: [GoButton(label: 'Продолжить ${modeTitle(mode)}', expand: true, onPressed: () => onResume(save))],
          ),
    ],
  );
}
