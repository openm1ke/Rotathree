import 'package:flutter/material.dart';

import 'hud.dart';
import 'style.dart';
import 'widgets/controls.dart';

/// The first screen: the name of the game, its rules in four lines and three
/// slabs anchored to the right edge.
class MenuScreen extends StatefulWidget {
  const MenuScreen({
    super.key,
    required this.onPlay,
    required this.onOpenSettings,
  });

  final ValueChanged<GameMode> onPlay;
  final VoidCallback onOpenSettings;

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _intro = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  static const _rules = [
    'В каждом стакане падает своя фигура — во всех одновременно.',
    'Поворачивайте поле: стакан сверху — ваш, в нём фигура шагает быстрее.',
    'Три и больше одного цвета в ряд лопаются, блоки сверху падают.',
    'Стакан, заполненный до края рукава, заканчивает игру.',
  ];

  @override
  void dispose() {
    _intro.dispose();
    super.dispose();
  }

  /// Fades and lifts [child] in, starting [delay] into the intro.
  Widget _rise(double delay, Widget child) {
    final animation = CurvedAnimation(
      parent: _intro,
      curve: Interval(
        delay,
        (delay + 0.58).clamp(0.0, 1.0),
        curve: Motion.snap,
      ),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 18 * (1 - animation.value)),
          child: child,
        ),
      ),
      child: child,
    );
  }

  /// Slides a slab in from beyond the right edge.
  Widget _slide(double delay, Widget child) {
    final animation = CurvedAnimation(
      parent: _intro,
      curve: Interval(delay, (delay + 0.5).clamp(0.0, 1.0), curve: Motion.snap),
    );
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) => Opacity(
        opacity: animation.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(160 * (1 - animation.value), 0),
          child: child,
        ),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxHeight < 640;
          // The spacers share out whatever height is left; on a screen too
          // short for everything the menu simply scrolls.
          return SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: box.maxHeight),
              child: IntrinsicHeight(child: _buildColumn(compact)),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColumn(bool compact) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Spacer(flex: compact ? 1 : 2),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _rise(0, const _Logo()),
              const SizedBox(height: 14),
              _rise(
                0.08,
                Text(
                  'ЧЕТЫРЕ СТАКАНА. ОДИН ЦЕНТР. ТРИ В РЯД.',
                  style: Type.body(
                    12.5,
                    color: Palette.accent,
                    height: 1.3,
                  ).copyWith(letterSpacing: 1.6),
                ),
              ),
              if (!compact) ...[
                const SizedBox(height: 20),
                _rise(
                  0.16,
                  Column(children: [for (final rule in _rules) _Rule(rule)]),
                ),
              ],
            ],
          ),
        ),
        const Spacer(flex: 2),
        _slide(
          0.1,
          _Slab(
            key: const ValueKey('menu-play'),
            badge: 'GO',
            title: 'Играть',
            subtitle: 'Одиночная партия на выживание',
            colors: const [Color(0xFFFF2E7E), Color(0xFFA53BFF)],
            glow: const Color(0xFFFF2E7E),
            onPressed: () => widget.onPlay(GameMode.classic),
          ),
        ),
        const SizedBox(height: 12),
        _slide(
          0.19,
          _Slab(
            key: const ValueKey('menu-zen'),
            badge: 'ZEN',
            title: 'Дзен',
            subtitle: 'Спокойная игра по уровням',
            colors: const [Palette.zenDeep, Palette.zenBlue],
            glow: Palette.zenDeep,
            onPressed: () => widget.onPlay(GameMode.zen),
          ),
        ),
        const SizedBox(height: 12),
        _slide(
          0.28,
          _Slab(
            key: const ValueKey('menu-settings'),
            badge: 'CFG',
            title: 'Настройки',
            subtitle: 'Крестовины, поле, интерфейс',
            colors: const [Color(0xFF2B3350), Color(0xFF1A1F33)],
            glow: Colors.black,
            onPressed: widget.onOpenSettings,
          ),
        ),
        const Spacer(),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
          child: _rise(
            0.34,
            Text(
              'Управление — две крестовины внизу экрана. '
              'Что делает каждая кнопка, выбирается в настройках.',
              style: Type.body(
                12,
                color: Palette.textFaint,
                weight: FontWeight.w400,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo();

  @override
  Widget build(BuildContext context) {
    final style = Type.display(
      66,
      spacing: -2,
      height: 0.95,
      shadows: Type.glow(Palette.accent.withValues(alpha: 0.25), 36),
    );
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('ROTA', style: style),
          ShaderMask(
            blendMode: BlendMode.srcIn,
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Palette.pink, Palette.orange],
            ).createShader(bounds),
            child: Text('THREE', style: style.copyWith(shadows: const [])),
          ),
          // The slant of the last letter needs a little room.
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _Rule extends StatelessWidget {
  const _Rule(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 7,
            height: 2.5,
            margin: const EdgeInsets.only(top: 8, right: 10),
            color: Palette.accent,
          ),
          Expanded(
            child: Text(
              text,
              style: Type.body(
                13.5,
                color: Palette.textDim,
                weight: FontWeight.w400,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A big slab that reaches the right edge of the screen.
class _Slab extends StatelessWidget {
  const _Slab({
    super.key,
    required this.badge,
    required this.title,
    required this.subtitle,
    required this.colors,
    required this.glow,
    required this.onPressed,
  });

  final String badge;
  final String title;
  final String subtitle;
  final List<Color> colors;
  final Color glow;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 30),
      child: Pressable(
        onPressed: onPressed,
        pressedScale: 0.985,
        builder: (context, pressed) => AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Motion.snap,
          transform: Matrix4.translationValues(pressed ? 12 : 0, 0, 0),
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.horizontal(
              left: Radius.circular(12),
            ),
            gradient: LinearGradient(colors: colors, stops: const [0, 0.75]),
            boxShadow: [
              BoxShadow(
                color: glow.withValues(alpha: 0.3),
                blurRadius: 34,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          foregroundDecoration: pressed
              ? BoxDecoration(
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(12),
                  ),
                  color: Colors.white.withValues(alpha: 0.1),
                )
              : null,
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.26),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(badge, style: Type.display(18, spacing: 0.7)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title.toUpperCase(), style: Type.display(30)),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: Type.body(
                        12.5,
                        color: Colors.white.withValues(alpha: 0.72),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
