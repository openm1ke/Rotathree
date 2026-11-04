import 'package:flutter/material.dart';

import '../data/achievements.dart';
import '../i18n/strings.dart';
import '../style.dart';
import 'block_picture.dart';

/// The achievements waiting to be announced, one after another.
class AchievementToasts extends ChangeNotifier {
  final List<Achievement> _waiting = [];

  Achievement? get current => _waiting.isEmpty ? null : _waiting.first;

  void add(Iterable<Achievement> earned) {
    if (earned.isEmpty) return;
    _waiting.addAll(earned);
    notifyListeners();
  }

  void _shown() {
    if (_waiting.isEmpty) return;
    _waiting.removeAt(0);
    notifyListeners();
  }
}

/// A card at the top of the screen for an achievement just earned: it comes
/// in, stays a moment and goes, and the next one follows. Taps pass through.
class AchievementToast extends StatefulWidget {
  const AchievementToast({super.key, required this.toasts});

  final AchievementToasts toasts;

  @override
  State<AchievementToast> createState() => _AchievementToastState();
}

class _AchievementToastState extends State<AchievementToast> with SingleTickerProviderStateMixin {
  /// How long a card is up, coming in and going included.
  static const _stay = Duration(milliseconds: 3400);

  late final AnimationController _clock;
  Achievement? _showing;

  @override
  void initState() {
    super.initState();
    _clock = AnimationController(vsync: this, duration: _stay)
      ..addStatusListener((status) {
        if (status != AnimationStatus.completed) return;
        setState(() => _showing = null);
        widget.toasts._shown();
      });
    widget.toasts.addListener(_next);
    _next();
  }

  @override
  void didUpdateWidget(AchievementToast oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.toasts != widget.toasts) {
      oldWidget.toasts.removeListener(_next);
      widget.toasts.addListener(_next);
    }
  }

  @override
  void dispose() {
    widget.toasts.removeListener(_next);
    _clock.dispose();
    super.dispose();
  }

  void _next() {
    final next = widget.toasts.current;
    if (_showing != null || next == null) return;
    setState(() => _showing = next);
    _clock.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final achievement = _showing;
    if (achievement == null) return const SizedBox.shrink();
    final still = MediaQuery.disableAnimationsOf(context);
    final card = Container(
      constraints: const BoxConstraints(maxWidth: 420),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Palette.panelStrong,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Palette.brandYellow.withValues(alpha: 0.55)),
        boxShadow: const [BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, 6))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BlockPicture(achievement.picture, size: 34),
          const SizedBox(width: 12),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LText('Достижение открыто', style: Type.label(10.5, color: Palette.brandYellow)),
                const SizedBox(height: 2),
                LText(achievement.title, style: Type.body(15, weight: FontWeight.w800, height: 1.2)),
                LText(achievement.description, style: Type.body(12, color: Palette.textDim, height: 1.25)),
              ],
            ),
          ),
        ],
      ),
    );
    return IgnorePointer(
      child: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: AnimatedBuilder(
              animation: _clock,
              builder: (context, child) {
                final t = _clock.value;
                final shown = Curves.easeOut.transform((t / 0.08).clamp(0.0, 1.0)) *
                    (1 - Curves.easeIn.transform(((t - 0.9) / 0.1).clamp(0.0, 1.0)));
                return Opacity(
                  opacity: shown,
                  child: Transform.translate(offset: Offset(0, still ? 0 : -20 * (1 - shown)), child: child),
                );
              },
              child: Semantics(
                liveRegion: true,
                label: '${context.tr('Достижение открыто')}: ${context.tr(achievement.title)}',
                excludeSemantics: true,
                child: card,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
