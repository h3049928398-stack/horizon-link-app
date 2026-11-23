import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/l10n.dart';
import 'package:horizon_link/main.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';
import 'package:horizon_link/widgets/overtake_glow.dart';

const newStyles = [
  DashboardStyle.gt,
  DashboardStyle.endurance,
  DashboardStyle.rally,
];

void main() {
  test('race layout migrates safely and survives settings JSON', () {
    for (final value in [null, 'basic', 'unknown', 42]) {
      expect(
        AppSettings.fromJson({'raceStyle': value}).raceStyle,
        DashboardStyle.professional,
      );
    }
    for (final style in DashboardStyle.values.where((s) => s.isProfessional)) {
      final settings = AppSettings()..raceStyle = style;
      expect(
        AppSettings.fromJson(jsonDecode(jsonEncode(settings.toJson())))
            .raceStyle,
        style,
      );
    }
  });

  test('automatic race transition uses preferred layout and basic keeps preference', () {
    for (final style in newStyles) {
      final app = AppController(persist: false, tick: false);
      addTearDown(app.dispose);
      app.settings.raceDashboard = DashboardRef.builtin(style.name);
      app.chooseStyle(style);
      app.chooseStyle(DashboardStyle.basic);
      expect(app.settings.raceStyle, style);
      final epoch = DateTime(2026);
      void frame(int ms, {int position = 3}) => app.ingest(
        TelemetryFrame(
          timestamp: ms + 1,
          receivedAt: epoch.add(Duration(milliseconds: ms)),
          driving: true,
          position: position,
          speed: 35,
          raceTime: position > 0 ? 10 + ms / 1000 : 0,
          currentLap: position > 0 ? 10 + ms / 1000 : 0,
        ),
      );
      frame(0);
      frame(700);
      expect(app.racing, isTrue);
      expect(app.style, style);
      frame(800, position: 0);
      frame(2700, position: 0);
      expect(app.racing, isFalse);
      expect(app.style, DashboardStyle.basic);
      expect(app.settings.raceStyle, style);
      app.settings.autoSwitch = false;
      app.chooseStyle(DashboardStyle.basic);
      frame(3000);
      frame(3800);
      expect(app.racing, isTrue);
      expect(app.style, DashboardStyle.basic);
    }
  });

  for (final language in ['zh', 'en']) {
    testWidgets(
      '$language layout menu fits phones and controls every pro layout',
      (tester) async {
        final semantics = tester.ensureSemantics();
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        final app = AppController(persist: false, tick: false);
        addTearDown(app.dispose);
        app.updateSettings((s) {
          s.language = language;
          s.mph = true;
        });
        app.frame = TelemetryFrame(speed: 50, gear: 0, rpm: 6000);
        await tester.pumpWidget(HorizonApp(controller: app));
        await tester.pumpAndSettle();
        for (final style in newStyles) {
          app.gain = false;
          tester.view.physicalSize = const Size(360, 800);
          await tester.pumpAndSettle();
          final tile = find.text(localize(style.title, language));
          await tester.scrollUntilVisible(
            tile,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          await tester.tap(tile);
          await tester.pumpAndSettle();
          expect(app.style, style);
          for (final size in [
            const Size(640, 360),
            const Size(844, 390),
            const Size(360, 800),
          ]) {
            tester.view.physicalSize = size;
            await tester.pump();
            await tester.tap(find.byKey(const ValueKey('race-layout-menu')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(ValueKey('race-layout-${style.name}')));
            await tester.pumpAndSettle();
            expect(app.style, style);
            expect(app.settings.raceStyle, DashboardStyle.professional);
            expect(tester.takeException(), isNull);
          }
          app.gain = true;
          app.notifyListeners();
          await tester.pump();
          expect(
            tester.widget<OvertakeGlow>(find.byType(OvertakeGlow)).active,
            isTrue,
          );
          final canvas = tester.widget<DashCanvas>(find.byType(DashCanvas));
          expect(canvas.style, style);
          expect(find.bySemanticsLabel(RegExp('.*(mph).*R.*')), findsWidgets);
          await tester.tap(find.byTooltip(localize('退出仪表', language)));
          await tester.pumpAndSettle();
          expect(find.byType(NavigationBar), findsOneWidget);
        }
        semantics.dispose();
      },
    );
  }

  for (final style in newStyles) {
    testWidgets(
      '${style.name} shares timed shift cue, stops in background and disposes',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: DashCanvas(
              frame: TelemetryFrame(rpm: 7600, maxRpm: 9000),
              shiftTargetRpm: 7500,
              settings: AppSettings(),
              style: style,
            ),
          ),
        );
        DashboardPainter painter() => tester
            .widgetList<CustomPaint>(find.byType(CustomPaint))
            .map((p) => p.painter)
            .whereType<DashboardPainter>()
            .single;
        await tester.pump(const Duration(milliseconds: 125));
        expect(painter().shiftFlashOn, false);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(painter().shiftFlashOn, true);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump(const Duration(milliseconds: 125));
        expect(painter().shiftFlashOn, false);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      },
    );
  }

  test(
    'new layouts render distinct designs and respond to component settings',
    () async {
      for (final font in [('Dashboard', 'dashboard'), ('Chinese', 'chinese')]) {
        final loader = FontLoader(font.$1)
          ..addFont(rootBundle.load('assets/${font.$2}.ttf'));
        await loader.load();
      }
      Future<List<int>> render(
        DashboardStyle style,
        AppSettings settings, {
        bool flash = true,
      }) async {
        final recorder = ui.PictureRecorder();
        DashboardPainter(
          TelemetryFrame(
            speed: 52.5,
            gear: 4,
            rpm: 7600,
            maxRpm: 7500,
            fuel: .78,
            position: 3,
            lap: 1,
            currentLap: 62.315,
            bestLap: 85.463,
            lastLap: 87.104,
            raceTime: 152.8,
            throttle: .72,
            brake: .16,
            power: 248,
            torque: 412,
            boost: 12.8,
            tires: [86, 87, 84, 85],
          ),
          settings,
          style,
          null,
          null,
          flash,
          null,
          7500,
        ).paint(Canvas(recorder), const Size(1280, 540));
        final picture = recorder.endRecording();
        final image = await picture.toImage(1280, 540);
        try {
          if (Platform.environment['RENDER_DASHBOARDS'] == '1' &&
              settings.tires &&
              flash) {
            final png = await image.toByteData(format: ui.ImageByteFormat.png);
            await File('../artifacts/layout-${style.name}.png')
                .writeAsBytes(png!.buffer.asUint8List());
          }
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!
              .buffer
              .asUint8List()
              .toList();
        } finally {
          image.dispose();
          picture.dispose();
        }
      }

      final designs = <List<int>>[];
      for (final style in newStyles) {
        final normal = await render(style, AppSettings());
        final hidden = await render(
          style,
          AppSettings()
            ..tires = false
            ..inputs = false,
        );
        final off = await render(style, AppSettings(), flash: false);
        expect(
          normal.sublist(412 * 1280 * 4),
          isNot(hidden.sublist(412 * 1280 * 4)),
        );
        expect(normal.sublist(40 * 1280 * 4), off.sublist(40 * 1280 * 4));
        expect(
          normal.sublist(0, 40 * 1280 * 4),
          isNot(off.sublist(0, 40 * 1280 * 4)),
        );
        for (final other in designs) {
          expect(normal, isNot(other));
        }
        designs.add(normal);
      }
    },
  );
}
