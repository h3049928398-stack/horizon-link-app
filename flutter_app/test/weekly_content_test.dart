import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/navigation.dart';
import 'package:horizon_link/core/road_graph.dart';
import 'package:horizon_link/core/weekly_content.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/services/weekly_content_service.dart';
import 'package:horizon_link/services/weekly_platform_io.dart' as platform;

class _LocalHttpOverrides extends HttpOverrides {}

final now = DateTime.utc(2026, 11, 2);
final graph = RoadGraph(
  [],
  [],
  [],
  places: [
    const MapPlace(
      'base',
      'Existing place',
      '赛事',
      MapPoint(100, 10, 200),
      quality: 'community',
    ),
  ],
);
Map<String, dynamic> fixture([int revision = 1]) => {
  'schemaVersion': 1,
  'revision': revision,
  'periods': [
    {
      'id': 'week',
      'name': {'zh': '测试周期', 'en': 'Test week'},
      'startsAt': '2026-11-01T00:00:00+08:00',
      'endsAt': '2026-11-08T00:00:00+08:00',
      'events': [
        {
          'id': 'race',
          'type': 'seasonal',
          'name': {'zh': '测试赛事', 'en': 'Test race'},
          'locations': [
            {
              'id': 'location',
              'name': {'zh': '测试位置', 'en': 'Test location'},
              'placeId': 'base',
              'source': 'Test fixture only',
              'quality': 'verified',
            },
            {
              'id': 'pending',
              'name': {'zh': '待定位置'},
              'source': 'Awaiting evidence',
              'quality': 'unknown',
            },
          ],
        },
        {
          'id': 'chest',
          'type': 'treasure',
          'name': {'zh': '测试宝箱'},
          'locations': [
            {
              'id': 'chest-location',
              'name': {'zh': '宝箱位置'},
              'coordinates': {'x': -100, 'y': 10, 'z': -200},
              'source': 'Test only',
              'quality': 'community',
            },
          ],
        },
      ],
    },
  ],
};
Map<String, dynamic> location(Map<String, dynamic> j) =>
    j['periods'][0]['events'][0]['locations'][0];
String encoded([int revision = 1]) => jsonEncode(fixture(revision));

