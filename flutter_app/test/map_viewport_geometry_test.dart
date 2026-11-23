import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/widgets/map_viewport_geometry.dart';

void main() {
  test('map covers portrait, landscape and square viewports at every edge', () {
    for (final size in [
      const Size(320, 560),
      const Size(844, 300),
      const Size(400, 400),
    ]) {
      for (final zoom in [.5, 1.0, 4.0, 14.0, 20.0]) {
        for (final delta in [
          const Offset(-100000, -100000),
          const Offset(100000, 100000),
          const Offset(-100000, 100000),
          Offset.zero,
        ]) {
          final value = Matrix4.identity()
            ..translateByDouble(delta.dx, delta.dy, 0, 1)
            ..scaleByDouble(zoom, zoom, 1, 1);
          final bounded = MapViewportGeometry.constrain(value, size);
          final rect = MatrixUtils.transformRect(
            bounded,
            MapViewportGeometry.mapBounds(size),
          );
          expect(rect.left, lessThanOrEqualTo(.000001));
          expect(rect.top, lessThanOrEqualTo(.000001));
          expect(rect.right, greaterThanOrEqualTo(size.width - .000001));
          expect(rect.bottom, greaterThanOrEqualTo(size.height - .000001));
          expect(
            bounded.getMaxScaleOnAxis(),
            inInclusiveRange(MapViewportGeometry.minScale(size), 14),
          );
          final again = MapViewportGeometry.constrain(bounded, size);
          for (var i = 0; i < 16; i++) {
            expect(again.storage[i], closeTo(bounded.storage[i], .000001));
          }
        }
      }
    }
  });
}
