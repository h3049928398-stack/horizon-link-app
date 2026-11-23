import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/services/app_version_check.dart';
import 'package:horizon_link/widgets/version_check_tile.dart';

void main() {
  const base = 'https://example.org/weekly/weekly.json';
  test(
    'uses platform version and compares numeric release and build parts',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      Future<String> fetch(Uri uri) async {
        expect(uri.toString(), 'https://example.org/weekly/app-version.json');
        return jsonEncode({'android': '1.0.0+1', 'ios': '0.10.0+10'});
      }

      Future<String?> check(String version) =>
          checkAppVersion(version, weeklyUrl: base, fetch: fetch);
      expect(await check('0.9.9+99'), '0.10.0+10');
      expect(await check('0.10.0+9'), '0.10.0+10');
      expect(await check('0.10.0+10'), isNull);
      expect(await check('0.11.0+1'), isNull);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      expect(await check('0.10.0+10'), '1.0.0+1');
    },
  );

  test('missing or malformed version data cannot report up to date', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    for (final body in ['{}', '{"android":"latest"}', '<html>']) {
      await expectLater(
        checkAppVersion('0.2.0+2', weeklyUrl: base, fetch: (_) async => body),
        throwsFormatException,
      );
    }
  });

  testWidgets('tap checks inline, coalesces taps and supports retry', (
    tester,
  ) async {
    var request = Completer<String?>();
    var calls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VersionCheckTile(
            installedVersion: () async => '0.2.0+2',
            check: (_) {
              calls++;
              return request.future;
            },
          ),
        ),
      ),
    );
    await tester.pump();
    expect(calls, 0);
    await tester.tap(find.text('Horizon Link'));
    await tester.tap(find.text('Horizon Link'));
    await tester.pump();
    expect(calls, 1);
    expect(find.textContaining('正在检查更新'), findsOneWidget);
    request.completeError(const FormatException());
    await tester.pumpAndSettle();
    expect(find.textContaining('点击重试'), findsOneWidget);
    request = Completer<String?>();
    await tester.tap(find.text('Horizon Link'));
    request.complete('0.3.0+3');
    await tester.pumpAndSettle();
    expect(find.textContaining('发现新版本 0.3.0+3'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    request = Completer<String?>();
    await tester.tap(find.text('Horizon Link'));
    request.complete(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('已是最新版本'), findsOneWidget);
  });
}
