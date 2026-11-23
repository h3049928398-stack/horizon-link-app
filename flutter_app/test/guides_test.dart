import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/main.dart';

void main() {
  test('fixed guide replaces legacy URLs without resetting other settings', () {
    const expected =
        'https://api.xiaoheihe.cn/v3/bbs/app/api/web/share?h_camp=link&h_session_id=4OBWU20qN1doG17z&h_src=YXBwX3NoYXJl&link_id=300372ba1810&new_post_share_style_v2=1';
    expect(AppSettings().guideUrl, expected);
    for (final oldUrl in [
      null,
      'https://forza.net/news',
      'https://example.com',
    ]) {
      final restored = AppSettings.fromJson({
        'guideUrl': oldUrl,
        'port': 8123,
        'language': 'en',
        'appearance': 'light',
      });
      expect(restored.guideUrl, expected);
      final saved = AppSettings.fromJson(
        jsonDecode(jsonEncode(restored.toJson())),
      );
      expect(saved.guideUrl, expected);
      expect(saved.port, 8123);
      expect(saved.language, 'en');
      expect(saved.appearance, AppAppearance.light);
    }
  });

  for (final language in ['zh', 'en']) {
    testWidgets('$language guide source is read-only on a narrow phone', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      app.updateSettings((s) => s.language = language);
      await tester.pumpWidget(HorizonApp(controller: app));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      final address = find.text(app.settings.guideUrl);
      await tester.scrollUntilVisible(address, 150);
      await tester.pumpAndSettle();
      expect(address, findsOneWidget);
      final tile = tester.widget<ListTile>(
        find.ancestor(of: address, matching: find.byType(ListTile)),
      );
      expect(tile.onTap, isNull);
      expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
      await tester.ensureVisible(address);
      await tester.pumpAndSettle();
      await tester.tap(address);
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      await tester.scrollUntilVisible(
        find.text(language == 'zh' ? '打开攻略网页' : 'Open guide website'),
        -150,
      );
      await tester.pumpAndSettle();
      expect(
        find.text(language == 'zh' ? '打开攻略网页' : 'Open guide website'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language My Forza photo entry opens the exact URL in a browser',
      (tester) async {
        tester.view.physicalSize = const Size(320, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        var launchSucceeded = true;
        final calls = <MethodCall>[];
        const channel = MethodChannel('plugins.flutter.io/url_launcher');
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          (call) async {
            calls.add(call);
            return launchSucceeded;
          },
        );
        addTearDown(
          () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            channel,
            null,
          ),
        );
        final app = AppController(persist: false, tick: false);
        addTearDown(app.dispose);
        app.updateSettings((s) => s.language = language);
        final guideUrl = app.settings.guideUrl;
        await tester.pumpWidget(HorizonApp(controller: app));
        await tester.pumpAndSettle();
        await tester.tap(find.byType(NavigationDestination).at(2));
        await tester.pumpAndSettle();
        final entry = find.byKey(const ValueKey('my-forza-photos'));
        await tester.scrollUntilVisible(entry, 150);
        await tester.ensureVisible(entry);
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'zh' ? 'My Forza 摄影作品' : 'My Forza photos'),
          findsOneWidget,
        );
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(calls.single.method, 'launch');
        expect(calls.single.arguments['url'], 'https://forza.net/myforza');
        expect(calls.single.arguments['useWebView'], false);
        expect(calls.single.arguments['useSafariVC'], false);
        expect(app.settings.guideUrl, guideUrl);
        launchSucceeded = false;
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(
          find.text(language == 'zh' ? '网页暂时无法打开' : 'Could not load this page'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
