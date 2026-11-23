import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

class MapPoint {
  final double x, y, z;
  const MapPoint(this.x, this.y, this.z);
  double distance(MapPoint b) => math.sqrt(
    (x - b.x) * (x - b.x) + (y - b.y) * (y - b.y) + (z - b.z) * (z - b.z),
  );
  MapPoint mix(MapPoint b, double t) =>
      MapPoint(x + (b.x - x) * t, y + (b.y - y) * t, z + (b.z - z) * t);
}

class MapPlace {
  final String id, name, category, quality, note;
  final String? nameZh, nameEn;
  final MapPoint point;
  const MapPlace(
    this.id,
    this.name,
    this.category,
    this.point, {
    this.quality = 'user',
    this.note = '自定义坐标',
    this.nameZh,
    this.nameEn,
  });
  String displayName(String language) =>
      language == 'en' ? (nameEn ?? name) : (nameZh ?? name);
  bool matchesName(String query) => [id, name, nameZh, nameEn]
      .whereType<String>()
      .any((s) => s.toLowerCase().contains(query.toLowerCase()));
  factory MapPlace.fromJson(
    Map<String, dynamic> j, [
    Map<String, dynamic>? names,
  ]) => MapPlace(
    j['id'],
    j['name'],
    j['category'],
    MapPoint(
      (j['x'] as num).toDouble(),
      (j['y'] as num).toDouble(),
      (j['z'] as num).toDouble(),
    ),
    quality: j['quality'] ?? 'community',
    note: j['note'] ?? '社区坐标 · 待游戏实测',
    nameZh: names?['zh'] as String?,
    nameEn: names?['en'] as String?,
  );
}

class RoadSegment {
  final int id, section, from, to;
  final double length;
  final String type;
  const RoadSegment(
    this.id,
    this.section,
    this.from,
    this.to,
    this.length,
    this.type,
  );
}

class RoadSnap {
  final int segment;
  final double t, distance;
  final MapPoint point;
  const RoadSnap(this.segment, this.t, this.distance, this.point);
}

class NavigationRoute {
  final List<int> segments;
  final List<MapPoint> points;
  final List<double> cumulative;
  final double length;
  const NavigationRoute(
    this.segments,
    this.points,
    this.cumulative,
    this.length,
  );
  MapPoint at(double meters) {
    if (meters <= 0) return points.first;
    for (var i = 1; i < points.length; i++) {
      if (cumulative[i] >= meters) {
        final length = cumulative[i] - cumulative[i - 1];
        return length < .001
            ? points[i]
            : points[i - 1].mix(
                points[i],
                (meters - cumulative[i - 1]) / length,
              );
      }
    }
    return points.last;
  }
}

/// Explicit WVAN topology: crossings connect only through shared game node IDs.
class RoadGraph {
  final List<MapPoint> points;
  final List<RoadSegment> segments;
  final List<List<int>> next;
  final List<MapPlace> places;
  final String sha;
  final Map<(int, int), List<int>> _grid = {};
  RoadGraph(
    this.points,
    this.segments,
    this.next, {
    this.places = const [],
    this.sha = '',
  }) {
    for (final s in segments) {
      final a = points[s.from], b = points[s.to];
      for (
        var x = (math.min(a.x, b.x) / 100).floor();
        x <= (math.max(a.x, b.x) / 100).floor();
        x++
      ) {
        for (
          var z = (math.min(a.z, b.z) / 100).floor();
          z <= (math.max(a.z, b.z) / 100).floor();
          z++
        ) {
          (_grid[(x, z)] ??= []).add(s.id);
        }
      }
    }
  }
  static Future<RoadGraph> load() async {
    final texts = await Future.wait(
      [
        'assets/map/navgraph.json',
        'assets/map/places.json',
        'assets/map/place_names.json',
      ].map(rootBundle.loadString),
    );
    return compute(fromAssetTexts, texts, debugLabel: 'offline-road-graph');
  }

  /// Decode and build the spatial index together, away from the UI isolate.
  static RoadGraph fromAssetTexts(List<String> texts) {
    final j = jsonDecode(texts[0]) as Map<String, dynamic>;
    final pts = (j['points'] as List)
        .map(
          (p) => MapPoint(
            (p[1] as num).toDouble(),
            (p[2] as num).toDouble(),
            (p[3] as num).toDouble(),
          ),
        )
        .toList();
    final segs = (j['segments'] as List)
        .map(
          (s) => RoadSegment(
            s[0],
            s[1],
            s[2],
            s[3],
            (s[4] as num).toDouble(),
            s[6],
          ),
        )
        .toList();
    final adjacency = List.generate(segs.length, (_) => <int>[]);
    for (final t in j['transitions']) {
      adjacency[t[0]].add(t[1]);
    }
    final names =
        (jsonDecode(texts[2]) as Map<String, dynamic>)['names']
            as Map<String, dynamic>;
    final places = (jsonDecode(texts[1]) as List)
        .map(
          (p) => MapPlace.fromJson(
            Map<String, dynamic>.from(p),
            names[p['id']] == null
                ? null
                : Map<String, dynamic>.from(names[p['id']]),
          ),
        )
        .toList();
    return RoadGraph(
      pts,
      segs,
      adjacency,
      places: places,
      sha: j['source']['sha256'],
    );
  }

  /// Conservative X/Z query including roads whose endpoints are outside.
  /// Uses the existing 100 m index rather than scanning the full road graph.
  Set<int> segmentsInWindow(MapPoint center, double halfExtent) {
    final result = <int>{};
    for (
      var x = ((center.x - halfExtent) / 100).floor();
      x <= ((center.x + halfExtent) / 100).floor();
      x++
    ) {
      for (
        var z = ((center.z - halfExtent) / 100).floor();
        z <= ((center.z + halfExtent) / 100).floor();
        z++
      ) {
        result.addAll(_grid[(x, z)] ?? const <int>[]);
      }
    }
    return result;
  }

