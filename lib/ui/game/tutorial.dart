import '../i18n/strings.dart';
import 'package:flutter/material.dart';
import '../data/bindings.dart';
import '../input/game_action.dart';
import '../audio/sound_effects.dart';
import '../layout.dart';
import '../style.dart';
import '../widgets/controls.dart';

/// One short line per lesson, read at a glance above the glass; the glowing
/// pad buttons say the rest. A lesson with an action goes on by itself once
/// the action is done; the first and the last wait for a button. The same
/// lessons as the web version.
const tutorialLessons = [
  ('Собирай 3 в ряд', 'Три клетки одного цвета исчезают'),
  ('Двигай фигуру', ''),
  ('Поверни фигуру', ''),
  ('Брось — собери 3', ''),
  ('Поверни стакан', 'Наверху — активный стакан'),
  ('Следи за всеми стаканами', 'Активный падает быстрее — переключайся'),
];

/// What to press, said again after a wrong button or a wait.
const _hintColour = Color(0xFFFFD36A);

class TutorialPanel extends StatelessWidget {
  const TutorialPanel({
    super.key,
    required this.step,
    required this.performed,
    required this.onNext,
    required this.onSkip,
    this.hint,
    this.urging = false,
    this.onPractice,
    this.bindings,
    this.actions = const [],
    this.lessons = tutorialLessons,
  });

  /// The lessons shown: the flat game's, or Cube's.
  final List<(String, String)> lessons;
  final int step;
  final bool performed;

  /// What to press, said again after a wrong button or a wait.
  final String? hint;

  /// The player has waited: the call to the pads beats faster.
  final bool urging;
  final VoidCallback? onPractice;
  final Bindings? bindings;
  final List<GameAction> actions;
  final VoidCallback onNext, onSkip;

