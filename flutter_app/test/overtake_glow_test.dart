import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/widgets/overtake_glow.dart';

void main() {
  testWidgets(
    'glow paints bright edges while the instrument area stays clear',
    (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      for (final size in [const Size(844, 390), const Size(390, 844)]) {
        tester.view.physicalSize = size;
        final key = GlobalKey();
        await tester.pumpWidget(
          TickerMode(
            enabled: false,
            child: RepaintBoundary(
              key: key,
              child: const OvertakeGlow(active: true),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final pixels = await tester.runAsync(() async {
          final image = await boundary.toImage();
          try {
            return (await image.toByteData(
              format: ui.ImageByteFormat.rawRgba,
            ))!;
          } finally {
            image.dispose();
          }
        });
        final width = size.width.toInt();
        final height = size.height.toInt();
        int alpha(int x, int y) => pixels!.getUint8((y * width + x) * 4 + 3);
        // Catch the original full-screen yellow fill, throughout the central area.
        for (var y = 40; y < height - 40; y++) {
          for (var x = 40; x < width - 40; x++) {
            expect(alpha(x, y), 0);
          }
        }
        for (final point in [
          Offset(width / 2, 0),
          Offset(width / 2, height - 1),
          Offset(0, height / 2),
          Offset(width - 1, height / 2),
        ]) {
          expect(
            alpha(point.dx.toInt(), point.dy.toInt()),
            inInclusiveRange(220, 245),
          );
        }
        expect(alpha(width ~/ 2, 1), greaterThan(alpha(width ~/ 2, 15)));
      }
    },
  );

  testWidgets('glow fades out and never blocks dashboard controls', (
    tester,
  ) async {
    var active = false;
    var taps = 0;
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Stack(
              children: [
                Center(
                  child: TextButton(
                    onPressed: () => taps++,
                    child: const Text('Control'),
                  ),
                ),
                Positioned.fill(child: OvertakeGlow(active: active)),
              ],
            );
          },
        ),
      ),
    );
    update(() => active = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(OvertakeGlow),
        matching: find.byType(FadeTransition),
      ).first,
    );
    expect(fade.opacity.value, inExclusiveRange(0, 1));
    await tester.pump(const Duration(milliseconds: 240));
    await tester.tap(find.text('Control'));
    expect(taps, 1);
    update(() => active = false);
    await tester.pumpAndSettle();
    expect(fade.opacity.value, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active glow repeatedly pulses with strong brightness contrast', (
    tester,
  ) async {
    await tester.pumpWidget(const OvertakeGlow(active: true));
    final pulse = tester
        .widget<FadeTransition>(find.byKey(const ValueKey('overtake-pulse')))
        .opacity;
    expect(pulse.value, closeTo(1, .01));
    await tester.pump(const Duration(milliseconds: 250));
    expect(pulse.value, closeTo(.18, .01));
    await tester.pump(const Duration(milliseconds: 250));
    expect(pulse.value, closeTo(1, .01));
    await tester.pump(const Duration(milliseconds: 250));
    expect(pulse.value, closeTo(.18, .01));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
