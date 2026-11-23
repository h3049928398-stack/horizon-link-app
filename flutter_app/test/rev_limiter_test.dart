import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/backup.dart';
import 'package:horizon_link/core/rev_limiter.dart';
import 'package:horizon_link/core/telemetry.dart';

void main() {
  late RevLimiterLearner learner;
  late Map<String, LimiterCalibration> saved;
  var tick = 0;
  TelemetryFrame frame(
    double rpm, {
    int gear = 2,
    int car = 17,
    int pi = 800,
    double max = 9000,
    double throttle = 1,
    bool driving = true,
  }) {
    tick += 16;
    return TelemetryFrame(
      timestamp: tick,
      receivedAt: DateTime(2026).add(Duration(milliseconds: tick)),
      carId: car,
      pi: pi,
      rpm: rpm,
      maxRpm: max,
      gear: gear,
      throttle: throttle,
      driving: driving,
      speed: 30,
      power: 100,
    );
  }

  void feed(List<double> rpms) {
    for (final rpm in rpms) {
      learner.update(frame(rpm), saved);
    }
  }

  void learn() => feed([6000, 7000, 6500, 7000, 6500, 7000, 6500]);
  setUp(() {
    learner = RevLimiterLearner();
    saved = {};
    tick = 0;
  });

  test('locks after three recovered bounces; low/high gear targets differ', () {
    feed([6000, 7000, 6500, 7000, 6500]);
    expect(saved, isEmpty);
    feed([7000, 6500]);
    expect(saved['17:800']!.rpm, 7000);
    final low = learner.snapshot(frame(6500), saved, available: true);
    expect(low.shiftTargetRpm, 6250);
    expect(
      learner
          .snapshot(frame(6500, gear: 4), saved, available: true)
          .shiftTargetRpm,
      6500,
    );
    for (final gear in [0, 11, 20]) {
      expect(
        learner
            .snapshot(frame(6500, gear: gear), saved, available: true)
            .shiftTargetRpm,
        isNull,
      );
    }
    expect(
      learner.snapshot(frame(6500), saved, available: false).shiftTargetRpm,
      isNull,
    );
  });

  test('one descending slope cannot count as three bounces', () {
    feed([7000, 6940, 6880, 6820, 6760]);
    expect(saved, isEmpty);
    expect(learner.snapshot(frame(6760), saved, available: true).bounces, 1);
  });

  test('higher peak restarts evidence instead of locking a lower peak', () {
    feed([7000, 6500, 7000, 6500, 7100, 6600]);
    expect(saved, isEmpty);
    expect(learner.snapshot(frame(6600), saved, available: true).bounces, 1);
    feed([7100, 6600, 7100, 6600]);
    expect(saved['17:800']!.rpm, 7100);
  });

  test('normal upshifts and unknown gears do not count as limiter hits', () {
    for (final gear in [1, 2, 3, 4, 11, 5]) {
      learner.update(frame(7000, gear: gear), saved);
      learner.update(frame(6500, gear: gear + 1), saved);
    }
    expect(saved, isEmpty);
  });

  test('throttle boundary and invalid frames clear incomplete evidence', () {
    feed([7000, 6500, 7000, 6500]);
    learner.update(frame(7000, throttle: 249 / 255), saved);
    feed([7000, 6500]);
    expect(saved, isEmpty);
    learner.update(frame(7000, throttle: 250 / 255), saved);
    learner.update(frame(6500, throttle: 250 / 255), saved);
    expect(learner.snapshot(frame(6500), saved, available: true).bounces, 2);
    learner.update(frame(double.nan), saved);
    expect(learner.snapshot(frame(6500), saved, available: true).bounces, 0);
  });

  test(
    'interruptions, pauses and long gaps clear only incomplete learning',
    () {
      for (final interruption in ['pause', 'rewind', 'gap']) {
        feed([7000, 6500, 7000, 6500]);
        if (interruption == 'pause') {
          learner.update(frame(0, driving: false), saved);
        } else if (interruption == 'rewind') {
          learner.update(frame(7000), saved, interrupted: true);
        } else {
          tick += 2000;
          learner.update(frame(7000), saved);
        }
        feed([7000, 6500]);
        expect(saved, isEmpty);
        learner.interrupt();
      }
      learn();
      learner.interrupt();
      expect(saved['17:800']!.rpm, 7000);
    },
  );

  test(
    'car and PI separate caches; tachometer changes invalidate above 250 RPM',
    () {
      learn();
      learner.update(frame(6500, car: 18), saved);
      expect(
        learner
            .snapshot(frame(6500, car: 18), saved, available: true)
            .limiterRpm,
        isNull,
      );
      expect(
        learner
            .snapshot(frame(6500, pi: 801), saved, available: true)
            .limiterRpm,
        isNull,
      );
      learner.update(frame(6500, max: 9250), saved);
      expect(saved, hasLength(1));
      expect(learner.update(frame(6500, max: 9251), saved), true);
      expect(saved, isEmpty);
    },
  );

  test('version 2 settings and backups preserve calibrations, old data defaults empty', () {
    final settings = AppSettings();
    settings.limiterCalibrations['17:800'] = const LimiterCalibration(
      7000.5,
      9000,
    );
    final restored = AppSettings.fromJson(
      jsonDecode(jsonEncode(settings.toJson())),
    );
    expect(restored.limiterCalibrations['17:800']!.rpm, 7000.5);
    expect(AppSettings.fromJson({}).limiterCalibrations, isEmpty);
    final backup = {
      'version': 2,
      'settings': settings.toJson(),
      'sessions': [],
    };
    expect(parseUserBackup(jsonEncode(backup))['version'], 2);
    final reboot = RevLimiterLearner();
    expect(
      reboot
          .snapshot(frame(6500), restored.limiterCalibrations, available: true)
          .shiftTargetRpm,
      6250.5,
    );
  });

  test('invalid calibration backup is rejected before restore', () {
    for (final invalid in [
      [],
      {
        'oops': {'rpm': 7000, 'nominalMaxRpm': 9000},
      },
      {
        '17:800': {'rpm': -1, 'nominalMaxRpm': 9000},
      },
      {
        '17:800': {'rpm': 7000, 'nominalMaxRpm': '9000'},
      },
      {
        '17:800': {'rpm': 7000, 'nominalMaxRpm': 9000, 'extra': 1},
      },
    ]) {
      expect(
        () => parseUserBackup(
          jsonEncode({
            'version': 2,
            'settings': {'limiterCalibrations': invalid},
            'sessions': [],
          }),
        ),
        throwsFormatException,
      );
    }
  });

  test('controller learns free roam, rejects stale frames and resets current car only', () {
    final app = AppController(persist: false, tick: false)..ready = true;
    addTearDown(app.dispose);
    expect(app.limiter.shiftTargetRpm, isNull);
    for (final rpm in [6000.0, 7000, 6500, 7000, 6500, 7000, 6500]) {
      app.ingest(frame(rpm.toDouble()));
    }
    expect(app.racing, false);
    expect(app.recording, isNull);
    expect(app.limiter.shiftTargetRpm, 6250);
    final stale = TelemetryFrame(
      timestamp: tick - 1,
      receivedAt: DateTime(2026).add(Duration(milliseconds: tick)),
      carId: 17,
      pi: 800,
      rpm: 9000,
      maxRpm: 12000,
      gear: 2,
      driving: true,
      throttle: 1,
    );
    app.ingest(stale);
    expect(app.frame.maxRpm, 9000);
    expect(app.limiter.shiftTargetRpm, 6250);
    app.settings.limiterCalibrations['18:800'] = const LimiterCalibration(
      8000,
      10000,
    );
    app.setLimiterForeground(false);
    expect(app.limiter.shiftTargetRpm, isNull);
    app.setLimiterForeground(true);
    expect(app.limiter.shiftTargetRpm, isNull);
    app.ingest(frame(6500, gear: 4));
    expect(app.limiter.shiftTargetRpm, 6500);
    app.resetCurrentLimiter();
    expect(app.limiter.shiftTargetRpm, isNull);
    expect(app.settings.limiterCalibrations.keys, ['18:800']);
  });

  test(
    'learning during a layout transaction survives the serialized final flush',
    () async {
      final blocker = Completer<void>();
      final writes = <String>[];
      final app = AppController(
        tick: false,
        writeData: (text) async {
          writes.add(text);
          if (writes.length == 1) await blocker.future;
        },
      )..ready = true;
      addTearDown(app.dispose);
      final transaction = app.saveCustomDashboard(
        'test',
        CustomDashboard.parse(CustomDashboard.example),
      );
      await Future<void>.delayed(Duration.zero);
      for (final rpm in [6000.0, 7000, 6500, 7000, 6500, 7000, 6500]) {
        app.ingest(frame(rpm.toDouble()));
      }
      expect(app.limiter.shiftTargetRpm, 6250);
      blocker.complete();
      await transaction;
      await app.flushSaved();
      final data = parseUserBackup(writes.last);
      expect(data['settings']['limiterCalibrations']['17:800']['rpm'], 7000);
      expect(data['settings']['customDashboards'], hasLength(1));
    },
  );

  test(
    'failed calibration save leaves existing disk data intact and can retry',
    () async {
      var disk = jsonEncode({'version': 2, 'settings': {}, 'sessions': []});
      final original = disk;
      var fail = true;
      final app = AppController(
        tick: false,
        writeData: (text) async {
          if (fail) throw StateError('disk unavailable');
          disk = text;
        },
      )..ready = true;
      addTearDown(app.dispose);
      for (final rpm in [6000.0, 7000, 6500, 7000, 6500, 7000, 6500]) {
        app.ingest(frame(rpm.toDouble()));
      }
      await expectLater(app.flushSaved(), throwsStateError);
      expect(disk, original);
      fail = false;
      await app.flushSaved();
      expect(
        parseUserBackup(
          disk,
        )['settings']['limiterCalibrations']['17:800']['rpm'],
        7000,
      );
    },
  );
}