  RoadSnap project(MapPoint p, int id, {bool altitude = true}) {
    final s = segments[id],
        a = points[s.from],
        b = points[s.to],
        dx = b.x - a.x,
        dz = b.z - a.z;
    final t = (((p.x - a.x) * dx + (p.z - a.z) * dz) / (dx * dx + dz * dz))
        .clamp(0.0, 1.0);
    final q = a.mix(b, t), dy = altitude ? p.y - q.y : 0.0;
    return RoadSnap(
      id,
      t,
      math.sqrt(
        (p.x - q.x) * (p.x - q.x) + (p.z - q.z) * (p.z - q.z) + dy * dy,
      ),
      q,
    );
  }

  List<RoadSnap> nearby(
    MapPoint p, {
    double? heading,
    bool altitude = true,
    double radius = 180,
  }) {
    final ids = <int>{},
        cells = (radius / 100).ceil(),
        cx = (p.x / 100).floor(),
        cz = (p.z / 100).floor();
    for (var x = cx - cells; x <= cx + cells; x++) {
      for (var z = cz - cells; z <= cz + cells; z++) {
        ids.addAll(_grid[(x, z)] ?? const []);
      }
    }
    final matches = ids
        .map((id) => project(p, id, altitude: altitude))
        .where((s) => s.distance <= radius)
        .toList();
    double score(RoadSnap n) {
      if (heading == null) return n.distance;
      final s = segments[n.segment], a = points[s.from], b = points[s.to];
      return n.distance +
          (1 - math.cos(math.atan2(b.x - a.x, b.z - a.z) - heading)) * 35;
    }

    matches.sort((a, b) => score(a).compareTo(score(b)));
    return matches;
  }

  /// A* over directed segments, honoring the extracted legal transition table.
  NavigationRoute? route(RoadSnap start, MapPoint destination) {
    final goals = nearby(destination, radius: 600);
    if (goals.isEmpty) return null;
    final closest = goals.reduce((a, b) => a.distance < b.distance ? a : b),
        gseg =
            segments[goals
                .reduce((a, b) => a.distance < b.distance ? a : b)
                .segment];
    final targets = {
      for (final g in goals.where((g) {
        final s = segments[g.segment];
        return (s.from == gseg.from && s.to == gseg.to) ||
            (s.from == gseg.to && s.to == gseg.from);
      }))
        g.segment: g,
    };
    NavigationRoute make(List<int> ids, RoadSnap end) {
      final path = <MapPoint>[start.point];
      for (var i = 0; i < ids.length; i++) {
        path.add(i == ids.length - 1 ? end.point : points[segments[ids[i]].to]);
      }
      final cumulative = <double>[0];
      for (var i = 1; i < path.length; i++) {
        cumulative.add(cumulative.last + path[i - 1].distance(path[i]));
      }
      return NavigationRoute(ids, path, cumulative, cumulative.last);
    }

    final direct = targets[start.segment];
    if (direct != null && direct.t >= start.t) {
      return make([start.segment], direct);
    }
    final seed = segments[start.segment],
        initial = segments[start.segment].length * (1 - start.t);
    final cost = <int, double>{start.segment: initial}, prev = <int, int>{};
    double heuristic(int id) {
      final p = points[segments[id].to];
      return math.sqrt(
        math.pow(p.x - closest.point.x, 2) + math.pow(p.z - closest.point.z, 2),
      );
    }

    final heap = _MinHeap()
      ..add((initial + heuristic(seed.id), seed.id, initial));
    double best = double.infinity;
    List<int>? bestIds;
    RoadSnap? bestEnd;
    while (heap.isNotEmpty) {
      final entry = heap.pop(), id = entry.$2;
      if (entry.$1 >= best) break;
      if (entry.$3 > cost[id]!) continue;
      for (final n in next[id]) {
        final s = segments[n], end = targets[n];
        if (end != null) {
          final total = cost[id]! + s.length * end.t;
          if (total < best) {
            best = total;
            bestEnd = end;
            var current = id;
            final reverse = <int>[current];
            while (current != start.segment) {
              current = prev[current]!;
              reverse.add(current);
            }
            bestIds = [...reverse.reversed, n];
          }
        }
        final proposed = cost[id]! + s.length;
        if (proposed < (cost[n] ?? double.infinity)) {
          cost[n] = proposed;
          prev[n] = id;
          heap.add((proposed + heuristic(n), n, proposed));
        }
      }
    }
    return bestIds == null ? null : make(bestIds, bestEnd!);
  }
}

class _MinHeap {
  final _items = <(double, int, double)>[];
  bool get isNotEmpty => _items.isNotEmpty;
  void add((double, int, double) item) {
    _items.add(item);
    var i = _items.length - 1;
    while (i > 0) {
      final p = (i - 1) ~/ 2;
      if (_items[p].$1 <= item.$1) break;
      _items[i] = _items[p];
      i = p;
    }
    _items[i] = item;
  }

  (double, int, double) pop() {
    final top = _items.first, last = _items.removeLast();
    if (_items.isEmpty) return top;
    var i = 0;
    while (i * 2 + 1 < _items.length) {
      var c = i * 2 + 1;
      if (c + 1 < _items.length && _items[c + 1].$1 < _items[c].$1) c++;
      if (_items[c].$1 >= last.$1) break;
      _items[i] = _items[c];
      i = c;
    }
    _items[i] = last;
    return top;
  }
}

String mapDistance(double meters) => meters >= 1000
    ? '${(meters / 1000).toStringAsFixed(1)} km'
    : '${(meters / 10).round() * 10} m';
