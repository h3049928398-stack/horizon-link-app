import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'core/telemetry.dart';
import 'core/rev_limiter.dart';
import 'core/custom_dashboard.dart';
export 'core/custom_dashboard.dart' show DashboardRef, CustomDashboard;
import 'core/backup.dart';
import 'l10n.dart';
import 'core/racing.dart';
import 'core/road_graph.dart';
import 'core/navigation.dart';
import 'services/storage.dart' as storage;
import 'services/udp.dart';
import 'services/weekly_content_service.dart';

enum DashboardStyle { basic, professional, gt, endurance, rally }

extension DashboardStyleInfo on DashboardStyle {
  bool get isProfessional => this != DashboardStyle.basic;
  String get title => switch (this) {
    DashboardStyle.basic => '基础仪表',
    DashboardStyle.professional => '专业仪表',
    DashboardStyle.gt => 'GT 竞速',
    DashboardStyle.endurance => '耐力赛',
    DashboardStyle.rally => '拉力赛',
  };
  String get shortTitle => switch (this) {
    DashboardStyle.basic => '基础',
    DashboardStyle.professional => '专业',
    _ => title,
  };
}

enum AppAppearance { dark, light, system }

(AppSettings, List<DrivingSession>) _decodeSavedState(String text) {
  final data = parseUserBackup(text);
  return (
    AppSettings.fromJson(data['settings']),
    (data['sessions'] as List)
        .map((s) => DrivingSession.fromJson(Map<String, dynamic>.from(s)))
        .toList(),
  );
}

class AppSettings {
  final limiterCalibrations = <String, LimiterCalibration>{};
  DashboardStyle raceStyle = DashboardStyle.professional;
  DashboardRef? _raceDashboard;
  final customDashboards = <String, CustomDashboard>{};
  DashboardRef? get raceDashboard => !autoSwitch
      ? null
      : _raceDashboard ?? DashboardRef.builtin(raceStyle.name);
  set raceDashboard(DashboardRef? value) {
    _raceDashboard = value;
    autoSwitch = value != null;
    if (value?.kind == 'builtin' && value!.id != 'basic') {
      raceStyle = DashboardStyle.values.byName(value.id);
    }
  }

  AppAppearance appearance = AppAppearance.dark;
  bool autoSwitch = true,
      autoRecord = true,
      effects = true,
      miniNav = true,
      expandedNav = false,
      tires = true,
      inputs = true,
      mph = false;
  // Retain shiftRpm only for version 2 backup compatibility.
  int port = 8000, shiftRpm = 7500;
  String language = 'zh';
  static const guideWebsiteUrl =
      'https://api.xiaoheihe.cn/v3/bbs/app/api/web/share?h_camp=link&h_session_id=4OBWU20qN1doG17z&h_src=YXBwX3NoYXJl&link_id=300372ba1810&new_post_share_style_v2=1';
  String get guideUrl => guideWebsiteUrl;
  Map<String, dynamic> toJson() => {
    'raceStyle': raceStyle.name,
    'raceDashboard': raceDashboard?.toJson(),
    'customDashboards': customDashboards.entries
        .map((e) => {'id': e.key, 'layout': e.value.json})
        .toList(),
    'language': language,
    'appearance': appearance.name,
    'autoSwitch': autoSwitch,
    'autoRecord': autoRecord,
    'effects': effects,
    'miniNav': miniNav,
    'expandedNav': expandedNav,
    'tires': tires,
    'inputs': inputs,
    'mph': mph,
    'port': port,
    'shiftRpm': shiftRpm,
    'limiterCalibrations': limiterCalibrations.map(
      (k, v) => MapEntry(k, v.toJson()),
    ),
    'guideUrl': guideUrl,
  };
  factory AppSettings.fromJson(Map<String, dynamic> j) {
    validateCustomSettings(j);
    final s = AppSettings();
    s.limiterCalibrations.addAll(
      readLimiterCalibrations(j['limiterCalibrations']),
    );
    s.raceStyle = DashboardStyle.values.firstWhere(
      (style) => style.isProfessional && style.name == j['raceStyle'],
      orElse: () => DashboardStyle.professional,
    );
    s.appearance = switch (j['appearance']) {
      'light' => AppAppearance.light,
      'system' => AppAppearance.system,
      'dark' => AppAppearance.dark,
      null => j['darkMode'] == false ? AppAppearance.light : AppAppearance.dark,
      _ => AppAppearance.dark,
    };
    s.language = j['language'] == 'en' ? 'en' : 'zh';
    s.autoSwitch = j['autoSwitch'] != false;
    for (final item in (j['customDashboards'] as List? ?? [])) {
      s.customDashboards[item['id'] as String] = CustomDashboard.parse(
        jsonEncode(item['layout']),
      );
    }
    if (j.containsKey('raceDashboard')) {
      s.raceDashboard = j['raceDashboard'] == null
          ? null
          : DashboardRef.parse(j['raceDashboard']);
    }
    s.autoRecord = j['autoRecord'] != false;
    s.effects = j['effects'] != false;
    s.miniNav = j['miniNav'] != false;
    s.expandedNav = j['expandedNav'] == true;
    s.tires = j['tires'] != false;
    s.inputs = j['inputs'] != false;
    s.mph = j['mph'] == true;
    s.port = (j['port'] as num?)?.toInt() ?? 8000;
    s.shiftRpm = (j['shiftRpm'] as num?)?.toInt() ?? 7500;
    // The guide source is fixed; ignore URLs saved by earlier versions.
    return s;
  }
  AppSettings();
}

