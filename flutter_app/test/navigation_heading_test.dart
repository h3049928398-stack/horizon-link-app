import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/navigation.dart';
import 'package:horizon_link/core/road_graph.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/pages/map_page.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';

RoadGraph twoWayRoad() => RoadGraph(
  const [MapPoint(-100, 0, 0), MapPoint(100, 0, 0)],
  const [RoadSegment(0, 0, 0, 1, 200, ''), RoadSegment(1, 0, 1, 0, 200, '')],
  [[], []],
);

Uint8List packet(double yaw) {
  final bytes = Uint8List(324);
  final view = ByteData.sublistView(bytes);
  view.setInt32(0, 1, Endian.little);
  view.setUint32(4, 100, Endian.little);
  // Fixed wire offset from the documented header, independent of parser fields.
  view.setFloat32(56, yaw, Endian.little);
  return bytes;
}

Future<Uint8List> dashboardPixels(NavigationState? navigation) async {
  final recorder = ui.PictureRecorder();
  DashboardPainter(
    TelemetryFrame(),
    AppSettings(),
    DashboardStyle.basic,
    null,
    navigation,
  ).paint(Canvas(recorder), const Size(1280, 540));
  final picture = recorder.endRecording();
  final image = await picture.toImage(1280, 540);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final result = Uint8List.fromList(data.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

List<int> rgb(Uint8List data, int x, int y) =>
    data.sublist((y * 1280 + x) * 4, (y * 1280 + x) * 4 + 3);

List<(int, int)> arrowPixels(Uint8List data) => [
  for (var y = 417; y <= 443; y++)
    for (var x = 628; x <= 652; x++)
      if (rgb(data, x, y)[0] > 220 && rgb(data, x, y)[1] > 220) (x, y),
];

NavigationState preview(
  double heading, {
  bool routeFollowsHeading = false,
  double length = 500,
}) {
  final n = NavigationState(twoWayRoad());
  n.update(const MapPoint(0, 0, 0), yaw: heading);
  final angle = routeFollowsHeading ? heading : 0.0;
  n.route = NavigationRoute(
    const [0],
    [
      const MapPoint(0, 0, 0),
      MapPoint(length * math.sin(angle), 0, length * math.cos(angle)),
    ],
    [0, length],
    length,
  );
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('UDP body yaw survives JSON; missing old yaw stays unknown', () {
    for (final yaw in [0.0, math.pi / 2, -math.pi / 2, math.pi]) {
      final f = decodePacket(packet(yaw));
      expect(f.yaw, closeTo(yaw, .000001));
      expect(
        TelemetryFrame.fromJson(jsonDecode(jsonEncode(f.toJson()))).yaw,
        f.yaw,
      );
    }
    expect(TelemetryFrame.fromJson({'x': 10, 'z': 20}).yaw, isNull);
    expect(TelemetryFrame().toJson().containsKey('yaw'), false);
    expect(TelemetryFrame.fromJson({'yaw': double.nan}).yaw, isNull);
    expect(() => decodePacket(packet(double.nan)), throwsFormatException);
  });

  test(
    'body yaw updates at rest and low speed, independent of displacement',
    () {
      final n = NavigationState(twoWayRoad());
      for (final yaw in [0.0, math.pi / 2, math.pi, -math.pi / 2]) {
        n.update(const MapPoint(0, 0, 0), moving: false, yaw: yaw);
        expect(n.heading, closeTo(yaw, .000001));
      }
      n.update(const MapPoint(.1, 0, 0), moving: false, yaw: .3);
      expect(n.heading, closeTo(.3, .000001));
      n.update(const MapPoint(.2, 0, 0), yaw: 2 * math.pi + .4);
      expect(n.heading, closeTo(.4, .000001));
      n.update(const MapPoint(.3, 0, 0), yaw: double.infinity);
      expect(n.heading, closeTo(.4, .000001));
    },
  );

  test(
    'reverse and drift keep body heading while matching the travel direction',
    () {
      final n = NavigationState(twoWayRoad());
      n.update(const MapPoint(20, 0, 0), yaw: math.pi / 2);
      n.update(const MapPoint(10, 0, 0), yaw: math.pi / 2);
      expect(n.heading, closeTo(math.pi / 2, .000001));
      expect(n.snap!.segment, 1); // Moving west, nose east.
      n.update(const MapPoint(30, 0, 0), yaw: 0);
      expect(n.heading, 0); // Sliding east, nose north.
      expect(n.snap!.segment, 0);
    },
  );

  test('old frames fall back to course; reconnect clears stale heading', () {
    final n = NavigationState(twoWayRoad());
    n.update(const MapPoint(0, 0, 0));
    n.update(const MapPoint(10, 0, 0));
    expect(n.heading, closeTo(math.pi / 2, .000001));
    n.update(const MapPoint(10, 0, 0), moving: false);
    expect(n.heading, closeTo(math.pi / 2, .000001));
    n.resetLocation();
    expect(n.heading, isNull);
    expect(n.location, isNull);
    n.update(const MapPoint(0, 0, 0), yaw: 0);
    expect(n.heading, 0);
    expect(n.snap!.segment, 0);
  });

  test(
    'controller forwards decoded yaw and invalidates stationary map view',
    () async {
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      app.navigation = NavigationState(twoWayRoad());
      app.ingest(decodePacket(packet(0)));
      final before = MapPage.viewState(app);
      final bytes = packet(math.pi / 2);
      ByteData.sublistView(bytes).setUint32(4, 200, Endian.little);
      app.ingest(decodePacket(bytes));
      expect(app.navigation!.heading, closeTo(math.pi / 2, .000001));
      expect(MapPage.viewState(app), isNot(before));
      app.ingest(TelemetryFrame(timestamp: 300, yaw: math.pi, driving: false));
      expect(app.navigation!.heading, closeTo(math.pi / 2, .000001));
      await app.connect();
      expect(app.navigation!.heading, isNull);
    },
  );

  test(
    'basic navigation arrow stays up while northbound route rotates around it',
    () async {
      final north = await dashboardPixels(preview(0));
      final east = await dashboardPixels(preview(math.pi / 2));
      final south = await dashboardPixels(preview(math.pi));
      final west = await dashboardPixels(preview(-math.pi / 2));
      final noRoute = await dashboardPixels(null);
      expect(arrowPixels(north).length, greaterThan(60));
      for (final data in [east, south, west, noRoute]) {
        expect(arrowPixels(data), arrowPixels(north));
      }
      expect(rgb(north, 640, 405), [89, 229, 243]);
      expect(rgb(east, 610, 432), [89, 229, 243]);
      expect(rgb(west, 670, 432), [89, 229, 243]);
      expect(rgb(south, 640, 405), [3, 4, 5]);
    },
  );

  test(
    'road ahead stays above arrow in all cardinal headings and across wrap',
    () async {
      for (final heading in [
        0.0,
        math.pi / 2,
        math.pi,
        -math.pi / 2,
        2 * math.pi + .01,
      ]) {
        final pixels = await dashboardPixels(
          preview(heading, routeFollowsHeading: true, length: 1500),
        );
        expect(rgb(pixels, 640, 370), [89, 229, 243]);
        // About 1.15 km ahead is visible; the old preview ended at 600 m.
        expect(rgb(pixels, 640, 340), [89, 229, 243]);
        expect(rgb(pixels, 640, 423), [244, 245, 241]);
        expect(rgb(pixels, 610, 432), [3, 4, 5]);
      }
    },
  );

  test(
    'mini route is relative to actual car location instead of road snap',
    () async {
      final n = preview(0)..location = const MapPoint(-100, 0, 0);
      final pixels = await dashboardPixels(n);
      expect(rgb(pixels, 648, 405), [89, 229, 243]);
      expect(rgb(pixels, 640, 405), [3, 4, 5]);
      expect(rgb(pixels, 640, 423), [244, 245, 241]);
    },
  );
}
