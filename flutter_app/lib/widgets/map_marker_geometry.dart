import 'dart:math' as math;

import 'package:flutter/painting.dart';

/// Screen-space sizing shared by marker painting and touch handling.
abstract final class MapMarkerGeometry {
  static double height(double zoom) =>
      26 - 2 * math.log(zoom.clamp(1, 14)) / math.log(14);

  static double unit(Size viewport, double zoom) =>
      screenUnit(viewport, zoom) * height(zoom) / 34;

  static double screenUnit(Size viewport, double zoom) =>
      1024 / (math.min(viewport.width, viewport.height) * zoom);

  static Rect hitBounds(Offset anchor, Size viewport, double zoom) {
    final scale = unit(viewport, zoom);
    final minimum = 44 * screenUnit(viewport, zoom);
    return Rect.fromCenter(
      center: anchor - Offset(0, 17 * scale),
      width: math.max(26 * scale, minimum),
      height: math.max(34 * scale, minimum),
    );
  }
}