class AppController extends ChangeNotifier {
  final _limiter = RevLimiterLearner();
  bool _limiterForeground = true, _limiterUsable = false;
  LimiterSnapshot get limiter => _limiter.snapshot(
    frame,
    settings.limiterCalibrations,
    available: hasTelemetry && !_gap && _limiterForeground && _limiterUsable,
  );
  void setLimiterForeground(bool value) {
    if (_disposed || value == _limiterForeground) return;
    _limiterForeground = value;
    if (!value) {
      _limiter.interrupt();
      _limiterUsable = false;
    }
    notifyListeners();
  }

  void resetCurrentLimiter() {
    if (_disposed || !ready || storageReadFailed || _dataMutation) return;
    final key = limiterVehicleKey(frame);
    if (key == null) return;
    settings.limiterCalibrations.remove(key);
    _limiter.interrupt();
    save();
    notifyListeners();
  }

  AppSettings settings = AppSettings();
  final language = ValueNotifier<String>('zh');
  final appearance = ValueNotifier<AppAppearance>(AppAppearance.dark);
  TelemetryFrame frame = TelemetryFrame();
  DashboardStyle style = DashboardStyle.basic;
  String? _customId;
  DashboardRef? _beforeRace;
  DashboardRef get currentDashboard => _customId == null
      ? DashboardRef.builtin(style.name)
      : DashboardRef.custom(_customId!);
  CustomDashboard? get customDashboard => settings.customDashboards[_customId];
  bool get hasTelemetry => _lastReceive != null;
  bool get dataMutation => _dataMutation;
  bool racing = false, gain = false, ready = false;
  bool _connected = false;
  bool get connected => _connected;
  String status = '等待游戏数据', message = '';
  final sessions = <DrivingSession>[];
  DrivingSession? recording;
  int packets = 0, rejected = 0;
  List<String> addresses = [];
  String? destination;
  RoadGraph? roadGraph;
  NavigationState? navigation;
  String mapError = '';
  final WeeklyContentService weekly;
  ({int serial, MapPlace place})? mapFocus;
  int _focusSerial = 0;
  String get guideUrl =>
      weekly.content?.guideUrl ?? AppSettings.guideWebsiteUrl;
  void focusWeeklyPlace(MapPlace place) {
    mapFocus = (serial: ++_focusSerial, place: place);
    notifyListeners();
  }

  void _weeklyChanged() {
    if (!_disposed) notifyListeners();
  }

