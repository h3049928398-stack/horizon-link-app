import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/navigation.dart';
import '../core/road_graph.dart';

const expandedNavigationRect = Rect.fromLTWH(950, 105, 330, 330);
const expandedNavigationCloseCenter = Offset(1115, 50);

/// A heading-up square in world metres, independent of map image projection.
class NavigationWindow {
  static const sideMeters = 800.0;
  final MapPoint origin;
  final double heading;
  final double side;
  const NavigationWindow(this.origin, this.heading, this.side);

  Offset project(MapPoint point) {
    final dx = point.x - origin.x, dz = point.z - origin.z;
    return Offset(
      side / 2 +
          (dx * math.cos(heading) - dz * math.sin(heading)) * side / sideMeters,
      side / 2 -
          (dx * math.sin(heading) + dz * math.cos(heading)) * side / sideMeters,
    );
  }

  Set<int> candidates(RoadGraph graph) =>
      graph.segmentsInWindow(origin, sideMeters / 2 * math.sqrt2);
}

class ExpandedNavigationPainter extends CustomPainter {
  final NavigationState? navigation;
  ExpandedNavigationPainter(this.navigation);

  @override
  void paint(Canvas canvas, Size size) {
    final side = math.min(size.width, size.height);
    final rect = Rect.fromLTWH(0, 0, side, side);
    canvas.save();
    canvas.clipRect(rect);
    canvas.drawRect(rect, Paint()..color = const Color(0xff0c1116));
    final n = navigation;
    final origin = n?.location;
    if (n != null && origin != null) {
      final window = NavigationWindow(origin, n.heading ?? 0, side);
      final roads = Path();
      final seen = <(int, int)>{};
      for (final id in window.candidates(n.graph)) {
        final s = n.graph.segments[id];
        // Opposite directed lanes share geometry; keep every distinct road.
        if (!seen.add((math.min(s.from, s.to), math.max(s.from, s.to)))) {
          continue;
        }
        final a = window.project(n.graph.points[s.from]);
        final b = window.project(n.graph.points[s.to]);
        roads.moveTo(a.dx, a.dy);
        roads.lineTo(b.dx, b.dy);
      }
      canvas.drawPath(
        roads,
        Paint()
          ..color = const Color(0xff778793)
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..style = PaintingStyle.stroke,
      );
      final route = n.route;
      if (route != null) {
        final path = Path();
        for (var i = 0; i < route.points.length; i++) {
          final p = window.project(route.points[i]);
          if (i == 0) {
            path.moveTo(p.dx, p.dy);
          } else {
            path.lineTo(p.dx, p.dy);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xff59e5f3)
            ..strokeWidth = 4
            ..strokeJoin = StrokeJoin.round
            ..style = PaintingStyle.stroke,
        );
      }
      final center = side / 2;
      final arrow = Path()
        ..moveTo(center, center - 14)
        ..lineTo(center + 10, center + 12)
        ..lineTo(center, center + 7)
        ..lineTo(center - 10, center + 12)
        ..close();
      canvas.drawPath(
        arrow,
        Paint()
          ..color = const Color(0xff030405)
          ..strokeWidth = 5
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      canvas.drawPath(arrow, Paint()..color = Colors.white);
    }
    canvas.restore();
    canvas.drawRect(
      rect.deflate(.5),
      Paint()
        ..color = const Color(0xff303e49)
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant ExpandedNavigationPainter oldDelegate) => true;
}
