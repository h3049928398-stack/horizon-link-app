import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/navigation.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/services/weekly_content_service.dart';
import 'package:horizon_link/widgets/ios_glass_controls.dart';
import 'package:horizon_link/widgets/liquid_glass.dart';

import 'weekly_content_test.dart' show encoded, graph, now;

const _glassEvents = EventChannel('horizon_link/liquid_glass');
const _glassNavigation = ValueKey('glass-navigation');
const _ios = TargetPlatformVariant({TargetPlatform.iOS});

Finder get _bar => find.byType(NavigationBar);
Finder get _iosBar => find.byKey(_glassNavigation);
final _ids = <String, int>{};
final _updates = <String, MethodCall>{};
Future<void> _activate(String kind, int index) async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  await messenger.handlePlatformMessage(
    'horizon_link/controls/${_ids[kind]}',
    const StandardMethodCodec().encodeMethodCall(MethodCall('activate', index)),
    null,
  );
}

Finder get _material => find.byWidgetPredicate(
  (widget) =>
      widget is UiKitView &&
      (widget.viewType == 'horizon_link/liquid_glass_surface' ||
          [
            'tabs',
            'connection',
          ].contains((widget.creationParams as Map)['kind'])),
);

Future<({void Function(bool) reportSupport, Future<void> Function() close})>
_mountApp(
  WidgetTester tester,
  AppController app, {
  bool initialSupport = true,
  VoidCallback? onListen,
}) async {
  tester.view.physicalSize = const Size(320, 780);
  tester.view.devicePixelRatio = 1;
  tester.view.padding = const FakeViewPadding(top: 48, bottom: 34);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
    tester.view.resetPadding();
    tester.view.resetViewInsets();
  });
  MockStreamHandlerEventSink? sink;
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockStreamHandler(
    _glassEvents,
    MockStreamHandler.inline(
      onListen: (_, events) {
        sink = events;
        onListen?.call();
        events.success(initialSupport);
      },
    ),
  );
  messenger.setMockMethodCallHandler(SystemChannels.platform_views, (
    call,
  ) async {
    if (call.method == 'create' &&
        call.arguments['viewType'] == 'horizon_link/controls') {
      final params = const StandardMessageCodec().decodeMessage(
        ByteData.sublistView(call.arguments['params'] as Uint8List),
      ) as Map;
      final kind = params['kind'] as String;
      final option = '$kind/${params['name']}';
      final id = call.arguments['id'] as int;
      _ids[kind] = id;
      _ids[option] = id;
      messenger.setMockMethodCallHandler(
        MethodChannel('horizon_link/controls/$id'),
        (update) async {
          _updates[kind] = update;
          _updates[option] = update;
          return null;
        },
      );
    }
    return null;
  });
  var closed = false;
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await tester.pumpWidget(const SizedBox.shrink());
    for (final id in _ids.values) {
      messenger.setMockMethodCallHandler(
        MethodChannel('horizon_link/controls/$id'),
        null,
      );
    }
    _ids.clear();
    _updates.clear();
    app.dispose();
    messenger.setMockStreamHandler(_glassEvents, null);
    messenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
  }

  addTearDown(close);
  await tester.pumpWidget(HorizonApp(controller: app));
  await tester.pumpAndSettle();
  return (reportSupport: (supported) => sink!.success(supported), close: close);
}

