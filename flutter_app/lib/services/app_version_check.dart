import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'weekly_platform.dart' as platform;

/// Returns the newer version for this phone, or null if it is up to date.
Future<String?> checkAppVersion(
  String installed, {
  String weeklyUrl = const String.fromEnvironment('WEEKLY_CONTENT_URL'),
  Future<String> Function(Uri) fetch = platform.fetchWeekly,
}) async {
  final current = _versionParts(installed);
  final base = Uri.parse(weeklyUrl);
  if (base.scheme != 'https' || base.host.isEmpty || base.userInfo.isNotEmpty) {
    throw const FormatException('Invalid content URL');
  }
  final target = switch (defaultTargetPlatform) {
    TargetPlatform.android => 'android',
    TargetPlatform.iOS => 'ios',
    _ => throw UnsupportedError('Mobile builds only'),
  };
  final json = jsonDecode(await fetch(base.resolve('app-version.json')));
  if (json is! Map || json[target] is! String) {
    throw const FormatException('Missing platform version');
  }
  final latest = json[target] as String;
  final remote = _versionParts(latest);
  for (var i = 0; i < current.length; i++) {
    if (remote[i] != current[i]) return remote[i] > current[i] ? latest : null;
  }
  return null;
}

List<int> _versionParts(String value) {
  if (!RegExp(r'^\d+\.\d+\.\d+\+\d+$').hasMatch(value)) {
    throw const FormatException('Expected major.minor.patch+build');
  }
  return value.split(RegExp(r'[.+]')).map(int.parse).toList();
}
