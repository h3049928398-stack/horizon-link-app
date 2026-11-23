import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/pages/dashboard_screen.dart';
import 'package:horizon_link/services/dashboard_hint.dart';
import 'package:horizon_link/widgets/app_theme.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';

const _ios = TargetPlatformVariant({TargetPlatform.iOS});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final toastCalls = <MethodCall>[];
  setUp(() {
    toastCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DashboardHint.channel, (call) async {
          toastCalls.add(call);
          return null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DashboardHint.channel, null),
  );

  Future<void> holdToReturn(WidgetTester tester) async {
    final gesture = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('dashboard-fullscreen-surface')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1999));
    expect(find.byKey(const ValueKey('dashboard-toolbar')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await gesture.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('dashboard-toolbar')), findsOneWidget);
  }

  testWidgets('iOS built-in instruments fill the landscape safe area', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(956, 440);
    addTearDown(tester.view.reset);
    final app = AppController(persist: false, tick: false);
    addTearDown(app.dispose);
    await tester.pumpWidget(MaterialApp(home: DashboardScreen(app: app)));
    final canvas = find.byType(DashCanvas);
    final toggle = find.byKey(const ValueKey('dashboard-fullscreen-toggle'));
    final toolbar = find.byKey(const ValueKey('dashboard-toolbar'));
    final navigation = find.byKey(const ValueKey('expanded-navigation-toggle'));
    final surface = find.byKey(const ValueKey('dashboard-fullscreen-surface'));
    for (final (left, right) in [(62.0, 44.0), (44.0, 62.0)]) {
      tester.view.padding = FakeViewPadding(
        left: left,
        right: right,
        bottom: 21,
      );
      await tester.pump();
      for (final style in DashboardStyle.values) {
        app.chooseStyle(style);
        await tester.pump();
        final normal = tester.getRect(canvas);
        expect(
          normal,
          Rect.fromLTRB(
            left,
            tester.getRect(toolbar).bottom,
            956 - right - (style == DashboardStyle.basic ? 48 : 0),
            419,
          ),
        );
        if (style == DashboardStyle.basic) {
          await tester.tap(navigation);
          await tester.pump();
          expect(tester.getRect(canvas).right, 956 - right);
          expect(
            tester.getRect(navigation).center.dx,
            greaterThan(normal.center.dx),
          );
          await tester.tap(navigation);
          await tester.pump();
          expect(app.settings.expandedNav, isFalse);
        }
        await tester.tap(toggle);
        await tester.pump();
        expect(toolbar, findsNothing);
        expect(
          tester.getRect(canvas),
          Rect.fromLTRB(left, 0, 956 - right, 419),
        );
        expect(tester.getRect(surface), const Rect.fromLTWH(0, 0, 956, 440));
        expect(
          tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
          DashboardPainter.background,
        );
        await holdToReturn(tester);
        expect(tester.getRect(canvas), normal);
      }
    }
    expect(toastCalls.where((c) => c.method == 'showFullscreenHint'), isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: _ios);

  testWidgets(
    'iOS custom canvas keeps its proportions over the full backdrop',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(956, 440);
      tester.view.padding = const FakeViewPadding(
        left: 62,
        right: 62,
        bottom: 21,
      );
      addTearDown(tester.view.reset);
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      final layout = CustomDashboard.parse(
        CustomDashboard.example.replaceFirst('#05090D', '#80306090'),
      );
      app.settings.customDashboards['test'] = layout;
      app.chooseDashboard(const DashboardRef.custom('test'));
      final settingsBefore = app.settings.toJson();
      await tester.pumpWidget(MaterialApp(home: DashboardScreen(app: app)));
      await tester.tap(
        find.byKey(const ValueKey('dashboard-fullscreen-toggle')),
      );
      await tester.pump();
      final canvas = find.byType(DashCanvas);
      final bounds = tester.getRect(canvas);
      expect(bounds.size.aspectRatio, closeTo(1280 / 540, .001));
      expect(bounds.width, 832);
      expect(tester.widget<DashCanvas>(canvas).paintBackground, isFalse);
      expect(
        tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
        Color.alphaBlend(const Color(0x80306090), Colors.black),
      );
      expect(app.settings.toJson(), settingsBefore);
      await holdToReturn(tester);
      expect(tester.takeException(), isNull);
    },
    variant: _ios,
  );

  for (final language in ['zh', 'en']) {
    for (final style in DashboardStyle.values) {
      testWidgets('status and fullscreen fit $language ${style.name}', (
        tester,
      ) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(844, 390);
        tester.view.padding = const FakeViewPadding(left: 24, right: 8);
        addTearDown(tester.view.reset);
        final app = AppController(persist: false, tick: false);
        addTearDown(app.dispose);
        app.settings.language = language;
        app.chooseStyle(style);
        final settingsBefore = app.settings.toJson();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildTheme(),
            locale: Locale(language),
            supportedLocales: const [Locale('zh'), Locale('en')],
            localizationsDelegates: const [
              AppCopy.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            home: DashboardScreen(app: app),
          ),
        );
        final toggle = find.byKey(
          const ValueKey('dashboard-fullscreen-toggle'),
        );
        final status = find.byKey(
          const ValueKey('dashboard-connection-status'),
        );
        final toolbar = find.byKey(const ValueKey('dashboard-toolbar'));
        final navigation = find.byKey(
          const ValueKey('expanded-navigation-toggle'),
        );
        for (final size in [
          const Size(640, 300),
          const Size(844, 390),
          const Size(932, 430),
        ]) {
          tester.view.physicalSize = size;
          await tester.pump();
          final normal = tester.getRect(find.byType(DashCanvas));
          final connection = tester.getRect(status);
          final basic = tester.getRect(find.text(localize('基础', language)));
          expect(connection.right, lessThanOrEqualTo(basic.left));
          expect(connection.bottom, lessThanOrEqualTo(normal.top));
          expect(tester.getRect(toggle).right, closeTo(size.width - 8, .01));
          expect(find.byTooltip(localize('全屏仪表', language)), findsOneWidget);
          await tester.tap(toggle);
          await tester.pump();
          expect(toolbar, findsNothing);
          expect(status, findsNothing);
          expect(navigation, findsNothing);
          expect(find.byIcon(Icons.tune_rounded), findsNothing);
          expect(find.byIcon(Icons.more_horiz_rounded), findsNothing);
          expect(toggle, findsNothing);
          expect(find.byType(IconButton), findsNothing);
          expect(find.byType(SnackBar), findsNothing);
          expect(
            toastCalls
                .lastWhere((c) => c.method == 'showFullscreenHint')
                .arguments,
            {'text': localize('长按屏幕两秒返回', language)},
          );
          final full = tester.getRect(find.byType(DashCanvas));
          expect(full.width, greaterThanOrEqualTo(normal.width));
          expect(full.height, greaterThanOrEqualTo(normal.height));
          expect(full.width / full.height, closeTo(1280 / 540, .001));
          // Uses every available pixel on at least one axis, without stretching.
          expect(
            (full.width - (size.width - 32)).abs() < .01 ||
                (full.height - size.height).abs() < .01,
            isTrue,
          );
          expect(app.settings.toJson(), settingsBefore);
          await holdToReturn(tester);
          expect(tester.getRect(find.byType(DashCanvas)), normal);
          expect(toolbar, findsOneWidget);
          expect(tester.takeException(), isNull);
        }
        // Temporary portrait/small windows can scroll controls; fullscreen stays reachable.
        tester.view.physicalSize = const Size(360, 800);
        await tester.pump();
        await tester.tap(toggle);
        await tester.pump();
        expect(toolbar, findsNothing);
        await holdToReturn(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets(
    'system Toast dismissal redraws the dashboard without cancelling a hold',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      await tester.pumpWidget(MaterialApp(home: DashboardScreen(app: app)));
      await tester.tap(
        find.byKey(const ValueKey('dashboard-fullscreen-toggle')),
      );
      await tester.pump();
      final previousState = tester.state(find.byType(DashCanvas));
      final previousRect = tester.getRect(find.byType(DashCanvas));
      final previousFrame = tester
          .widget<DashCanvas>(find.byType(DashCanvas))
          .frame;
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const ValueKey('dashboard-fullscreen-surface')),
        ),
      );
      await tester.pump(const Duration(seconds: 1));
      tester.binding.channelBuffers.push(
        'horizon_link/dashboard',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('fullscreenHintHidden'),
        ),
        (_) {},
      );
      await tester.pump();
      expect(tester.state(find.byType(DashCanvas)), isNot(same(previousState)));
      expect(tester.getRect(find.byType(DashCanvas)), previousRect);
      expect(
        tester.widget<DashCanvas>(find.byType(DashCanvas)).frame,
        same(previousFrame),
      );
      // A late hide from an older, cancelled Toast must not consume the current
      // Toast's eventual dismissal notification.
      tester.binding.channelBuffers.push(
        'horizon_link/dashboard',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('fullscreenHintHidden'),
        ),
        (_) {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 999));
      expect(find.byKey(const ValueKey('dashboard-toolbar')), findsNothing);
      await tester.pump(const Duration(milliseconds: 1));
      await gesture.up();
      await tester.pump();
      expect(find.byKey(const ValueKey('dashboard-toolbar')), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      tester.binding.channelBuffers.push(
        'horizon_link/dashboard',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('fullscreenHintHidden'),
        ),
        (_) {},
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'short, moved, cancelled and backgrounded holds cannot restore fullscreen',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      app.message = 'Do not cover the fullscreen dashboard';
      await tester.pumpWidget(MaterialApp(home: DashboardScreen(app: app)));
      await tester.tap(
        find.byKey(const ValueKey('dashboard-fullscreen-toggle')),
      );
      await tester.pump();
      expect(find.text(app.message), findsNothing);
      final surface = find.byKey(
        const ValueKey('dashboard-fullscreen-surface'),
      );
      final point = tester.getCenter(surface);
      var gesture = await tester.startGesture(point);
      await tester.pump(const Duration(milliseconds: 1500));
      await gesture.up();
      await tester.pump(const Duration(seconds: 1));
      expect(surface, findsOneWidget);
      gesture = await tester.startGesture(point);
      await tester.pump(const Duration(seconds: 1));
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      expect(surface, findsOneWidget);
      gesture = await tester.startGesture(point);
      await tester.pump(const Duration(seconds: 1));
      await gesture.cancel();
      await tester.pump(const Duration(seconds: 2));
      expect(surface, findsOneWidget);
      gesture = await tester.startGesture(point);
      await tester.pump(const Duration(seconds: 1));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      expect(surface, findsOneWidget);
      await holdToReturn(tester);
      expect(
        toastCalls.where((c) => c.method == 'showFullscreenHint').length,
        1,
      );
      expect(
        toastCalls.where((c) => c.method == 'cancelFullscreenHint'),
        isNotEmpty,
      );
      // Destroying a route with an unfinished hold must not fire a stale callback.
      await tester.tap(
        find.byKey(const ValueKey('dashboard-fullscreen-toggle')),
      );
      await tester.pump();
      gesture = await tester.startGesture(point);
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await tester.pump(const Duration(seconds: 2));
      await gesture.up();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'back restores controls before exiting, reentry resets fullscreen',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
      app.settings.expandedNav = true;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openDashboard(context, app, DashboardStyle.basic),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      final toggle = find.byKey(const ValueKey('dashboard-fullscreen-toggle'));
      await tester.tap(toggle);
      await tester.pump();
      // A live/automatic style update keeps the page fullscreen.
      app.chooseStyle(DashboardStyle.gt);
      await tester.pump();
      expect(
        tester.widget<DashCanvas>(find.byType(DashCanvas)).style,
        DashboardStyle.gt,
      );
      expect(find.byKey(const ValueKey('dashboard-toolbar')), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboard-toolbar')), findsOneWidget);
      expect(find.byType(DashboardScreen), findsOneWidget);
      expect(app.settings.expandedNav, isTrue);
      await tester.tap(toggle);
      await tester.pump();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(DashboardScreen), findsNothing);
      expect(
        calls
            .lastWhere(
              (c) => c.method == 'SystemChrome.setPreferredOrientations',
            )
            .arguments,
        ['DeviceOrientation.portraitUp'],
      );
      expect(
        calls
            .lastWhere((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
            .arguments,
        'SystemUiMode.edgeToEdge',
      );
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboard-toolbar')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('expanded-navigation-toggle')),
        findsOneWidget,
      );
    },
  );
}
