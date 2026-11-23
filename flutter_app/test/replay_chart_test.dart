import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/core/racing.dart';
import 'package:horizon_link/core/replay.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/widgets/replay_chart.dart';

ReplayTimeline timeline() {
  final s = DrivingSession('udp');
  for (var i = 0; i < 3; i++) {
    s.add(
      TelemetryFrame(
        receivedAt: DateTime(2026).add(Duration(seconds: i)),
        raceTime: 10.0 + i,
        speed: 20.0 + i,
        throttle: [.2, .8, .4][i],
        steer: -.5 + i * .5,
        tires: const [],
      ),
    );
  }
  return ReplayTimeline(s);
}

void main() {
  test('chart ranges retain signed inputs and show consistent speed units', () {
    final data = ReplayChartData(timeline());
    expect(data.range(ReplayChannel.steer), (-100, 100));
    expect(
      data.normalized(ReplayChannel.steer, data.timeline.samples.first.frame),
      .25,
    );
    expect(data.range(ReplayChannel.throttle), (0, 100));
    expect(
      ReplayChannel.speed.display(data.timeline.samples.first.frame, false),
      '72 km/h',
    );
    expect(
      ReplayChannel.speed.display(data.timeline.samples.first.frame, true),
      '45 mph',
    );
    for (final channel in ReplayChannel.values) {
      expect(
        channel.value(data.timeline.samples.first.frame, false).isFinite,
        isTrue,
      );
    }
  });

  test('chart caches snapshot paths and breaks lines across timeline gaps', () {
    final replay = timeline();
    replay.breaks.add(2);
    final data = ReplayChartData(replay);
    const size = Size(200, 100);
    final path = data.path(ReplayChannel.throttle, size);
    expect(identical(path, data.path(ReplayChannel.throttle, size)), isTrue);
    expect(path.computeMetrics().length, 1);
    expect(
      identical(path, data.path(ReplayChannel.throttle, const Size(300, 100))),
      isFalse,
    );
  });

  test(
    'progressive chart draws no future curve after seeking backwards',
    () async {
      final data = ReplayChartData(timeline());
      const size = Size(240, 140);
      Future<int> futureColoredPixels(int index) async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        ReplayChartPainter(data, {
          ReplayChannel.throttle,
        }, index).paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(240, 140);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        final rect = ReplayChartPainter.plotRect(size);
        var pixels = 0;
        for (
          var x = (rect.left + rect.width * .65).ceil();
          x < rect.right.floor();
          x++
        ) {
          for (var y = rect.top.ceil(); y < rect.bottom.floor(); y++) {
            final offset = (y * 240 + x) * 4;
            if (bytes.getUint8(offset) == 192 &&
                bytes.getUint8(offset + 1) == 243 &&
                bytes.getUint8(offset + 2) == 91) {
              pixels++;
            }
          }
        }
        image.dispose();
        picture.dispose();
        return pixels;
      }

      expect(await futureColoredPixels(2), greaterThan(0));
      expect(await futureColoredPixels(1), 0);
    },
  );
}
