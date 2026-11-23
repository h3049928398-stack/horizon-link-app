import 'dart:typed_data';

import 'protocol.dart';

class TelemetryFrame {
  final int timestamp, gear, lap, position, carId, pi;
  // EngineMaxRpm is the tachometer scale maximum, not a shift target or limiter.
  final double speed, rpm, maxRpm, power, torque, boost, fuel;
  final double throttle, brake, steer, raceTime, currentLap, bestLap, lastLap;
  final double x, y, z;

  /// World-space body yaw in radians. Null for older recordings without yaw.
  final double? yaw;
  final List<double> tires;
  final bool driving;
  final DateTime receivedAt;
  TelemetryFrame({
    this.timestamp = 0,
    this.gear = 0,
    this.lap = 0,
    this.position = 0,
    this.carId = 0,
    this.pi = 0,
    this.speed = 0,
    this.rpm = 0,
    this.maxRpm = 8500,
    this.power = 0,
    this.torque = 0,
    this.boost = 0,
    this.fuel = 0,
    this.throttle = 0,
    this.brake = 0,
    this.steer = 0,
    this.raceTime = 0,
    this.currentLap = 0,
    this.bestLap = 0,
    this.lastLap = 0,
    this.x = 0,
    this.y = 0,
    this.z = 0,
    this.yaw,
    this.tires = const [0, 0, 0, 0],
    this.driving = false,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();
  Map<String, dynamic> toJson() => {
    'timestamp': timestamp,
    'gear': gear,
    'lap': lap,
    'position': position,
    'carId': carId,
    'pi': pi,
    'speed': speed,
    'rpm': rpm,
    'maxRpm': maxRpm,
    'power': power,
    'torque': torque,
    'boost': boost,
    'fuel': fuel,
    'throttle': throttle,
    'brake': brake,
    'steer': steer,
    'raceTime': raceTime,
    'currentLap': currentLap,
    'bestLap': bestLap,
    'lastLap': lastLap,
    'x': x,
    'y': y,
    'z': z,
    if (yaw != null) 'yaw': yaw,
    'tires': tires,
    'driving': driving,
    'receivedAt': receivedAt.toIso8601String(),
  };
  factory TelemetryFrame.fromJson(Map<String, dynamic> j) {
    double n(String k, [double d = 0]) => (j[k] as num?)?.toDouble() ?? d;
    return TelemetryFrame(
      timestamp: n('timestamp').toInt(),
      gear: n('gear').toInt(),
      lap: n('lap').toInt(),
      position: n('position').toInt(),
      carId: n('carId').toInt(),
      pi: n('pi').toInt(),
      speed: n('speed'),
      rpm: n('rpm'),
      maxRpm: n('maxRpm', 8500),
      power: n('power'),
      torque: n('torque'),
      boost: n('boost'),
      fuel: n('fuel'),
      throttle: n('throttle'),
      brake: n('brake'),
      steer: n('steer'),
      raceTime: n('raceTime'),
      currentLap: n('currentLap'),
      bestLap: n('bestLap'),
      lastLap: n('lastLap'),
      x: n('x'),
      y: n('y'),
      z: n('z'),
      yaw: (j['yaw'] as num?)?.isFinite == true ? n('yaw') : null,
      tires:
          (j['tires'] as List?)?.map((v) => (v as num).toDouble()).toList() ??
          const [0, 0, 0, 0],
      driving: j['driving'] == true,
      receivedAt: DateTime.tryParse(j['receivedAt'] ?? ''),
    );
  }
}

/// Experimental layout from the supplied document: 323 described field bytes,
/// despite a declared datagram size of 324. Validate real offsets before release.
TelemetryFrame decodePacket(Uint8List bytes, {DateTime? receivedAt}) {
  if (bytes.length != 324) throw const FormatException('当前实验协议要求 324 字节');
  final view = ByteData.sublistView(bytes), raw = <String, num>{};
  int offset = 0;
  for (final field in protocolFields) {
    final type = field.$2;
    final num value = switch (type) {
      'F32' => view.getFloat32(offset, Endian.little),
      'S32' => view.getInt32(offset, Endian.little),
      'U32' => view.getUint32(offset, Endian.little),
      'U16' => view.getUint16(offset, Endian.little),
      'S8' => view.getInt8(offset),
      _ => view.getUint8(offset),
    };
    if (!value.isFinite) throw FormatException('字段 ${field.$1} 无效');
    raw[field.$1] = value;
    offset += int.parse(type.substring(1)) ~/ 8;
  }
  double n(String k) => raw[k]!.toDouble();
  if (![0, 1].contains(raw['IsRaceOn']) ||
      n('Speed') < 0 ||
      n('Speed') > 300 ||
      n('CurrentEngineRpm') < 0 ||
      n('CurrentEngineRpm') > 60000 ||
      n('Gear') > 20) {
    throw const FormatException('字段超出合理范围，请核对协议');
  }
  return TelemetryFrame(
    timestamp: raw['TimestampMS']!.toInt(),
    gear: raw['Gear']!.toInt(),
    lap: raw['LapNumber']!.toInt(),
    position: raw['RacePosition']!.toInt(),
    carId: raw['CarOrdinal']!.toInt(),
    pi: raw['CarPerformanceIndex']!.toInt(),
    speed: n('Speed'),
    rpm: n('CurrentEngineRpm'),
    maxRpm: n('EngineMaxRpm'),
    power: n('Power') / 1000,
    torque: n('Torque'),
    boost: n('Boost'),
    fuel: n('Fuel'),
    throttle: n('Accel') / 255,
    brake: n('Brake') / 255,
    steer: n('Steer') / 127,
    raceTime: n('CurrentRaceTime'),
    currentLap: n('CurrentLap'),
    bestLap: n('BestLap'),
    lastLap: n('LastLap'),
    x: n('PositionX'),
    y: n('PositionY'),
    z: n('PositionZ'),
    yaw: n('Yaw'),
    tires: [
      n('TireTempFrontLeft'),
      n('TireTempFrontRight'),
      n('TireTempRearLeft'),
      n('TireTempRearRight'),
    ],
    driving: raw['IsRaceOn'] == 1,
    receivedAt: receivedAt,
  );
}

bool freshTimestamp(int previous, int next) {
  final delta = (next - previous) & 0xffffffff;
  return delta > 0 && delta < 0x80000000;
}

String lapTime(double value) {
  if (value <= 0 || !value.isFinite) return '--:--.---';
  final ms = (value * 1000).round();
  return '${ms ~/ 60000}:${((ms ~/ 1000) % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
}
