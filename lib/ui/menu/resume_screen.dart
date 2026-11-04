import 'package:flutter/material.dart';
import '../../game/config/modes.dart';
import '../../game/session.dart';
import '../../cube/save.dart';
import '../data/run_save.dart';
import '../format.dart';
import '../widgets/controls.dart';

class ResumeScreen extends StatelessWidget {
  const ResumeScreen({
    super.key,
    required this.runs,
    required this.onResume,
    required this.onBack,
    this.cubeRuns = const {},
    this.onResumeCube,
  });
  final Map<ModeId, RunSave> runs;
  final ValueChanged<RunSave> onResume;
  final VoidCallback onBack;

  /// Cube's kept games: the endless one, a level.
  final Map<CubeKind, CubeSave> cubeRuns;
  final ValueChanged<CubeKind>? onResumeCube;
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
      for (final kind in CubeKind.values)
        if (cubeRuns[kind] case final CubeSave save)
          () {
            final record = save.abandoned();
            final mode = kind == CubeKind.endless ? ModeId.cube : ModeId.cubeCampaign;
            return Section(
              title: modeTitle(mode),
              note: '${save.level != null ? 'Уровень ${save.level! + 1} · ' : ''}'
                  '${formatPoints(record.score)} · ${formatDuration(record.seconds)}',
              children: [
                GoButton(label: 'Продолжить ${modeTitle(mode)}', expand: true, onPressed: () => onResumeCube?.call(kind)),
              ],
            );
          }(),
    ],
  );
}
