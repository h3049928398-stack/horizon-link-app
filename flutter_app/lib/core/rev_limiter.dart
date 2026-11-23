import 'telemetry.dart';

/// Adapted from 23sigma/forza-wheel-leds (MIT), with interruption and
/// same-gear guards. See assets/licenses/forza-wheel-leds-MIT.txt.
class LimiterCalibration {
  final double rpm, nominalMaxRpm;
  const LimiterCalibration(this.rpm, this.nominalMaxRpm);
  Map<String, dynamic> toJson() => {'rpm': rpm, 'nominalMaxRpm': nominalMaxRpm};
}

Map<String, LimiterCalibration> readLimiterCalibrations(Object? value) {
  if (value == null) return {};
  if (value is! Map || value.length > 2048) {
    throw const FormatException('Invalid limiter calibrations');
  }
  final result = <String, LimiterCalibration>{};
  for (final entry in value.entries) {
    final key = entry.key;
    final v = entry.value;
    if (key is! String ||
        !RegExp(r'^[1-9][0-9]{0,9}:(0|[1-9][0-9]{0,4})$').hasMatch(key) ||
        int.parse(key.split(':').first) > 2147483647 ||
        v is! Map ||
        v.length != 2 ||
        !v.containsKey('rpm') ||
        !v.containsKey('nominalMaxRpm')) {
      throw const FormatException('Invalid limiter calibration');
    }
    final rpm = v['rpm'], nominal = v['nominalMaxRpm'];
    if (rpm is! num ||
        nominal is! num ||
        !validRpm(rpm) ||
        !validRpm(nominal)) {
      throw const FormatException('Invalid limiter RPM');
    }
    result[key] = LimiterCalibration(rpm.toDouble(), nominal.toDouble());
  }
  return result;
}

bool validRpm(num value) => value.isFinite && value > 0 && value <= 60000;
String? limiterVehicleKey(TelemetryFrame f) =>
    f.carId > 0 && f.carId <= 2147483647 && f.pi >= 0 && f.pi <= 99999
    ? '${f.carId}:${f.pi}'
    : null;

class LimiterSnapshot {
  final bool available;
  final String? vehicleKey;
  final int bounces;
  final double? limiterRpm, shiftTargetRpm;
  const LimiterSnapshot({
    this.available = false,
    this.vehicleKey,
    this.bounces = 0,
    this.limiterRpm,
    this.shiftTargetRpm,
  });
}

class RevLimiterLearner {
  String? _key;
  TelemetryFrame? _previous;
  double _peak = 0;
  int _bounces = 0;
  bool _needsRecovery = false;

  void interrupt() {
    _previous = null;
    _peak = 0;
    _bounces = 0;
    _needsRecovery = false;
  }

  /// Returns whether the persistent calibration map changed.
  bool update(
    TelemetryFrame f,
    Map<String, LimiterCalibration> saved, {
    bool interrupted = false,
  }) {
    final key = limiterVehicleKey(f);
    if (key != _key) {
      interrupt();
      _key = key;
    }
    if (key == null || !validRpm(f.maxRpm)) {
      interrupt();
      return false;
    }
    var changed = false;
    final calibration = saved[key];
    if (calibration != null &&
        (calibration.nominalMaxRpm - f.maxRpm).abs() > 250) {
      saved.remove(key);
      interrupt();
      changed = true;
    }
    final previous = _previous;
    if (interrupted ||
        !f.driving ||
        !validRpm(f.rpm) ||
        !f.throttle.isFinite ||
        f.throttle < 250 / 255 ||
        f.throttle > 1 ||
        f.gear < 1 ||
        f.gear > 10) {
      interrupt();
      return changed;
    }
    if (previous != null &&
        (!freshTimestamp(previous.timestamp, f.timestamp) ||
            f.receivedAt.isBefore(previous.receivedAt))) {
      interrupt();
      return changed;
    }
    if (previous != null &&
        (previous.gear != f.gear ||
            f.receivedAt.difference(previous.receivedAt).inMilliseconds >
                1000)) {
      interrupt();
      // Start fresh in the new gear; never compare across the transition.
    }
    if (saved.containsKey(key)) return changed;
    if (f.rpm > _peak) {
      _peak = f.rpm;
      _bounces = 0;
      _needsRecovery = false;
    }
    final last = _previous;
    if (_needsRecovery) {
      if (last != null && f.rpm > last.rpm && f.rpm >= _peak * .98) {
        _needsRecovery = false;
      }
    } else if (last != null &&
        last.rpm > _peak * .98 &&
        last.rpm - f.rpm > 40) {
      _bounces++;
      _needsRecovery = true;
      if (_bounces >= 3) {
        // Bound the cache without evicting other cars implicitly.
        if (saved.length < 2048 || saved.containsKey(key)) {
          saved[key] = LimiterCalibration(_peak, f.maxRpm);
          changed = true;
        }
      }
    }
    _previous = f;
    return changed;
  }

  LimiterSnapshot snapshot(
    TelemetryFrame f,
    Map<String, LimiterCalibration> saved, {
    required bool available,
  }) {
    final key = limiterVehicleKey(f);
    final candidate = saved[key];
    final calibration =
        candidate != null &&
            validRpm(f.maxRpm) &&
            (candidate.nominalMaxRpm - f.maxRpm).abs() <= 250
        ? candidate
        : null;
    final active = available && key != null && validRpm(f.maxRpm);
    final target = active && calibration != null && f.gear >= 1 && f.gear <= 10
        ? calibration.rpm - (f.gear <= 3 ? 750 : 500)
        : null;
    return LimiterSnapshot(
      available: active,
      vehicleKey: key,
      bounces: key == _key ? _bounces : 0,
      limiterRpm: calibration?.rpm,
      shiftTargetRpm: target != null && target > 0 ? target : null,
    );
  }
}
