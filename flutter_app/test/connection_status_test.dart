import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/racing.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/pages/dashboard_screen.dart';
import 'package:horizon_link/widgets/app_theme.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';

void main() {
  test(
    'startup never generates telemetry or marks injected frames connected',
    () async {
      final app = AppController(persist: false);
      addTearDown(app.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      expect(app.frame.speed, 0);
      expect(app.packets, 0);
      expect(app.connected, false);
      expect(app.recording, isNull);
      app.ingest(TelemetryFrame(timestamp: 1, speed: 30));
      expect(app.connected, false);
      app.startRecording();
      expect(app.recording, isNull);
      final old = DrivingSession.fromJson({'source': 'demo', 'samples': []});
      expect(old.source, 'demo');
    },
  );

  testWidgets(
    'real UDP drives both status labels, expires, resumes and resets',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      RawDatagramSocket? sender;
      addTearDown(() => sender?.close());
      await tester.runAsync(() async {
        sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        app.settings.port = sender!.port;
        sender!.close();
        sender = await RawDatagramSocket.bind(InternetAddress.loopbackIPv4, 0);
        await app.connect();
      });
      await tester.pumpWidget(HorizonApp(controller: app));
      await tester.pumpAndSettle();
      expect(find.text('未连接'), findsWidgets);
      expect(
        find.textContaining(RegExp('Demo|演示|模拟', caseSensitive: false)),
        findsNothing,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(),
          home: DashboardScreen(app: app),
        ),
      );
      await tester.pumpAndSettle();
      Text status() => tester.widget<Text>(
        find.descendant(
          of: find.byKey(const ValueKey('dashboard-connection-status')),
          matching: find.byType(Text),
        ),
      );
      expect(status().style!.color, appMuted);
      Future<void> send(List<int> bytes) async {
        await tester.runAsync(() async {
          final received = Completer<void>();
          void listener() {
            if (!received.isCompleted && app.connected) received.complete();
          }

          app.addListener(listener);
          try {
            sender!.send(
              bytes,
              InternetAddress.loopbackIPv4,
              app.settings.port,
            );
            await received.future.timeout(const Duration(seconds: 3));
          } finally {
            app.removeListener(listener);
          }
        });
        await tester.pump();
      }

      await send([1, 2, 3]);
      expect(app.rejected, 1);
      expect(status().data, '已连接');
      expect(status().style!.color, raceCyan);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2150)),
      );
      await tester.pump();
      expect(status().data, '未连接');
      expect(status().style!.color, appMuted);
      await send(Uint8List(324));
      expect(app.rejected, 1);
      expect(app.connected, true);
      app.updateSettings((s) => s.language = 'en');
      // A localized shell uses the same controller state as the driving page.
      await tester.pumpWidget(HorizonApp(controller: app));
      await tester.pumpAndSettle();
      expect(find.text('Connected'), findsWidgets);
      await tester.runAsync(app.connect);
      await tester.pump();
      expect(find.text('Disconnected'), findsWidgets);
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets('release controls fit a narrow screen ($language)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
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
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.text(localize('仪表设置', language)), findsOneWidget);
      expect(
        find.textContaining(RegExp('Demo|演示|模拟', caseSensitive: false)),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });
  }
}
