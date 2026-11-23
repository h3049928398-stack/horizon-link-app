import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/navigation.dart';
import 'package:horizon_link/core/road_graph.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/widgets/map_viewport_geometry.dart';

class MapHarness {
  final WidgetTester tester;
  final AppController app = AppController(persist: false, tick: false);
  final origin = const MapPoint(
    (512 - 582.896) / .046504,
    0,
    (499.376 - 512) / .046504,
  );
  MapHarness(this.tester);
  void background() {
    for (final state in [
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
  }

  void resume() {
    if (tester.binding.lifecycleState == AppLifecycleState.paused) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    }
    if (tester.binding.lifecycleState == AppLifecycleState.hidden) {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  }

  Finder get finder => find.byType(InteractiveViewer);
  InteractiveViewer get viewer => tester.widget<InteractiveViewer>(finder);
  TransformationController get transform => viewer.transformationController!;
  Size get size => tester.getSize(finder);
  Offset get center => Offset(size.width / 2, size.height / 2);
  Offset get car {
    final p = app.navigation!.location!;
    final side = size.shortestSide;
    final local =
        Offset((size.width - side) / 2, (size.height - side) / 2) +
        Offset(582.896 + p.x * .046504, 499.376 - p.z * .046504) *
            (side / 1024);
    return MatrixUtils.transformPoint(transform.value, local);
  }

  Future<void> mount({bool navigating = true}) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(app.dispose);
    addTearDown(() async {
      resume();
      await tester.pumpWidget(const SizedBox.shrink());
    });
    app.roadGraph = RoadGraph(
      [
        MapPoint(origin.x - 2000, 0, origin.z),
        MapPoint(origin.x + 2000, 0, origin.z),
      ],
      const [RoadSegment(0, 0, 0, 1, 4000, '')],
      [[]],
    );
    app.navigation = NavigationState(app.roadGraph!)..update(origin);
    if (navigating) startNavigation();
    await tester.pumpWidget(HorizonApp(controller: app));
    await tester.pumpAndSettle();
    await tab(1);
  }

  void startNavigation() => app.navigateTo(
    MapPlace('target', 'Target', '自定义', MapPoint(origin.x + 1500, 0, origin.z)),
  );

  Future<void> tab(int index) async {
    tester
        .widget<NavigationBar>(find.byType(NavigationBar))
        .onDestinationSelected!(index);
    await tester.pumpAndSettle();
  }

  Future<void> moveCar(double meters) async {
    app.navigation!.update(
      MapPoint(origin.x + meters, 0, origin.z),
      moving: false,
    );
    app.notifyListeners();
    await tester.pump();
    await tester.pump();
  }

  Future<void> beginPan() async {
    viewer.onInteractionStart!(ScaleStartDetails());
    await tester.pump();
    final value = transform.value.clone();
    value.setTranslationRaw(value.storage[12] + 100, value.storage[13] + 60, 0);
    transform.value = value;
    await tester.pump();
  }

  void endPan() => viewer.onInteractionEnd!(ScaleEndDetails());

  void expectCentered() => expect((car - center).distance, lessThan(.001));
  void expectCovered() {
    final rect = MatrixUtils.transformRect(
      transform.value,
      MapViewportGeometry.mapBounds(size),
    );
    expect(rect.left, lessThanOrEqualTo(.001));
    expect(rect.top, lessThanOrEqualTo(.001));
    expect(rect.right, greaterThanOrEqualTo(size.width - .001));
    expect(rect.bottom, greaterThanOrEqualTo(size.height - .001));
  }
}

void main() {
  testWidgets('starting navigation locks to car and follows new positions', (
    tester,
  ) async {
    final h = MapHarness(tester);
    await h.mount(navigating: false);
    await h.beginPan();
    h.endPan();
    expect((h.car - h.center).distance, greaterThan(50));
    h.startNavigation();
    await tester.pumpAndSettle();
    h.expectCentered();
    await h.moveCar(50);
    h.expectCentered();
  });

  testWidgets(
    'waits three seconds then eases to latest car at the chosen zoom',
    (tester) async {
      final h = MapHarness(tester);
      await h.mount();
      // Change scale through the same interaction callbacks as a pinch.
      h.viewer.onInteractionStart!(ScaleStartDetails());
      h.transform.value = h.transform.value.clone()
        ..scaleByDouble(1.4, 1.4, 1, 1);
      h.endPan();
      final zoom = h.transform.value.getMaxScaleOnAxis();
      final before = h.transform.value.clone();
      await h.moveCar(40);
      await tester.pump(const Duration(milliseconds: 2999));
      expect(h.transform.value, before);
      await tester.pump(const Duration(milliseconds: 1));
      final distance = (h.car - h.center).distance;
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        (h.car - h.center).distance,
        allOf(greaterThan(1), lessThan(distance)),
      );
      await h.moveCar(90);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pump();
      h.expectCentered();
      expect(h.transform.value.getMaxScaleOnAxis(), closeTo(zoom, .000001));
      await h.moveCar(130);
      h.expectCentered();
      expect(h.transform.value.getMaxScaleOnAxis(), closeTo(zoom, .000001));
    },
  );

