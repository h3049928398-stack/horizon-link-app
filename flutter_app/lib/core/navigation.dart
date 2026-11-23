import 'dart:math' as math;

import 'road_graph.dart';

class NavigationState {
  final RoadGraph graph;
  MapPlace? destination;
  NavigationRoute? route;
  MapPoint? location;
  RoadSnap? snap;
  double? heading;
  // Course follows displacement; body heading must not select the opposite
  // carriageway while reversing or sliding sideways.
  double? _course;
  double progress = 0, remaining = 0, turnDistance = 0;
  String instruction = '选择目的地', status = '等待车辆定位';
  int turn = 0, reroutes = 0;
  bool arrived = false, offRoute = false;
  DateTime? _offSince, _lastReroute;
  NavigationState(this.graph);
  bool start(MapPlace place) {
    if (snap == null) {
      status = '车辆离道路太远，请先返回道路';
      return false;
    }
    destination = place;
    arrived = false;
    reroutes = 0;
    progress = 0;
    route = graph.route(snap!, place.point);
    status = route == null ? '未找到符合道路限制的路线' : '沿路线行驶';
    remaining = route?.length ?? 0;
    _offSince = null;
    offRoute = false;
    _instructions();
    return route != null;
  }

  void stop() {
    destination = null;
    route = null;
    instruction = '选择目的地';
    status = '导航已结束';
    arrived = false;
    offRoute = false;
  }

  void resetLocation() {
    location = null;
    snap = null;
    heading = null;
    _course = null;
  }

  void update(
    MapPoint point, {
    DateTime? now,
    bool moving = true,
    double? yaw,
  }) {
    now ??= DateTime.now();
    if (location != null &&
        point.distance(location!) > 2 &&
        point.distance(location!) < 100) {
      _course = math.atan2(point.x - location!.x, point.z - location!.z);
    }
    // Forza yaw: zero faces world +Z, positive turns toward +X. The map
    // projects +Z upward and +X rightward, so it uses this same clockwise angle.
    // Normalize with sin/cos to handle wrapping without a 360-degree jump.
    heading = yaw != null && yaw.isFinite
        ? math.atan2(math.sin(yaw), math.cos(yaw))
        : _course ?? heading;
    location = point;
    final matches = graph.nearby(point, heading: moving ? _course : null);
    snap = matches.isEmpty ? null : matches.first;
    if (route == null) {
      if (destination == null) {
        status = snap == null ? '车辆离道路较远' : '已定位到游戏道路';
        return;
      }
      if (snap == null ||
          !moving ||
          (_lastReroute != null &&
              now.difference(_lastReroute!).inSeconds < 4)) {
        return;
      }
      _lastReroute = now;
      route = graph.route(snap!, destination!.point);
      if (route == null) return;
      progress = 0;
      remaining = route!.length;
      reroutes++;
    }
    final r = route!;
    double best = double.infinity, bestDistance = double.infinity, along = 0;
    for (var i = 0; i < r.segments.length; i++) {
      final a = r.points[i],
          b = r.points[i + 1],
          dx = b.x - a.x,
          dz = b.z - a.z,
          denom = (b.x - a.x) * (b.x - a.x) + (b.z - a.z) * (b.z - a.z);
      final t = denom == 0
          ? 0.0
          : (((point.x - a.x) * dx + (point.z - a.z) * dz) / denom).clamp(
              0.0,
              1.0,
            );
      final d = point.distance(a.mix(b, t));
      final candidate =
          d + math.max(0, (r.cumulative[i] - progress).abs() - 250) * .005;
      if (candidate < best) {
        best = candidate;
        bestDistance = d;
        along = r.cumulative[i] + (r.cumulative[i + 1] - r.cumulative[i]) * t;
      }
    }
    progress = along;
    remaining = math.max(0, r.length - progress);
    arrived = remaining < 25 && point.distance(r.points.last) < 35;
    if (arrived) {
      instruction = '已到达道路入口';
      status = '目的地附近 · 留意实际入口';
      offRoute = false;
      return;
    }
    offRoute = bestDistance > 55;
    if (offRoute) {
      _offSince ??= now;
      status = '已偏离路线';
      if (snap != null &&
          moving &&
          now.difference(_offSince!).inMilliseconds >= 1200 &&
          (_lastReroute == null ||
              now.difference(_lastReroute!).inSeconds >= 4)) {
        _lastReroute = now;
        reroutes++;
        route = graph.route(snap!, destination!.point);
        progress = 0;
        remaining = route?.length ?? 0;
        status = route == null ? '无可用路线，请返回道路' : '路线已重新规划';
        _offSince = null;
      }
    } else {
      _offSince = null;
      status = '沿路线行驶';
    }
    _instructions();
  }

  void _instructions() {
    turn = 0;
    turnDistance = remaining;
    instruction = route == null ? '未找到可用路线' : '继续行驶';
    final r = route;
    if (r == null) return;
    for (var i = 1; i < r.points.length - 1; i++) {
      if (r.cumulative[i] < progress + 12) continue;
      final incoming = graph.segments[r.segments[i - 1]],
          outgoing = graph.segments[r.segments[i]];
      if (incoming.section == outgoing.section) continue;
      final a = r.at(math.max(0, r.cumulative[i] - 35)),
          b = r.points[i],
          c = r.at(math.min(r.length, r.cumulative[i] + 35));
      final cross = (b.x - a.x) * (c.z - b.z) - (b.z - a.z) * (c.x - b.x),
          dot = (b.x - a.x) * (c.x - b.x) + (b.z - a.z) * (c.z - b.z);
      final angle = math.atan2(cross, dot) * 180 / math.pi;
      if (angle.abs() < 25) continue;
      turn = angle < 0 ? 1 : -1;
      turnDistance = r.cumulative[i] - progress;
      instruction = angle.abs() > 125
          ? '前方急${turn > 0 ? '右' : '左'}转'
          : angle.abs() < 50
          ? '向${turn > 0 ? '右' : '左'}前方行驶'
          : '前方${turn > 0 ? '右' : '左'}转';
      return;
    }
    if (remaining < 120) instruction = '即将到达道路入口';
  }
}
