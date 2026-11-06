import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../audio/sound_effects.dart';
import '../i18n/strings.dart';
import '../layout.dart';
import '../style.dart';

/// The page of a game, the flat one's and Cube's: the heading, a lesson, the
/// campaign's progress, the square stage and the pads.
///
/// On a phone or a tablet they go top to bottom, the lesson above the stage.
/// In a computer's window, which is wide and has no pads, the heading, the
/// lesson and the progress are drawn larger with the window (see
/// [desktopScale]), the stage takes the whole height and the lesson stands
/// beside it.
class PlayLayout extends StatelessWidget {
  const PlayLayout({
    super.key,
    required this.heading,
    required this.stage,
    this.lesson,
    this.progress,
    this.pads,
    this.snap,
  });

  final Widget heading;

  /// The stage, [side] logical pixels square.
  final Widget Function(double side) stage;

  /// The tutorial's panel.
  final Widget? lesson;

  /// The campaign's progress bar.
  final Widget? progress;

  /// The pads under the stage, on a touch screen.
  final Widget? pads;

  /// Rounds a length to what the stage is drawn at, e.g. whole pixels.
  final double Function(double logical)? snap;

  /// Narrowest a lesson beside the stage may be, before it is scaled.
  static const _sideLesson = 300.0;

  /// Widest it is.
  static const _sideLessonMax = 420.0;

  @override
  Widget build(BuildContext context) {
    final scale = desktopScale(MediaQuery.sizeOf(context));
    final round = snap ?? (double logical) => logical;
    Widget stageIn(double width, double height) {
      final side = round(math.min(width, height));
      return Padding(
        padding: EdgeInsets.only(
          left: round((width - side) / 2),
          top: round((height - side) / 2),
        ),
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox.square(dimension: side, child: stage(side)),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final lesson = this.lesson;
        final progress = this.progress;
        final desktop = usesDesktopKeyboard;
        return Column(
          children: [
            Scaled(scale: scale, child: heading),
            if (progress != null)
              desktop
                  // In a window the bar is as wide as the stage is, at most.
                  ? Center(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: math.min(constraints.maxWidth, 760 * scale),
                        ),
                        child: Scaled(
                          scale: scale,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                            child: progress,
                          ),
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                      child: progress,
                    ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  if (lesson == null) {
                    return stageIn(box.maxWidth, box.maxHeight);
                  }
                  // Beside the stage when the window is wide enough for it,
                  // the stage giving up some width if it has to.
                  if (desktop) {
                    final gap = 16 * scale;
                    final narrowest = _sideLesson * scale + 2 * gap;
                    final side = math.min(
                      box.maxHeight,
                      box.maxWidth - 2 * narrowest,
                    );
                    if (side >= box.maxHeight * 0.7) {
                      final room = (box.maxWidth - side) / 2 - 2 * gap;
                      final width = math.min(room, _sideLessonMax * scale);
                      return Stack(
                        children: [
                          Positioned.fill(
                            child: stageIn(box.maxWidth, box.maxHeight),
                          ),
                          Positioned(
                            left: (box.maxWidth - side) / 2 - gap - width,
                            width: width,
                            top: math.max(0, (box.maxHeight - side) / 2) + gap,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: box.maxHeight - 2 * gap,
                              ),
                              child: Scaled(scale: scale, child: lesson),
                            ),
                          ),
                        ],
                      );
                    }
                  }
                  return Column(
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxHeight: math.min(
                            constraints.maxHeight * 0.4,
                            260 * math.max(scale, tabletScaleOf(context)),
                          ),
                        ),
                        child: Scaled(scale: scale, child: lesson),
                      ),
                      Expanded(
                        child: LayoutBuilder(
                          builder: (context, rest) =>
                              stageIn(rest.maxWidth, rest.maxHeight),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            ?pads,
          ],
        );
      },
    );
  }
}