void main() {
  testWidgets('Android never opens the iOS channel and keeps Material', (
    tester,
  ) async {
    final app = AppController(persist: false, tick: false);
    var listens = 0;
    await _mountApp(tester, app, onListen: () => listens++);
    expect(listens, 0);
    expect(_material, findsNothing);
    expect(find.byKey(_glassNavigation), findsNothing);
    expect(tester.widget<NavigationBar>(_bar).height, 74);
  }, variant: const TargetPlatformVariant({TargetPlatform.android}));

  testWidgets('iOS capability changes keep the selected tab and app theme', (
    tester,
  ) async {
    final app = AppController(persist: false, tick: false);
    final (:reportSupport, close: _) = await _mountApp(
      tester,
      app,
      initialSupport: false,
    );
    expect(_material, findsNothing);
    await tester.tap(find.byType(NavigationDestination).last);
    await tester.pumpAndSettle();
    reportSupport(true);
    await tester.pumpAndSettle();
    expect(tester.widget<IosGlassControls>(_iosBar).selectedIndex, 3);
    expect(find.byKey(_glassNavigation), findsOneWidget);
    expect(tester.getSize(_iosBar).height, 68 + 34);
    expect(_updates['tabs']!.arguments['dark'], true);
    app.updateSettings((s) => s.appearance = AppAppearance.light);
    await tester.pumpAndSettle();
    expect(_updates['tabs']!.arguments['dark'], false);
    reportSupport(false);
    await tester.pumpAndSettle();
    expect(_material, findsNothing);
    expect(find.byKey(_glassNavigation), findsNothing);
    expect(tester.widget<NavigationBar>(_bar).selectedIndex, 3);
  }, variant: _ios);

  testWidgets(
    'UIKit settings options change existing preferences and survive fallback',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      final mounted = await _mountApp(tester, app);
      await _activate('tabs', 3);
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('auto-race-recording')),
      );
      final next = !app.settings.autoRecord;
      await _activate('switch/进入比赛自动开始数据记录', next ? 1 : 0);
      await tester.pumpAndSettle();
      expect(app.settings.autoRecord, next);
      await _activate('menu/进入赛事后切换仪表盘', 0);
      await tester.pumpAndSettle();
      expect(app.settings.raceDashboard, isNull);
      final unitKind = tester
          .widgetList<IosOptionControl>(find.byType(IosOptionControl))
          .singleWhere((control) => control.name == '车速单位')
          .kind;
      expect(unitKind, anyOf('segments', 'menu'));
      await _activate('$unitKind/车速单位', 1);
      await tester.pumpAndSettle();
      expect(app.settings.mph, isTrue);
      await tester.dragUntilVisible(
        find.byKey(const ValueKey('language-selector')),
        find.byType(ListView).first,
        const Offset(0, 220),
      );
      await tester.pumpAndSettle();
      await _activate('menu/主题', 1);
      await tester.pumpAndSettle();
      expect(app.settings.appearance, AppAppearance.light);
      await _activate('menu/语言', 1);
      await tester.pumpAndSettle();
      expect(app.settings.language, 'en');
      mounted.reportSupport(false);
      await tester.pumpAndSettle();
      expect(find.byType(UiKitView), findsNothing);
      expect(
        tester
            .widget<SwitchListTile>(
              find.byKey(const ValueKey('auto-race-recording')),
            )
            .value,
        next,
      );
    },
    variant: _ios,
  );

  testWidgets('UIKit tab events switch pages and invalid indices are ignored', (
    tester,
  ) async {
    await _mountApp(tester, AppController(persist: false, tick: false));
    final id = _ids['tabs'];
    await _activate('tabs', 3);
    await tester.pumpAndSettle();
    expect(tester.widget<IosGlassControls>(_iosBar).selectedIndex, 3);
    expect(_ids['tabs'], id);
    await _activate('tabs', -1);
    await tester.pumpAndSettle();
    expect(tester.widget<IosGlassControls>(_iosBar).selectedIndex, 3);
  }, variant: _ios);

  testWidgets(
    'native controls update labels and accent without replacing the tab controller',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      await _mountApp(tester, app);
      final id = _ids['tabs'];
      final accent = _updates['tabs']!.arguments['accent'];
      app.updateSettings((s) {
        s.language = 'en';
        s.appearance = AppAppearance.light;
      });
      await tester.pumpAndSettle();
      expect(_ids['tabs'], id);
      expect(_updates['tabs']!.arguments['labels'], [
        'Dashboard',
        'Map',
        'Guides',
        'Settings',
      ]);
      expect(_updates['tabs']!.arguments['accent'], isNot(accent));
    },
    variant: _ios,
  );

  testWidgets('connection switches controls without losing the edited port', (
    tester,
  ) async {
    final mounted = await _mountApp(
      tester,
      AppController(persist: false, tick: false),
    );
    await tester.tap(
      find.descendant(of: find.byType(AppBar), matching: find.text('未连接')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '8001');
    mounted.reportSupport(false);
    await tester.pumpAndSettle();
    expect(find.text('8001'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '开始监听'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('连接游戏'), findsNothing);
  }, variant: _ios);

  testWidgets(
    'native connection actions stack for large English text above the keyboard',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      app.updateSettings((s) => s.language = 'en');
      await _mountApp(tester, app);
      await tester.tap(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Disconnected'),
        ),
      );
      await tester.pumpAndSettle();
      tester.platformDispatcher.textScaleFactorTestValue = 1.7;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pumpAndSettle();
      expect(_updates['connection']!.arguments['stacked'], true);
      expect(tester.getRect(_material).bottom, lessThanOrEqualTo(480));
      expect(tester.takeException(), isNull);
    },
    variant: _ios,
  );

  testWidgets('native map filter switches keep drafts local until Apply', (
    tester,
  ) async {
    final app = AppController(persist: false, tick: false)
      ..roadGraph = graph
      ..navigation = NavigationState(graph);
    await _mountApp(tester, app);
    await _activate('tabs', 1);
    await tester.pumpAndSettle();
    Future<void> open() async {
      await _activate('choice/筛选地点', 0);
      await tester.pumpAndSettle();
    }

    await open();
    final toggle = tester
        .widgetList<IosOptionControl>(find.byType(IosOptionControl))
        .firstWhere((option) => option.kind == 'switch');
    final previous = toggle.selected;
    final target = 'switch/${toggle.name}';
    await _activate(target, 1 - previous);
    await tester.pumpAndSettle();
    expect(_updates[target]!.arguments['selected'], 1 - previous);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await open();
    expect(_updates[target]!.arguments['selected'], previous);
    await _activate(target, 1 - previous);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('apply-place-filters')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<IosOptionControl>(
            find.byKey(const ValueKey('map-place-filters')),
          )
          .selected,
      0,
    );
  }, variant: _ios);

  testWidgets('weekly guide selects Map and keyboard clears the floating bar', (
    tester,
  ) async {
    final service = WeeklyContentService(
      persist: false,
      url: 'https://example.com/weekly.json',
      clock: () => now,
      fetch: (_) async => encoded(),
    );
    final app = AppController(persist: false, tick: false, weekly: service)
      ..roadGraph = graph
      ..navigation = NavigationState(graph);
    app.updateSettings((s) => s.language = 'en');
    await service.initialize(graph);
    final mounted = await _mountApp(tester, app);
    expect(tester.widget<IosGlassControls>(_iosBar).labels, [
      'Dashboard',
      'Map',
      'Guides',
      'Settings',
    ]);
    await _activate('tabs', 2);
    await tester.pumpAndSettle();
    final locate = find.byKey(const ValueKey('weekly-locate-location'));
    await tester.ensureVisible(locate);
    await tester.pumpAndSettle();
    expect(
      tester.getRect(locate).bottom,
      lessThan(tester.getRect(_iosBar).top),
    );
    await tester.tap(locate);
    await tester.pumpAndSettle();
    expect(tester.widget<IosGlassControls>(_iosBar).selectedIndex, 1);
    expect(_updates['tabs']!.arguments['selected'], 1);
    expect(find.text('Test location'), findsOneWidget);
    expect(_material, findsNWidgets(3)); // navigation, connection, map buttons
    final fitMap = find.byTooltip('Show full map');
    expect(
      tester.getRect(find.text('Test location')).bottom,
      lessThan(tester.getRect(_iosBar).top),
    );
    await _activate('menu/Change season', 2);
    await tester.pumpAndSettle();
    expect(_updates['menu/Change season']!.arguments['selected'], 2);
    expect(_material, findsNWidgets(3));
    expect(fitMap, findsOneWidget);

    final search = find.byType(TextField);
    await tester.enterText(search, 'no-match');
    tester.view.viewInsets = const FakeViewPadding(bottom: 310);
    await tester.pumpAndSettle();
    expect(_iosBar, findsNothing);
    expect(search.hitTestable(), findsOneWidget);
    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
    expect(tester.widget<IosGlassControls>(_iosBar).selectedIndex, 1);
    expect(tester.takeException(), isNull);
    await mounted.close();
  }, variant: _ios);

  testWidgets(
    'glass sheet and alert actions respond over the native backdrop',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      await _mountApp(tester, app);
      final status = find.descendant(
        of: find.byType(AppBar),
        matching: find.text('未连接'),
      );
      await tester.tap(status);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(BottomSheet)))
            .bottomSheetTheme
            .shape,
        isA<RoundedSuperellipseBorder>(),
      );
      expect(_material, findsOneWidget); // covered home surfaces are suspended
      expect(_updates['connection']!.arguments['labels'], ['关闭', '开始监听']);
      await tester.enterText(find.byType(TextField), '5200');
      await _activate('connection', 1);
      await tester.pumpAndSettle();
      expect(find.textContaining('请输入有效端口'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '8001');
      await _activate('connection', 0);
      await tester.pumpAndSettle();
      expect(find.text('连接游戏'), findsNothing);
      expect(_material, findsNWidgets(2));

      final context = tester.element(_iosBar);
      final dialog = showDialog<bool>(
        context: context,
        builder: (context) => LiquidGlassAlertDialog(
          title: const Text('Confirm change'),
          content: const Text('Keep only the selected layout.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel change'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply change'),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();
      expect(_material, findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(AlertDialog))).dialogTheme.shape,
        isA<RoundedSuperellipseBorder>(),
      );
      await tester.tap(find.text('Apply change'));
      await tester.pumpAndSettle();
      expect(await dialog, isTrue);
      expect(tester.takeException(), isNull);
    },
    variant: _ios,
  );
}
