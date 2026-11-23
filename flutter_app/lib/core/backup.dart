import 'dart:convert';

import 'custom_dashboard.dart';
import 'rev_limiter.dart';

/// Validate the entire file before touching live settings or persistent data.
/// Old version 2 records without yaw remain supported.
Map<String, dynamic> parseUserBackup(String text) {
  if (utf8.encode(text).length > 64 * 1024 * 1024) {
    throw const FormatException('Backup exceeds 64 MiB');
  }
  final value = jsonDecode(text);
  if (value is! Map<String, dynamic> ||
      value['version'] != 2 ||
      value['settings'] is! Map<String, dynamic> ||
      value['sessions'] is! List) {
    throw const FormatException(
      'Expected a version 2 settings and recordings backup',
    );
  }
  final settings = value['settings'] as Map<String, dynamic>;
  validateCustomSettings(settings);
  readLimiterCalibrations(settings['limiterCalibrations']);
  for (final key in [
    'autoSwitch',
    'autoRecord',
    'effects',
    'miniNav',
    'expandedNav',
    'tires',
    'inputs',
    'mph',
    'darkMode',
  ]) {
    if (settings.containsKey(key) && settings[key] is! bool) {
      throw FormatException('Invalid $key');
    }
  }
  for (final key in ['language', 'raceStyle', 'appearance', 'guideUrl']) {
    if (settings.containsKey(key) && settings[key] is! String) {
      throw FormatException('Invalid $key');
    }
  }
  final port = settings['port'] ?? 8000;
  if (port is! int ||
      port < 1024 ||
      port > 65535 ||
      (port >= 5200 && port <= 5300)) {
    throw const FormatException('Invalid UDP port');
  }
  final rpm = settings['shiftRpm'] ?? 7500;
  if (rpm is! int || rpm <= 0 || rpm > 60000) {
    throw const FormatException('Invalid shift RPM');
  }
  final sessions = value['sessions'] as List;
  if (sessions.length > 8) {
    throw const FormatException('More than eight recordings');
  }
  final ids = <String>{};
  void date(dynamic v) {
    if (v is! String || DateTime.tryParse(v) == null) {
      throw const FormatException('Invalid timestamp');
    }
  }

  for (final session in sessions) {
    if (session is! Map<String, dynamic> ||
        session['id'] is! String ||
        (session['id'] as String).isEmpty ||
        !ids.add(session['id']) ||
        session['source'] is! String ||
        session['samples'] is! List) {
      throw const FormatException('Invalid recording');
    }
    date(session['started']);
    if (session['ended'] != null) date(session['ended']);
    for (final key in ['rewinds', 'interruptions', 'finalPosition']) {
      final n = session[key];
      if (n != null && (n is! int || n < 0)) {
        throw FormatException('Invalid $key');
      }
    }
    final samples = session['samples'] as List;
    if (samples.length > 12000) throw const FormatException('Too many samples');
    for (final sample in samples) {
      if (sample is! Map ||
          sample['frame'] is! Map<String, dynamic> ||
          (sample['segment'] != null &&
              (sample['segment'] is! int || sample['segment'] < 0)) ||
          (sample['superseded'] != null && sample['superseded'] is! bool)) {
        throw const FormatException('Invalid sample');
      }
      final frame = sample['frame'] as Map<String, dynamic>;
      date(frame['receivedAt']);
      if (frame['driving'] != null && frame['driving'] is! bool) {
        throw const FormatException('Invalid driving flag');
      }
      final tires = frame['tires'];
      if (tires is! List ||
          tires.length != 4 ||
          tires.any((v) => v is! num || !v.isFinite)) {
        throw const FormatException('Invalid tires');
      }
      for (final key in [
        'timestamp',
        'gear',
        'lap',
        'position',
        'carId',
        'pi',
        'speed',
        'rpm',
        'maxRpm',
        'power',
        'torque',
        'boost',
        'fuel',
        'throttle',
        'brake',
        'steer',
        'raceTime',
        'currentLap',
        'bestLap',
        'lastLap',
        'x',
        'y',
        'z',
        'yaw',
      ]) {
        final n = frame[key];
        if (n != null && (n is! num || !n.isFinite)) {
          throw FormatException('Invalid $key');
        }
      }
    }
  }
  return value;
}
