import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/core/racing.dart';

void main() {
  test('rejects short packets and non-finite data', () {
    expect(() => decodePacket(Uint8List(323)), throwsFormatException);
    final bytes = Uint8List(324);
    ByteData.sublistView(bytes).setFloat32(16, double.nan, Endian.little);
    expect(() => decodePacket(bytes), throwsFormatException);
  });
  test('reads little-endian header from offset buffer', () {
    final bytes = Uint8List(350), view = ByteData.sublistView(bytes, 10, 334);
    view.setInt32(0, 1, Endian.little);
    view.setUint32(4, 123456, Endian.little);
    view.setFloat32(16, 4700, Endian.little);
    final f = decodePacket(Uint8List.sublistView(bytes, 10, 334));
    expect(f.driving, true);
    expect(f.timestamp, 123456);
    expect(f.rpm, 4700);
  });
  test('accepts timestamp rollover, rejects stale frames', () {
    expect(freshTimestamp(0xfffffff0, 20), true);
    expect(freshTimestamp(20, 20), false);
    expect(freshTimestamp(20, 19), false);
  });
  test('free roam is not a race, timed sprint is', () {
    final d = RaceDetector(), now = DateTime(2026);
    expect(
      d
          .update(TelemetryFrame(driving: true, raceTime: 10, receivedAt: now))
          .racing,
      false,
    );
    d.update(
      TelemetryFrame(driving: true, position: 6, raceTime: 1, receivedAt: now),
    );
    expect(
      d
          .update(
            TelemetryFrame(
              driving: true,
              position: 6,
              raceTime: 2,
              receivedAt: now.add(const Duration(seconds: 1)),
            ),
          )
          .racing,
      true,
    );
  });
  test('dropout preserves race, stable free roam restores it', () {
    final d = RaceDetector(), now = DateTime(2026);
    d.update(
      TelemetryFrame(driving: true, position: 6, raceTime: 1, receivedAt: now),
    );
    d.update(
      TelemetryFrame(
        driving: true,
        position: 6,
        raceTime: 2,
        receivedAt: now.add(const Duration(seconds: 1)),
      ),
    );
    d.gap();
    expect(d.racing, true);
    d.update(TelemetryFrame(receivedAt: now.add(const Duration(seconds: 3))));
    expect(d.racing, true);
    d.update(
      TelemetryFrame(
        driving: true,
        speed: 20,
        receivedAt: now.add(const Duration(seconds: 4)),
      ),
    );
    expect(
      d
          .update(
            TelemetryFrame(
              driving: true,
              speed: 20,
              receivedAt: now.add(const Duration(seconds: 6)),
            ),
          )
          .racing,
      false,
    );
  });
  test('confirmed rewind deletes future; unknown reset keeps segments', () {
    final s = DrivingSession('demo');
    for (final t in [1.0, 2.0, 3.0, 4.0]) {
      s.add(TelemetryFrame(raceTime: t));
    }
    s.add(TelemetryFrame(raceTime: 2.5), confirmedRewind: true);
    expect(s.samples.length, 3);
    expect(s.effective.map((s) => s.frame.raceTime), [1, 2, 2.5]);
    expect(s.rewinds, 1);
    final u = DrivingSession('udp')
      ..add(TelemetryFrame(raceTime: 10))
      ..add(TelemetryFrame(raceTime: 1));
    expect(u.effective.length, 2);
    expect(u.samples.last.segment, 1);
  });
  test('lap timer carries milliseconds', () {
    expect(lapTime(59.9996), '1:00.000');
    expect(lapTime(0), '--:--.---');
  });
  test('saved session preserves trimmed timeline and result', () {
    final s = DrivingSession('demo')
      ..add(TelemetryFrame(raceTime: 3, speed: 20))
      ..add(TelemetryFrame(raceTime: 1, speed: 30), confirmedRewind: true);
    s.finalPosition = 2;
    final restored = DrivingSession.fromJson(s.toJson());
    expect(restored.samples.length, 1);
    expect(restored.effective.length, 1);
    expect(restored.topSpeed, 108);
    expect(restored.finalPosition, 2);
  });
}
