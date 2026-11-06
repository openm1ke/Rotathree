import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Desktop apps use physical controls at any window size.
bool get usesDesktopKeyboard => !kIsWeb && switch (defaultTargetPlatform) {
  TargetPlatform.macOS || TargetPlatform.windows || TargetPlatform.linux => true,
  _ => false,
};

/// The widest column a menu takes on a tablet. Phones use the whole width.
const double tabletMenuWidth = 880;

/// Phones are narrower than this on their short side, tablets are not.
const double tabletShortestSide = 600;

bool isTablet(Size size) => size.shortestSide >= tabletShortestSide;

/// Tablets read from further away, so the text, panels and tiles are larger.
double tabletScale(Size size) => isTablet(size) ? 1.5 : 1;

/// How much larger a game's own controls — its header, lesson, progress and
/// dialogs — are drawn in a computer's window: in proportion to the window,
/// from a 1280 × 720 one, where they are drawn as on a phone, up to twice
/// that on a large screen. 1 off a computer.
double desktopScale(Size size) {
  if (!usesDesktopKeyboard) return 1;
  return math.min(size.height / 720, size.width / 1280).clamp(1.0, 2.0);
}

/// The tablet factor for the widgets under [context]: 1 inside [Scaled],
/// which has already made them larger as a whole.
double tabletScaleOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<_Unscaled>() != null ? 1 : tabletScale(MediaQuery.sizeOf(context));

class _Unscaled extends InheritedWidget {
  const _Unscaled({required super.child});

  @override
  bool updateShouldNotify(_Unscaled oldWidget) => false;
}

/// Centres its child in a column. On a phone the column is the whole screen;
/// on a tablet it is [tabletMenuWidth] wide, or [maxWidth] when given.
class MenuWidth extends StatelessWidget {
  const MenuWidth({super.key, required this.child, this.maxWidth});

  final Widget child;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final tablet = isTablet(MediaQuery.sizeOf(context));
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth ?? (tablet ? tabletMenuWidth : double.infinity)),
        child: child,
      ),
    );
  }
}

/// Scales the text inside it by the tablet factor, so every label, title and
/// button grows together. Sizes that are not text are scaled by the caller.
class TabletScale extends StatelessWidget {
  const TabletScale({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = tabletScaleOf(context);
    if (scale == 1) return child;
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(scale * media.textScaler.scale(1))),
      child: child,
    );
  }
}

/// Draws its child [scale] times larger as a whole — text, icons, padding
/// and corners alike — laid out in the room it has divided by [scale]. The
/// child is laid out as on a phone: the tablet factor is 1 inside.
class Scaled extends StatelessWidget {
  const Scaled({super.key, required this.scale, required this.child});

  final double scale;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      scale == 1 ? child : _ScaledBox(scale: scale, child: _Unscaled(child: child));
}

class _ScaledBox extends SingleChildRenderObjectWidget {
  const _ScaledBox({required this.scale, super.child});

  final double scale;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderScaled(scale);

  @override
  void updateRenderObject(BuildContext context, _RenderScaled renderObject) => renderObject.scale = scale;
}

class _RenderScaled extends RenderProxyBox {
  _RenderScaled(this._scale);

  double _scale;
  double get scale => _scale;
  set scale(double value) {
    if (value == _scale) return;
    _scale = value;
    markNeedsLayout();
  }

  Matrix4 get _transform => Matrix4.diagonal3Values(_scale, _scale, 1);

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain((child?.getDryLayout(constraints / _scale) ?? Size.zero) * _scale);

  @override
  double computeMinIntrinsicWidth(double height) => (child?.getMinIntrinsicWidth(height / _scale) ?? 0) * _scale;

  @override
  double computeMaxIntrinsicWidth(double height) => (child?.getMaxIntrinsicWidth(height / _scale) ?? 0) * _scale;

  @override
  double computeMinIntrinsicHeight(double width) => (child?.getMinIntrinsicHeight(width / _scale) ?? 0) * _scale;

  @override
  double computeMaxIntrinsicHeight(double width) => (child?.getMaxIntrinsicHeight(width / _scale) ?? 0) * _scale;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(constraints / _scale, parentUsesSize: true);
    size = constraints.constrain(child.size * _scale);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    layer = context.pushTransform(needsCompositing, offset, _transform, super.paint, oldLayer: layer as TransformLayer?);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) => result.addWithPaintTransform(
        transform: _transform,
        position: position,
        hitTest: (result, position) => super.hitTestChildren(result, position: position),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) => transform.multiply(_transform);
}
