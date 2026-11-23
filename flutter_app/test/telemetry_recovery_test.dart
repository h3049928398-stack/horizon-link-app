import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/racing.dart';
import 'package:horizon_link/core/telemetry.dart';

final _epoch = DateTime(2026, 10, 30);

TelemetryFrame _frame(
  int ms,
  double time, {
  double speed = 30,
  double rpm = 4000,
  double? currentLap,
  int lap = 0,
  int position = 5,
  bool driving = true,
}) => TelemetryFrame(
  timestamp: ms,
  receivedAt: _epoch.add(Duration(milliseconds: ms)),
  driving: driving,
  speed: speed,
  rpm: rpm,
  raceTime: time,
  currentLap: currentLap ?? time,
  lap: lap,
  position: position,
);

AppController _recordingApp() {
  final app = AppController(persist: false, tick: false);
  addTearDown(app.dispose);
  app.ingest(_frame(100, 10));
  app.ingest(_frame(800, 10.7));
  app.ingest(_frame(1000, 11));
  expect(app.racing, isTrue);
  expect(app.recording, isNotNull);
  return app;
}

List<double> _times(DrivingSession session) =>
    session.samples.map((s) => s.frame.raceTime).toList();

void main() {
  test('zero packets, including RPM-only rewind, wait indefinitely', () {
    final app = _recordingApp();
    final session = app.recording!;
    for (final ms in [1100, 2000, 5000, 10000]) {
      app.ingest(_frame(ms, 0, speed: 0, position: 0));
    }
    expect(app.racing, isTrue);
    expect(app.recording, same(session));
    expect(app.sessions, isEmpty);
    expect(_times(session), [10.7, 11]);
    expect(session.rewinds, 0);
    app.ingest(_frame(10200, 11.1));
    expect(_times(session), [10.7, 11, 11.1]);
    expect(session.rewinds, 0);
    expect(app.gain, isFalse);
  });

  test('resumed earlier clock removes every sample at or after target', () {
    final app = _recordingApp();
    final session = app.recording!;
    app.ingest(_frame(1200, 12, speed: 90));
    app.ingest(_frame(1400, 13, speed: 100));
    app.ingest(_frame(1500, 0, speed: 0, position: 0));
    app.ingest(_frame(1700, 11, speed: 20, position: 3));
    app.ingest(_frame(1900, 11.2, speed: 25, position: 3));
    expect(app.recording, same(session));
    expect(_times(session), [10.7, 11, 11.2]);
    expect(session.rewinds, 1);
    expect(session.samples.last.segment, 1);
    expect(session.topSpeed, 108);
    expect(session.averageSpeed, closeTo(90, .001));
    expect(app.gain, isFalse);
    app.stopRecording();
    final restored = DrivingSession.fromJson(
      jsonDecode(jsonEncode(app.sessions.single.toJson())),
    );
    expect(_times(restored), [10.7, 11, 11.2]);
    expect(restored.samples.any((s) => s.superseded), isFalse);
  });

  test('repeated short rewinds bypass sampling interval and trim again', () {
    final app = _recordingApp();
    final session = app.recording!;
    app.ingest(_frame(1020, 0, speed: 0, position: 0));
    app.ingest(_frame(1040, 10.8));
    expect(_times(session), [10.7, 10.8]);
    app.ingest(_frame(1050, 0, speed: 0, position: 0));
    app.ingest(_frame(1060, 10.6));
    expect(_times(session), [10.6]);
    expect(session.rewinds, 2);
    expect(session.samples.single.segment, 2);
  });

  test('vehicle recovery without race data saves only the race timeline', () {
    final app = _recordingApp();
    app.ingest(_frame(1100, 0, speed: 0, position: 0));
    for (final ms in [2000, 3000, 3799]) {
      app.ingest(_frame(ms, 0, position: 0));
      expect(app.racing, isTrue);
      expect(app.sessions, isEmpty);
    }
    app.ingest(_frame(3800, 0, position: 0));
    expect(app.racing, isFalse);
    expect(app.recording, isNull);
    final saved = app.sessions.single;
    expect(_times(saved), [10.7, 11]);
    expect(saved.finalPosition, isNull);
    expect(saved.rewinds, 0);
  });

  test('frozen positive race fields also finish, without restarting', () {
    final app = _recordingApp();
    app.ingest(_frame(1100, 11, speed: 0));
    for (final ms in [2000, 3000, 3800, 4000, 5000, 6000]) {
      app.ingest(_frame(ms, 11));
    }
    expect(app.racing, isFalse);
    expect(app.recording, isNull);
    expect(_times(app.sessions.single), [10.7, 11]);
    // A genuinely advancing new race may still start normally.
    app.ingest(_frame(6200, 11.2));
    expect(app.racing, isTrue);
    expect(app.recording, isNotNull);
  });

  test('delayed race fields recover before end confirmation', () {
    final app = _recordingApp();
    app.ingest(_frame(1100, 0, speed: 0, position: 0));
    app.ingest(_frame(2000, 0, position: 0));
    app.ingest(_frame(3000, 11)); // Still frozen; continue waiting.
    expect(_times(app.recording!), [10.7, 11]);
    app.ingest(_frame(3700, 10.9));
    expect(app.racing, isTrue);
    expect(_times(app.recording!), [10.7, 10.9]);
    expect(app.recording!.rewinds, 1);
    expect(app.sessions, isEmpty);
  });

  test('another zero interval resets vehicle recovery confirmation', () {
    final app = _recordingApp();
    app.ingest(_frame(1100, 0, speed: 0, position: 0));
    app.ingest(_frame(2000, 0, position: 0));
    app.ingest(_frame(3000, 0, speed: 0, position: 0));
    app.ingest(_frame(5000, 0, position: 0));
    expect(app.racing, isTrue);
    app.ingest(_frame(6000, 11.1));
    expect(_times(app.recording!), [10.7, 11, 11.1]);
    expect(app.sessions, isEmpty);
  });

  test('real stationary driving and lap boundaries retain their samples', () {
    final app = _recordingApp();
    app.ingest(_frame(1200, 11.2, speed: 0));
    app.ingest(_frame(1400, 11.4, speed: 0));
    app.ingest(_frame(1600, 11.6, currentLap: .1, lap: 1));
    expect(_times(app.recording!), [10.7, 11, 11.2, 11.4, 11.6]);
    expect(app.recording!.rewinds, 0);
  });

  test('stale packets cannot confirm a rewind', () {
    final app = _recordingApp();
    app.ingest(_frame(1100, 0, speed: 0, position: 0));
    app.ingest(_frame(1050, 5));
    expect(_times(app.recording!), [10.7, 11]);
    expect(app.recording!.rewinds, 0);
    app.ingest(_frame(1200, 11.2));
    expect(app.recording!.rewinds, 0);
  });

  test('non-driving frames cannot end a race even with vehicle fields', () {
    final app = _recordingApp();
    app.ingest(_frame(1200, 0, driving: false, position: 0));
    app.ingest(_frame(5000, 0, driving: false, position: 0));
    expect(app.racing, isTrue);
    expect(_times(app.recording!), [10.7, 11]);
    app.ingest(_frame(6000, 9));
    expect(_times(app.recording!), [9]);
    expect(app.recording!.rewinds, 1);
  });

  test('a new race after free roam does not inherit the old rewind clock', () {
    final app = _recordingApp();
    app.ingest(_frame(1200, 0, position: 0));
    app.ingest(_frame(3000, 0, position: 0));
    expect(app.racing, isFalse);
    expect(_times(app.sessions.single), [10.7, 11]);
    app.ingest(_frame(3200, 1));
    app.ingest(_frame(4000, 1.8));
    expect(app.racing, isTrue);
    expect(_times(app.recording!), [1.8]);
    expect(app.recording!.rewinds, 0);
  });

  test('stream gap preserves race and resolves using the last live clock', () {
    final detector = RaceDetector();
    detector.update(_frame(100, 10));
    detector.update(_frame(800, 10.7));
    detector.gap();
    expect(detector.racing, isTrue);
    expect(detector.awaitingRecovery, isTrue);
    final result = detector.update(_frame(5000, 9));
    expect(result.rewound, isTrue);
    expect(result.recordable, isTrue);
    expect(result.racing, isTrue);
  });

  test('lap-only clocks distinguish next lap from rewind across a lap', () {
    final detector = RaceDetector();
    detector.update(_frame(100, 0, currentLap: 59));
    detector.update(_frame(800, 0, currentLap: 59.7));
    expect(detector.racing, isTrue);
    expect(
      detector.update(_frame(1000, 0, currentLap: .1, lap: 1)).rewound,
      isFalse,
    );
    detector.update(_frame(1200, 0, speed: 0, currentLap: 0, position: 0));
    final f = _frame(1400, 0, currentLap: 58);
    expect(detector.update(f).rewound, isTrue);
    final session = DrivingSession('udp')
      ..add(_frame(100, 0, currentLap: 57))
      ..add(_frame(800, 0, currentLap: 59.7))
      ..add(_frame(1000, 0, currentLap: .1, lap: 1))
      ..add(f, confirmedRewind: true);
    expect(session.samples.map((s) => s.frame.currentLap), [57, 58]);
    expect(session.rewinds, 1);
  });

  test('old version 2 sessions with superseded samples still load', () {
    final session = DrivingSession.fromJson({
      'source': 'udp',
      'samples': [
        {'frame': _frame(100, 12).toJson(), 'superseded': true},
        {'frame': _frame(200, 10).toJson(), 'segment': 1},
      ],
    });
    expect(session.samples.length, 2);
    expect(_times(session), [12, 10]);
    expect(session.effective.single.frame.raceTime, 10);
    session.add(_frame(300, 9), confirmedRewind: true);
    expect(_times(session), [9]);
  });
}
