import 'racing.dart';
import 'telemetry.dart';

/// A detached, read-only view of the retained recording. Playback never ingests
/// frames into the live controller or interpolates driving inputs.
class ReplayTimeline {
  final List<Sample> samples;
  final List<double> times = [0];
  final Set<int> breaks = {};

  ReplayTimeline(DrivingSession session)
    : samples = List.unmodifiable(
        session.effective.map((s) => Sample.fromJson(s.toJson())),
      ) {
    for (var i = 1; i < samples.length; i++) {
      final previous = samples[i - 1], next = samples[i];
      final wall =
          next.frame.receivedAt
              .difference(previous.frame.receivedAt)
              .inMicroseconds /
          1000000;
      final race = next.frame.raceTime - previous.frame.raceTime;
      final hasRaceClock =
          previous.frame.raceTime > 0 && next.frame.raceTime > 0;
      final delta = hasRaceClock && race > 0 ? race : wall;
      final discontinuity =
          previous.segment != next.segment ||
          wall > 2 ||
          wall < 0 ||
          (hasRaceClock && race < -.01) ||
          !delta.isFinite ||
          delta <= 0 ||
          delta > 2;
      if (discontinuity) breaks.add(i);
      times.add(times.last + (discontinuity ? .1 : delta));
    }
  }

  double get duration => samples.isEmpty ? 0 : times.last;
  int indexAt(double seconds) {
    if (samples.isEmpty) return -1;
    var low = 0, high = samples.length;
    while (low < high) {
      final mid = (low + high) ~/ 2;
      if (times[mid] <= seconds) {
        low = mid + 1;
      } else {
        high = mid;
      }
    }
    return (low - 1).clamp(0, samples.length - 1);
  }

  TelemetryFrame? frameAt(double seconds) {
    final index = indexAt(seconds);
    return index < 0 ? null : samples[index].frame;
  }
}