  @override
  Widget build(BuildContext context) {
    final (title, body) = lessons[step];
    final last = step == lessons.length - 1;
    final waitsForButton = step == 0 || last;
    final keys = bindings;
    final keyboard = keys != null;
    final media = MediaQuery.of(context);
    final scale = tabletScaleOf(context);
    // A low phone keeps its glass tall: the lesson's type is smaller there.
    final compact = media.size.height < 700;
    // A done lesson keeps its size: its call and hint dim instead of leaving.
    Widget dimmed(Widget child) =>
        AnimatedOpacity(opacity: performed ? 0.25 : 1, duration: const Duration(milliseconds: 200), child: child);
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(scale * media.textScaler.scale(1))),
      child: Semantics(
        liveRegion: true,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: EdgeInsets.fromLTRB(12, 4, 12, 8) * scale,
          decoration: BoxDecoration(
            color: Palette.panelStrong,
            borderRadius: BorderRadius.circular(18 * scale),
            border: Border.all(color: performed ? Palette.accent : Palette.lineStrong),
            boxShadow: performed ? [BoxShadow(color: Palette.accent.withValues(alpha: 0.25), blurRadius: 24)] : null,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.fromLTRB(14, 4, 6, 10) * scale,
              // The frame grows and shrinks with its lesson instead of
              // jumping, and the glass below gives way just as smoothly.
              child: AnimatedSize(
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        LText(
                          '${step + 1} / ${lessons.length}',
                          style: Type.label(12, color: Palette.accent).copyWith(letterSpacing: 2.4),
                        ),
                        const SizedBox(width: 8),
                        // Beside the glass the panel is narrow: the way out shrinks.
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: TextButton(
                                onPressed: clicking(onSkip),
                                style: TextButton.styleFrom(
                                  foregroundColor: Palette.textDim,
                                  minimumSize: const Size(48, 34),
                                  padding: const EdgeInsets.symmetric(horizontal: 8),
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    LText('Пропустить', style: Type.body(13, color: Palette.textDim)),
                                    if (keyboard) ...[const SizedBox(width: 8), const Keycap(label: 'Backspace')],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      // A new lesson fades in where the last one was.
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        layoutBuilder: (current, previous) => Stack(
                          alignment: Alignment.topCenter,
                          children: [...previous, ?current],
                        ),
                        child: Column(
                          key: ValueKey(step),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  if (performed)
                                    const TextSpan(text: '✓ ', style: TextStyle(color: Palette.accent)),
                                  TextSpan(text: context.tr(title).toUpperCase()),
                                ],
                              ),
                              textAlign: TextAlign.center,
                              style: Type.display(compact ? 20 : 24, height: 1.1),
                            ),
                            if (body.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: LText(body, style: Type.body(compact ? 13 : 15, height: 1.3), textAlign: TextAlign.center),
                              ),
                            if (!waitsForButton)
                              Padding(
                                padding: EdgeInsets.only(top: compact ? 4 : 8),
                                child: dimmed(
                                  keys == null
                                      ? _PadsCall(urging: urging && !performed, still: performed, compact: compact)
                                      : Wrap(
                                          spacing: 12,
                                          runSpacing: 4,
                                          alignment: WrapAlignment.center,
                                          children: [
                                            for (final action in actions)
                                              if (keys[action]!.isNotEmpty)
                                                Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    LText(action.label, style: Type.body(13, color: Palette.accent)),
                                                    const SizedBox(width: 6),
                                                    for (final key in keys[action]!)
                                                      Padding(
                                                        padding: const EdgeInsets.only(right: 4),
                                                        child: Keycap(label: keyLabel(key)),
                                                      ),
                                                  ],
                                                ),
                                          ],
                                        ),
                                ),
                              ),
                            if (hint case final said?)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: dimmed(
                                  LText(
                                    said,
                                    style: Type.body(compact ? 13 : 14, weight: FontWeight.w700, color: _hintColour),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ),
                            if (onPractice != null && !performed) ...[
                              const SizedBox(height: 6),
                              LText(
                                keyboard
                                    ? 'Нет назначенной клавиши. Выберите «Попробовать».'
                                    : 'Нет кнопки. Нажмите «Попробовать» или назначьте в настройках.',
                                style: Type.body(12, color: Palette.textDim),
                                textAlign: TextAlign.center,
                              ),
                              TextButton(onPressed: clicking(onPractice), child: const LText('Попробовать')),
                            ],
                            if (waitsForButton)
                              Padding(
                                padding: EdgeInsets.only(top: compact ? 6 : 10),
                                child: Wrap(
                                  spacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  alignment: WrapAlignment.center,
                                  children: [
                                    ConstrainedBox(
                                      constraints: BoxConstraints(minWidth: 200 * scale),
                                      child: GoButton(label: last ? 'Играть' : 'Начать', onPressed: onNext),
                                    ),
                                    if (keyboard) const Keycap(label: 'Enter'),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Press the glowing buttons", bobbing towards the pads below it.
class _PadsCall extends StatefulWidget {
  const _PadsCall({required this.urging, required this.still, required this.compact});

  final bool urging;
  final bool still;
  final bool compact;

  @override
  State<_PadsCall> createState() => _PadsCallState();
}

class _PadsCallState extends State<_PadsCall> with SingleTickerProviderStateMixin {
  late final AnimationController _bob = AnimationController(vsync: this);

  void _run() {
    final calm = widget.still || MediaQuery.disableAnimationsOf(context);
    if (calm) {
      _bob.stop();
      _bob.value = 0;
      return;
    }
    final period = Duration(milliseconds: widget.urging ? 600 : 1300);
    if (_bob.isAnimating && _bob.duration == period) return;
    _bob
      ..duration = period
      ..repeat();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _run();
  }

  @override
  void didUpdateWidget(_PadsCall oldWidget) {
    super.didUpdateWidget(oldWidget);
    _run();
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _bob,
    builder: (context, child) =>
        Transform.translate(offset: Offset(0, 3 * Curves.easeInOut.transform(1 - (2 * _bob.value - 1).abs())), child: child),
    child: LText(
      'Жми светящиеся кнопки ↓',
      style: Type.body(widget.compact ? 14 : 16, weight: FontWeight.w800, color: Palette.accent),
      textAlign: TextAlign.center,
    ),
  );
}
