import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/racing.dart';
import 'package:horizon_link/core/replay.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/pages/replay_page.dart';
import 'package:horizon_link/pages/telemetry_page.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';
import 'package:horizon_link/widgets/replay_chart.dart';

void main() {
  final session = DrivingSession('test')
    ..add(TelemetryFrame(x: 10, z: 20, speed: 20))
    ..add(TelemetryFrame(x: 20, z: 30, speed: 25));
  final timeline = ReplayTimeline(session);
  final painters = <String, CustomPainter>{
    'dashboard': DashboardPainter(
      TelemetryFrame(),
      AppSettings(),
      DashboardStyle.professional,
      null,
    ),
    'telemetry': TelemetryPainter(session, 0),
    'replay chart': ReplayChartPainter(ReplayChartData(timeline), {
      ReplayChannel.speed,
    }, 1),
    'replay track': ReplayTrackPainter(ReplayTrack(timeline), 1, null),
  };
  for (final entry in painters.entries) {
    testWidgets('${entry.key} never clears sibling canvas pixels', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 400, 240),
          Paint()..color = const Color(0xffff0000),
        );
        canvas.save();
        canvas.translate(100, 50);
        entry.value.paint(canvas, const Size(180, 130));
        canvas.restore();
        final picture = recorder.endRecording();
        final image = await picture.toImage(400, 240);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final point in [
          const Offset(10, 10),
          const Offset(390, 230),
          const Offset(300, 60),
        ]) {
          final offset = (point.dy.toInt() * 400 + point.dx.toInt()) * 4;
          expect(
            [for (var n = 0; n < 4; n++) bytes.getUint8(offset + n)],
            [255, 0, 0, 255],
            reason:
                '${entry.key} erased pixels outside its own bounds at $point',
          );
        }
        image.dispose();
        picture.dispose();
      });
    });
  }
}
