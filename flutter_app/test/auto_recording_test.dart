import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/main.dart';

final _epoch = DateTime(2026, 11, 1);
void _frame(
  AppController app,
  int ms, {
  bool race = true,
  bool paused = false,
}) => app.ingest(
  TelemetryFrame(
    timestamp: ms,
    receivedAt: _epoch.add(Duration(milliseconds: ms)),
    driving: true,
    speed: paused ? 0 : 30,
    position: race ? 5 : 0,
    raceTime: race ? 10 + ms / 1000 : 0,
    currentLap: race ? 10 + ms / 1000 : 0,
  ),
);
AppController _app() {
  final app = AppController(persist: false, tick: false);
  addTearDown(app.dispose);
  return app;
}

void _enter(AppController app) {
  _frame(app, 100);
  _frame(app, 800);
}

void _leave(AppController app) {
  _frame(app, 1100, race: false);
  _frame(app, 3000, race: false);
}

void main() {
  test(
    'auto-record defaults preserve existing behavior and JSON round trips',
    () {
      expect(AppSettings.fromJson({}).autoRecord, isTrue);
      for (final enabled in [true, false]) {
        final settings = AppSettings()
          ..autoRecord = enabled
          ..autoSwitch = !enabled;
        final saved = AppSettings.fromJson(
          jsonDecode(jsonEncode(settings.toJson())),
        );
        expect(saved.autoRecord, enabled);
        expect(saved.autoSwitch, !enabled);
      }
    },
  );

  test(
    'only confirmed race entry starts recording and completion saves it once',
    () {
      final app = _app()..settings.autoSwitch = false;
      _frame(app, 1, race: false);
      _frame(app, 2, race: false);
      expect(
        app.recording,
        isNull,
      ); // IsRaceOn/free driving alone is insufficient.
      _frame(app, 100);
      expect(app.recording, isNull);
      _frame(app, 800);
      final session = app.recording!;
      expect(app.racing, isTrue);
      expect(app.style, DashboardStyle.basic);
      expect(session.samples.single.frame.timestamp, 800);
      _frame(app, 1000);
      expect(app.recording, same(session));
      _leave(app);
      expect(app.recording, isNull);
      expect(app.sessions.single, same(session));
      expect(session.finalPosition, isNull);
      _frame(app, 3100, race: false);
      expect(app.sessions.length, 1);
    },
  );

  test('disabled auto-record still detects races and switches dashboard independently', () {
    for (final autoSwitch in [false, true]) {
      final app = _app();
      app.settings.autoRecord = false;
      app.settings.autoSwitch = autoSwitch;
      _enter(app);
      expect(app.racing, isTrue);
      expect(
        app.style,
        autoSwitch ? DashboardStyle.professional : DashboardStyle.basic,
      );
      expect(app.recording, isNull);
      _leave(app);
      expect(app.sessions, isEmpty);
    }
  });

  test('toggling on during race waits for the next race entry', () {
    final app = _app()..settings.autoRecord = false;
    _enter(app);
    app.updateSettings((s) => s.autoRecord = true);
    _frame(app, 1000);
    expect(app.recording, isNull);
    _leave(app);
    _frame(app, 3100);
    _frame(app, 3900);
    expect(app.recording, isNotNull);
    expect(app.recording!.samples.single.frame.timestamp, 3900);
  });

  test('toggle off and pause keep current recording; manual stop does not auto-restart it', () {
    final app = _app();
    _enter(app);
    final session = app.recording!;
    app.updateSettings((s) => s.autoRecord = false);
    _frame(app, 900, race: false, paused: true);
    expect(app.recording, same(session));
    expect(app.sessions, isEmpty);
    _frame(app, 1000);
    expect(session.samples.length, 2);
    app.stopRecording();
    app.updateSettings((s) => s.autoRecord = true);
    _frame(app, 1100);
    expect(app.recording, isNull);
    expect(app.sessions.single, same(session));
  });

  test(
    'manual recording works with auto-record off and survives race entry',
    () async {
      final app = _app()..settings.autoRecord = false;
      final probe = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      app.settings.port = probe.port;
      probe.close();
      await app.connect();
      final sender = await RawDatagramSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      addTearDown(sender.close);
      final received = Completer<void>();
      app.addListener(() {
        if (app.connected && !received.isCompleted) received.complete();
      });
      sender.send(
        Uint8List(324),
        InternetAddress.loopbackIPv4,
        app.settings.port,
      );
      await received.future.timeout(const Duration(seconds: 3));
      app.startRecording();
      final manual = app.recording!;
      _enter(app);
      expect(app.recording, same(manual));
      expect(manual.samples, isNotEmpty);
      _leave(app);
      expect(app.sessions.single, same(manual));
    },
  );

  for (final language in ['zh', 'en']) {
    testWidgets(
      'auto-record switch fits narrow phones and restores saved preference ($language)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 700);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final app = _app();
        app.updateSettings((s) => s.language = language);
        await tester.pumpWidget(HorizonApp(controller: app));
        await tester.pumpAndSettle();
        await tester.tap(find.text(language == 'zh' ? '设置' : 'Settings').last);
        await tester.pumpAndSettle();
        final toggle = find.byKey(const ValueKey('auto-race-recording'));
        await tester.scrollUntilVisible(toggle, 250);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, true);
        await tester.tap(toggle);
        await tester.pumpAndSettle();
        expect(app.settings.autoRecord, false);
        expect(app.settings.autoSwitch, true);
        final restored = _app()
          ..settings = AppSettings.fromJson(
            jsonDecode(jsonEncode(app.settings.toJson())),
          );
        restored.updateSettings((_) {});
        await tester.pumpWidget(HorizonApp(controller: restored));
        await tester.pumpAndSettle();
        await tester.ensureVisible(toggle);
        await tester.pumpAndSettle();
        expect(tester.widget<SwitchListTile>(toggle).value, false);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
