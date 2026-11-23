import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:horizon_link/widgets/replay_chart.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/racing.dart';
import 'package:horizon_link/core/replay.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/pages/replay_page.dart';
import 'package:horizon_link/pages/telemetry_page.dart';
import 'package:horizon_link/widgets/app_theme.dart';

final epoch = DateTime(2026, 10, 30);
TelemetryFrame frame(int ms, {double? raceTime, double value = 0}) =>
    TelemetryFrame(
      receivedAt: epoch.add(Duration(milliseconds: ms)),
      driving: true,
      raceTime: raceTime ?? 10 + ms / 1000,
      speed: 10 + value,
      rpm: 1000 + value,
      gear: value.toInt() + 1,
      throttle: value / 10,
      brake: value / 20,
      steer: -value / 10,
      x: value * 100,
      y: value * 2,
      z: value * 200,
      tires: [value, value + 1, value + 2, value + 3],
    );

DrivingSession recording() => DrivingSession('udp')
  ..add(frame(0))
  ..add(frame(1000, value: 2))
  ..add(frame(2000, value: 4));

Widget host(Widget child, [String language = 'zh']) => MaterialApp(
  theme: buildTheme(),
  locale: Locale(language),
  supportedLocales: const [Locale('zh'), Locale('en')],
  localizationsDelegates: const [
    AppCopy.delegate,
    ...GlobalMaterialLocalizations.delegates,
  ],
  home: child,
);