  final bool persist;
  Future<void> Function()? withdrawConsent;
  final Future<String?> Function() readData;
  final Future<void> Function(String) writeData;
  final Future<RoadGraph> Function() loadRoadGraph;
  Future<void> _mapLoaded = Future<void>.value();
  Future<void> get mapLoaded => _mapLoaded;
  bool storageReadFailed = false;
  bool _dataMutation = false;
  bool _layoutMutation = false;
  Future<void> _writeQueue = Future<void>.value();
  DateTime? _lastCheckpoint;
  Timer? _ticker, _saveTimer, _gainTimer, _connectionTimer, _messageTimer;
  RaceDetector _detector = RaceDetector();
  final _udp = UdpReceiver();
  bool _disposed = false, _gap = false;
  TelemetryFrame? _previous;
  DateTime? _lastReceive, _lastSample;
  AppController({
    this.persist = true,
    bool tick = true,
    WeeklyContentService? weekly,
    this.readData = storage.readSaved,
    this.writeData = storage.writeSaved,
    this.loadRoadGraph = RoadGraph.load,
  }) : weekly = weekly ?? WeeklyContentService(persist: persist) {
    this.weekly.addListener(_weeklyChanged);
    if (tick) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 100),
        (_) => _tick(),
      );
    }
  }
  Future<void> initialize() async {
    // Map parsing must not delay saved preferences, the library or UDP startup.
    _mapLoaded = _loadMap();
    if (persist) {
      try {
        final text = await readData();
        if (_disposed) return;
        if (text != null) {
          final saved = await compute(
            _decodeSavedState,
            text,
            debugLabel: 'saved-driving-data',
          );
          if (_disposed) return;
          settings = saved.$1;
          sessions.addAll(saved.$2);
        }
      } catch (_) {
        if (_disposed) return;
        storageReadFailed = true;
        notifyMessage('无法读取旧设置，已使用默认设置');
      }
    }
    if (_disposed) return;
    ready = true;
    language.value = settings.language;
    appearance.value = settings.appearance;
    notifyListeners();
  }

  Future<void> _loadMap() async {
    try {
      final graph = await loadRoadGraph();
      if (_disposed) return;
      roadGraph = graph;
      navigation = NavigationState(graph);
      if (_lastReceive != null && frame.driving) {
        navigation!.update(
          MapPoint(frame.x, frame.y, frame.z),
          moving: false,
          yaw: frame.yaw,
        );
      }
    } catch (e) {
      if (_disposed) return;
      mapError = '地图加载失败：$e';
    }
    if (!_disposed) {
      notifyListeners();
      if (roadGraph != null) unawaited(weekly.initialize(roadGraph!));
    }
  }

  double get displaySpeed => frame.speed * (settings.mph ? 2.236936 : 3.6);
  String get speedUnit => settings.mph ? 'mph' : 'km/h';
  String get gearLabel => frame.gear == 0 ? 'R' : frame.gear.toString();
  void updateSettings(void Function(AppSettings) change) {
    if (_dataMutation) return;
    change(settings);
    language.value = settings.language;
    appearance.value = settings.appearance;
    save();
    notifyListeners();
  }

  void chooseStyle(DashboardStyle value) =>
      chooseDashboard(DashboardRef.builtin(value.name));

  bool _validDashboard(DashboardRef value) => value.kind == 'builtin'
      ? DashboardRef.builtinIds.contains(value.id)
      : settings.customDashboards.containsKey(value.id);
  void _applyDashboard(DashboardRef value) {
    final valid = _validDashboard(value)
        ? value
        : const DashboardRef.builtin('basic');
    _customId = valid.kind == 'custom' ? valid.id : null;
    style = valid.kind == 'builtin'
        ? DashboardStyle.values.byName(valid.id)
        : DashboardStyle.professional;
  }

  void chooseDashboard(DashboardRef value) {
    if (_dataMutation) return;
    _beforeRace = null; // A manual choice takes control of this race.
    _applyDashboard(value);
    notifyListeners();
  }

  /// Commit a complete settings snapshot before publishing the new layout.
  Future<void> saveCustomDashboard(String id, CustomDashboard? layout) async {
    if (!ready || storageReadFailed || _dataMutation) {
      throw StateError('Data is not ready');
    }
    if (id.isEmpty || id.length > 80) {
      throw const FormatException('Invalid scheme id');
    }
    final next = AppSettings.fromJson(settings.toJson());
    if (layout == null) {
      next.customDashboards.remove(id);
      if (next.raceDashboard == DashboardRef.custom(id)) {
        next.raceDashboard = null;
      }
    } else {
      next.customDashboards[id] = CustomDashboard.parse(layout.code);
    }
    validateCustomSettings(next.toJson());
    _saveTimer?.cancel();
    _dataMutation = true;
    _layoutMutation = true;
    try {
      final data = jsonDecode(exportBackup()) as Map<String, dynamic>;
      data['settings'] = next.toJson();
      if (persist) await _write(jsonEncode(data));
      if (_disposed) return;
      // Live learning may complete while the layout snapshot is being written.
      next.limiterCalibrations
        ..clear()
        ..addAll(settings.limiterCalibrations);
      settings = next;
      if (!_validDashboard(currentDashboard)) {
        _applyDashboard(const DashboardRef.builtin('basic'));
      }
      if (_beforeRace != null && !_validDashboard(_beforeRace!)) {
        _beforeRace = const DashboardRef.builtin('basic');
      }
      notifyListeners();
    } finally {
      _dataMutation = false;
      _layoutMutation = false;
      // Telemetry continues during a layout write; flush the latest recordings.
      save();
      if (!_disposed) notifyListeners();
    }
  }

  void setDestination(String? value) {
    destination = value;
    notifyListeners();
  }

  void navigateTo(MapPlace place) {
    if (navigation == null) return;
    if (navigation!.start(place)) {
      destination = place.name;
    } else {
      destination = null;
      notifyMessage(navigation!.status);
    }
    notifyListeners();
  }

  void stopNavigation() {
    navigation?.stop();
    destination = null;
    notifyListeners();
  }

  String placeName(MapPlace place) => place.displayName(settings.language);

  String? get navigationLabel {
    final n = navigation;
    if (n?.destination == null) return null;
    if (n!.route == null) return localize(n.status, settings.language);
    return '${localize(n.instruction, settings.language)} · ${mapDistance(n.turnDistance)}';
  }

  void notifyMessage(String value) {
    if (_disposed) return;
    message = value;
    _messageTimer?.cancel();
    _messageTimer = Timer(const Duration(seconds: 4), () {
      if (!_disposed) {
        message = '';
        notifyListeners();
      }
    });
    notifyListeners();
  }

  void save() {
    if (_disposed || !persist || !ready || storageReadFailed || _dataMutation) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 300), () async {
      try {
        await flushSaved();
      } catch (_) {
        notifyMessage('本地保存失败，请先导出重要记录');
      }
    });
  }

  String exportBackup() => jsonEncode({
    'version': 2,
    'settings': settings.toJson(),
    'sessions': [
      ?recording,
      ...sessions,
    ].take(8).map((s) => s.toJson()).toList(),
  });

  Future<void> _write(String text) {
    final next = _writeQueue.then((_) => writeData(text));
    // A failed write is reported to its caller but does not poison later saves.
    _writeQueue = next.catchError((Object _) {});
    return next;
  }

  Future<void> flushSaved() async {
    _saveTimer?.cancel();
    if (_dataMutation) {
      await _writeQueue;
      return;
    }
    if (!persist || !ready || storageReadFailed) return;
    await _write(exportBackup());
  }

  Future<void> restoreBackup(String text) async {
    if (!ready || recording != null || _dataMutation) {
      throw StateError('Data is not ready for restoring');
    }
    final data = parseUserBackup(text);
    final restoredSettings = AppSettings.fromJson(data['settings']);
    final restoredSessions = (data['sessions'] as List)
        .map((s) => DrivingSession.fromJson(Map<String, dynamic>.from(s)))
        .toList();
    _saveTimer?.cancel();
    _dataMutation = true;
    try {
      if (persist) {
        await _write(
          jsonEncode({
            'version': 2,
            'settings': restoredSettings.toJson(),
            'sessions': restoredSessions.map((s) => s.toJson()).toList(),
          }),
        );
      }
      if (_disposed) return;
      settings = restoredSettings;
      _limiter.interrupt();
      _limiterUsable = false;
      _beforeRace = null;
      if (!_validDashboard(currentDashboard)) {
        _applyDashboard(const DashboardRef.builtin('basic'));
      }
      sessions
        ..clear()
        ..addAll(restoredSessions);
      storageReadFailed = false;
      language.value = settings.language;
      appearance.value = settings.appearance;
      notifyListeners();
    } finally {
      _dataMutation = false;
    }
    // Rebind only after a successful commit, using the restored port.
    await connect();
  }

  Future<void> deleteSession(String id) async {
    if (!ready || recording != null || storageReadFailed || _dataMutation) {
      throw StateError('Data is not ready for deletion');
    }
    final remaining = sessions.where((s) => s.id != id).toList();
    _saveTimer?.cancel();
    _dataMutation = true;
    try {
      if (persist) {
        await _write(
          jsonEncode({
            'version': 2,
            'settings': settings.toJson(),
            'sessions': remaining.map((s) => s.toJson()).toList(),
          }),
        );
      }
      if (_disposed) return;
      sessions
        ..clear()
        ..addAll(remaining);
      notifyListeners();
    } finally {
      _dataMutation = false;
    }
  }

  void _tick() {
    if (_lastReceive == null ||
        DateTime.now().difference(_lastReceive!).inSeconds >= 2) {
      if (!_gap) {
        status = _lastReceive == null ? '等待游戏数据' : '数据中断 · 暂停或回溯待判断';
        _gap = true;
        _limiter.interrupt();
        _limiterUsable = false;
        _detector.gap();
        recording?.interruptions++;
        notifyListeners();
      }
    }
  }

  void ingest(TelemetryFrame incoming, {bool notify = true}) {
    if (_disposed || (_dataMutation && !_layoutMutation)) return;
    if (_previous != null &&
        incoming.receivedAt.difference(_previous!.receivedAt).inSeconds < 3 &&
        !freshTimestamp(_previous!.timestamp, incoming.timestamp)) {
      return;
    }
    _previous = incoming;
    _lastReceive = DateTime.now();
    _gap = false;
    final result = _detector.update(incoming);
    _limiterUsable =
        _limiterForeground &&
        incoming.driving &&
        !result.rewound &&
        !_detector.awaitingRecovery;
    if (_limiter.update(
      incoming,
      settings.limiterCalibrations,
      interrupted: !_limiterUsable,
    )) {
      save();
    }
    if (result.racing != racing) {
      racing = result.racing;
      if (racing) {
        final target = settings.raceDashboard;
        if (target != null) {
          _beforeRace = currentDashboard;
          _applyDashboard(target);
        }
      } else {
        final previous = _beforeRace;
        _beforeRace = null;
        if (previous != null) _applyDashboard(previous);
      }
      if (racing && settings.autoRecord && recording == null) {
        recording = DrivingSession('udp');
        _lastSample = null;
      } else if (!racing && recording != null) {
        stopRecording();
      }
    }
    if (result.gained && settings.effects) {
      gain = true;
      _gainTimer?.cancel();
      _gainTimer = Timer(const Duration(seconds: 2), () {
        if (!_disposed) {
          gain = false;
          notifyListeners();
        }
      });
    }
    if (recording != null &&
        result.recordable &&
        (result.rewound ||
            _lastSample == null ||
            incoming.receivedAt.difference(_lastSample!).inMilliseconds >=
                95)) {
      recording!.add(incoming, confirmedRewind: result.rewound);
      _lastSample = incoming.receivedAt;
      if (_lastCheckpoint == null ||
          incoming.receivedAt.difference(_lastCheckpoint!).inSeconds >= 5) {
        _lastCheckpoint = incoming.receivedAt;
        save();
      }
      if (recording!.samples.length >= 12000) {
        stopRecording();
        notifyMessage('已达到单段录制上限，记录已保存');
      }
    }
    frame = incoming;
    if (incoming.driving) {
      navigation?.update(
        MapPoint(incoming.x, incoming.y, incoming.z),
        moving: incoming.speed > 2,
        yaw: incoming.yaw,
      );
    }
    if (notify) notifyListeners();
  }

  void startRecording() {
    if (_dataMutation) return;
    if (recording != null) return;
    if (!connected || _lastReceive == null) {
      notifyMessage('请先连接游戏');
      return;
    }
    recording = DrivingSession('udp');
    _lastSample = null;
    notifyListeners();
  }

  void stopRecording({int? rank}) {
    if (recording == null) return;
    recording!.ended = DateTime.now();
    recording!.finalPosition = rank;
    sessions.insert(0, recording!);
    if (sessions.length > 8) sessions.removeRange(8, sessions.length);
    recording = null;
    _lastSample = null;
    save();
    notifyListeners();
  }

  Future<void> connect() async {
    if (_disposed) return;
    stopRecording();
    _udp.stop();
    _connected = false;
    _connectionTimer?.cancel();
    stopNavigation();
    navigation?.resetLocation();
    racing = false;
    _beforeRace = null;
    _detector = RaceDetector();
    _previous = null;
    _limiter.interrupt();
    _limiterUsable = false;
    _lastReceive = null;
    _gap = false;
    packets = 0;
    rejected = 0;
    frame = TelemetryFrame();
    status = '正在开启 UDP';
    notifyListeners();
    try {
      addresses = await _udp.start(
        settings.port,
        (bytes) {
          if (_disposed) return;
          packets++;
          _connected = true;
          _connectionTimer?.cancel();
          _connectionTimer = Timer(const Duration(seconds: 2), () {
            if (_disposed) return;
            _connected = false;
            status = '数据中断 · 暂停或回溯待判断';
            _tick();
            notifyListeners();
          });
          try {
            status = '实验协议 · 正在接收';
            ingest(decodePacket(bytes), notify: false);
            // Publish once, including connection changes for stale packets.
            notifyListeners();
          } catch (_) {
            rejected++;
            status = '数据格式待校准';
            notifyListeners();
          }
        },
        (error) {
          _connected = false;
          _connectionTimer?.cancel();
          status = error;
          notifyListeners();
        },
      );
      if (_disposed) {
        _udp.stop();
        return;
      }
      status = '等待游戏数据';
    } catch (error) {
      _udp.stop();
      status = '连接未建立';
      notifyMessage(error.toString());
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    weekly.removeListener(_weeklyChanged);
    weekly.dispose();
    _ticker?.cancel();
    _saveTimer?.cancel();
    _gainTimer?.cancel();
    _connectionTimer?.cancel();
    _messageTimer?.cancel();
    _udp.stop();
    super.dispose();
    language.dispose();
    appearance.dispose();
  }
}
