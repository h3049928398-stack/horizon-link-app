import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/widgets/map_marker_geometry.dart';

void main() {
  test(
    'zooming in reduces marker screen size while keeping icons readable',
    () {
      var previous = double.infinity;
      expect(MapMarkerGeometry.height(1), 26);
      expect(MapMarkerGeometry.height(14), 24);
      for (var zoom = 1.0; zoom <= 14; zoom += .25) {
        final height = MapMarkerGeometry.height(zoom);
        expect(height, lessThan(previous));
        expect(height, inInclusiveRange(24, 26));
        for (final size in [const Size(320, 700), const Size(520, 900)]) {
          final screenHeight =
              MapMarkerGeometry.unit(size, zoom) *
              34 /
              MapMarkerGeometry.screenUnit(size, zoom);
          expect(screenHeight, closeTo(height, .0001));
        }
        previous = height;
      }
    },
  );

  test('touch targets stay at least 44 pixels at every zoom and viewport', () {
    const anchor = Offset(512, 512);
    for (final size in [const Size(320, 700), const Size(520, 900)]) {
      for (final zoom in [1.0, 3.0, 5.0, 14.0]) {
        final bounds = MapMarkerGeometry.hitBounds(anchor, size, zoom);
        final screenUnit = MapMarkerGeometry.screenUnit(size, zoom);
        expect(bounds.width / screenUnit, greaterThanOrEqualTo(44 - 1e-6));
        expect(bounds.height / screenUnit, greaterThanOrEqualTo(44 - 1e-6));
        expect(bounds.contains(anchor), isTrue);
        final head =
            anchor - Offset(0, 21 * MapMarkerGeometry.unit(size, zoom));
        expect(bounds.contains(head), isTrue);
      }
    }
  });
}
