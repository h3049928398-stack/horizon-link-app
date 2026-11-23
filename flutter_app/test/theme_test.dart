import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/pages/settings_page.dart';
import 'package:horizon_link/widgets/app_theme.dart';

void main() {
  test(
    'old settings stay dark and light preference survives JSON round trip',
    () {
      expect(AppSettings.fromJson({}).appearance, AppAppearance.dark);
      expect(
        AppSettings.fromJson({'darkMode': false}).appearance,
        AppAppearance.light,
      );
      expect(
        AppSettings.fromJson({'appearance': 'unknown', 'darkMode': false})
            .appearance,
        AppAppearance.dark,
      );
      final settings = AppSettings()
        ..appearance = AppAppearance.light
        ..port = 8123
        ..language = 'en';
      final restored = AppSettings.fromJson(
        jsonDecode(jsonEncode(settings.toJson())),
      );
      expect(restored.appearance, AppAppearance.light);
      for (final mode in AppAppearance.values) {
        restored.appearance = mode;
        expect(
          AppSettings.fromJson(jsonDecode(jsonEncode(restored.toJson())))
              .appearance,
          mode,
        );
      }
      expect(restored.port, 8123);
      expect(restored.language, 'en');
    },
  );

  testWidgets(
    'default stays dark; system follows live brightness changes and explicit modes override it',
    (tester) async {
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      await tester.pumpWidget(HorizonApp(controller: app));
      await tester.pumpAndSettle();
      Brightness brightness() =>
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness;
      expect(brightness(), Brightness.dark);
      app.updateSettings((s) => s.appearance = AppAppearance.system);
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
      app.updateSettings((s) => s.appearance = AppAppearance.light);
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      app.updateSettings((s) => s.appearance = AppAppearance.dark);
      await tester.pumpAndSettle();
      expect(brightness(), Brightness.dark);
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language toggles theme across cached tabs and connection sheet',
      (tester) async {
        tester.view.physicalSize = const Size(360, 800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = AppController(persist: false, tick: false);
        addTearDown(app.dispose);
        app.updateSettings((s) => s.language = language);
        await tester.pumpWidget(HorizonApp(controller: app));
        await tester.pumpAndSettle();
        Future<void> tab(int index) async {
          await tester.tap(find.byType(NavigationDestination).at(index));
          await tester.pumpAndSettle();
        }

        await tab(3);
        final selector = find.byKey(const ValueKey('appearance-selector'));
        Future<void> select(String label) async {
          await tester.ensureVisible(selector);
          await tester.tap(selector);
          await tester.pumpAndSettle();
          await tester.tap(find.text(label).last);
          await tester.pumpAndSettle();
        }

        await select(language == 'en' ? 'Light' : '浅色');
        expect(app.settings.appearance, AppAppearance.light);
        expect(find.text(language == 'en' ? 'Theme' : '主题'), findsOneWidget);
        for (var i = 0; i < 4; i++) {
          await tab(i);
          final context = tester.element(find.byType(Scaffold).first);
          expect(Theme.of(context).brightness, Brightness.light);
          expect(context.appSurface.computeLuminance(), greaterThan(.9));
          final mutedContrast =
              (context.appSurface.computeLuminance() + .05) /
              (context.appMuted.computeLuminance() + .05);
          expect(mutedContrast, greaterThan(4.5));
          expect(tester.takeException(), isNull);
        }
        final context = tester.element(find.byType(Scaffold).first);
        showConnection(context, app);
        await tester.pumpAndSettle();
        expect(
          Theme.of(tester.element(find.byType(TextField))).brightness,
          Brightness.light,
        );
        Navigator.of(tester.element(find.byType(TextField))).pop();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await select(language == 'en' ? 'Dark' : '深色');
        expect(app.settings.appearance, AppAppearance.dark);
        await select(language == 'en' ? 'System' : '跟随系统');
        expect(app.settings.appearance, AppAppearance.system);
        await select(language == 'en' ? 'Dark' : '深色');
        expect(
          Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
          Brightness.dark,
        );
      },
    );
  }
}
