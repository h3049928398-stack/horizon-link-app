import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/pages/problem_feedback_page.dart';
import 'package:horizon_link/pages/settings_page.dart';
import 'package:horizon_link/services/problem_feedback.dart';
import 'package:horizon_link/services/problem_feedback_io.dart';
import 'package:horizon_link/services/release_info.dart';

class _LoopbackHttpOverrides extends HttpOverrides {}

void main() {
  test(
    'the POST sends only the allowed fields to the fixed HTTPS endpoint',
    () async {
      final report = FeedbackReport(
        message: '无法打开地图 🏁',
        platform: 'ios',
        installedVersion: '0.3.2+5',
      );
      final result = await sendProblemFeedback(
        report,
        post: (uri, raw) async {
          expect(
            uri.toString(),
            'https://ninaaa.cloud/api/horizon-link/feedback',
          );
          expect(report.requestId, matches(r'^[0-9a-f]{32}$'));
          expect(jsonDecode(raw), {
            'requestId': report.requestId,
            'message': '无法打开地图 🏁',
            'platform': 'ios',
            'appVersion': '0.3.2+5',
          });
          return (201, jsonEncode({'id': report.requestId}));
        },
      );
      expect(result, FeedbackResult.sent);
    },
  );

  test('native POST sends UTF-8 JSON and refuses redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    final seen = <(String, String, String?, String)>[];
    const payload = '{"message":"地图问题 🏁"}';
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      seen.add((
        request.method,
        request.uri.path,
        request.headers.contentType?.mimeType,
        body,
      ));
      final response = request.response;
      if (request.uri.path == '/redirect') {
        response.statusCode = HttpStatus.temporaryRedirect;
        response.headers.set(HttpHeaders.locationHeader, '/receipt');
      } else {
        response.statusCode = HttpStatus.created;
        response.headers.contentType = ContentType.json;
        response.write('{"id":"test-receipt"}');
      }
      await response.close();
    });
    Uri endpoint(String path) => Uri.http('127.0.0.1:${server.port}', path);
    await HttpOverrides.runWithHttpOverrides(() async {
      expect(await postFeedback(endpoint('/redirect'), payload), (307, ''));
      expect(await postFeedback(endpoint('/receipt'), payload), (
        201,
        '{"id":"test-receipt"}',
      ));
    }, _LoopbackHttpOverrides());
    expect(seen, [
      ('POST', '/redirect', 'application/json', payload),
      ('POST', '/receipt', 'application/json', payload),
    ]);
  });

  test(
    'a retry receipt must match, and invalid responses never count as sent',
    () async {
      final report = FeedbackReport(
        message: 'App issue',
        platform: 'android',
        installedVersion: '—',
      );
      expect(report.toJson(), isNot(contains('appVersion')));
      for (final (status, body, result) in [
        (200, jsonEncode({'id': report.requestId}), FeedbackResult.sent),
        (200, '{"id":"wrong"}', FeedbackResult.unavailable),
        (200, '<html></html>', FeedbackResult.unavailable),
        (302, '', FeedbackResult.unavailable),
        (404, '', FeedbackResult.unavailable),
        (429, '', FeedbackResult.rateLimited),
        (503, '', FeedbackResult.unavailable),
      ]) {
        expect(
          await sendProblemFeedback(
            report,
            post: (_, _) async => (status, body),
          ),
          result,
        );
      }
      expect(
        await sendProblemFeedback(
          report,
          post: (_, _) async => throw TimeoutException('timeout'),
        ),
        FeedbackResult.unavailable,
      );
    },
  );

  for (final (platform, english) in [
    (TargetPlatform.android, false),
    (TargetPlatform.iOS, true),
  ]) {
    testWidgets('settings opens feedback on ${platform.name}', (tester) async {
      final app = AppController(persist: false, tick: false)
        ..settings.language = english ? 'en' : 'zh';
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: SettingsPage(app: app)),
        ),
      );
      final row = find.byKey(const ValueKey('problem-feedback'));
      await tester.scrollUntilVisible(row, 230);
      await tester.tap(row);
      await tester.pumpAndSettle();
      final page = tester.widget<ProblemFeedbackPage>(
        find.byType(ProblemFeedbackPage),
      );
      expect(page.platform, platform.name.toLowerCase());
      expect(page.english, english);
      expect(find.text(english ? 'Send feedback' : '发送反馈'), findsOneWidget);
    }, variant: TargetPlatformVariant({platform}));
  }

  testWidgets('form retains a failed draft, deduplicates taps and retries', (
    tester,
  ) async {
    final requests = <FeedbackReport>[];
    final first = Completer<FeedbackResult>();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      ReleaseInfo.channel,
      (call) async => call.method == 'version' ? '0.3.2+5' : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ReleaseInfo.channel,
        null,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: ProblemFeedbackPage(
          english: false,
          platform: 'android',
          send: (report) async {
            requests.add(report);
            return switch (requests.length) {
              1 => first.future,
              2 => FeedbackResult.rateLimited,
              _ => FeedbackResult.sent,
            };
          },
        ),
      ),
    );
    final input = find.byType(TextFormField);
    final button = find.byType(FilledButton);
    await tester.tap(button);
    await tester.pump();
    expect(find.text('请输入问题描述。'), findsOneWidget);
    await tester.enterText(input, '🏁' * (feedbackMessageLimit + 1));
    await tester.tap(button);
    await tester.pump();
    expect(find.textContaining('$feedbackMessageLimit 字'), findsOneWidget);
    expect(requests, isEmpty);

    await tester.enterText(input, '  地图没有打开  ');
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(requests, hasLength(1));
    expect(requests.single.message, '地图没有打开');
    expect(requests.single.appVersion, '0.3.2+5');
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    first.complete(FeedbackResult.unavailable);
    await tester.pump();
    expect(find.textContaining('未能确认送达'), findsOneWidget);
    expect(find.text('  地图没有打开  '), findsOneWidget);

    await tester.tap(button);
    await tester.pump();
    expect(requests[1], same(requests[0]));
    expect(find.textContaining('发送过于频繁'), findsOneWidget);

    await tester.enterText(input, '地图没有打开，重启后仍有问题');
    await tester.tap(button);
    await tester.pump();
    expect(requests[2].requestId, isNot(requests[0].requestId));
    expect(find.text('反馈已送达开发者。'), findsOneWidget);
    expect(find.textContaining(requests[2].requestId), findsOneWidget);
    expect(input, findsNothing);
  });
}
