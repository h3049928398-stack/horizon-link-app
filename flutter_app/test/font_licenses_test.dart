import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/services/bundled_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    registerBundledLicenses();
    registerBundledLicenses();
    for (final font in [
      ('Chinese', 'chinese'),
      ('GainLabel', 'gain_label'),
      ('Dashboard', 'dashboard'),
    ]) {
      await (FontLoader(
        font.$1,
      )..addFont(rootBundle.load('assets/${font.$2}.ttf'))).load();
    }
  });

  setUpAll(() async {
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
  });

  test('both embedded font notices ship complete and register once', () async {
    final entries = await LicenseRegistry.licenses.toList();
    for (final name in ['Noto Sans SC', 'Barlow Condensed']) {
      final fonts = entries.where((e) => e.packages.contains(name)).toList();
      expect(fonts, hasLength(1));
      final text = fonts.single.paragraphs.map((p) => p.text).join('\n');
      expect(text, contains('SIL OPEN FONT LICENSE Version 1.1'));
      expect(text, contains('Copyright'));
      expect(text, contains('TERMINATION'));
      expect(text, contains('DISCLAIMER'));
    }
  });

  test(
    'adapted limiter detector retains full MIT notice and registers once',
    () async {
      final entries = (await LicenseRegistry.licenses.toList())
          .where((entry) => entry.packages.contains('forza-wheel-leds'))
          .toList();
      expect(entries, hasLength(1));
      final text = entries.single.paragraphs.map((p) => p.text).join('\n');
      expect(
        text,
        contains('Copyright (c) 2026 forza-wheel-leds contributors'),
      );
      expect(text, contains('Permission is hereby granted, free of charge'));
      expect(text, contains('THE SOFTWARE IS PROVIDED "AS IS"'));
      expect(text, contains('https://github.com/23sigma/forza-wheel-leds'));
    },
  );

  test(
    'vendored MIT notice preserves upstream copyright and permission',
    () async {
      final bundled = await rootBundle.loadString(
        'assets/licenses/fh6-scenic-navigator-MIT.txt',
      );
      final upstream = File('../scripts/vendor/fh6_nav/LICENSE')
          .readAsStringSync();
      expect(
        bundled.replaceAll('\r\n', '\n'),
        upstream.replaceAll('\r\n', '\n'),
      );
      final entries = (await LicenseRegistry.licenses.toList())
          .where((entry) => entry.packages.contains('FH6 Scenic Navigator'))
          .toList();
      expect(entries, hasLength(1));
      final text = entries.single.paragraphs.map((p) => p.text).join('\n');
      expect(
        text,
        contains('https://github.com/atikhobaev/fh6-scenic-navigator'),
      );
      expect(text, contains('Copyright (c) 2026 atikhobaev'));
      expect(text, contains('Permission is hereby granted, free of charge'));
      expect(text, contains('THE SOFTWARE IS PROVIDED'));
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets('real fonts and license reader work at 320px in $language', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(persist: false, tick: false);
      app.updateSettings((s) => s.language = language);
      addTearDown(app.dispose);
      const capture = ValueKey('font-license-capture');
      await tester.pumpWidget(
        RepaintBoundary(
          key: capture,
          child: HorizonApp(controller: app),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      if (Platform.environment['RENDER_FONTS'] == '1') {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File('../artifacts/font-home-$language.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.tap(find.text(language == 'zh' ? '设置' : 'Settings'));
      await tester.pumpAndSettle();
      final entry = find.byKey(const ValueKey('open-source-licenses'));
      await tester.scrollUntilVisible(entry, 200);
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      expect(
        find.text(language == 'zh' ? '开源许可' : 'Open-source licenses'),
        findsOneWidget,
      );
      await tester.tap(entry);
      await tester.pump(const Duration(milliseconds: 300));
      for (
        var attempt = 0;
        attempt < 50 && find.text('Noto Sans SC').evaluate().isEmpty;
        attempt++
      ) {
        // Alternate real isolate/asset work with the widget test's fake clock.
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 40));
        });
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(find.text('Noto Sans SC'), findsOneWidget);
      await tester.tap(find.text('Noto Sans SC'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('SIL OPEN FONT LICENSE Version 1.1'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('FH6 Scenic Navigator'), -160);
      await tester.tap(find.text('FH6 Scenic Navigator'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Copyright (c) 2026 atikhobaev'),
        findsWidgets,
      );
      expect(tester.takeException(), isNull);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(entry, findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
}
