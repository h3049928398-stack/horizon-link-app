import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The square map uses BoxFit.contain inside the viewport before transforming.
abstract final class MapViewportGeometry {
  static double minScale(Size viewport) =>
      viewport.longestSide / viewport.shortestSide;

  static Rect mapBounds(Size viewport) {
    final side = viewport.shortestSide;
    return Rect.fromLTWH(
      (viewport.width - side) / 2,
      (viewport.height - side) / 2,
      side,
      side,
    );
  }

  static Matrix4 constrain(Matrix4 value, Size viewport) {
    final scale = value.getMaxScaleOnAxis();
    final zoom = scale
        .clamp(minScale(viewport), math.max(14, minScale(viewport)))
        .toDouble();
    // When raising the minimum zoom after a resize, keep the viewport center.
    final ratio = zoom / scale;
    final x =
        (value.storage[12] - viewport.width / 2) * ratio + viewport.width / 2;
    final y =
        (value.storage[13] - viewport.height / 2) * ratio + viewport.height / 2;
    final map = mapBounds(viewport);
    return Matrix4.identity()
      ..translateByDouble(
        x.clamp(
          math.min(viewport.width - map.right * zoom, -map.left * zoom),
          -map.left * zoom,
        ),
        y.clamp(
          math.min(viewport.height - map.bottom * zoom, -map.top * zoom),
          -map.top * zoom,
        ),
        0,
        1,
      )
      ..scaleByDouble(zoom, zoom, 1, 1);
  }
}
