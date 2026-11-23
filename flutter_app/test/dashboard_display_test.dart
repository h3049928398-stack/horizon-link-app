import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/pages/dashboard_screen.dart';
import 'package:horizon_link/services/dashboard_display.dart';

void main() {
  testWidgets(
    'keeps only the visible foreground driving dashboard awake',
    (tester) async {
      final calls = <bool>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(DashboardDisplay.channel, (
        call,
      ) async {
        expect(call.method, 'setAwake');
        calls.add(call.arguments as bool);
        return null;
      });
      addTearDown(
        () =>
            messenger.setMockMethodCallHandler(DashboardDisplay.channel, null),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  openDashboard(context, app, DashboardStyle.basic),
              child: const Text('Drive'),
            ),
          ),
        ),
      );
      expect(calls, isEmpty);

      await tester.tap(find.text('Drive'));
      await tester.pumpAndSettle();
      expect(calls, [true]);

      final context = tester.element(find.byType(DashboardScreen));
      showModalBottomSheet<void>(
        context: context,
        builder: (_) => const Text('Controls'),
      );
      await tester.pumpAndSettle();
      expect(calls, [true]);
      nav.currentState!.pop();
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey('dashboard-fullscreen-toggle')),
      );
      await tester.pumpAndSettle();
      expect(calls, [true]);

      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
        await tester.pump();
        expect(calls, [true, false]);
      }
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, [true, false, true]);

      final hold = await tester.startGesture(
        tester.getCenter(find.byType(DashboardScreen)),
      );
      await tester.pump(const Duration(seconds: 2));
      await hold.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('dashboard-toolbar')), findsOneWidget);
      expect(calls, [true, false, true]);

      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('Telemetry history')),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls, [true, false, true, false]);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(calls, [true, false, true, false]);

      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(calls, [true, false, true, false, true]);
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(calls, [true, false, true, false, true, false]);
      expect(find.text('Drive'), findsOneWidget);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
  );
}