void main() {
  test('native transport receives UTF8 and rejects redirects, errors and oversized bodies', () async {
    await HttpOverrides.runWithHttpOverrides(() async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        switch (request.uri.path) {
          case '/ok':
            request.response.headers.contentType = ContentType.json;
            request.response.write(encoded());
          case '/redirect':
            request.response.statusCode = 302;
            request.response.headers.set('location', '/ok');
          case '/large':
            request.response.add(List.filled(weeklyMaxBytes + 1, 32));
          default:
            request.response.statusCode = 503;
        }
        await request.response.close();
      });
      Uri uri(String path) => Uri.parse('http://127.0.0.1:${server.port}$path');
      expect(
        WeeklyContent.parse(
          await platform.fetchWeekly(uri('/ok')),
          graph,
        ).revision,
        1,
      );
      for (final path in ['/redirect', '/error', '/large']) {
        await expectLater(
          platform.fetchWeekly(uri(path)),
          throwsA(isA<HttpException>()),
        );
      }
    }, _LocalHttpOverrides());
  });

  testWidgets(
    'scheduled rollover expires markers and next content refreshes map caches',
    (tester) async {
      var clock = DateTime.parse('2026-11-07T23:59:59+08:00');
      var response = encoded();
      final service = WeeklyContentService(
        persist: false,
        url: 'https://example.com/weekly.json',
        clock: () => clock,
        fetch: (_) async => response,
      );
      final app = AppController(persist: false, tick: false, weekly: service);
      var disposed = false;
      addTearDown(() {
        if (!disposed) app.dispose();
      });
      app.roadGraph = graph;
      app.navigation = NavigationState(graph);
      await service.initialize(graph);
      await tester.pumpWidget(HorizonApp(controller: app));
      await tester.pumpAndSettle();
      app.focusWeeklyPlace(service.mapPlaces.first);
      await tester.pumpAndSettle();
      expect(find.text('测试位置'), findsOneWidget);
      final changed = fixture(2);
      location(changed)['name'] = {'zh': '新版位置'};
      location(changed).remove('placeId');
      location(changed)['coordinates'] = {'x': -200, 'y': 0, 'z': -200};
      response = jsonEncode(changed);
      await service.refresh(force: true);
      await tester.pumpAndSettle();
      expect(find.text('新版位置'), findsOneWidget);
      expect(service.mapPlaces.first.point.x, -200);
      clock = DateTime.parse('2026-11-08T00:00:00+08:00');
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(service.current, isNull);
      expect(service.mapPlaces, isEmpty);
      expect(find.text('新版位置'), findsNothing);
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('上期内容'), 150);
      await tester.pumpAndSettle();
      expect(find.text('此内容已过期，仅供参考'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      app.dispose();
      disposed = true;
    },
  );

  test(
    'HTTP endpoint and mismatched source cache never load content',
    () async {
      var calls = 0;
      final service = WeeklyContentService(
        url: 'http://example.com/weekly.json',
        clock: () => now,
        readCache: () async => jsonEncode({
          'url': 'https://old.example/weekly.json',
          'checkedAt': now.toIso8601String(),
          'content': encoded(),
        }),
        fetch: (_) async {
          calls++;
          return encoded();
        },
      );
      addTearDown(service.dispose);
      await service.initialize(graph);
      expect(calls, 0);
      expect(service.content, isNull);
      expect(service.status, WeeklyStatus.unconfigured);
    },
  );

  test('period boundaries, fallback language, multi-location and inherited quality', () {
    final content = WeeklyContent.parse(encoded(), graph);
    expect(content.current(now), isNotNull);
    expect(
      content.current(DateTime.parse('2026-11-08T00:00:00+08:00')),
      isNull,
    );
    expect(
      content.current(DateTime.parse('2026-11-01T00:00:00+08:00')),
      isNotNull,
    );
    expect(content.previous(now), isNull);
    expect(content.previous(DateTime.utc(2026, 11, 10))?.id, 'week');
    final event = content.current(now)!.events.first;
    expect(event.locations.length, 2);
    expect(
      event.locations.first.resolve(graph, event.name)!.quality,
      'community',
    );
    expect(event.locations.last.resolve(graph, event.name), isNull);
    expect(event.locations.last.name.display('en'), '待定位置');
  });

  final invalid = <String, void Function(Map<String, dynamic>)>{
    'schema': (j) => j['schemaVersion'] = 2,
    'fractional revision': (j) => j['revision'] = 1.5,
    'duplicate IDs': (j) => location(j)['id'] = 'race',
    'unknown place': (j) => location(j)['placeId'] = 'missing',
    'ambiguous coordinate': (j) =>
        location(j)['coordinates'] = {'x': 0, 'y': 0, 'z': 0},
    'outside map': (j) {
      location(j).remove('placeId');
      location(j)['coordinates'] = {'x': 1e9, 'y': 0, 'z': 0};
    },
    'invalid coordinate': (j) {
      location(j).remove('placeId');
      location(j)['coordinates'] = {'x': '0', 'y': 0, 'z': 0};
    },
    'missing timezone': (j) =>
        j['periods'][0]['startsAt'] = '2026-11-01T00:00:00',
    'invalid calendar': (j) =>
        j['periods'][0]['startsAt'] = '2026-02-30T00:00:00Z',
    'invalid timezone': (j) =>
        j['periods'][0]['startsAt'] = '2026-11-01T00:00:00+14:30',
    'oversized revision': (j) => j['revision'] = 2147483648,
    'reversed dates': (j) => j['periods'][0]['endsAt'] = '2025-11-01T00:00:00Z',
    'overlap': (j) {
      final p = jsonDecode(jsonEncode(j['periods'][0]));
      p['id'] = 'second';
      p['events'] = [];
      j['periods'].add(p);
    },
    'missing source': (j) => location(j)['source'] = '',
    'missing quality': (j) => location(j)['quality'] = null,
    'empty name': (j) => location(j)['name'] = {'zh': ''},
  };
  for (final entry in invalid.entries) {
    test('reject ${entry.key}', () {
      final j = jsonDecode(encoded()) as Map<String, dynamic>;
      entry.value(j);
      expect(
        () => WeeklyContent.parse(jsonEncode(j), graph),
        throwsFormatException,
      );
    });
  }
  test('reject malformed and oversized content', () {
    expect(
      () => WeeklyContent.parse('<html>unavailable</html>', graph),
      throwsFormatException,
    );
    expect(
      () => WeeklyContent.parse(' ' * (weeklyMaxBytes + 1), graph),
      throwsFormatException,
    );
  });

  test('cache restart, two revisions without install, failure and rollback protection', () async {
    String? disk;
    var response = encoded();
    var fail = false, requests = 0;
    var clock = now;
    WeeklyContentService create() => WeeklyContentService(
      url: 'https://example.com/weekly.json',
      clock: () => clock,
      readCache: () async => disk,
      writeCache: (s) async {
        disk = s;
      },
      fetch: (_) async {
        requests++;
        if (fail) throw StateError('offline');
        return response;
      },
    );
    final s = create();
    addTearDown(s.dispose);
    await s.initialize(graph);
    expect(s.content!.revision, 1);
    expect(requests, 1);
    final firstCache = disk;
    await s.refresh();
    expect(requests, 1);
    response = encoded(2);
    await s.refresh(force: true);
    expect(s.content!.revision, 2);
    expect(disk, isNot(firstCache));
    response = 'broken';
    await s.refresh(force: true);
    expect(s.status, WeeklyStatus.failed);
    expect(s.content!.revision, 2);
    response = encoded(1);
    await s.refresh(force: true);
    expect(s.content!.revision, 2);
    expect(s.status, WeeklyStatus.failed);
    final changed = fixture(2);
    changed['periods'][0]['name']['zh'] = 'Unversioned edit';
    response = jsonEncode(changed);
    await s.refresh(force: true);
    expect(s.status, WeeklyStatus.failed);
    fail = true;
    final restarted = create();
    addTearDown(restarted.dispose);
    await restarted.initialize(graph);
    expect(restarted.content!.revision, 2);
    clock = clock.add(const Duration(hours: 7));
    await restarted.refresh();
    expect(restarted.status, WeeklyStatus.failed);
    clock = DateTime.utc(2026, 11, 10);
    expect(restarted.current, isNull);
    expect(restarted.displayed!.id, 'week');
    expect(restarted.mapPlaces, isEmpty);
  });

  test(
    'unconfigured, corrupt cache, write failure and request deduplication',
    () async {
      final unconfigured = WeeklyContentService(persist: false);
      addTearDown(unconfigured.dispose);
      await unconfigured.initialize(graph);
      expect(unconfigured.status, WeeklyStatus.unconfigured);
      final gate = Completer<String>();
      var count = 0;
      final s = WeeklyContentService(
        url: 'https://example.com/weekly.json',
        readCache: () async => 'bad',
        writeCache: (_) async => throw StateError('disk full'),
        fetch: (_) {
          count++;
          return gate.future;
        },
        clock: () => now,
      );
      addTearDown(s.dispose);
      final pending = s.initialize(graph);
      await Future<void>.delayed(Duration.zero);
      await s.refresh(force: true);
      expect(count, 1);
      gate.complete(encoded());
      await pending;
      expect(s.status, WeeklyStatus.failed);
      expect(s.content, isNull);
    },
  );

  testWidgets('timeout does not replace current content', (tester) async {
    final s = WeeklyContentService(
      persist: false,
      url: 'https://example.com/weekly.json',
      clock: () => now,
      fetch: (_) => Completer<String>().future,
    );
    addTearDown(s.dispose);
    final pending = s.initialize(graph);
    await tester.pump(const Duration(seconds: 17));
    await pending;
    expect(s.status, WeeklyStatus.failed);
    expect(s.content, isNull);
  });

  for (final lang in ['zh', 'en']) {
    for (final appearance in [AppAppearance.dark, AppAppearance.light]) {
      testWidgets(
        'guide locate, filters, repeated focus and layer ($lang/$appearance)',
        (tester) async {
          tester.view.physicalSize = const Size(320, 780);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final service = WeeklyContentService(
            persist: false,
            url: 'https://example.com/weekly.json',
            clock: () => now,
            fetch: (_) async => encoded(),
          );
          final app = AppController(
            persist: false,
            tick: false,
            weekly: service,
          );
          var disposed = false;
          addTearDown(() {
            if (!disposed) app.dispose();
          });
          app.roadGraph = graph;
          app.navigation = NavigationState(graph);
          app.updateSettings((s) {
            s.language = lang;
            s.appearance = appearance;
          });
          await service.initialize(graph);
          final settings = jsonEncode(app.settings.toJson());
          await tester.pumpWidget(HorizonApp(controller: app));
          await tester.pumpAndSettle();
          await tester.tap(find.byType(NavigationDestination).at(1));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'no-match');
          await tester.pumpAndSettle();
          await tester.tap(find.byType(NavigationDestination).at(2));
          await tester.pumpAndSettle();
          final pending = find.byKey(const ValueKey('weekly-locate-pending'));
          await tester.scrollUntilVisible(pending, 150);
          await tester.ensureVisible(pending);
          await tester.pumpAndSettle();
          expect(tester.widget<OutlinedButton>(pending).onPressed, isNull);
          final locate = find.byKey(const ValueKey('weekly-locate-location'));
          await tester.ensureVisible(locate);
          await tester.pumpAndSettle();
          await tester.tap(locate);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            1,
          );
          expect(
            find.text(lang == 'zh' ? '测试位置' : 'Test location'),
            findsOneWidget,
          );
          final viewer = tester.widget<InteractiveViewer>(
            find.byType(InteractiveViewer),
          );
          final centered = viewer.transformationController!.value.clone();
          expect(centered.getMaxScaleOnAxis(), 3);
          viewer.transformationController!.value = Matrix4.identity()
            ..scaleByDouble(4, 4, 1, 1);
          app.focusWeeklyPlace(app.mapFocus!.place);
          await tester.pumpAndSettle();
          expect(
            viewer.transformationController!.value,
            isNot(centered),
          ); // preserves the user's new zoom
          expect(viewer.transformationController!.value.storage[0], 4);
          final recentered = viewer.transformationController!.value.clone();
          viewer.transformationController!.value = recentered.clone()
            ..translateByDouble(30, 30, 0, 1);
          app.focusWeeklyPlace(app.mapFocus!.place);
          await tester.pumpAndSettle();
          expect(viewer.transformationController!.value, recentered);

          expect(app.navigation!.route, isNull);
          expect(jsonEncode(app.settings.toJson()), settings);
          await tester.tap(find.byKey(const ValueKey('weekly-map-layer')));
          await tester.pumpAndSettle();
          expect(
            find.text(lang == 'zh' ? '测试位置' : 'Test location'),
            findsNothing,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
          app.dispose();
          disposed = true;
        },
      );
    }
  }

  testWidgets('queued focus survives map load and preserves active route', (
    tester,
  ) async {
    final app = AppController(persist: false, tick: false);
    var disposed = false;
    addTearDown(() {
      if (!disposed) app.dispose();
    });
    const target = MapPlace(
      'weekly:queued',
      'Queued',
      '本周活动',
      MapPoint(0, 0, 0),
    );
    await tester.pumpWidget(HorizonApp(controller: app));
    await tester.pumpAndSettle();
    app.focusWeeklyPlace(target);
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    app.roadGraph = graph;
    final route = NavigationRoute(
      [],
      const [MapPoint(0, 0, 0), MapPoint(100, 0, 100)],
      const [0, 141],
      141,
    );
    app.navigation = NavigationState(graph)..route = route;
    app.updateSettings((s) {});
    await tester.pumpAndSettle();
    expect(find.text('Queued'), findsOneWidget);
    expect(app.navigation!.route, same(route));
    await tester.pumpWidget(const SizedBox.shrink());
    app.dispose();
    disposed = true;
  });
}
