import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../format.dart';
import '../i18n/strings.dart';
import '../style.dart';

/// A compact score goal. Pulses only when points arrive, not while idle.
class CampaignProgress extends StatefulWidget {
  const CampaignProgress({super.key, required this.level, required this.into, required this.target, required this.animated});

  final int level, into, target;
  final bool animated;

  @override
  State<CampaignProgress> createState() => _CampaignProgressState();
}

class _CampaignProgressState extends State<CampaignProgress> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, value: 1, duration: const Duration(milliseconds: 650));
  }

  @override
  void didUpdateWidget(CampaignProgress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.level != oldWidget.level || !widget.animated || MediaQuery.disableAnimationsOf(context)) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (widget.level == oldWidget.level && widget.into > oldWidget.into) {
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.target <= 0) return const SizedBox.shrink();
    final earned = math.max(0, widget.into);
    final remaining = math.max(0, widget.target - earned);
    final fraction = (earned / widget.target).clamp(0.0, 1.0);
    final animate = widget.animated && !MediaQuery.disableAnimationsOf(context);
    return RepaintBoundary(
      child: Semantics(
        label: context.tr('Прогресс уровня ${widget.level}'),
        value: context.tr('${formatNumber(earned)} / ${formatNumber(widget.target)}. Ещё ${formatNumber(remaining)}.'),
        child: ExcludeSemantics(
          child: AnimatedBuilder(
            animation: _pulse,
            builder: (context, child) {
              final wave = animate ? math.sin(_pulse.value * math.pi).abs() : 0.0;
              return DecoratedBox(
                decoration: BoxDecoration(
                  color: Palette.panelStrong,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Palette.accent.withValues(alpha: .4 + wave * .5)),
                  boxShadow: wave > .01 ? [BoxShadow(color: Palette.accent.withValues(alpha: wave * .25), blurRadius: 8)] : [],
                ),
                child: child,
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: SizedBox(
                height: 32,
                child: Stack(children: [
                  Positioned.fill(
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(widget.level),
                      tween: Tween(begin: fraction, end: fraction),
                      duration: animate ? const Duration(milliseconds: 320) : Duration.zero,
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) => FractionallySizedBox(
                        alignment: Alignment.centerLeft, widthFactor: value, child: child,
                      ),
                      child: const DecoratedBox(decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Color(0x9936A9FF), Color(0x992EE6C0), Color(0x998F5BFF)]),
                      )),
                    ),
                  ),
                  const Positioned.fill(child: CustomPaint(painter: _Ticks())),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(children: [
                        Expanded(child: LText('Цель', style: Type.label(9, color: Palette.accent), maxLines: 1)),
                        Expanded(flex: 2, child: FittedBox(fit: BoxFit.scaleDown, child: LText(
                          '${formatNumber(earned)} / ${formatNumber(widget.target)}', style: Type.display(15),
                        ))),
                        Expanded(child: LText('Ещё ${formatNumber(remaining)}', textAlign: TextAlign.right,
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: Type.body(10, weight: FontWeight.w700))),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Ticks extends CustomPainter {
  const _Ticks();
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.white.withValues(alpha: .07)..strokeWidth = 1;
    for (double x = 24; x < size.width; x += 24) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
  }
  @override
  bool shouldRepaint(_Ticks oldDelegate) => false;
}
