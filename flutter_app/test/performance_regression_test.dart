import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/road_graph.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/pages/dashboard_library.dart';
import 'package:horizon_link/pages/map_page.dart';
import 'package:horizon_link/pages/settings_page.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';
import 'package:horizon_link/widgets/dashboard_text_cache.dart';

void main() {
  testWidgets('waiting and interrupted states do not keep notifying at 10 Hz', (
    tester,
  ) async {
    final app = AppController(persist: false);
    var notifications = 0;
    app.addListener(() => notifications++);
    await tester.pump(const Duration(seconds: 1));
    final settled = notifications;
    await tester.pump(const Duration(seconds: 5));
    expect(notifications, settled);
    app.dispose();
  });

  test(
    'saved preferences become ready before a slow map and survive map failure',
    () async {
      final map = Completer<RoadGraph>();
      final settings = AppSettings()
        ..language = 'en'
        ..mph = true;
      final app = AppController(
        tick: false,
        loadRoadGraph: () => map.future,
        readData: () async => jsonEncode({
          'version': 2,
          'settings': settings.toJson(),
          'sessions': [],
        }),
      );
      addTearDown(app.dispose);
      await app.initialize().timeout(const Duration(seconds: 5));
      expect(app.ready, true);
      expect(app.settings.mph, true);
      expect(app.language.value, 'en');
      expect(app.roadGraph, isNull);
      map.completeError(StateError('map unavailable'));
      await app.mapLoaded;
      expect(app.mapError, contains('map unavailable'));
      expect(app.storageReadFailed, false);
      expect(app.settings.mph, true);
    },
  );

  test('late map completion seeds the latest real frame and is safe after disposal', () async {
    final map = Completer<RoadGraph>();
    final app = AppController(
      persist: false,
      tick: false,
      loadRoadGraph: () => map.future,
    );
    await app.initialize();
    app.ingest(TelemetryFrame(timestamp: 1, driving: true, x: 12, z: 34));
    map.complete(RoadGraph([], [], []));
    await app.mapLoaded;
    expect(app.navigation!.location!.x, 12);
    app.dispose();
    final lateMap = Completer<RoadGraph>();
    final disposed = AppController(
      persist: false,
      tick: false,
      loadRoadGraph: () => lateMap.future,
    );
    await disposed.initialize();
    disposed.dispose();
    lateMap.complete(RoadGraph([], [], []));
    await disposed.mapLoaded;
    expect(disposed.roadGraph, isNull);
  });

  testWidgets(
    'tabs are created on first visit and retained; covered library stays quiet',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      await tester.pumpWidget(HorizonApp(controller: app));
      await tester.pumpAndSettle();
      expect(find.byType(MapPage, skipOffstage: false), findsNothing);
      expect(find.byType(SettingsPage, skipOffstage: false), findsNothing);
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      final mapState = tester.state(find.byType(MapPage));
      await tester.tap(find.byType(NavigationDestination).at(0));
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(DashboardLibrary));
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('covered')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final library = tester.widget(
        find.byType(DashboardLibrary, skipOffstage: false),
      );
      app.ingest(TelemetryFrame(timestamp: 1, speed: 10));
      await tester.pump();
      expect(
        tester.widget(find.byType(DashboardLibrary, skipOffstage: false)),
        same(library),
      );
      Navigator.of(tester.element(find.text('covered'))).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(MapPage)), same(mapState));
    },
  );

  testWidgets(
    'settings page ignores unrelated telemetry but responds to preferences',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      await tester.pumpWidget(HorizonApp(controller: app));
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      final page = tester.widget(find.byType(SettingsPage));
      app.ingest(TelemetryFrame(timestamp: 1, speed: 20));
      await tester.pump();
      expect(tester.widget(find.byType(SettingsPage)), same(page));
      app.updateSettings((s) => s.mph = true);
      await tester.pump();
      expect(tester.widget(find.byType(SettingsPage)), isNot(same(page)));
    },
  );

  test('paragraph cache reuses layouts and bounds changing readouts', () {
    final cache = DashboardTextCache(capacity: 2);
    addTearDown(cache.clear);
    const style = TextStyle(fontSize: 20);
    final first = cache.layout('100', style);
    expect(cache.layout('100', style), same(first));
    cache.layout('101', style);
    cache.layout('102', style);
    expect(cache.layout('100', style), isNot(same(first)));
    final narrow = cache.layout('100', style, maxWidth: 15);
    expect(narrow.width, lessThanOrEqualTo(15));
    cache.clear();
    expect(cache.layout('100', style), isNot(same(narrow)));
  });

  test(
    'cached dashboard paint matches uncached output for every built-in layout',
    () async {
      final cache = DashboardTextCache();
      addTearDown(cache.clear);
      final settings = AppSettings();
      final frame = TelemetryFrame(speed: 31, rpm: 6500, maxRpm: 7000);
      for (final style in DashboardStyle.values) {
        Future<List<int>> render(DashboardTextCache? cache) async {
          final recorder = ui.PictureRecorder();
          DashboardPainter(
            frame,
            settings,
            style,
            null,
            null,
            true,
            cache,
          ).paint(Canvas(recorder), const Size(640, 270));
          final picture = recorder.endRecording();
          final image = await picture.toImage(640, 270);
          final bytes = (await image.toByteData())!.buffer.asUint8List();
          image.dispose();
          picture.dispose();
          return bytes;
        }

        final expected = await render(null);
        expect(await render(cache), expected, reason: style.name);
        expect(await render(cache), expected, reason: 'warm ${style.name}');
      }
    },
  );
}
