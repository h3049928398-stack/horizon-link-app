import 'telemetry.dart';

class RaceDetector {
  bool racing = false;
  DateTime? candidate, freeSince, lastGain;
  int previousPosition = 0;
  double previousTime = 0;
  TelemetryFrame? _lastRaceFrame;
  TelemetryFrame? _candidateFrame;
  bool awaitingRecovery = false;

  ({bool racing, bool gained, bool rewound, bool recordable}) update(
    TelemetryFrame f,
  ) {
    final evidence = _raceEvidence(f);
    final clockChange = _lastRaceFrame == null
        ? null
        : _raceClockChange(_lastRaceFrame!, f);
    final zeroed =
        f.speed <= .01 &&
        f.throttle <= .001 &&
        f.brake <= .001 &&
        f.power.abs() <= .01;
    var rewound = false;
    var recovered = false;
    if (racing &&
        (!f.driving ||
            (zeroed &&
                (!evidence || clockChange == null || clockChange <= .01)))) {
      awaitingRecovery = true;
      freeSince = null;
      candidate = null;
      previousPosition = 0;
    }
    if (awaitingRecovery) {
      // RPM may remain valid during rewind. Keep the last live race clock,
      // rather than comparing against the zero/frozen packets in between.
      if (evidence &&
          clockChange != null &&
          clockChange.abs() > .01 &&
          (!zeroed || clockChange > 0)) {
        rewound = clockChange < 0;
        recovered = true;
        awaitingRecovery = false;
        freeSince = null;
      } else {
        if (f.driving && !zeroed) {
          freeSince ??= f.receivedAt;
          if (f.receivedAt.difference(freeSince!).inMilliseconds >= 1800) {
            racing = false;
            awaitingRecovery = false;
            _lastRaceFrame = null;
            _candidateFrame = null;
            previousPosition = 0;
          }
        } else {
          freeSince = null;
        }
        return (
          racing: racing,
          gained: false,
          rewound: false,
          recordable: false,
        );
      }
    }
    if (evidence) {
      freeSince = null;
      candidate ??= f.receivedAt;
      _candidateFrame ??= f;
      if (f.receivedAt.difference(candidate!).inMilliseconds >= 650 &&
          (_raceClockChange(_candidateFrame!, f) ?? 0) > .01) {
        racing = true;
      }
    } else if (f.driving && !zeroed && f.position == 0 && f.currentLap == 0) {
      candidate = null;
      _candidateFrame = null;
      freeSince ??= f.receivedAt;
      if (f.receivedAt.difference(freeSince!).inMilliseconds >= 1800) {
        racing = false;
        _lastRaceFrame = null;
      }
    }
    final gained =
        racing &&
        !recovered &&
        f.raceTime >= previousTime - .5 &&
        previousPosition > 0 &&
        f.position > 0 &&
        f.position < previousPosition &&
        (lastGain == null ||
            f.receivedAt.difference(lastGain!).inMilliseconds > 1800);
    if (gained) lastGain = f.receivedAt;
    previousPosition = f.position;
    previousTime = f.raceTime;
    if (racing && evidence) {
      rewound = rewound || (clockChange != null && clockChange < -.01);
      _lastRaceFrame = f;
    }
    return (
      racing: racing,
      gained: gained && !rewound,
      rewound: rewound,
      recordable: !racing || evidence,
    );
  }

  void gap() {
    candidate = null;
    _candidateFrame = null;
    freeSince = null;
    awaitingRecovery = racing;
    previousPosition = 0;
  }
}

bool _raceEvidence(TelemetryFrame f) =>
    f.driving && f.position > 0 && (f.currentLap > 0 || f.raceTime > 0);

double? _raceClockChange(TelemetryFrame previous, TelemetryFrame next) {
  if (previous.raceTime > 0 && next.raceTime > 0) {
    return next.raceTime - previous.raceTime;
  }
  // Use lap number together with the lap timer only if total race time is
  // unavailable on both frames. A normal lap boundary is forward progress.
  if (previous.raceTime == 0 &&
      next.raceTime == 0 &&
      previous.currentLap > 0 &&
      next.currentLap > 0) {
    if (next.lap != previous.lap) return (next.lap - previous.lap).toDouble();
    return next.currentLap - previous.currentLap;
  }
  return null;
}

class Sample {
  final TelemetryFrame frame;
  final int segment;
  bool superseded;
  Sample(this.frame, this.segment, {this.superseded = false});
  Map<String, dynamic> toJson() => {
    'frame': frame.toJson(),
    'segment': segment,
    'superseded': superseded,
  };
  factory Sample.fromJson(Map<String, dynamic> j) => Sample(
    TelemetryFrame.fromJson(Map<String, dynamic>.from(j['frame'])),
    j['segment'] ?? 0,
    superseded: j['superseded'] == true,
  );
}

class DrivingSession {
  final String id, source;
  final DateTime started;
  DateTime? ended;
  int? finalPosition;
  int rewinds = 0, interruptions = 0;
  int _segment = 0;
  final List<Sample> samples = [];
  DrivingSession(this.source, {String? id, DateTime? started})
    : id = id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      started = started ?? DateTime.now();
  List<Sample> get effective => samples.where((s) => !s.superseded).toList();
  void rewindTo(TelemetryFrame f) {
    _segment = (samples.isEmpty ? _segment : samples.last.segment) + 1;
    rewinds++;
    // Delete the abandoned future from the actual list, so counts, statistics,
    // saved JSON and exported JSON all describe the same retained timeline.
    samples.removeWhere((s) {
      if (f.raceTime > 0) return s.frame.raceTime >= f.raceTime;
      return s.frame.lap > f.lap ||
          (s.frame.lap == f.lap && s.frame.currentLap >= f.currentLap);
    });
  }

  void add(TelemetryFrame f, {bool confirmedRewind = false}) {
    final previous = samples.isEmpty ? null : samples.last;
    _segment = previous?.segment ?? _segment;
    if (confirmedRewind) {
      rewindTo(f);
    } else if (previous != null && f.raceTime < previous.frame.raceTime - .5) {
      _segment++;
      rewinds++;
    }
    samples.add(Sample(f, _segment));
  }

  double get topSpeed => effective.fold(
    0.0,
    (v, s) => v > s.frame.speed * 3.6 ? v : s.frame.speed * 3.6,
  );
  double get averageSpeed {
    final frames = effective;
    if (frames.isEmpty) return 0;
    return frames.fold(0.0, (v, s) => v + s.frame.speed * 3.6) / frames.length;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'started': started.toIso8601String(),
    'ended': ended?.toIso8601String(),
    'finalPosition': finalPosition,
    'rewinds': rewinds,
    'interruptions': interruptions,
    'samples': samples.map((s) => s.toJson()).toList(),
  };
  factory DrivingSession.fromJson(Map<String, dynamic> j) {
    final s = DrivingSession(
      j['source'] ?? 'unknown',
      id: j['id'],
      started: DateTime.tryParse(j['started'] ?? ''),
    );
    s.ended = DateTime.tryParse(j['ended'] ?? '');
    s.finalPosition = j['finalPosition'];
    s.rewinds = j['rewinds'] ?? 0;
    s.interruptions = j['interruptions'] ?? 0;
    s.samples.addAll(
      (j['samples'] as List? ?? []).map(
        (v) => Sample.fromJson(Map<String, dynamic>.from(v)),
      ),
    );
    return s;
  }
}
