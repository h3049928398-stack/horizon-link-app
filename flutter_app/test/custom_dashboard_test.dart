import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/backup.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/pages/custom_dashboard_editor.dart';
import 'package:horizon_link/pages/dashboard_screen.dart';
import 'package:horizon_link/services/dashboard_hint.dart';
import 'package:horizon_link/widgets/custom_dashboard_canvas.dart';
import 'package:horizon_link/widgets/dash_canvas.dart';
import 'package:horizon_link/widgets/race_dashboard_selector.dart';

Map<String, dynamic> example() => jsonDecode(CustomDashboard.example);
Map<String, dynamic> node(String type) => {
  'type': type,
  'x': 10,
  'y': 10,
  'width': 300,
  'height': 200,
  if (type == 'text') 'text': 'Hello',
  if (['value', 'bar', 'arc'].contains(type)) 'source': 'speed',
};
CustomDashboard single(Map<String, dynamic> n) =>
    CustomDashboard.parse(jsonEncode(example()..['components'] = [n]));
AppController app() {
  final a = AppController(persist: false, tick: false)..ready = true;
  addTearDown(a.dispose);
  return a;
}

void frame(AppController a, int ms, {bool race = true}) => a.ingest(
  TelemetryFrame(
    timestamp: ms + 1,
    receivedAt: DateTime(2026).add(Duration(milliseconds: ms)),
    driving: true,
    speed: 30,
    position: race ? 3 : 0,
    raceTime: race ? 10 + ms / 1000 : 0,
    currentLap: race ? 10 + ms / 1000 : 0,
  ),
);
void enter(AppController a, int start) {
  frame(a, start);
  frame(a, start + 700);
}

