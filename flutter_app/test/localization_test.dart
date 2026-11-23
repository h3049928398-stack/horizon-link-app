import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/road_graph.dart';
import 'package:horizon_link/l10n.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/pages/dashboard_screen.dart';
import 'package:horizon_link/pages/settings_page.dart';
import 'package:horizon_link/pages/telemetry_page.dart';

void main() {
  test('older saved settings default to Chinese; both locales round-trip', () {
    expect(AppSettings.fromJson({}).language, 'zh');
    expect(AppSettings.fromJson({'language': 'fr'}).language, 'zh');
    final settings = AppSettings()
      ..language = 'en'
      ..port = 8123
      ..mph = true;
    final restored = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())),
    );
    expect(restored.language, 'en');
    expect(restored.port, 8123);
    expect(restored.guideUrl, settings.guideUrl);
    expect(restored.mph, true);
    restored.language = 'zh';
    expect(AppSettings.fromJson(restored.toJson()).language, 'zh');
  });

  test('dynamic navigation, connection and telemetry copy translates', () {
    expect(localize('浏览 795 个地点', 'en'), 'Browse 795 places');
    expect(localize('已连接', 'en'), 'Connected');
    expect(
      localize('12 个采样 · 回溯分段 2 次\n已确认第 3 名', 'en'),
      '12 samples · 2 rewind segments\nConfirmed P3',
    );
    expect(localize('前方急右转 · 200 m', 'en'), 'Sharp right ahead · 200 m');
    expect(
      localize('等待游戏数据\n数据包 125 · 无效 3', 'en'),
      'Waiting for game data\nPackets 125 · rejected 3',
    );
  });

  test(
    'bilingual overlay preserves IDs, coordinates and source categories',
    () async {
      final graph = await RoadGraph.load();
      final tower = graph.places.firstWhere((p) => p.name == 'Tokyo Tower');
      expect(tower.displayName('zh'), '东京塔');
      expect(tower.displayName('en'), 'Tokyo Tower');
      expect(tower.matchesName('东京塔'), true);
      expect(tower.matchesName('TOKYO TOWER'), true);
      expect(tower.matchesName(tower.id), true);
      expect(tower.category, '地标');
      final raw = (jsonDecode(
        await rootBundle.loadString('assets/map/places.json'),
      ) as List).firstWhere((p) => p['id'] == tower.id);
      expect(tower.point.x, raw['x']);
      expect(tower.point.z, raw['z']);
      final dango = graph.places.firstWhere((p) => p.name == 'Dango');
      expect(dango.displayName('zh'), '团子');
      final missing = const MapPlace(
        'unmatched',
        'Unmatched name',
        '地标',
        MapPoint(0, 0, 0),
      );
      expect(missing.displayName('zh'), 'Unmatched name');
    },
  );

  testWidgets(
    'settings switch all four tabs and Material dialogs in both languages',
    (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      await tester.runAsync(app.initialize);
      await tester.runAsync(() => app.mapLoaded);
      app.navigation!.update(app.roadGraph!.points[0], moving: false);
      await tester.pumpWidget(HorizonApp(controller: app));
      await tester.pumpAndSettle();
      expect(find.text('基础仪表'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();
      expect(app.settings.language, 'en');
      expect(
        tester.widget<MaterialApp>(find.byType(MaterialApp)).locale,
        const Locale('en'),
      );
      expect(find.text('Driving preferences'), findsOneWidget);
      for (final label in ['Dashboard', 'Map', 'Guides', 'Settings']) {
        await tester.tap(
          find.descendant(
            of: find.byType(NavigationBar),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
        for (final text in tester.widgetList<Text>(find.byType(Text))) {
          expect(
            RegExp(r'[\u4e00-\u9fff]')
                .hasMatch(text.data?.replaceAll('中文', '') ?? ''),
            false,
            reason: 'Untranslated visible copy: ${text.data}',
          );
        }
        expect(tester.takeException(), isNull);
      }
      final context = tester.element(find.byType(SettingsPage));
      showConnection(context, app);
      await tester.pumpAndSettle();
      expect(find.text('Connect to game'), findsOneWidget);
      expect(find.text('UDP receive port'), findsOneWidget);
      Navigator.of(context).pop();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-selector')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('中文').last);
      await tester.pumpAndSettle();
      expect(find.text('驾驶偏好'), findsOneWidget);
      expect(app.settings.language, 'zh');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'map search accepts both languages and route name follows locale',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      await tester.runAsync(app.initialize);
      await tester.runAsync(() => app.mapLoaded);
      app.navigation!.update(app.roadGraph!.points[0], moving: false);
      await tester.pumpWidget(HorizonApp(controller: app));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('地图'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Tokyo Tower');
      await tester.pumpAndSettle();
      expect(find.text('东京塔'), findsWidgets);
      await tester.enterText(find.byType(TextField), '东京塔');
      await tester.pumpAndSettle();
      expect(find.text('东京塔'), findsWidgets);
      await tester.tap(find.text('东京塔').first);
      await tester.pumpAndSettle();
      app.navigateTo(
        app.roadGraph!.places.firstWhere((p) => p.name == 'Tokyo Tower'),
      );
      await tester.pumpAndSettle();
      if (find.byTooltip('收起地点列表').evaluate().isNotEmpty) {
        await tester.tap(find.byTooltip('收起地点列表'));
        await tester.pumpAndSettle();
      }
      expect(find.byTooltip('结束导航'), findsOneWidget);
      final route = app.navigation!.route;
      expect(route, isNotNull);
      app.updateSettings((s) => s.language = 'en');
      await tester.pumpAndSettle();
      expect(find.text('Tokyo Tower'), findsWidgets);
      expect(app.navigation!.route, same(route));
      expect(find.text('Stop navigation'), findsNothing); // an icon tooltip
      expect(
        find.byTooltip('Stop navigation'),
        findsOneWidget,
        reason: tester
            .widgetList<IconButton>(find.byType(IconButton))
            .map((w) => w.tooltip)
            .join(' / '),
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('English telemetry and landscape controls fit on phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppController(persist: false, tick: false);
    addTearDown(app.dispose);
    app.updateSettings((s) => s.language = 'en');
    await tester.pumpWidget(HorizonApp(controller: app));
    await tester.pumpAndSettle();
    final nav = Navigator.of(tester.element(find.byType(NavigationBar)));
    nav.push(MaterialPageRoute<void>(builder: (_) => TelemetryPage(app: app)));
    await tester.pumpAndSettle();
    expect(find.text('Driving telemetry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    nav.pop();
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(780, 360);
    nav.push(
      MaterialPageRoute<void>(builder: (_) => DashboardScreen(app: app)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Basic'), findsOneWidget);
    await tester.tap(find.byTooltip('Dashboard settings'));
    await tester.pumpAndSettle();
    expect(find.text('Dashboard on race entry'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
