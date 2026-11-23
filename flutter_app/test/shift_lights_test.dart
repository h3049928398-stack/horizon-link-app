import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/shift_lights.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';

void main() {
  test('lights begin 1500 RPM before target and accumulate every 75 RPM', () {
    for (final target in [3000, 7500, 12000]) {
      expect(ShiftLights(target - 1500.01, target).litCount, 0);
      for (var i = 0; i < 20; i++) {
        final rpm = target - 1500.0 + 75 * i;
        expect(ShiftLights(rpm, target).litCount, i + 1);
        expect(ShiftLights(rpm, target).shiftNow, false);
      }
      expect(ShiftLights(target.toDouble(), target).shiftNow, true);
      expect(ShiftLights(target + 500.0, target).litCount, 20);
      expect(ShiftLights(target - 1501.0, target).litCount, 0);
    }
  });

  test('invalid RPM and targets never produce a shift warning', () {
    for (final rpm in [0.0, -1.0, double.nan, double.infinity]) {
      expect(ShiftLights(rpm, 7500).litCount, 0);
      expect(ShiftLights(rpm, 7500).shiftNow, false);
    }
    expect(ShiftLights(8000, 0).shiftNow, false);
    for (final target in [-1, double.nan, double.infinity]) {
      expect(ShiftLights(8000, target).litCount, 0);
      expect(ShiftLights(8000, target).shiftNow, false);
    }
  });

  test(
    'paint uses green yellow red progression and synchronized blue cue',
    () async {
      Future<List<int>> pixels(double rpm, bool flashOn) async {
        final recorder = ui.PictureRecorder();
        DashboardPainter(
          TelemetryFrame(rpm: rpm, maxRpm: 7500),
          AppSettings()..shiftRpm = 12000,
          DashboardStyle.professional,
          null,
          null,
          flashOn,
          null,
          7500,
        ).paint(Canvas(recorder), const Size(1280, 540));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1280, 540);
        final data = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final result = data.buffer.asUint8List().toList();
        image.dispose();
        picture.dispose();
        return result;
      }

      List<int> rgb(List<int> data, int led) {
        final offset = (21 * 1280 + 45 + led * 62) * 4;
        return data.sublist(offset, offset + 3);
      }

      final low = await pixels(5999, true);
      expect(rgb(low, 0)[1], lessThan(50));
      final start = await pixels(6000, true);
      expect(rgb(start, 0), [94, 255, 103]);
      expect(rgb(start, 1)[1], lessThan(50));
      final nearly = await pixels(7499, true);
      expect(rgb(nearly, 8), [94, 255, 103]);
      expect(rgb(nearly, 9), [229, 255, 67]);
      expect(rgb(nearly, 14), [255, 79, 80]);
      final on = await pixels(7500, true);
      final off = await pixels(7500, false);
      for (var i = 0; i < 20; i++) {
        expect(rgb(on, i), [48, 139, 255]);
        expect(rgb(off, i)[2], lessThan(50));
      }
      // Flashing changes only the upper row, including no change to the lower RPM bar.
      expect(on.sublist(40 * 1280 * 4), off.sublist(40 * 1280 * 4));
    },
  );

  testWidgets('flash keeps time across telemetry and stops after RPM drops', (
    tester,
  ) async {
    final settings = AppSettings();
    Future<void> show(
      double rpm, {
      DashboardStyle style = DashboardStyle.professional,
      bool enabled = true,
      double maxRpm = 7500,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TickerMode(
            enabled: enabled,
            child: DashCanvas(
              frame: TelemetryFrame(rpm: rpm, maxRpm: 12000),
              shiftTargetRpm: maxRpm,
              settings: settings,
              style: style,
            ),
          ),
        ),
      );
    }

    DashboardPainter painter() => tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<DashboardPainter>()
        .single;
    await show(7500);
    expect(painter().shiftFlashOn, true);
    await tester.pump(const Duration(milliseconds: 125));
    expect(painter().shiftFlashOn, false);
    await show(7600);
    expect(painter().shiftFlashOn, false);
    await tester.pump(const Duration(milliseconds: 125));
    expect(painter().shiftFlashOn, true);
    await tester.pump(const Duration(milliseconds: 125));
    expect(painter().shiftFlashOn, false);
    await show(6500);
    await tester.pumpAndSettle();
    expect(painter().shiftFlashOn, true);
    // Legacy manual settings cannot override the live UDP target.
    settings.shiftRpm = 6000;
    await show(6500);
    await tester.pump(const Duration(milliseconds: 125));
    expect(painter().shiftFlashOn, true);
    // A new vehicle's EngineMaxRpm must re-evaluate the threshold immediately.
    await show(6500, maxRpm: 6000);
    await tester.pump(const Duration(milliseconds: 125));
    expect(painter().shiftFlashOn, false);
    await show(6500, maxRpm: 0);
    await tester.pumpAndSettle();
    expect(painter().shiftFlashOn, true);
    await show(6500, style: DashboardStyle.basic);
    await tester.pumpAndSettle();
    expect(painter().shiftFlashOn, true);
    await show(6500, enabled: false);
    await tester.pumpAndSettle();
    expect(painter().shiftFlashOn, true);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('background suspends flash and resume restarts it', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: DashCanvas(
          frame: TelemetryFrame(rpm: 7500, maxRpm: 12000),
          shiftTargetRpm: 7500,
          settings: AppSettings(),
          style: DashboardStyle.professional,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 125));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 125));
    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<DashboardPainter>()
        .single;
    expect(painter.shiftFlashOn, false);
    await tester.pumpWidget(const SizedBox());
  });
}
