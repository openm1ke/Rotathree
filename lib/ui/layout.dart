import 'package:flutter/widgets.dart';

/// The widest column a menu takes on a tablet. Phones use the whole width.
const double tabletMenuWidth = 880;

/// Phones are narrower than this on their short side, tablets are not.
const double tabletShortestSide = 600;

bool isTablet(Size size) => size.shortestSide >= tabletShortestSide;

/// Tablets read from further away, so the text, panels and tiles are larger.
double tabletScale(Size size) => isTablet(size) ? 1.5 : 1;

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
    final scale = tabletScale(media.size);
    if (scale == 1) return child;
    return MediaQuery(
      data: media.copyWith(textScaler: TextScaler.linear(scale * media.textScaler.scale(1))),
      child: child,
    );
  }
}
