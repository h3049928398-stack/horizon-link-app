import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/l10n.dart';
import 'package:horizon_link/pages/dashboard_screen.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';
import 'package:horizon_link/widgets/overtake_glow.dart';

void main() {
  testWidgets('position gain lasts two seconds and a new gain refreshes it', (
    tester,
  ) async {
    final app = AppController(persist: false, tick: false);
    addTearDown(app.dispose);
    final start = DateTime(2026);
    void frame(int ms, int position) => app.ingest(
      TelemetryFrame(
        timestamp: ms + 1,
        receivedAt: start.add(Duration(milliseconds: ms)),
        driving: true,
        position: position,
        raceTime: 1 + ms / 1000,
      ),
    );
    frame(0, 6);
    frame(700, 6);
    frame(800, 5);
    expect(app.gain, isTrue);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(app.gain, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(app.gain, isFalse);

    frame(3000, 4);
    await tester.pump(const Duration(milliseconds: 1900));
    frame(4900, 3);
    await tester.pump(const Duration(milliseconds: 1500));
    expect(app.gain, isTrue);
    await tester.pump(const Duration(milliseconds: 500));
    expect(app.gain, isFalse);
  });

  for (final language in ['zh', 'en']) {
    testWidgets('position gain stays above the pro instruments ($language)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      app.gain = true;
      final label = language == 'zh' ? '名次提升' : 'POSITION GAINED';
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
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(OvertakeGlow), findsNothing);
      expect(find.text(label), findsNothing);

      await tester.tap(find.text(language == 'zh' ? '专业' : 'Pro'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        tester.widget<OvertakeGlow>(find.byType(OvertakeGlow)).active,
        isTrue,
      );
      expect(find.text(label), findsOneWidget);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNWidgets(2));
      for (final size in [const Size(844, 390), const Size(640, 360)]) {
        tester.view.physicalSize = size;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        final title = tester.getRect(
          find.byKey(const ValueKey('position-gain-heading')),
        );
        final instruments = tester.getRect(find.byType(DashCanvas));
        final basic = tester.getRect(
          find.text(language == 'zh' ? '基础' : 'Basic'),
        );
        final status = tester.getRect(find.byIcon(Icons.arrow_back_rounded));
        expect(title.bottom, lessThanOrEqualTo(instruments.top));
        expect(title.top, greaterThanOrEqualTo(0));
        expect(title.bottom, lessThanOrEqualTo(48));
        final connection = tester.getRect(
          find.byKey(const ValueKey('dashboard-connection-status')),
        );
        expect(title.right, lessThan(connection.left));
        expect(title.left, greaterThan(status.right));
        expect(title.right, lessThan(basic.left));
        expect(tester.takeException(), isNull);
      }

      // Switching back removes even an active glow immediately, without a fade
      // lingering over the basic instruments.
      await tester.tap(find.text(language == 'zh' ? '基础' : 'Basic'));
      await tester.pump();
      expect(find.byType(OvertakeGlow), findsNothing);
      expect(find.text(label), findsNothing);
      expect(app.gain, isTrue);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone has four destinations and both dashboard types', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppController(persist: false, tick: false);
    addTearDown(app.dispose);
    await tester.pumpWidget(HorizonApp(controller: app));
    await tester.pumpAndSettle();
    final nav = tester.widget<NavigationBar>(find.byType(NavigationBar));
    expect(nav.destinations.map((w) => (w as NavigationDestination).label), [
      '仪表盘',
      '地图',
      '攻略',
      '设置',
    ]);
    expect(find.text('基础仪表'), findsOneWidget);
    expect(find.text('专业仪表'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dashboard requests landscape; returning restores portrait', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final calls = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        calls.add(call);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    final app = AppController(persist: false, tick: false);
    addTearDown(app.dispose);
    await tester.pumpWidget(HorizonApp(controller: app));
    await tester.pumpAndSettle();
    await tester.tap(find.text('基础仪表'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(844, 390);
    await tester.pumpAndSettle();
    expect(find.byType(DashboardScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(
      calls.any(
        (c) =>
            c.method == 'SystemChrome.setPreferredOrientations' &&
            (c.arguments as List).contains('DeviceOrientation.landscapeLeft'),
      ),
      true,
    );
    await tester.tap(find.text('专业'));
    await tester.pumpAndSettle();
    expect(app.style, DashboardStyle.professional);
    expect(find.byType(DashCanvas), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('退出仪表'));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(
      calls.any(
        (c) =>
            c.method == 'SystemChrome.setPreferredOrientations' &&
            (c.arguments as List).contains('DeviceOrientation.portraitUp'),
      ),
      true,
    );
  });
  testWidgets('all four tabs work on a narrow phone', (tester) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final app = AppController(persist: false, tick: false);
    addTearDown(app.dispose);
    await tester.pumpWidget(HorizonApp(controller: app));
    await tester.pumpAndSettle();
    for (final label in ['地图', '攻略', '设置', '仪表盘']) {
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text(label),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });
}