  testWidgets(
    'new gesture cancels return and restarts delay only after release',
    (tester) async {
      final h = MapHarness(tester);
      await h.mount();
      await h.beginPan();
      await tester.pump(const Duration(seconds: 4));
      final held = h.transform.value.clone();
      await tester.pump(const Duration(seconds: 4));
      expect(h.transform.value, held);
      h.endPan();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 400));
      await h.beginPan();
      final interrupted = h.transform.value.clone();
      await tester.pump(const Duration(seconds: 4));
      expect(h.transform.value, interrupted);
      h.endPan();
      await tester.pump(const Duration(milliseconds: 2999));
      expect(h.transform.value, interrupted);
      await tester.pump(const Duration(milliseconds: 1));
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      h.expectCentered();
    },
  );

  testWidgets(
    'actual drag returns after release; browsing without route stays put',
    (tester) async {
      final h = MapHarness(tester);
      await h.mount();
      final start = tester.getTopLeft(h.finder) + const Offset(100, 140);
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(const Offset(30, 20));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(80, 40));
      await tester.pump(const Duration(milliseconds: 500));
      await gesture.up();
      await tester.pumpAndSettle();
      expect((h.car - h.center).distance, greaterThan(20));
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      h.expectCentered();
      h.app.stopNavigation();
      await tester.pumpAndSettle();
      await h.beginPan();
      h.endPan();
      final before = h.transform.value.clone();
      await tester.pump(const Duration(seconds: 5));
      expect(h.transform.value, before);
    },
  );

  for (final duringAnimation in [false, true]) {
    testWidgets(
      'stop, hidden tab and background cancel return (animating=$duringAnimation)',
      (tester) async {
        final h = MapHarness(tester);
        await h.mount();
        for (final reason in ['stop', 'tab', 'background']) {
          await h.beginPan();
          h.endPan();
          if (duringAnimation) {
            await tester.pump(const Duration(seconds: 3));
            await tester.pump(const Duration(milliseconds: 400));
          }
          if (reason == 'stop') {
            h.app.stopNavigation();
            await tester.pump();
          } else if (reason == 'tab') {
            await h.tab(0);
          } else {
            h.background();
            await tester.pump();
          }
          final hidden = find.byType(InteractiveViewer, skipOffstage: false);
          final before = tester
              .widget<InteractiveViewer>(hidden)
              .transformationController!
              .value
              .clone();
          await tester.pump(const Duration(seconds: 5));
          // The map remains mounted while hidden, so inspect its controller directly.
          expect(
            tester
                .widget<InteractiveViewer>(hidden)
                .transformationController!
                .value,
            before,
          );
          if (reason == 'stop') {
            h.startNavigation();
            await tester.pumpAndSettle();
          } else if (reason == 'tab') {
            await h.tab(1);
          } else {
            h.resume();
            await tester.pumpAndSettle();
          }
          h.expectCentered();
        }
        await h.beginPan();
        h.endPan();
        if (duringAnimation) {
          await tester.pump(const Duration(seconds: 3));
          await tester.pump(const Duration(milliseconds: 400));
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 5));
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'return and resize obey map edges without showing outside the image',
    (tester) async {
      final h = MapHarness(tester);
      await h.mount();
      await h.beginPan();
      h.endPan();
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 250));
      tester.view.physicalSize = const Size(844, 600);
      await tester.pump();
      h.expectCovered();
      h.app.navigation!.location = const MapPoint(
        (1000 - 582.896) / .046504,
        0,
        (499.376 - 1000) / .046504,
      );
      h.app.notifyListeners();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
        h.expectCovered();
      }
      // Exact center yields to the existing no-empty-border constraint near edges.
      expect((h.car - h.center).distance.isFinite, true);
      expect(
        h.transform.value.getMaxScaleOnAxis(),
        lessThanOrEqualTo(math.max(14, MapViewportGeometry.minScale(h.size))),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
