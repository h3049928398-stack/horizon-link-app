import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/core/road_graph.dart';
import 'package:horizon_link/core/navigation.dart';

RoadGraph square({bool blocked = false}) => RoadGraph(
  const [
    MapPoint(0, 0, 0),
    MapPoint(100, 0, 0),
    MapPoint(100, 0, 100),
    MapPoint(0, 0, 100),
  ],
  const [
    RoadSegment(0, 0, 0, 1, 100, ''),
    RoadSegment(1, 1, 1, 2, 100, ''),
    RoadSegment(2, 2, 2, 3, 100, ''),
    RoadSegment(3, 3, 3, 0, 100, ''),
  ],
  [
    [1],
    blocked ? [] : [2],
    [3],
    [0],
  ],
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'same segment uses projected endpoints, reverse travel follows legal loop',
    () {
      final g = square(), start = g.project(const MapPoint(10, 0, 0), 0);
      final direct = g.route(start, const MapPoint(90, 0, 0))!;
      expect(direct.length, closeTo(80, .01));
      expect(direct.segments, [0]);
      final reverse = g.route(start, const MapPoint(5, 0, 0))!;
      expect(reverse.segments, [0, 1, 2, 3, 0]);
      expect(reverse.length, closeTo(395, .01));
    },
  );
  test('no route bypasses a missing legal transition', () {
    final g = square(blocked: true);
    expect(
      g.route(
        g.project(const MapPoint(10, 0, 0), 0),
        const MapPoint(50, 0, 100),
      ),
      isNull,
    );
  });
  test('3D map matching separates stacked roads and respects heading', () {
    final g = RoadGraph(
      const [
        MapPoint(0, 0, 0),
        MapPoint(100, 0, 0),
        MapPoint(0, 30, 0),
        MapPoint(100, 30, 0),
      ],
      const [
        RoadSegment(0, 0, 0, 1, 100, ''),
        RoadSegment(1, 0, 1, 0, 100, ''),
        RoadSegment(2, 1, 2, 3, 100, ''),
      ],
      [[], [], []],
    );
    expect(g.nearby(const MapPoint(50, 29, 0)).first.segment, 2);
    expect(
      g.nearby(const MapPoint(50, 0, 0), heading: -1.570796).first.segment,
      1,
    );
  });
  test(
    'persistent deviation reroutes, pause does not; rewind can reduce progress',
    () {
      final n = NavigationState(square());
      n.update(const MapPoint(10, 0, 0), moving: false);
      expect(
        n.start(const MapPlace('test', '终点', '自定义', MapPoint(90, 0, 0))),
        true,
      );
      n.update(const MapPoint(70, 0, 0));
      expect(n.remaining, closeTo(20, .01));
      n.update(const MapPoint(30, 0, 0));
      expect(n.remaining, closeTo(60, .01));
      final t = DateTime(2026);
      n.update(const MapPoint(0, 0, 90), now: t, moving: false);
      n.update(
        const MapPoint(0, 0, 90),
        now: t.add(const Duration(seconds: 2)),
        moving: false,
      );
      expect(n.reroutes, 0);
      n.update(
        const MapPoint(0, 0, 90),
        now: t.add(const Duration(seconds: 3)),
      );
      expect(n.reroutes, 1);
      expect(n.route, isNotNull);
    },
  );
  test('bundled real game graph loads and routes through allowed transitions', () async {
    final g = await RoadGraph.load();
    expect(g.points.length, 38473);
    expect(g.segments.length, 71222);
    expect(g.next.fold<int>(0, (sum, n) => sum + n.length), 75626);
    expect(g.places.length, greaterThan(900));
    expect(
      g.places.where((p) => p.quality == 'community').length,
      greaterThan(700),
    );
    expect(g.places.where((p) => p.category == '广告牌').length, 200);
    expect(g.places.where((p) => p.category == '吉祥物').length, 200);
    expect(g.places.where((p) => p.category == '地标').length, 75);
    final start = g.nearby(g.points[0]).first;
    var reachable = 0;
    final watch = Stopwatch()..start();
    for (final place in g.places.where((p) => p.category == '赛道').take(24)) {
      final r = g.route(start, place.point);
      if (r == null) continue;
      reachable++;
      expect(r.length.isFinite, true);
      for (var i = 1; i < r.segments.length; i++) {
        expect(g.next[r.segments[i - 1]], contains(r.segments[i]));
      }
      expect(r.points.last.distance(place.point), lessThan(600));
    }
    expect(reachable, greaterThanOrEqualTo(20));
    var publicReachable = 0;
    for (final p
        in g.places
            .where((p) => ['地标', '广告牌', '吉祥物'].contains(p.category))
            .take(30)) {
      final r = g.route(start, p.point);
      if (r == null) continue;
      publicReachable++;
      expect(r.points.last.distance(p.point), lessThan(600));
      for (var i = 1; i < r.segments.length; i++) {
        expect(g.next[r.segments[i - 1]], contains(r.segments[i]));
      }
    }
    expect(publicReachable, greaterThanOrEqualTo(25));
    // A bounded smoke test for the complete game asset, not a mobile benchmark.
    expect(watch.elapsed.inSeconds, lessThan(30));
  });
}
