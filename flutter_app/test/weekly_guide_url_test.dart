import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/road_graph.dart';
import 'package:horizon_link/core/web_navigation.dart';
import 'package:horizon_link/core/weekly_content.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/services/weekly_content_service.dart';

const first =
    'https://api.xiaoheihe.cn/v3/bbs/app/api/web/share?link_id=first&h_src=a%2Bb';
const second = 'https://www.xiaoheihe.cn/app/bbs/link/second';
final graph = RoadGraph([], [], []);
String document(int revision, [Object? url = first]) => jsonEncode({
  'schemaVersion': 1,
  'revision': revision,
  'periods': [],
  'guideUrl': url,
});

void main() {
  test(
    'optional guide URLs are backward compatible and retain share queries',
    () {
      expect(WeeklyContent.parse(document(1), graph).guideUrl, first);
      expect(WeeklyContent.parse(document(1, null), graph).guideUrl, isNull);
      expect(
        WeeklyContent.parse(
          '{"schemaVersion":1,"revision":1,"periods":[]}',
          graph,
        ).guideUrl,
        isNull,
      );
      expect(
        WeeklyContent.parse(
          document(1, 'https://xiaoheihe.cn/post'),
          graph,
        ).guideUrl,
        'https://xiaoheihe.cn/post',
      );
    },
  );

  test('reject unsafe hosts, transport, credentials, fragments and malformed fields', () {
    for (final url in <Object>[
      '',
      ' ',
      1,
      {},
      [],
      'http://api.xiaoheihe.cn/post',
      'https://xiaoheihe.cn.evil.test/post',
      'https://evilxiaoheihe.cn/post',
      'https://user:secret@api.xiaoheihe.cn/post',
      'https://api.xiaoheihe.cn:444/post',
      'https://api.xiaoheihe.cn/post#redirect',
      '//api.xiaoheihe.cn/post',
      'javascript:alert(1)',
      'https://api.xiaoheihe.cn/post\n',
      'https://api.xiaoheihe.cn/po st',
      'https://api.xiaoheihe.cn/${'a' * 4096}',
    ]) {
      expect(
        () => WeeklyContent.parse(document(1, url), graph),
        throwsFormatException,
        reason: '$url',
      );
    }
    expect(guideNavigation(second, first), WebNavigation.internal);
    expect(
      guideNavigation(second, 'https://evil.test'),
      WebNavigation.external,
    );
    expect(
      guideNavigation(second, 'http://api.xiaoheihe.cn'),
      WebNavigation.blocked,
    );
  });

  test(
    'guide-only revisions, cache restart, invalid updates and explicit reset',
    () async {
      String? disk;
      var response = document(1);
      var offline = false;
      var time = DateTime.utc(2026, 11, 8);
      WeeklyContentService service() => WeeklyContentService(
        url: 'https://content.example.test/weekly.json',
        clock: () => time,
        readCache: () async => disk,
        writeCache: (value) async => disk = value,
        fetch: (_) async {
          if (offline) throw StateError('offline');
          return response;
        },
      );
      final weekly = service();
      final app = AppController(weekly: weekly, persist: false, tick: false);
      addTearDown(app.dispose);
      final saved = jsonEncode(app.settings.toJson());
      await weekly.initialize(graph);
      expect(app.guideUrl, first);
      response = document(2, second);
      await weekly.refresh(); // Six-hour automatic check throttles both fields.
      expect(app.guideUrl, first);
      await weekly.refresh(force: true);
      expect(app.guideUrl, second);
      final validCache = disk;
      for (final bad in [
        document(2),
        document(1),
        document(3, 'https://evil.test'),
      ]) {
        response = bad;
        await weekly.refresh(force: true);
        expect(weekly.status, WeeklyStatus.failed);
        expect(app.guideUrl, second);
        expect(disk, validCache);
      }
      offline = true;
      time = time.add(const Duration(days: 7));
      final restored = service();
      addTearDown(restored.dispose);
      await restored.initialize(graph);
      expect(restored.status, WeeklyStatus.failed);
      expect(restored.content!.guideUrl, second);
      offline = false;
      response = document(3, null);
      await weekly.refresh(force: true);
      expect(app.guideUrl, AppSettings.guideWebsiteUrl);
      expect(jsonEncode(app.settings.toJson()), saved);
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language guides react to refreshed URL without recreating page',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var response = document(1);
        final weekly = WeeklyContentService(
          persist: false,
          url: 'https://content.example.test/weekly.json',
          fetch: (_) async => response,
        );
        final app = AppController(weekly: weekly, persist: false, tick: false);
        addTearDown(app.dispose);
        app.roadGraph = graph;
        app.updateSettings((s) => s.language = language);
        await weekly.initialize(graph);
        await tester.pumpWidget(HorizonApp(controller: app));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NavigationDestination).at(2));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text(first), 150);
        expect(find.text(first), findsOneWidget);
        response = document(2, second);
        await weekly.refresh(force: true);
        await tester.pumpAndSettle();
        expect(find.text(second), findsOneWidget);
        expect(find.text(first), findsNothing);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
