import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/pages/settings_page.dart';

void main() {
  for (final dismissal in ['back', 'barrier', 'close']) {
    testWidgets('connection sheet survives $dismissal after editing the port', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showConnection(context, app),
                child: const Text('Open connection'),
              ),
            ),
          ),
        ),
      );
      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.tap(find.text('Open connection'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), '8001');
        await tester.pump();
        switch (dismissal) {
          case 'back':
            // Pop the sheet while its text field still has focus.
            await tester.binding.handlePopRoute();
          case 'barrier':
            await tester.tapAt(const Offset(8, 80));
          case 'close':
            await tester.tap(find.text('关闭'));
        }
        await tester.pump();
        // Telemetry can still rebuild the sheet during its exit animation.
        app.updateSettings((s) => s.mph = !s.mph);
        await tester.pump(const Duration(milliseconds: 50));
        expect(tester.takeException(), isNull);
        await tester.pumpAndSettle();
        expect(find.text('连接游戏'), findsNothing);
        expect(tester.takeException(), isNull);
      }
    });
  }
}
