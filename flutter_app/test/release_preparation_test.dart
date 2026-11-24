import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:horizon_link/app_controller.dart';
import 'package:horizon_link/core/backup.dart';
import 'package:horizon_link/core/racing.dart';
import 'package:horizon_link/core/telemetry.dart';
import 'package:horizon_link/core/web_navigation.dart';
import 'package:horizon_link/pages/data_management_page.dart';
import 'package:horizon_link/pages/release_about_page.dart';
import 'package:horizon_link/privacy_bootstrap.dart';
import 'package:horizon_link/services/privacy_consent.dart';
import 'package:horizon_link/services/release_info.dart';

class QuietController extends AppController {
  QuietController({super.persist = false, super.readData, super.writeData})
    : super(tick: false);
  int connects = 0;
  bool closed = false;
  @override
  Future<void> initialize() async {
    ready = true;
  }

  @override
  Future<void> connect() async {
    connects++;
  }

  @override
  void dispose() {
    closed = true;
    super.dispose();
  }
}

String backup({int port = 8000}) => jsonEncode({
  'version': 2,
  'settings': (AppSettings()..port = port).toJson(),
  'sessions': [
    (DrivingSession(
      'udp',
      id: 'one',
      started: DateTime(2026),
    )..add(TelemetryFrame(receivedAt: DateTime(2026), speed: 23))).toJson(),
  ],
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('consent version, refusal and storage failure fail closed', () async {
    String? value = 'old';
    var fail = false;
    final consent = PrivacyConsent(
      read: () async => value,
      write: (v) async {
        if (fail) throw const FileSystemException('full');
        value = v;
      },
    );
    addTearDown(consent.dispose);
    await consent.load();
    expect(consent.accepted, false);
    fail = true;
    await expectLater(consent.accept(), throwsA(isA<FileSystemException>()));
    expect(consent.accepted, false);
    fail = false;
    await consent.accept();
    expect(value, ReleaseInfo.policyVersion);
    final reload = PrivacyConsent(read: () async => value, write: (_) async {});
    addTearDown(reload.dispose);
    await reload.load();
    expect(reload.accepted, true);
    await consent.revoke();
    expect(value, '');
    expect(consent.accepted, false);
  });

  for (final en in [false, true]) {
    testWidgets('about page reveals the developer only on tap ($en)', (
      tester,
    ) async {
      final app = QuietController()..settings.language = en ? 'en' : 'zh';
      addTearDown(app.dispose);
      final developer = ReleaseInfo.developer.isNotEmpty
          ? ReleaseInfo.developer
          : (en ? 'Pending before release' : '发布前待补充');
      final heading = en ? 'Developer' : '开发者';
      final row = find.widgetWithText(ExpansionTile, heading);
      final name = find.descendant(of: row, matching: find.text(developer));

      await tester.pumpWidget(MaterialApp(home: ReleaseAboutPage(app: app)));
      expect(row, findsOneWidget);
      expect(name, findsNothing);

      await tester.tap(find.text(heading));
      await tester.pumpAndSettle();
      expect(name, findsOneWidget);

      await tester.tap(find.text(heading));
      await tester.pumpAndSettle();
      expect(name, findsNothing);
    });

    testWidgets('privacy gate does not create services before consent ($en)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(320, 780);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var created = 0;
      QuietController? app;
      final consent = PrivacyConsent(
        read: () async => null,
        write: (_) async {},
      );
      await tester.pumpWidget(
        PrivacyBootstrap(
          consent: consent,
          createController: () {
            created++;
            return app = QuietController();
          },
        ),
      );
      await tester.pumpAndSettle();
      if (en) {
        await tester.tap(find.text('English'));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byKey(const ValueKey('decline-privacy')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('decline-privacy')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(en ? 'No network services' : '尚未启动网络服务'),
        findsOneWidget,
      );
      await tester.pumpAndSettle();
      expect(created, 0);
      await tester.ensureVisible(find.byKey(const ValueKey('read-privacy')));
      await tester.tap(find.byKey(const ValueKey('read-privacy')));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(en ? 'not your phone' : '不是手机'),
        findsOneWidget,
      );
      expect(created, 0);
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const ValueKey('accept-privacy')));
      await tester.tap(find.byKey(const ValueKey('accept-privacy')));
      await tester.pumpAndSettle();
      expect(created, 1);
      expect(app!.connects, 1);
      expect(find.byType(NavigationBar), findsOneWidget);
      await consent.revoke();
      await tester.pumpAndSettle();
      expect(app!.closed, true);
      expect(find.byType(NavigationBar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      consent.dispose();
    });
  }

  test(
    'version 2 backup preserves samples, no yaw, settings and excludes consent',
    () {
      final raw = parseUserBackup(backup(port: 8123));
      expect(raw['settings']['port'], 8123);
      expect(raw['sessions'][0]['samples'][0]['frame']['yaw'], isNull);
      expect(raw.containsKey('consent'), false);
      expect(raw.containsKey('weekly'), false);
    },
  );

  for (final kind in [
    'version',
    'port',
    'tires',
    'nonfinite',
    'timestamp',
    'duplicate',
    'count',
    'samples',
  ]) {
    test('invalid $kind rejects whole backup', () {
      final data = jsonDecode(backup());
      switch (kind) {
        case 'version':
          data['version'] = 99;
        case 'port':
          data['settings']['port'] = 0;
        case 'tires':
          data['sessions'][0]['samples'][0]['frame']['tires'] = [1];
        case 'nonfinite':
          data['sessions'][0]['samples'][0]['frame']['speed'] = 'NaN';
        case 'timestamp':
          data['sessions'][0]['started'] = 'invalid';
        case 'duplicate':
          data['sessions'].add(data['sessions'][0]);
        case 'count':
          data['sessions'] = List.filled(9, data['sessions'][0]);
        case 'samples':
          data['sessions'][0]['samples'] = List.filled(
            12001,
            data['sessions'][0]['samples'][0],
          );
      }
      expect(() => parseUserBackup(jsonEncode(data)), throwsFormatException);
    });
  }

  test(
    'restore validates then commits, preserves live data on disk failure',
    () async {
      var fail = true;
      String? written;
      final app = QuietController(
        persist: true,
        writeData: (text) async {
          if (fail) throw const FileSystemException('full');
          written = text;
        },
      );
      addTearDown(app.dispose);
      app.ready = true;
      app.sessions.add(DrivingSession('old', id: 'old'));
      await expectLater(
        app.restoreBackup(backup(port: 8123)),
        throwsA(isA<FileSystemException>()),
      );
      expect(app.settings.port, 8000);
      expect(app.sessions.single.id, 'old');
      expect(app.connects, 0);
      fail = false;
      await app.restoreBackup(backup(port: 8123));
      expect(app.settings.port, 8123);
      expect(app.sessions.single.id, 'one');
      expect(jsonDecode(written!)['sessions'][0]['id'], 'one');
      expect(app.connects, 1);
    },
  );

  test(
    'serialized saves and lifecycle flush retain unfinished final sample',
    () async {
      final first = Completer<void>();
      final writes = <String>[];
      final app = QuietController(
        persist: true,
        writeData: (value) async {
          writes.add(value);
          if (writes.length == 1) await first.future;
        },
      );
      addTearDown(app.dispose);
      app.ready = true;
      app.recording = DrivingSession('udp', id: 'active')
        ..add(TelemetryFrame(speed: 20));
      final a = app.flushSaved();
      await Future<void>.delayed(Duration.zero);
      app.recording!.add(TelemetryFrame(speed: 30));
      final b = app.flushSaved();
      expect(writes.length, 1);
      first.complete();
      await Future.wait([a, b]);
      expect(writes.length, 2);
      final data = parseUserBackup(writes.last);
      expect(data['sessions'][0]['samples'], hasLength(2));
      expect(data['sessions'][0]['ended'], isNull);
    },
  );

  test('unreadable save blocks automatic overwrite', () async {
    var writes = 0;
    final app = AppController(
      tick: false,
      readData: () async => '{broken',
      writeData: (_) async {
        writes++;
      },
    );
    addTearDown(app.dispose);
    await app.initialize();
    expect(app.storageReadFailed, true);
    app.updateSettings((s) => s.mph = true);
    await app.flushSaved();
    expect(writes, 0);
  });

  test(
    'delete is committed before mutating and only removes selected record',
    () async {
      var fail = true;
      final app = QuietController(
        persist: true,
        writeData: (_) async {
          if (fail) throw StateError('disk full');
        },
      );
      addTearDown(app.dispose);
      app.ready = true;
      app.sessions.addAll([
        DrivingSession('udp', id: 'a'),
        DrivingSession('udp', id: 'b'),
      ]);
      app.settings.mph = true;
      await expectLater(app.deleteSession('a'), throwsStateError);
      expect(app.sessions, hasLength(2));
      fail = false;
      await app.deleteSession('a');
      expect(app.sessions.single.id, 'b');
      expect(app.settings.mph, true);
    },
  );

  testWidgets(
    'document picker cancellation and corrupt import leave data unchanged',
    (tester) async {
      final app = QuietController()..ready = true;
      addTearDown(app.dispose);
      app.sessions.add(DrivingSession('udp', id: 'original'));
      String? selected;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        ReleaseInfo.channel,
        (call) async => call.method == 'import' ? selected : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          ReleaseInfo.channel,
          null,
        ),
      );
      await tester.pumpWidget(MaterialApp(home: DataManagementPage(app: app)));
      await tester.tap(find.byKey(const ValueKey('import-backup')));
      await tester.pumpAndSettle();
      expect(app.sessions.single.id, 'original');
      selected = '{bad';
      await tester.tap(find.byKey(const ValueKey('import-backup')));
      await tester.pumpAndSettle();
      expect(app.sessions.single.id, 'original');
      expect(find.textContaining('操作失败'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  test('installed version comes from package bridge', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      ReleaseInfo.channel,
      (_) async => '1.2.3+45',
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(ReleaseInfo.channel, null),
    );
    expect(await ReleaseInfo.installedVersion(), '1.2.3+45');
  });

  test(
    'guide navigation preserves source HTTPS and confirms external hosts',
    () {
      const source = 'https://api.xiaoheihe.cn/share';
      expect(
        guideNavigation(source, 'https://www.xiaoheihe.cn/post'),
        WebNavigation.internal,
      );
      expect(
        guideNavigation(source, 'https://xiaoheihe.cn.evil.test/post'),
        WebNavigation.external,
      );
      for (final url in [
        'http://api.xiaoheihe.cn',
        'file:///tmp/x',
        'javascript:alert(1)',
        'intent://foo',
        'https://user:pass@api.xiaoheihe.cn',
        'https://api.xiaoheihe.cn:444',
      ]) {
        expect(guideNavigation(source, url), WebNavigation.blocked);
      }
    },
  );
}