void main() {
  test('telemetry chart background cannot cover the replay entry above it', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    const outside = Color(0xff123456);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 400, 400),
      Paint()..color = outside,
    );
    canvas.save();
    canvas.translate(40, 180);
    TelemetryPainter(recording(), 0).paint(canvas, const Size(320, 180));
    canvas.restore();
    final picture = recorder.endRecording();
    final image = await picture.toImage(400, 400);
    try {
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      List<int> pixel(int x, int y) =>
          List.generate(4, (i) => bytes.getUint8((y * 400 + x) * 4 + i));
      for (final point in [
        const Offset(200, 40),
        const Offset(10, 250),
        const Offset(390, 250),
        const Offset(200, 390),
      ]) {
        expect(
          pixel(point.dx.toInt(), point.dy.toInt()),
          [0x12, 0x34, 0x56, 0xff],
          reason: 'The chart must not paint over the replay button, metrics or adjacent content.',
        );
      }
      expect(pixel(42, 182), isNot([0x12, 0x34, 0x56, 0xff]));
      var curvePixels = 0;
      for (var y = 180; y < 360; y++) {
        for (var x = 40; x < 360; x++) {
          final rgba = pixel(x, y);
          if (rgba[1] > 180 && rgba[0] > 100 && rgba[2] < 150) curvePixels++;
        }
      }
      expect(
        curvePixels,
        greaterThan(100),
        reason:
            'The driving curve must still be painted inside the clipped card.',
      );
    } finally {
      image.dispose();
      picture.dispose();
    }
  });

  for (final language in ['zh', 'en']) {
    testWidgets(
      'landscape panels keep map left and chart above inputs ($language)',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        for (final size in [
          const Size(640, 360),
          const Size(844, 390),
          const Size(1024, 461),
        ]) {
          tester.view.physicalSize = size;
          await tester.pumpWidget(
            host(
              ReplayPage(key: ValueKey(size), session: recording()),
              language,
            ),
          );
          await tester.pumpAndSettle();
          final map = tester.getRect(
            find.byKey(const ValueKey('replay-map-panel')),
          );
          final chart = tester.getRect(
            find.byKey(const ValueKey('replay-chart-panel')),
          );
          final inputs = tester.getRect(
            find.byKey(const ValueKey('replay-input-panel')),
          );
          expect(map.right, lessThan(chart.left));
          expect(map.width, greaterThan(chart.width * 1.4));
          expect(chart.bottom, lessThan(inputs.top));
          expect(chart.left, inputs.left);
          expect(map.top, chart.top);
          expect(map.bottom, inputs.bottom);
          expect(tester.takeException(), isNull);
        }
      },
    );
  }

  testWidgets(
    'replay requests immersive landscape and restores portrait on exit',
    (tester) async {
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
      await tester.pumpWidget(host(ReplayPage(session: recording())));
      await tester.pumpAndSettle();
      expect(
        calls
            .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
            .last
            .arguments,
        ['DeviceOrientation.landscapeLeft', 'DeviceOrientation.landscapeRight'],
      );
      expect(
        calls
            .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
            .last
            .arguments,
        'SystemUiMode.immersiveSticky',
      );
      await tester.pumpWidget(const SizedBox());
      expect(
        calls
            .where((c) => c.method == 'SystemChrome.setPreferredOrientations')
            .last
            .arguments,
        ['DeviceOrientation.portraitUp'],
      );
      expect(
        calls
            .where((c) => c.method == 'SystemChrome.setEnabledSystemUIMode')
            .last
            .arguments,
        'SystemUiMode.edgeToEdge',
      );
    },
  );

  testWidgets(
    'channel selection applies multiple series, cancels edits and allows empty selection',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = recording();
      final before = jsonEncode(s.toJson());
      await tester.pumpWidget(host(ReplayPage(session: s)));
      await tester.pumpAndSettle();
      ReplayChartPainter painter() =>
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('replay-chart')),
                  )
                  .painter!
              as ReplayChartPainter;
      Future<void> edit(ReplayChannel channel) async {
        final finder = find.byKey(ValueKey('replay-channel-${channel.name}'));
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pump();
      }

      await tester.tap(find.byKey(const ValueKey('replay-select-channels')));
      await tester.pumpAndSettle();
      await edit(ReplayChannel.speed);
      await edit(ReplayChannel.brake);
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(painter().channels, {ReplayChannel.throttle, ReplayChannel.brake});
      await tester.tap(find.byKey(const ValueKey('replay-select-channels')));
      await tester.pumpAndSettle();
      await edit(ReplayChannel.speed);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expect(painter().channels, {ReplayChannel.throttle, ReplayChannel.brake});
      await tester.tap(find.byKey(const ValueKey('replay-select-channels')));
      await tester.pumpAndSettle();
      await edit(ReplayChannel.throttle);
      await edit(ReplayChannel.brake);
      await tester.tap(find.text('应用'));
      await tester.pumpAndSettle();
      expect(find.text('请选择曲线数据'), findsOneWidget);
      expect(jsonEncode(s.toJson()), before);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'chart touch seeks the same sample as map and pedals, including backwards',
    (tester) async {
      tester.view.physicalSize = const Size(844, 390);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(host(ReplayPage(session: recording())));
      await tester.pumpAndSettle();
      final finder = find.byKey(const ValueKey('replay-chart'));
      final origin = tester.getTopLeft(finder);
      final rect = ReplayChartPainter.plotRect(tester.getSize(finder));
      await tester.tapAt(
        origin + Offset(rect.left + rect.width * .75, rect.center.dy),
      );
      await tester.pump();
      expect(
        (tester.widget<CustomPaint>(finder).painter! as ReplayChartPainter)
            .index,
        1,
      );
      expect(
        (tester
                    .widget<CustomPaint>(
                      find.byKey(const ValueKey('replay-track')),
                    )
                    .painter!
                as ReplayTrackPainter)
            .index,
        1,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('replay-throttle'))).data,
        '20%',
      );
      await tester.tapAt(
        origin + Offset(rect.left + rect.width * .1, rect.center.dy),
      );
      await tester.pump();
      expect(
        (tester.widget<CustomPaint>(finder).painter! as ReplayChartPainter)
            .index,
        0,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('replay-throttle'))).data,
        '0%',
      );
      expect(tester.takeException(), isNull);
    },
  );

  test('timeline uses race timing and holds all fields at the same sample', () {
    final s = DrivingSession('udp')
      ..add(frame(0))
      ..add(frame(1500, raceTime: 11, value: 2))
      ..add(frame(1900, raceTime: 11.5, value: 4));
    final replay = ReplayTimeline(s);
    expect(replay.times, [0, 1, 1.5]);
    expect(replay.indexAt(-1), 0);
    expect(replay.indexAt(.999), 0);
    final f = replay.frameAt(1)!;
    expect(
      [f.speed, f.rpm, f.steer, f.throttle, f.brake, f.x],
      [12, 1002, -.2, .2, .1, 200],
    );
    expect(replay.indexAt(100), 2);
  });

  test('free driving uses receive times, including normal lap changes', () {
    final s = DrivingSession('udp')
      ..add(frame(0, raceTime: 0))
      ..add(frame(150, raceTime: 0))
      ..add(frame(450, raceTime: 0));
    final replay = ReplayTimeline(s);
    expect(replay.times, orderedEquals([0, .15, closeTo(.45, .000001)]));
    expect(replay.breaks, isEmpty);
  });

  test('gaps and segment changes compress waits and break the track', () {
    final s = recording()
      ..samples.add(Sample(frame(12000, raceTime: 12.1, value: 6), 0))
      ..samples.add(Sample(frame(12100, raceTime: 5, value: 8), 1));
    final replay = ReplayTimeline(s);
    expect(replay.breaks, {3, 4});
    expect(replay.duration, closeTo(2.2, .0001));
    final track = ReplayTrack(replay);
    expect(track.breaks, {3, 4});
    expect(track.path.computeMetrics().length, 1);
  });

  test('empty, single and duplicate timestamp recordings remain usable', () {
    final s = DrivingSession('udp');
    expect(ReplayTimeline(s).frameAt(0), isNull);
    s.add(frame(0));
    expect(ReplayTimeline(s).duration, 0);
    s.add(frame(0, value: 1));
    final replay = ReplayTimeline(s);
    expect(replay.duration, .1);
    expect(replay.breaks, {1});
  });

  test(
    'old non-driving zero coordinates never create a false track to origin',
    () {
      final s = recording();
      s.samples.insert(1, Sample(TelemetryFrame(receivedAt: epoch), 0));
      final replay = ReplayTimeline(s);
      final track = ReplayTrack(replay);
      expect(track.points[1], isNull);
      expect(track.path.computeMetrics().length, 1);
      expect(track.bounds.left, greaterThan(500));
      expect(replay.samples.length, 4);
      expect(replay.samples[1].frame.driving, isFalse);
    },
  );

  test('snapshot excludes superseded data and cannot change saved samples', () {
    final s = recording()..samples[1].superseded = true;
    final saved = jsonEncode(s.toJson());
    final replay = ReplayTimeline(s);
    expect(replay.samples.length, 2);
    replay.samples.first.frame.tires[0] = 99;
    expect(jsonEncode(s.toJson()), saved);
    s.add(frame(3000, value: 6));
    s.rewindTo(frame(1000));
    expect(replay.samples.length, 2);
    expect(replay.frameAt(replay.duration)!.x, 400);
  });

  test('confirmed rewind and old JSON replay only the retained branch', () {
    final s = recording()..add(frame(3000, value: 9));
    s.add(frame(4000, raceTime: 11, value: 3), confirmedRewind: true);
    final restored = DrivingSession.fromJson(
      jsonDecode(jsonEncode(s.toJson())),
    );
    final replay = ReplayTimeline(restored);
    expect(replay.samples.map((s) => s.frame.x), [0, 300]);
    expect(replay.breaks, {1});
  });

  for (final language in ['zh', 'en']) {
    testWidgets('landscape replay seeks all channels together ($language)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(640, 360);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final s = recording();
      final saved = jsonEncode(s.toJson());
      await tester.pumpWidget(host(ReplayPage(session: s), language));
      await tester.pumpAndSettle();
      final slider = tester.widget<Slider>(
        find.byKey(const ValueKey('replay-progress')),
      );
      slider.onChanged!(1);
      await tester.pump();
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('replay-throttle'))).data,
        '20%',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('replay-brake'))).data,
        '10%',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('replay-steer'))).data,
        '-20%',
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('replay-speed'))).data,
        '43 km/h',
      );
      final painter =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('replay-track')),
                  )
                  .painter!
              as ReplayTrackPainter;
      final curve =
          tester
                  .widget<CustomPaint>(
                    find.byKey(const ValueKey('replay-chart')),
                  )
                  .painter!
              as ReplayChartPainter;
      expect(painter.index, 1);
      expect(curve.index, 1);
      expect(curve.channels, {ReplayChannel.speed, ReplayChannel.throttle});
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('replay-chart-value-throttle')),
            )
            .data,
        '20 %',
      );
      expect(painter.track.points[1]!.dx, closeTo(592.1968, .0001));
      await tester.tap(
        find.byTooltip(language == 'zh' ? '采样详情' : 'Sample details'),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(
        find.byKey(const ValueKey('replay-detail-gear')),
      );
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('replay-detail-gear')))
            .data,
        '3',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('replay-detail-tires-front')),
      );
      expect(
        tester
            .widget<Text>(
              find.byKey(const ValueKey('replay-detail-tires-front')),
            )
            .data,
        '2.0 / 3.0',
      );
      expect(jsonEncode(s.toJson()), saved);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('play, pause, speed, completion, restart and dispose', (
    tester,
  ) async {
    await tester.pumpWidget(host(ReplayPage(session: recording())));
    await tester.pumpAndSettle();
    tester
        .widget<DropdownButton<double>>(
          find.byKey(const ValueKey('replay-rate')),
        )
        .onChanged!(2);
    await tester.tap(find.byKey(const ValueKey('replay-play')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 550));
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('replay-sample'))).data,
      '2 / 3',
    );
    await tester.tap(find.byKey(const ValueKey('replay-play')));
    await tester.pump();
    final paused = tester.widget<Slider>(find.byType(Slider)).value;
    await tester.pump(const Duration(seconds: 2));
    expect(tester.widget<Slider>(find.byType(Slider)).value, paused);
    await tester.tap(find.byKey(const ValueKey('replay-play')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget<Slider>(find.byType(Slider)).value, 2);
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    await tester.tap(find.byKey(const ValueKey('replay-play')));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('backgrounding pauses playback and step controls seek exactly', (
    tester,
  ) async {
    await tester.pumpWidget(host(ReplayPage(session: recording())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('下一采样'));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 1);
    await tester.tap(find.byTooltip('上一采样'));
    await tester.pump();
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    await tester.tap(find.byKey(const ValueKey('replay-play')));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(seconds: 4));
    expect(find.byIcon(Icons.pause_rounded), findsNothing);
    expect(tester.widget<Slider>(find.byType(Slider)).value, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets(
    'saved session can be selected during live recording without ingesting replay',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      app.recording = recording();
      final saved = recording()..samples.clear();
      saved.add(frame(0, value: 9));
      app.sessions.add(saved);
      await tester.pumpWidget(host(TelemetryPage(app: app)));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byType(ListTile), 300);
      await tester.tap(find.byType(ListTile).last);
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('open-replay')),
        -300,
      );
      await tester.tap(find.byKey(const ValueKey('open-replay')));
      await tester.pumpAndSettle();
      expect(find.byType(ReplayPage), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('replay-speed'))).data,
        '68 km/h',
      );
      expect(app.recording!.samples.length, 3);
      expect(app.frame.speed, isNot(19));
      expect(app.sessions.single, same(saved));
    },
  );

  testWidgets('empty and single-sample replay handle disabled playback', (
    tester,
  ) async {
    final s = DrivingSession('demo');
    await tester.pumpWidget(host(ReplayPage(session: s)));
    await tester.pumpAndSettle();
    expect(find.text('暂无可回放采样'), findsOneWidget);
    s.add(frame(0));
    await tester.pumpWidget(
      host(ReplayPage(key: const ValueKey('single'), session: s)),
    );
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('replay-play')))
          .onPressed,
      isNull,
    );
    expect(find.text('轨迹位置未变化'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
