import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';
import 'package:horizon_link/widgets/custom_dashboard_canvas.dart';
import 'package:horizon_link/widgets/limiter_settings.dart';

void main() {
  CustomDashboard layout() => CustomDashboard.parse(
    jsonEncode(
      jsonDecode(CustomDashboard.example)
        ..['components'] = [
          {
            'type': 'shiftLights',
            'x': 21,
            'y': 12,
            'width': 1240,
            'height': 18,
          },
        ],
    ),
  );
  test('builtin and custom lights stay dark without calibration and use explicit target', () async {
    Future<List<int>> pixel({
      required bool custom,
      double? target,
      bool flash = true,
    }) async {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      final frame = TelemetryFrame(rpm: 6250, maxRpm: 10000);
      final painter = custom
          ? CustomDashboardPainter(
              layout: layout(),
              frame: frame,
              settings: AppSettings(),
              hasData: true,
              flashOn: flash,
              shiftTargetRpm: target,
            )
          : DashboardPainter(
              frame,
              AppSettings(),
              DashboardStyle.professional,
              null,
              null,
              flash,
              null,
              target,
            );
      painter.paint(canvas, const Size(1280, 540));
      final picture = recorder.endRecording();
      final image = await picture.toImage(1280, 540);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final offset = (21 * 1280 + 45) * 4;
      final result = [for (var i = 0; i < 3; i++) bytes.getUint8(offset + i)];
      image.dispose();
      picture.dispose();
      return result;
    }

    for (final custom in [false, true]) {
      expect(
        (await pixel(custom: custom)).reduce((a, b) => a > b ? a : b),
        lessThan(65),
      );
      final on = await pixel(custom: custom, target: 6250);
      expect(on[2], 255);
      expect(on[2], greaterThan(on[0]));
      final off = await pixel(custom: custom, target: 6250, flash: false);
      expect(off[2], lessThan(65));
    }
  });

  for (final custom in [false, true]) {
    testWidgets('shared calibrated target flashes at 4 Hz (custom=$custom)', (
      tester,
    ) async {
      var target = 6250.0;
      Future<void> show() => tester.pumpWidget(
        MaterialApp(
          home: DashCanvas(
            frame: TelemetryFrame(rpm: 6250, maxRpm: 10000),
            settings: AppSettings(),
            style: DashboardStyle.professional,
            customLayout: custom ? layout() : null,
            shiftTargetRpm: target,
          ),
        ),
      );
      bool on() {
        final painters = tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.painter);
        return custom
            ? painters.whereType<CustomDashboardPainter>().single.flashOn
            : painters.whereType<DashboardPainter>().single.shiftFlashOn;
      }

      await show();
      expect(on(), true);
      await tester.pump(const Duration(milliseconds: 125));
      expect(on(), false);
      await tester.pump(const Duration(milliseconds: 125));
      expect(on(), true);
      target = 0;
      await show();
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'settings show learning, estimate, cue, reset, and both languages',
    (tester) async {
      final app = AppController(persist: false, tick: false)..ready = true;
      addTearDown(app.dispose);
      var timestamp = 0;
      void feed(double rpm) {
        timestamp += 16;
        app.ingest(
          TelemetryFrame(
            carId: 17,
            pi: 800,
            timestamp: timestamp,
            receivedAt: DateTime(2026).add(Duration(milliseconds: timestamp)),
            rpm: rpm,
            maxRpm: 10000,
            gear: 2,
            throttle: 1,
            driving: true,
          ),
        );
      }

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AnimatedBuilder(
              animation: app,
              builder: (_, _) => LimiterSettings(app: app),
            ),
          ),
        ),
      );
      expect(find.textContaining('等待驾驶数据'), findsOneWidget);
      feed(6000);
      await tester.pump();
      expect(find.textContaining('学习中'), findsOneWidget);
      for (final rpm in [7000.0, 6500, 7000, 6500, 7000, 6500]) {
        feed(rpm.toDouble());
      }
      await tester.pump();
      expect(find.textContaining('已标定限转估计：7000'), findsOneWidget);
      expect(find.textContaining('6250 RPM'), findsOneWidget);
      app.settings.language = 'en';
      app.notifyListeners();
      await tester.pump();
      expect(find.textContaining('Estimated limiter: 7000'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('reset-limiter')));
      await tester.pump();
      expect(app.settings.limiterCalibrations, isEmpty);
      expect(find.textContaining('Learning · 0/3'), findsOneWidget);
    },
  );
}
