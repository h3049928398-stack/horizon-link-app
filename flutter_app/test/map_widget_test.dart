import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/road_graph.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/l10n.dart';
import 'package:horizon_link/pages/map_page.dart';
import 'package:horizon_link/widgets/map_viewport_geometry.dart';

void main() {
  testWidgets('drag, fling, reset and resize keep map inside its boundaries', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppController(persist: false, tick: false);
    addTearDown(app.dispose);
    app.roadGraph = RoadGraph([], [], []);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MapPage(app: app)),
      ),
    );
    await tester.pumpAndSettle();
    final finder = find.byType(InteractiveViewer);
    void expectCovered() {
      final viewer = tester.widget<InteractiveViewer>(finder);
      final size = tester.getSize(finder);
      final bounds = MatrixUtils.transformRect(
        viewer.transformationController!.value,
        MapViewportGeometry.mapBounds(size),
      );
      expect(bounds.left, lessThanOrEqualTo(.001));
      expect(bounds.top, lessThanOrEqualTo(.001));
      expect(bounds.right, greaterThanOrEqualTo(size.width - .001));
      expect(bounds.bottom, greaterThanOrEqualTo(size.height - .001));
    }

    expectCovered();
    for (final scale in [2.0, 14.0]) {
      final viewer = tester.widget<InteractiveViewer>(finder);
      viewer.transformationController!.value = Matrix4.identity()
        ..scaleByDouble(scale, scale, 1, 1);
      await tester.pumpAndSettle();
      for (final delta in [
        const Offset(2000, 2000),
        const Offset(-4000, -4000),
        const Offset(4000, -4000),
        const Offset(-4000, 4000),
      ]) {
        await tester.flingFrom(
          tester.getTopLeft(finder) + const Offset(150, 100),
          delta,
          2000,
        );
        await tester.pump();
        expectCovered();
        await tester.pumpAndSettle();
        expectCovered();
      }
    }
    await tester.tap(find.byIcon(Icons.open_in_full_rounded));
    await tester.pumpAndSettle();
    expectCovered();
    tester.view.physicalSize = const Size(844, 600);
    await tester.pumpAndSettle();
    expectCovered();
    expect(tester.takeException(), isNull);
  });
  for (final language in ['zh', 'en']) {
    testWidgets(
      'multi-category filters, cancellation and empty map ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = AppController(persist: false, tick: false);
        addTearDown(app.dispose);
        final point = MapPoint(
          (512 - 582.896) / .046504,
          0,
          (499.376 - 512) / .046504,
        );
        app.roadGraph = RoadGraph(
          [],
          [],
          [],
          places: [
            MapPlace('race', 'Race test', '赛事', point),
            MapPlace('board', 'Board test', '广告牌', point),
            MapPlace('mascot', 'Mascot test', '吉祥物', point),
            MapPlace('track', 'Track test', '赛道', point),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              AppCopy.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: Scaffold(body: MapPage(app: app)),
          ),
        );
        await tester.pumpAndSettle();
        String tr(String s) => localize(s, language);
        Future<void> openFilters() async {
          await tester.tap(find.byKey(const ValueKey('map-place-filters')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'filter sheet');
        }

        Future<void> apply() async {
          await tester.tap(find.byKey(const ValueKey('apply-place-filters')));
          await tester.pumpAndSettle();
        }

        await openFilters();
        await tester.tap(find.text(tr('清空')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('place-filter-赛事')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('place-filter-广告牌')));
        await tester.pumpAndSettle();
        await apply();
        expect(find.text('${tr('筛选地点')} (2)'), findsOneWidget);
        // Hit testing uses the same filtered markers as painting, including overlaps.
        await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
        await tester.pumpAndSettle();
        expect(find.text('Race test'), findsOneWidget);
        expect(find.text('Board test'), findsOneWidget);
        expect(find.text('Mascot test'), findsNothing);
        expect(find.text('Track test'), findsNothing);
        await tester.tap(find.text('Board test'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: 'selected card');
        await openFilters();
        expect(
          tester
              .widget<CheckboxListTile>(
                find.byKey(const ValueKey('place-filter-广告牌')),
              )
              .value,
          true,
        );
        await tester.tap(find.text(tr('清空')));
        // System back cancels the draft, including an empty draft.
        Navigator.of(
          tester.element(find.byKey(const ValueKey('apply-place-filters'))),
        ).pop();
        await tester.pumpAndSettle();
        expect(find.text('${tr('筛选地点')} (2)'), findsOneWidget);
        expect(find.text('Board test'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'Mascot');
        await tester.pumpAndSettle();
        expect(find.text('Mascot test'), findsNothing);
        expect(find.text(tr('没有找到匹配地点\n可以更换类别或搜索名称')), findsOneWidget);
        await tester.enterText(find.byType(TextField), '');
        await openFilters();
        await tester.tap(find.text(tr('清空')));
        await apply();
        expect(find.text('${tr('筛选地点')} (0)'), findsOneWidget);
        expect(find.text('Board test'), findsNothing);
        await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
        await tester.pumpAndSettle();
        expect(find.text('Race test'), findsNothing);
        await openFilters();
        await tester.tap(find.text(tr('全选')));
        await apply();
        await tester.tap(find.byTooltip(tr('显示地点列表')));
        await tester.pumpAndSettle();
        expect(find.text('Race test'), findsOneWidget);
        expect(find.text('Mascot test'), findsOneWidget);
        expect(find.text('Track test'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
  for (final keyboardHeight in [0.0, 280.0]) {
    testWidgets(
      'list selection centers after keyboard $keyboardHeight closes',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetViewInsets);
        final app = AppController(persist: false, tick: false);
        addTearDown(app.dispose);
        final point = MapPoint(
          (700 - 582.896) / .046504,
          0,
          (499.376 - 400) / .046504,
        );
        app.roadGraph = RoadGraph(
          [],
          [],
          [],
          places: [
            MapPlace('target', 'Target', '房屋', point),
            MapPlace('other', 'Target other', '房屋', const MapPoint(0, 0, 0)),
          ],
        );
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(body: MapPage(app: app)),
          ),
        );
        await tester.pumpAndSettle();
        final viewerFinder = find.byType(InteractiveViewer);
        final transform = tester
            .widget<InteractiveViewer>(viewerFinder)
            .transformationController!;
        transform.value = Matrix4.identity()..scaleByDouble(2, 2, 1, 1);
        await tester.enterText(find.byType(TextField).first, 'Target');
        tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
        await tester.pumpAndSettle();
        final before = transform.value.clone();
        await tester.tap(find.text('Target').last);
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<EditableText>(find.byType(EditableText))
              .focusNode
              .hasFocus,
          isFalse,
        );
        if (keyboardHeight > 0) {
          expect(transform.value.storage, orderedEquals(before.storage));
          tester.view.viewInsets = const FakeViewPadding(bottom: 120);
          await tester.pumpAndSettle();
          expect(
            transform.value.storage,
            orderedEquals(before.storage),
            reason: 'do not center during keyboard dismissal',
          );
          tester.view.viewInsets = const FakeViewPadding();
          await tester.pumpAndSettle();
        }
        final size = tester.getSize(viewerFinder);
        final side = size.shortestSide;
        final localPoint =
            Offset((size.width - side) / 2, (size.height - side) / 2) +
            Offset(700, 400) * (side / 1024);
        final screenPoint = MatrixUtils.transformPoint(
          transform.value,
          localPoint,
        );
        expect(screenPoint.dx, closeTo(size.width / 2, .001));
        expect(screenPoint.dy, closeTo(size.height / 2, .001));
        expect(transform.value.getMaxScaleOnAxis(), 3);
        int markerCount() {
          final paint = tester
              .widgetList<CustomPaint>(find.byType(CustomPaint))
              .firstWhere(
                (p) => p.painter.runtimeType.toString() == '_MapMarkersPainter',
              );
          return ((paint.painter as dynamic).markers as List).length;
        }

        expect(
          markerCount(),
          0,
          reason: 'only the overlay draws the selected pin',
        );
        await tester.tap(find.byTooltip('取消选点'));
        await tester.pumpAndSettle();
        expect(markerCount(), 2, reason: 'cancel restores filtered places');
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'category results dismiss outside without selecting a map point',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      final point = MapPoint(
        (512 - 582.896) / .046504,
        0,
        (499.376 - 140) / .046504,
      );
      app.roadGraph = RoadGraph(
        [],
        [],
        [],
        places: [
          MapPlace('board', 'Billboard test', '广告牌', point),
          MapPlace('house', 'House test', '房屋', point),
        ],
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            appBar: AppBar(title: const Text('Map test')),
            body: MapPage(app: app),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final viewer = tester.widget<InteractiveViewer>(
        find.byType(InteractiveViewer),
      );
      final before = viewer.transformationController!.value.storage.toList();
      await tester.tap(find.text('广告牌'));
      await tester.pumpAndSettle();
      expect(find.text('Billboard test'), findsOneWidget);
      final map = tester.getRect(find.byType(InteractiveViewer));
      final side = map.width < map.height ? map.width : map.height;
      final anchor =
          map.topLeft +
          Offset(map.width / 2, (map.height - side) / 2 + 140 * side / 1024);
      await tester.tapAt(anchor - const Offset(0, 16));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-results-dismiss')), findsNothing);
      expect(
        find.text('导航到这里'),
        findsNothing,
        reason: 'the dismissing tap must not pass through to a marker',
      );
      expect(
        viewer.transformationController!.value.storage,
        orderedEquals(before),
      );
      await tester.tap(find.text('广告牌'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('房屋'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('房屋'));
      await tester.pumpAndSettle();
      expect(find.text('House test'), findsOneWidget);
      expect(find.text('Billboard test'), findsNothing);
      await tester.tap(find.text('Map test'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('map-results-dismiss')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('overlapping places remain individually selectable at overview', (
    tester,
  ) async {
    final app = AppController(persist: false, tick: false);
    addTearDown(app.dispose);
    final point = MapPoint(
      (512 - 582.896) / .046504,
      0,
      (499.376 - 512) / .046504,
    );
    app.roadGraph = RoadGraph(
      [],
      [],
      [],
      places: [
        MapPlace('a', 'Marker A', '房屋', point),
        MapPlace('b', 'Marker B', '吉祥物', point),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: MapPage(app: app)),
      ),
    );
    await tester.pumpAndSettle();
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    await tester.tapAt(tester.getCenter(find.byType(InteractiveViewer)));
    await tester.pumpAndSettle();
    expect(find.text('Marker A'), findsOneWidget);
    expect(find.text('Marker B'), findsOneWidget);
    await tester.tap(find.text('Marker B'));
    await tester.pumpAndSettle();
    expect(find.text('Marker A'), findsNothing);
    expect(find.text('Marker B'), findsOneWidget);
    expect(find.text('导航到这里'), findsOneWidget);
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      3,
      reason: 'choosing an overlapping marker focuses and zooms',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('real map search and navigation fit a narrow phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 700);
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
    expect(tester.takeException(), isNull, reason: 'initial app');
    await tester.tap(find.text('地图').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'map overview');
    final sceneFinder = find.byWidgetPredicate(
      (widget) => widget is CustomPaint && widget.isComplex,
    );
    final sceneBefore = tester.widget<CustomPaint>(sceneFinder).painter!;
    final viewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final center = tester.getCenter(find.byType(InteractiveViewer));
    final first = await tester.startGesture(
      center - const Offset(30, 0),
      pointer: 1,
    );
    final second = await tester.startGesture(
      center + const Offset(30, 0),
      pointer: 2,
    );
    await first.moveTo(center - const Offset(60, 0));
    await second.moveTo(center + const Offset(60, 0));
    await tester.pump();
    await first.up();
    await second.up();
    await tester.pumpAndSettle();
    final zoom = viewer.transformationController!.value.getMaxScaleOnAxis();
    expect(zoom, greaterThan(5));
    app.notifyListeners();
    await tester.pumpAndSettle();
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      zoom,
      reason: 'telemetry must not reset the user zoom',
    );
    final sceneAfter = tester.widget<CustomPaint>(sceneFinder).painter!;
    expect(
      sceneAfter.shouldRepaint(sceneBefore),
      isFalse,
      reason: 'gestures and telemetry must reuse the static road layer',
    );
    await tester.enterText(find.byType(TextField).first, 'Route101');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: 'search results');
    final searchZoom = viewer.transformationController!.value
        .getMaxScaleOnAxis();
    await tester.tap(find.text('赛道入口 Route101'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      viewer.transformationController!.value.getMaxScaleOnAxis(),
      searchZoom,
    );
    // The pin head sits above its coordinate. It must remain tappable after
    // deselecting, including on a narrow screen and after zooming.
    await tester.tap(find.byTooltip('取消选点'));
    await tester.pumpAndSettle();
    expect(find.text('导航到这里'), findsNothing);
    final beforePick = viewer.transformationController!.value.storage.toList();
    await tester.tapAt(
      tester.getCenter(find.byType(InteractiveViewer)) - const Offset(0, 14),
    );
    await tester.pumpAndSettle();
    expect(find.text('赛道入口 Route101'), findsOneWidget);
    expect(find.text('导航到这里'), findsOneWidget);
    expect(
      viewer.transformationController!.value.storage,
      orderedEquals(beforePick),
      reason: 'tapping a marker must preserve both zoom and position',
    );
    await tester.tap(find.text('导航到这里'));
    await tester.pumpAndSettle();
    expect(app.navigation!.route, isNotNull);
    expect(find.byTooltip('结束导航'), findsOneWidget);
    final route = app.navigation!.route;
    final routeView = viewer.transformationController!.value.storage.toList();
    await tester.tap(find.byKey(const ValueKey('map-place-filters')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-place-filters')));
    await tester.pumpAndSettle();
    expect(app.navigation!.route, same(route));
    expect(
      viewer.transformationController!.value.storage,
      orderedEquals(routeView),
    );
    expect(find.byTooltip('结束导航'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