void leave(AppController a, int start) {
  frame(a, start, race: false);
  frame(a, start + 1900, race: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('prompt, fenced JSON, immutable layouts', () {
    final layout = CustomDashboard.parse(CustomDashboard.example);
    expect(
      CustomDashboard.parse('```json\n${layout.code}\n```').name,
      layout.name,
    );
    for (final en in [false, true]) {
      final prompt = CustomDashboard.prompt(english: en);
      expect(prompt, contains(CustomDashboard.example));
      for (final key in [
        ...CustomDashboard.components.keys,
        ...CustomDashboard.sources.keys,
      ]) {
        expect(prompt, contains(key));
      }
    }
    expect(() => layout.json['name'] = 'mutated', throwsUnsupportedError);
    expect(() => layout.nodes.first['x'] = 500, throwsUnsupportedError);
    expect(
      () => CustomDashboard.parse('explanation\n${layout.code}'),
      throwsFormatException,
    );
    expect(
      () => CustomDashboard.parse('```json\n${layout.code}\n```\nextra'),
      throwsFormatException,
    );
  });
  for (final type in CustomDashboard.components.keys) {
    test('$type accepts documented fields, rejects unknown parameters', () {
      expect(single(node(type)).nodes.single['type'], type);
      expect(
        () => single(node(type)..['script'] = 'evil()'),
        throwsFormatException,
      );
    });
  }
  test(
    'syntax, bounds, sources and resource budgets checked before rendering',
    () {
      final bad = [
        example()..['schemaVersion'] = 2,
        example()..['name'] = '',
        example()..['background'] = 'red',
        example()..['components'] = [],
        example()..['components'] = List.generate(129, (_) => node('rect')),
        example()..['components'] = [node('rect')..['x'] = -1],
        example()..['components'] = [node('rect')..['width'] = 1280],
        example()..['components'] = [node('rect')..['height'] = '10'],
        example()..['components'] = [node('rect')..remove('height')],
        example()..['components'] = [node('value')..['source'] = 'oilTemp'],
        example()..['components'] = [node('bar')..['min'] = 100],
        example()..['components'] = [node('value')..['align'] = 'justify'],
      ];
      for (final b in bad) {
        expect(
          () => CustomDashboard.parse(jsonEncode(b)),
          throwsFormatException,
        );
      }
      expect(
        () => CustomDashboard.parse('{invalid}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'position',
            contains('line 1'),
          ),
        ),
      );
      expect(() => CustomDashboard.parse('{"x":1e999}'), throwsFormatException);
      expect(
        () => CustomDashboard.parse('${'[' * 9}0${']' * 9}'),
        throwsFormatException,
      );
      expect(() => CustomDashboard.parse(' ' * 65537), throwsFormatException);
      expect(() => CustomDashboard.parse('中' * 23000), throwsFormatException);
      expect(
        () => single(node('text')..['text'] = 'x' * 161),
        throwsFormatException,
      );
      expect(
        single(
          node('rect')
            ..['x'] = 980
            ..['y'] = 340,
        ).nodes.length,
        1,
      );
    },
  );
  test('near-limit compact JSON stays copyable and re-importable', () {
    final raw = jsonEncode(
      example()
        ..['components'] = List.generate(
          128,
          (_) => node('text')..['text'] = '中' * 125,
        ),
    );
    expect(
      utf8.encode(raw).length,
      lessThanOrEqualTo(CustomDashboard.maxBytes),
    );
    final layout = CustomDashboard.parse(raw);
    expect(
      utf8.encode(layout.code).length,
      lessThanOrEqualTo(CustomDashboard.maxBytes),
    );
    expect(CustomDashboard.parse(layout.code).nodes.length, 128);
  });
  test('version 2 migration and custom backup validation', () {
    expect(
      AppSettings.fromJson({}).raceDashboard,
      const DashboardRef.builtin('professional'),
    );
    expect(AppSettings.fromJson({'autoSwitch': false}).raceDashboard, isNull);
    expect(
      AppSettings.fromJson({'raceStyle': 'gt'}).raceDashboard,
      const DashboardRef.builtin('gt'),
    );
    final s = AppSettings()
      ..customDashboards['one'] = CustomDashboard.parse(CustomDashboard.example)
      ..raceDashboard = const DashboardRef.custom('one');
    expect(
      AppSettings.fromJson(jsonDecode(jsonEncode(s.toJson()))).raceDashboard,
      const DashboardRef.custom('one'),
    );
    final backup = {'version': 2, 'settings': s.toJson(), 'sessions': []};
    expect(parseUserBackup(jsonEncode(backup))['version'], 2);
    expect(
      () => parseUserBackup(
        jsonEncode({
          ...backup,
          'settings': s.toJson()..['customDashboards'] = [],
        }),
      ),
      throwsFormatException,
    );
    expect(
      () => AppSettings.fromJson(
        s.toJson()
          ..['customDashboards'] = [
            {'id': 'one', 'layout': example()},
            {'id': 'one', 'layout': example()},
          ],
      ),
      throwsFormatException,
    );
  });
  test('manual selection independent; confirmed race restores pre-race custom layout', () async {
    final a = app();
    await a.saveCustomDashboard(
      'one',
      CustomDashboard.parse(CustomDashboard.example),
    );
    a.settings.raceDashboard = const DashboardRef.builtin('gt');
    a.chooseDashboard(const DashboardRef.custom('one'));
    expect(a.settings.raceDashboard, const DashboardRef.builtin('gt'));
    enter(a, 0);
    expect(a.currentDashboard, const DashboardRef.builtin('gt'));
    leave(a, 800);
    expect(a.currentDashboard, const DashboardRef.custom('one'));
    expect(a.sessions.length, 1);
  });
  test(
    'manual takeover cancels restore and target edits wait for next race',
    () {
      final a = app();
      a.chooseStyle(DashboardStyle.rally);
      enter(a, 0);
      expect(a.style, DashboardStyle.professional);
      a.settings.raceDashboard = const DashboardRef.builtin('gt');
      expect(a.style, DashboardStyle.professional);
      a.chooseStyle(DashboardStyle.endurance);
      leave(a, 800);
      expect(a.style, DashboardStyle.endurance);
      enter(a, 3000);
      expect(a.style, DashboardStyle.gt);
      a.settings.raceDashboard = null;
      leave(a, 3800);
      expect(a.style, DashboardStyle.endurance);
      enter(a, 6000);
      expect(a.style, DashboardStyle.endurance);
    },
  );
  test(
    'deletion resets active, target and invalid pre-race reference',
    () async {
      final a = app();
      await a.saveCustomDashboard(
        'one',
        CustomDashboard.parse(CustomDashboard.example),
      );
      a.chooseDashboard(const DashboardRef.custom('one'));
      a.settings.raceDashboard = const DashboardRef.custom('one');
      enter(a, 0);
      await a.saveCustomDashboard('one', null);
      expect(a.style, DashboardStyle.basic);
      expect(a.customDashboard, isNull);
      expect(a.settings.raceDashboard, isNull);
      leave(a, 800);
      expect(a.style, DashboardStyle.basic);
    },
  );
  test(
    'atomic write failure retains layouts; telemetry continues during save',
    () async {
      final gate = Completer<void>();
      final a = AppController(
        persist: true,
        tick: false,
        writeData: (_) => gate.future,
      )..ready = true;
      addTearDown(a.dispose);
      final pending = a.saveCustomDashboard(
        'one',
        CustomDashboard.parse(CustomDashboard.example),
      );
      enter(a, 0);
      frame(a, 900);
      expect(a.recording!.samples.length, 2);
      gate.completeError(StateError('disk full'));
      await expectLater(pending, throwsStateError);
      expect(a.settings.customDashboards, isEmpty);
      expect(a.recording!.samples.length, 2);
      expect(a.dataMutation, false);
      a.storageReadFailed = true;
      await expectLater(
        a.saveCustomDashboard(
          'one',
          CustomDashboard.parse(CustomDashboard.example),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'scheme limit rejects new entries and allows editing existing entry',
    () async {
      final a = app();
      for (var i = 0; i < 20; i++) {
        await a.saveCustomDashboard(
          '$i',
          CustomDashboard.parse(CustomDashboard.example),
        );
      }
      await expectLater(
        a.saveCustomDashboard(
          'overflow',
          CustomDashboard.parse(CustomDashboard.example),
        ),
        throwsFormatException,
      );
      expect(a.settings.customDashboards.length, 20);
      await a.saveCustomDashboard('0', single(node('text')));
      expect(a.settings.customDashboards.length, 20);
    },
  );
  test('custom race target and old backup restore remain independent of recording preference', () async {
    final a = app();
    await a.saveCustomDashboard(
      'one',
      CustomDashboard.parse(CustomDashboard.example),
    );
    a.settings.autoRecord = false;
    a.settings.raceDashboard = const DashboardRef.custom('one');
    a.chooseStyle(DashboardStyle.rally);
    enter(a, 0);
    expect(a.currentDashboard, const DashboardRef.custom('one'));
    expect(a.recording, isNull);
    final backup = a.exportBackup();
    leave(a, 800);
    expect(a.style, DashboardStyle.rally);
    expect(
      parseUserBackup(backup)['settings']['customDashboards'],
      hasLength(1),
    );
    final old = {
      'version': 2,
      'settings': {'autoSwitch': false},
      'sessions': [],
    };
    await a.restoreBackup(jsonEncode(old));
    expect(a.settings.customDashboards, isEmpty);
    expect(a.settings.raceDashboard, isNull);
  });
  test(
    'successful snapshot keeps records arriving while disk write is pending',
    () async {
      final gate = Completer<void>();
      final writes = <String>[];
      final a = AppController(
        persist: true,
        tick: false,
        writeData: (text) async {
          writes.add(text);
          if (writes.length == 1) await gate.future;
        },
      )..ready = true;
      addTearDown(a.dispose);
      final pending = a.saveCustomDashboard(
        'one',
        CustomDashboard.parse(CustomDashboard.example),
      );
      enter(a, 0);
      frame(a, 900);
      leave(a, 1000);
      gate.complete();
      await pending;
      await a.flushSaved();
      final data = parseUserBackup(writes.last);
      expect(data['settings']['customDashboards'], hasLength(1));
      expect(data['sessions'], hasLength(1));
      expect(data['sessions'][0]['samples'], hasLength(2));
    },
  );
  test('formatting and settings constraints apply to all bound sources', () {
    final s = AppSettings();
    final p = CustomDashboardPainter(
      layout: CustomDashboard.parse(CustomDashboard.example),
      frame: TelemetryFrame(speed: 50),
      settings: s,
      hasData: true,
    );
    expect(p.formatted('speed'), '180 km/h');
    s.mph = true;
    expect(p.formatted('speed'), '112 mph');
    expect(p.formatted('position'), '--');
    expect(p.formatted('currentLap'), '--');
    expect(p.formatted('tireFL'), contains('RAW / UNIT UNVERIFIED'));
    s.tires = false;
    s.inputs = false;
    expect(p.sourceVisible('tireFL'), false);
    expect(p.sourceVisible('throttle'), false);
    expect(
      CustomDashboardPainter(
        layout: p.layout,
        frame: p.frame,
        settings: s,
      ).formatted('gear'),
      '--',
    );
  });
  testWidgets('all component painters preserve surrounding pixels', (
    tester,
  ) async {
    await tester.runAsync(() async {
      for (final type in CustomDashboard.components.keys) {
        final recorder = ui.PictureRecorder();
        final c = Canvas(recorder);
        c.drawRect(
          const Rect.fromLTWH(0, 0, 400, 240),
          Paint()..color = const Color(0xffff0000),
        );
        c.save();
        c.translate(100, 50);
        CustomDashboardPainter(
          layout: single(node(type)),
          frame: TelemetryFrame(),
          settings: AppSettings(),
          hasData: true,
        ).paint(c, const Size(180, 130));
        c.restore();
        final pic = recorder.endRecording();
        final image = await pic.toImage(400, 240);
        final bytes = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!;
        for (final p in [
          const Offset(10, 10),
          const Offset(390, 230),
          const Offset(300, 60),
        ]) {
          final at = (p.dy.toInt() * 400 + p.dx.toInt()) * 4;
          expect(
            [for (var i = 0; i < 4; i++) bytes.getUint8(at + i)],
            [255, 0, 0, 255],
            reason: type,
          );
        }
        image.dispose();
        pic.dispose();
      }
    });
  });
  for (final en in [false, true]) {
    testWidgets(
      '320px editor ${en ? 'English' : 'Chinese'} validates, invalidates, saves and retains failed input',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 700);
        addTearDown(tester.view.reset);
        final a = app();
        a.settings.language = en ? 'en' : 'zh';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showCustomDashboardEditor(context, a),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        final code = find.byKey(const ValueKey('custom-dashboard-code')),
            check = find.byKey(const ValueKey('check-custom-dashboard')),
            save = find.byKey(const ValueKey('save-custom-dashboard'));
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(of: save, matching: find.byType(FilledButton)),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(find.byType(DashCanvas), findsOneWidget);
        await tester.ensureVisible(code);
        await tester.pumpAndSettle();
        await tester.enterText(code, '{broken}');
        await tester.pump();
        expect(
          tester
              .widget<FilledButton>(
                find.descendant(of: save, matching: find.byType(FilledButton)),
              )
              .onPressed,
          isNull,
        );
        await tester.tap(check);
        await tester.pumpAndSettle();
        expect(
          find.byKey(const ValueKey('custom-dashboard-error')),
          findsOneWidget,
        );
        await tester.ensureVisible(code);
        await tester.pumpAndSettle();
        await tester.enterText(code, CustomDashboard.example);
        tester.testTextInput.hide();
        await tester.pump();
        await tester.tap(check);
        await tester.pumpAndSettle();
        a.storageReadFailed = true;
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(
          tester.widget<TextField>(code).controller!.text,
          CustomDashboard.example,
        );
        expect(a.settings.customDashboards, isEmpty);
        a.storageReadFailed = false;
        await tester.tap(save);
        await tester.pumpAndSettle();
        expect(a.settings.customDashboards.length, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('race selector offers all schemes and explicit none', (
    tester,
  ) async {
    final a = app();
    await a.saveCustomDashboard(
      'one',
      CustomDashboard.parse(CustomDashboard.example),
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AnimatedBuilder(
            animation: a,
            builder: (context, _) => RaceDashboardSelector(app: a),
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('race-dashboard-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My cockpit').last);
    await tester.pumpAndSettle();
    expect(a.settings.raceDashboard, const DashboardRef.custom('one'));
    await tester.tap(find.byKey(const ValueKey('race-dashboard-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('不切换').last);
    await tester.pumpAndSettle();
    expect(a.settings.raceDashboard, isNull);
  });
  testWidgets('custom canvas shares fullscreen and two-second hold', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.reset);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DashboardHint.channel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(DashboardHint.channel, null),
    );
    final a = app();
    await a.saveCustomDashboard(
      'one',
      CustomDashboard.parse(CustomDashboard.example),
    );
    a.chooseDashboard(const DashboardRef.custom('one'));
    await tester.pumpWidget(MaterialApp(home: DashboardScreen(app: a)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('dashboard-fullscreen-toggle')));
    await tester.pump();
    expect(find.byType(IconButton), findsNothing);
    expect(
      tester.widget<DashCanvas>(find.byType(DashCanvas)).customLayout!.name,
      'My cockpit',
    );
    final hold = await tester.startGesture(
      tester.getCenter(
        find.byKey(const ValueKey('dashboard-fullscreen-surface')),
      ),
    );
    await tester.pump(const Duration(milliseconds: 1999));
    expect(find.byKey(const ValueKey('dashboard-toolbar')), findsNothing);
    await tester.pump(const Duration(milliseconds: 1));
    await hold.up();
    await tester.pump();
    expect(find.byKey(const ValueKey('dashboard-toolbar')), findsOneWidget);
  });
  testWidgets('disposing during layout write does not schedule another save', (
    tester,
  ) async {
    final gate = Completer<void>();
    var writes = 0;
    final a = AppController(
      persist: true,
      tick: false,
      writeData: (_) async {
        writes++;
        await gate.future;
      },
    )..ready = true;
    final pending = a.saveCustomDashboard(
      'one',
      CustomDashboard.parse(CustomDashboard.example),
    );
    a.dispose();
    gate.complete();
    await pending;
    expect(writes, 1);
    expect(a.settings.customDashboards, isEmpty);
    // testWidgets automatically rejects post-disposal timers.
  });
}