/// A dialog over a game: the game, standing still, blurred and darkened
/// behind it. Put it straight into the game's [Stack].
class GameDialog extends StatelessWidget {
  const GameDialog({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scale = desktopScale(MediaQuery.sizeOf(context));
    return Positioned.fill(
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: ClipRect(
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(sigmaX: 6, sigmaY: 6),
                  child: const ColoredBox(color: Color(0xB0050508)),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(16 * scale),
                  child: FocusScope(
                    autofocus: usesDesktopKeyboard,
                    child: scale == 1
                        ? TabletScale(child: child)
                        : Scaled(scale: scale, child: child),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// One way out of a pause, drawn as a tile or as a link under them.
class PauseAction {
  const PauseAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool danger;
}

/// The pause: the mode and level, the way back into the game, the things to
/// do as tiles under it, and the ways out last.
class PauseCard extends StatelessWidget {
  const PauseCard({
    super.key,
    required this.kicker,
    required this.onResume,
    this.note,
    this.tiles = const [],
    this.links = const [],
  });

  final String kicker;
  final String? note;
  final VoidCallback onResume;
  final List<PauseAction> tiles;
  final List<PauseAction> links;

  @override
  Widget build(BuildContext context) {
    final s = tabletScaleOf(context);
    final radius = BorderRadius.circular(24 * s);
    // Three tiles a row, or two rows of two.
    final perRow = tiles.length == 4 ? 2 : math.min(3, tiles.length);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: 400 * s),
      // A border of light, brightest at the top left, round a dark glass.
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Palette.pink.withValues(alpha: 0.7),
              Palette.violet.withValues(alpha: 0.45),
              Palette.accent.withValues(alpha: 0.25),
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: Palette.violet.withValues(alpha: 0.28),
              blurRadius: 48 * s,
              spreadRadius: -6 * s,
            ),
            BoxShadow(
              color: const Color(0xAA000000),
              blurRadius: 30 * s,
              offset: Offset(0, 14 * s),
            ),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(1.5 * s),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22.5 * s),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xF61B1A2C), Color(0xF60B0B14)],
              ),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(22, 20, 22, 14) * s,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LText(
                              context.tr(kicker).toUpperCase(),
                              translate: false,
                              style: Type.label(11, color: Palette.accent),
                            ),
                            SizedBox(height: 4 * s),
                            LText(
                              'Пауза',
                              style: Type.display(
                                36,
                                shadows: Type.glow(
                                  Palette.violet.withValues(alpha: 0.6),
                                  18,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _PauseBadge(size: 52 * s),
                    ],
                  ),
                  if (note case final note?) ...[
                    SizedBox(height: 10 * s),
                    Row(
                      children: [
                        Icon(
                          Icons.track_changes_rounded,
                          size: 16 * s,
                          color: Palette.textDim,
                        ),
                        SizedBox(width: 6 * s),
                        Expanded(
                          child: LText(
                            note,
                            style: Type.body(13, color: Palette.textDim),
                          ),
                        ),
                      ],
                    ),
                  ],
                  SizedBox(height: 18 * s),
                  _ResumeButton(onPressed: onResume, scale: s),
                  if (tiles.isNotEmpty) ...[
                    SizedBox(height: 12 * s),
                    for (var start = 0; start < tiles.length; start += perRow)
                      Padding(
                        padding: EdgeInsets.only(bottom: 10 * s),
                        child: IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              for (var i = start; i < start + perRow; i++) ...[
                                if (i > start) SizedBox(width: 10 * s),
                                Expanded(
                                  child: i < tiles.length
                                      ? _PauseTile(action: tiles[i], scale: s)
                                      : const SizedBox(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                  if (links.isNotEmpty)
                    Padding(
                      padding: EdgeInsets.only(top: 2 * s),
                      child: Row(
                        children: [
                          for (final (i, link) in links.indexed) ...[
                            if (i > 0)
                              Container(
                                width: 1,
                                height: 20 * s,
                                color: Palette.line,
                              ),
                            Expanded(
                              child: _PauseLink(action: link, scale: s),
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
      ),
    );
  }
}

/// Two bars in a ring of the "go" colours.
class _PauseBadge extends StatelessWidget {
  const _PauseBadge({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: Palette.go,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Palette.pink.withValues(alpha: 0.35),
            blurRadius: size * 0.4,
          ),
        ],
      ),
      padding: EdgeInsets.all(size * 0.045),
      child: DecoratedBox(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Color(0xFF151423),
        ),
        child: Icon(Icons.pause_rounded, size: size * 0.5, color: Palette.text),
      ),
    ),
  );
}

/// Back into the game: the gradient of "go", a play sign, and on a computer
/// the key that does the same.
class _ResumeButton extends StatefulWidget {
  const _ResumeButton({required this.onPressed, required this.scale});

  final VoidCallback onPressed;
  final double scale;

  @override
  State<_ResumeButton> createState() => _ResumeButtonState();
}

class _ResumeButtonState extends State<_ResumeButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final radius = BorderRadius.circular(16 * s);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: const LinearGradient(colors: Palette.go),
        boxShadow: [BoxShadow(color: Palette.pink.withValues(alpha: 0.35), blurRadius: 22 * s, offset: Offset(0, 6 * s))],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          autofocus: true,
          borderRadius: radius,
          // The focus is a ring of light, not a wash over the colours.
          focusColor: Colors.transparent,
          hoverColor: const Color(0x14FFFFFF),
          onFocusChange: (focused) => setState(() => _focused = focused),
          onTap: clicking(widget.onPressed),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            // A lit top edge, as on the blocks.
            decoration: BoxDecoration(
              borderRadius: radius,
              border: Border.all(color: _focused ? const Color(0xE6FFFFFF) : const Color(0x00FFFFFF), width: 2 * s),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.center,
                colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF)],
              ),
            ),
            padding: EdgeInsets.symmetric(horizontal: 16 * s, vertical: 13 * s),
            child: Row(
              children: [
                Icon(Icons.play_arrow_rounded, size: 28 * s, color: Colors.white),
                SizedBox(width: 8 * s),
                Expanded(child: LText('Продолжить', style: Type.display(20, spacing: 0.4))),
                if (usesDesktopKeyboard) const _KeyHint('Esc'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _KeyHint extends StatelessWidget {
  const _KeyHint(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: const Color(0x26000000),
      borderRadius: BorderRadius.circular(6),
      border: Border.all(color: const Color(0x59FFFFFF)),
    ),
    child: LText(
      label,
      translate: false,
      style: Type.body(
        12,
        weight: FontWeight.w800,
        color: const Color(0xE6FFFFFF),
      ),
    ),
  );
}

/// A square of glass with an icon over its name, lit when it is pointed at
/// or has the focus.
class _PauseTile extends StatefulWidget {
  const _PauseTile({required this.action, required this.scale});

  final PauseAction action;
  final double scale;

  @override
  State<_PauseTile> createState() => _PauseTileState();
}

class _PauseTileState extends State<_PauseTile> {
  bool _lit = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    final action = widget.action;
    final radius = BorderRadius.circular(16 * s);
    final tone = action.danger ? Palette.danger : Palette.accent;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: radius,
        onTap: clicking(action.onPressed),
        onHover: (lit) => setState(() => _lit = lit),
        onFocusChange: (lit) => setState(() => _lit = lit),
        focusColor: Colors.transparent,
        hoverColor: Colors.transparent,
        splashColor: tone.withValues(alpha: 0.2),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: EdgeInsets.fromLTRB(8, 14, 8, 12) * s,
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: _lit
                  ? [tone.withValues(alpha: 0.22), tone.withValues(alpha: 0.08)]
                  : const [Color(0x14FFFFFF), Color(0x06FFFFFF)],
            ),
            border: Border.all(
              color: _lit ? tone.withValues(alpha: 0.8) : Palette.line,
              width: _lit ? 1.5 : 1,
            ),
            boxShadow: _lit
                ? [
                    BoxShadow(
                      color: tone.withValues(alpha: 0.25),
                      blurRadius: 16 * s,
                    ),
                  ]
                : null,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(action.icon, size: 26 * s, color: tone),
              SizedBox(height: 8 * s),
              LText(
                action.label,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: Type.body(
                  13,
                  weight: FontWeight.w800,
                  height: 1.15,
                  color: _lit ? Palette.text : const Color(0xFFD5D9EA),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet way out under the tiles.
class _PauseLink extends StatelessWidget {
  const _PauseLink({required this.action, required this.scale});

  final PauseAction action;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final color = action.danger ? const Color(0xFFFF7A90) : Palette.textDim;
    return TextButton(
      onPressed: clicking(action.onPressed),
      style: TextButton.styleFrom(
        foregroundColor: color,
        padding: EdgeInsets.symmetric(
          horizontal: 6 * scale,
          vertical: 12 * scale,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12 * scale),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(action.icon, size: 18 * scale, color: color),
          SizedBox(width: 6 * scale),
          // A long name shrinks whole rather than losing its last word.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: LText(
                action.label,
                maxLines: 1,
                softWrap: false,
                style: Type.body(13, weight: FontWeight.w800, color: color),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
