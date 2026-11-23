import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/navigation.dart';
import 'package:horizon_link/core/road_graph.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/l10n.dart';
import 'package:horizon_link/pages/dashboard_screen.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';
import 'package:horizon_link/widgets/expanded_navigation.dart';

RoadGraph graph() => RoadGraph(
  const [
    MapPoint(-800, 0, 100),
    MapPoint(800, 0, 100),
    MapPoint(100, 0, -800),
    MapPoint(100, 0, 800),
    MapPoint(-800, 0, 400),
    MapPoint(800, 0, 400),
  ],
  const [
    RoadSegment(0, 0, 0, 1, 1600, ''),
    RoadSegment(1, 0, 2, 3, 1600, ''),
    RoadSegment(2, 0, 4, 5, 1600, ''),
  ],
  [[], [], []],
);

Future<Uint8List> pixels(CustomPainter painter, Size size) async {
  final recorder = ui.PictureRecorder();
  painter.paint(Canvas(recorder), size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.toInt(), size.height.toInt());
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final result = Uint8List.fromList(data.buffer.asUint8List());
  image.dispose();
  picture.dispose();
  return result;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('expanded navigation is opt-in and survives settings serialization', () {
    expect(AppSettings.fromJson({'miniNav': false}).expandedNav, false);
    final s = AppSettings()..expandedNav = true;
    expect(AppSettings.fromJson(s.toJson()).expandedNav, true);
    expect(localize('拓展导航', 'en'), 'Expanded navigation');
  });

  test('800 m square uses actual origin, exact scale and body heading', () {
    const o = MapPoint(25, 12, -10);
    for (final yaw in [0.0, math.pi / 2, math.pi, -math.pi / 2, 3.7]) {
      final w = NavigationWindow(o, yaw, 300);
      expect(w.project(o), const Offset(150, 150));
      for (final metres in [-400.0, 400.0]) {
        final front = MapPoint(
          o.x + metres * math.sin(yaw),
          999,
          o.z + metres * math.cos(yaw),
        );
        final right = MapPoint(
          o.x + metres * math.cos(yaw),
          -999,
          o.z - metres * math.sin(yaw),
        );
        expect(w.project(front).dx, closeTo(150, .00001));
        expect(w.project(front).dy, closeTo(metres < 0 ? 300 : 0, .00001));
        expect(w.project(right).dx, closeTo(metres < 0 ? 0 : 300, .00001));
      }
    }
  });

  test('index includes crossing roads and rotated square corners', () {
    final g = graph();
    expect(
      NavigationWindow(const MapPoint(0, 0, 0), math.pi / 4, 300).candidates(g),
      containsAll([0, 1, 2]),
    );
    expect(g.segmentsInWindow(const MapPoint(5000, 0, 5000), 425), isEmpty);
  });

  test(
    'all local roads render without route, follow and rotate, clip outside',
    () async {
      final n = NavigationState(graph())
        ..update(const MapPoint(0, 0, 0), yaw: 0);
      Future<Uint8List> render() =>
          pixels(ExpandedNavigationPainter(n), const Size.square(800));
      final first = await render();
      int red(Uint8List p, int x, int y) => p[(y * 800 + x) * 4];
      expect(red(first, 50, 300), greaterThan(100)); // crossing east/west road
      expect(red(first, 500, 50), greaterThan(100)); // other road, no route
      expect(red(first, 400, 390), greaterThan(240)); // fixed centered arrow
      expect(red(first, 50, 10), lessThan(30)); // background, no map image
      n.update(const MapPoint(0, 0, 100), yaw: 0);
      final moved = await render();
      expect(red(moved, 50, 400), greaterThan(100));
      n.update(const MapPoint(0, 0, 0), yaw: math.pi / 2);
      final turned = await render();
      expect(red(turned, 300, 50), greaterThan(100));
      expect(red(turned, 400, 390), greaterThan(240));
    },
  );

  test(
    'expanded layout keeps professional pixels identical; route is highlighted',
    () async {
      final s = AppSettings();
      Future<Uint8List> pro() => pixels(
        DashboardPainter(
          TelemetryFrame(),
          s,
          DashboardStyle.professional,
          null,
        ),
        const Size(1280, 540),
      );
      final original = await pro();
      s.expandedNav = true;
      expect(await pro(), orderedEquals(original));
      final n = NavigationState(graph())
        ..update(const MapPoint(0, 0, 0), yaw: 0);
      n.route = const NavigationRoute(
        [0],
        [MapPoint(-800, 0, 100), MapPoint(800, 0, 100)],
        [0, 1600],
        1600,
      );
      final p = await pixels(
        ExpandedNavigationPainter(n),
        const Size.square(800),
      );
      final offset = (300 * 800 + 50) * 4;
      expect(p.sublist(offset, offset + 3), [89, 229, 243]);
      final full = await pixels(
        DashboardPainter(TelemetryFrame(), s, DashboardStyle.basic, null, n),
        const Size(1280, 540),
      );
      final center = (270 * 1280 + 1115) * 4;
      expect(full[center], greaterThan(240));
      // Header and footer are now entirely free of title, scale or destination.
      for (final y in [
        ...List.generate(100, (i) => i),
        ...List.generate(104, (i) => 436 + i),
      ]) {
        for (var x = y < 100 ? 1000 : 950; x < 1280; x++) {
          final offset = (y * 1280 + x) * 4;
          expect(full.sublist(offset, offset + 3), [3, 4, 5]);
        }
      }
    },
  );

  test('expanded dashboard map stays square on a taller viewport', () async {
    const size = Size(832, 419);
    final data = await pixels(
      DashboardPainter(
        TelemetryFrame(),
        AppSettings()..expandedNav = true,
        DashboardStyle.basic,
        null,
      ),
      size,
    );
    bool isMapBackground(int x, int y) {
      final offset = (y * size.width.toInt() + x) * 4;
      return data[offset] == 12 &&
          data[offset + 1] == 17 &&
          data[offset + 2] == 22;
    }

    final centerX = (expandedNavigationRect.center.dx * size.width / 1280)
        .round();
    final centerY = (expandedNavigationRect.center.dy * size.height / 540)
        .round();
    final width = List.generate(
      size.width.toInt(),
      (x) => x,
    ).where((x) => isMapBackground(x, centerY + 50)).length;
    final height = List.generate(
      size.height.toInt(),
      (y) => y,
    ).where((y) => isMapBackground(centerX + 50, y)).length;
    // Antialiasing at the map edges can remove a pixel at either end.
    expect(width, closeTo(330 * size.width / 1280, 3));
    expect(height, closeTo(width, 2));
  });

  for (final language in ['zh', 'en']) {
    testWidgets(
      'sidebar toggles navigation, replaces settings switch and fits phones $language',
      (tester) async {
        tester.view.physicalSize = const Size(844, 390);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = AppController(persist: false, tick: false);
        addTearDown(app.dispose);
        await tester.pumpWidget(
          MaterialApp(
            locale: Locale(language),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              AppCopy.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: DashboardScreen(app: app),
          ),
        );
        final toggle = find.byKey(const ValueKey('expanded-navigation-toggle'));
        expect(app.settings.expandedNav, false);
        expect(
          find.byTooltip(language == 'en' ? 'Show navigation' : '打开导航'),
          findsOneWidget,
        );
        final closedCanvas = tester.getRect(find.byType(DashCanvas));
        expect(
          tester.getRect(toggle).left,
          greaterThanOrEqualTo(closedCanvas.right),
        );
        await tester.tap(toggle);
        await tester.pump();
        expect(
          tester.getRect(find.byType(DashCanvas)).width,
          greaterThan(closedCanvas.width),
        );
        expect(app.settings.expandedNav, true);
        expect(AppSettings.fromJson(app.settings.toJson()).expandedNav, true);
        await tester.tap(find.byIcon(Icons.tune_rounded));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('expanded-navigation-setting')),
          findsNothing,
        );
        expect(
          find.text(language == 'en' ? 'Expanded navigation' : '拓展导航'),
          findsNothing,
        );
        await tester.ensureVisible(find.text(language == 'en' ? 'Done' : '完成'));
        await tester.tap(find.text(language == 'en' ? 'Done' : '完成'));
        await tester.pumpAndSettle();
        for (final size in [const Size(640, 360), const Size(844, 390)]) {
          tester.view.physicalSize = size;
          await tester.pump();
          expect(
            tester
                .widget<DashCanvas>(find.byType(DashCanvas))
                .settings
                .expandedNav,
            true,
          );
          final button = tester.getRect(toggle);
          final canvas = tester.getRect(find.byType(DashCanvas));
          final mapTop = canvas.top + canvas.height * 105 / 540;
          final mapLeft = canvas.left + canvas.width * 950 / 1280;
          expect(button.bottom, lessThanOrEqualTo(mapTop));
          expect(button.center.dx, greaterThan(mapLeft));
          expect(button.top, greaterThanOrEqualTo(canvas.top));
          expect(find.byIcon(Icons.arrow_back_rounded), findsNWidgets(2));
          expect(button.right, lessThanOrEqualTo(size.width));
          expect(button.height, greaterThanOrEqualTo(48));
          expect(tester.takeException(), isNull);
        }
        await tester.tap(toggle);
        await tester.pump();
        expect(app.settings.expandedNav, false);
        await tester.tap(find.text(language == 'en' ? 'Pro' : '专业'));
        await tester.pump();
        expect(toggle, findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
