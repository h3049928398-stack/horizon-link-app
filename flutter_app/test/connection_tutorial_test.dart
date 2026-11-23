import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/pages/settings_page.dart';
import 'package:horizon_link/widgets/app_theme.dart';
import 'package:horizon_link/widgets/connection_tutorial.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'packaged screenshots contain opaque IP redactions and no metadata',
    () async {
      for (final path in connectionTutorialImages) {
        final data = await rootBundle.load(path);
        var offset = 8;
        while (offset < data.lengthInBytes) {
          final length = data.getUint32(offset);
          final type = String.fromCharCodes(
            List.generate(4, (i) => data.getUint8(offset + 4 + i)),
          );
          expect(['IHDR', 'IDAT', 'IEND'], contains(type));
          offset += length + 12;
        }
        if (path.endsWith('port.png')) continue;
        final codec = await ui.instantiateImageCodec(data.buffer.asUint8List());
        final image = (await codec.getNextFrame()).image;
        try {
          final pixels = (await image.toByteData(
            format: ui.ImageByteFormat.rawRgba,
          ))!;
          final region = path.endsWith('data-out.png')
              ? const Rect.fromLTRB(1045, 720, 1170, 744)
              : const Rect.fromLTRB(720, 522, 950, 548);
          for (var y = region.top.toInt(); y < region.bottom; y++) {
            for (var x = region.left.toInt(); x < region.right; x++) {
              final p = (y * image.width + x) * 4;
              expect(pixels.getUint8(p), lessThan(12));
              expect(pixels.getUint8(p + 1), lessThan(12));
              expect(pixels.getUint8(p + 2), lessThan(12));
              expect(pixels.getUint8(p + 3), 255);
            }
          }
        } finally {
          image.dispose();
          codec.dispose();
        }
      }
    },
  );

  for (final language in ['zh', 'en']) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'connection tutorial images, zoom and footer ($language $brightness)',
        (tester) async {
          tester.view.physicalSize = const Size(320, 700);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          addTearDown(tester.view.resetViewInsets);
          final app = AppController(persist: false, tick: false);
          addTearDown(app.dispose);
          await tester.pumpWidget(
            MaterialApp(
              theme: buildTheme(brightness: brightness),
              locale: Locale(language),
              supportedLocales: const [Locale('zh'), Locale('en')],
              localizationsDelegates: const [
                AppCopy.delegate,
                ...GlobalMaterialLocalizations.delegates,
              ],
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () => showConnection(context, app),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          );
          await tester.tap(find.text('Open'));
          await tester.pumpAndSettle();
          for (var index = 0; index < 3; index++) {
            final imageFinder = find.byKey(
              const ValueKey('connection-tutorial-image'),
            );
            await tester.ensureVisible(imageFinder);
            await tester.pumpAndSettle();
            expect(
              tester
                  .widget<Image>(
                    find.descendant(
                      of: imageFinder,
                      matching: find.byType(Image),
                    ),
                  )
                  .image,
              AssetImage(connectionTutorialImages[index]),
            );
            await tester.tap(imageFinder);
            await tester.pumpAndSettle();
            expect(
              find.byKey(const ValueKey('connection-tutorial-viewer')),
              findsOneWidget,
            );
            await tester.tap(find.byType(BackButton));
            await tester.pumpAndSettle();
            if (index < 2) {
              final next = find.byKey(
                const ValueKey('connection-tutorial-next'),
              );
              await tester.ensureVisible(next);
              await tester.tap(next);
              await tester.pumpAndSettle();
            }
          }
          await tester.ensureVisible(find.byType(TextField));
          await tester.enterText(find.byType(TextField), '8001');
          app.updateSettings((s) => s.mph = true);
          await tester.pump();
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            '8001',
          );
          for (final size in [const Size(640, 360), const Size(320, 700)]) {
            tester.view.physicalSize = size;
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          tester.view.viewInsets = const FakeViewPadding(bottom: 260);
          await tester.pumpAndSettle();
          final close = find.text(language == 'zh' ? '关闭' : 'Close');
          expect(tester.getRect(close).bottom, lessThan(440));
          await tester.tap(close);
          await tester.pumpAndSettle();
          expect(find.byType(ConnectionTutorial), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
