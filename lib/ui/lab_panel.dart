import 'package:flutter/material.dart';

import '../game/config/game_config.dart';
import '../game/sim/bot_player.dart';
import 'neon_widgets.dart';
import 'theme.dart';

/// What the lab panel edits: the game rules plus an optional auto-player.
@immutable
class LabSettings {
  const LabSettings({this.config = const GameConfig(), this.bot});

  final GameConfig config;

  /// When set, this bot plays instead of the person (for watching the pace).
  final BotProfile? bot;

  /// One-line description for the status bar and screenshots.
  String get summary {
    final c = config;
    String seconds(double value) =>
        value == value.roundToDouble() ? value.toStringAsFixed(0) : '$value';
    return [
      '${seconds(c.activeStepSeconds)}s/${seconds(c.inactiveStepSeconds)}s',
      '${c.numberOfColors} colours',
      if (c.armLength != const GameConfig().armLength) 'arm ${c.armLength}',
      if (c.settleAfterBoardRotation) 'settle on turn',
      if (c.gravityScope == GravityScope.aboveCleared) 'local gravity',
      if (!c.pauseIncomingDuringCascade) 'no cascade pause',
      if (c.timeScale != 1) '×${c.timeScale} time',
      if (bot != null) 'bot: ${bot!.name}',
    ].join(' · ');
  }
}

/// Runtime tuning of the experiment: the values the design brief asks to
/// compare (travel time, colour count, re-settling) without rebuilding.
class LabPanel extends StatefulWidget {
  const LabPanel({
    super.key,
    required this.settings,
    required this.canResume,
    required this.onResume,
    required this.onApply,
  });

  final LabSettings settings;

  /// False when there is no running game to return to.
  final bool canResume;
  final VoidCallback onResume;
  final ValueChanged<LabSettings> onApply;

  @override
  State<LabPanel> createState() => _LabPanelState();
}

class _LabPanelState extends State<LabPanel> {
  late GameConfig _config = widget.settings.config;
  late BotProfile? _bot = widget.settings.bot;

  void _set(GameConfig config) => setState(() => _config = config);

  @override
  Widget build(BuildContext context) {
    return NeonPanel(
      maxWidth: 380,
      children: [
        const PanelTitle('LAB'),
        const SizedBox(height: 14),
        _Choice<double>(
          label: 'ONE STEP IN THE ACTIVE GLASS EVERY',
          value: _config.activeStepSeconds,
          options: const [
            (0.5, '0.5 s'),
            (0.75, '0.75 s'),
            (1, '1 s'),
            (1.5, '1.5 s'),
          ],
          onChanged: (v) => _set(_config.copyWith(activeStepSeconds: v)),
        ),
        _Choice<double>(
          label: 'ONE STEP IN THE OTHER GLASSES EVERY',
          value: _config.inactiveStepSeconds,
          options: const [(2, '2 s'), (3, '3 s'), (4, '4 s'), (6, '6 s')],
          onChanged: (v) => _set(_config.copyWith(inactiveStepSeconds: v)),
        ),
        _Choice<int>(
          label: 'ARM LENGTH, CELLS',
          value: _config.armLength,
          options: const [(6, '6'), (8, '8'), (9, '9'), (10, '10')],
          onChanged: (v) => _set(_config.copyWith(armLength: v)),
        ),
        _Choice<int>(
          label: 'COLOURS',
          value: _config.numberOfColors,
          options: const [(3, '3'), (4, '4')],
          onChanged: (v) => _set(_config.copyWith(numberOfColors: v)),
        ),
        _Choice<bool>(
          label: 'LET THE GLASS SETTLE ON EVERY TURN',
          value: _config.settleAfterBoardRotation,
          options: const [(false, 'OFF'), (true, 'ON')],
          onChanged: (v) => _set(_config.copyWith(settleAfterBoardRotation: v)),
        ),
        _Choice<GravityScope>(
          label: 'AFTER A POP, WHAT FALLS',
          value: _config.gravityScope,
          options: const [
            (GravityScope.wholeGlass, 'ALL UNSUPPORTED'),
            (GravityScope.aboveCleared, 'ABOVE THE GAP'),
          ],
          onChanged: (v) => _set(_config.copyWith(gravityScope: v)),
        ),
        _Choice<bool>(
          label: 'FREEZE PIECES DURING A CASCADE',
          value: _config.pauseIncomingDuringCascade,
          options: const [(true, 'ON'), (false, 'OFF')],
          onChanged: (v) =>
              _set(_config.copyWith(pauseIncomingDuringCascade: v)),
        ),
        _Choice<double>(
          label: 'GAME SPEED (DEBUG SLOW MOTION)',
          value: _config.timeScale,
          options: const [(1.0, '1×'), (0.5, '0.5×'), (0.25, '0.25×'), (0.1, '0.1×')],
          onChanged: (v) => _set(_config.copyWith(timeScale: v)),
        ),
        _Choice<BotProfile?>(
          label: 'AUTO-PLAY (WATCH A BOT)',
          value: _bot,
          options: const [
            (null, 'OFF'),
            (BotProfile.casual, 'CASUAL'),
            (BotProfile.average, 'AVERAGE'),
            (BotProfile.expert, 'EXPERT'),
          ],
          onChanged: (v) => setState(() => _bot = v),
        ),
        const SizedBox(height: 8),
        NeonButton(
          key: const ValueKey('lab-apply'),
          label: 'APPLY & RESTART',
          onPressed: () =>
              widget.onApply(LabSettings(config: _config, bot: _bot)),
        ),
        if (widget.canResume) ...[
          const SizedBox(height: 10),
          NeonButton(
            key: const ValueKey('lab-resume'),
            label: 'RESUME',
            primary: false,
            onPressed: widget.onResume,
          ),
        ],
      ],
    );
  }
}

class _Choice<T> extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<(T, String)> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: NeonPalette.textDim,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.3,
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              for (final (option, text) in options)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _Chip(
                      key: ValueKey('lab-$label-$text'),
                      label: text,
                      selected: option == value,
                      onTap: () => onChanged(option),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: selected
              ? NeonPalette.outline.withValues(alpha: 0.2)
              : const Color(0xFF0A111C),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? NeonPalette.outline : NeonPalette.outlineDim,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              label,
              style: TextStyle(
                color: selected ? NeonPalette.text : NeonPalette.textDim,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
