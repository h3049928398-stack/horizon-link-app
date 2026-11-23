import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../core/road_graph.dart';
import '../core/weekly_content.dart';
import 'weekly_platform.dart' as platform;

enum WeeklyStatus { unconfigured, idle, checking, ready, failed }

class WeeklyContentService extends ChangeNotifier {
  final String url;
  final bool persist;
  final Future<String> Function(Uri) fetch;
  final Future<String?> Function() readCache;
  final Future<void> Function(String) writeCache;
  final DateTime Function() clock;
  WeeklyContent? content;
  DateTime? lastChecked;
  WeeklyStatus status = WeeklyStatus.idle;
  RoadGraph? _graph;
  String? _raw;
  bool _disposed = false, _loading = false;
  Timer? _boundary;
  WeeklyContentService({
    this.url = const String.fromEnvironment('WEEKLY_CONTENT_URL'),
    this.persist = true,
    this.fetch = platform.fetchWeekly,
    this.readCache = platform.readWeeklyCache,
    this.writeCache = platform.writeWeeklyCache,
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;

  WeeklyPeriod? get current => content?.current(clock());
  WeeklyPeriod? get displayed => current ?? content?.previous(clock());
  List<MapPlace> get mapPlaces {
    if (_graph == null || current == null) return const [];
    return [
      for (final e in current!.events)
        for (final l in e.locations)
          if (l.resolve(_graph!, e.name) case final MapPlace p) p,
    ];
  }

  Future<void> initialize(RoadGraph graph) async {
    if (_disposed || _graph != null) return;
    _graph = graph;
    _loading = true;
    if (persist) {
      try {
        final saved = await readCache();
        if (_disposed) return;
        if (saved != null) {
          final j = jsonDecode(saved) as Map<String, dynamic>;
          if (j['url'] == url) {
            final text = j['content'] as String;
            final parsed = WeeklyContent.parse(text, graph);
            final checked = DateTime.parse(j['checkedAt'] as String);
            content = parsed;
            _raw = text;
            lastChecked = checked;
          }
        }
      } catch (_) {
        /* Invalid cache never touches user settings or telemetry. */
      }
    }
    _loading = false;
    if (_disposed) return;
    status = content == null ? WeeklyStatus.idle : WeeklyStatus.ready;
    _emit();
    await refresh();
  }

  Future<void> refresh({bool force = false}) async {
    if (_disposed || _loading || _graph == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.fragment.isNotEmpty) {
      status = WeeklyStatus.unconfigured;
      _emit();
      return;
    }
    final elapsed = lastChecked == null
        ? null
        : clock().difference(lastChecked!);
    if (!force &&
        elapsed != null &&
        !elapsed.isNegative &&
        elapsed < const Duration(hours: 6)) {
      _emit();
      return;
    }
    _loading = true;
    status = WeeklyStatus.checking;
    _emit();
    try {
      final text = await fetch(uri).timeout(const Duration(seconds: 16));
      if (_disposed) return;
      final parsed = WeeklyContent.parse(text, _graph!);
      if (content != null &&
          (parsed.revision < content!.revision ||
              (parsed.revision == content!.revision && text != _raw))) {
        throw const FormatException(
          'Revision must increase for changed content',
        );
      }
      final checked = clock();
      if (persist) {
        await writeCache(
          jsonEncode({
            'url': url,
            'checkedAt': checked.toUtc().toIso8601String(),
            'content': text,
          }),
        );
      }
      if (_disposed) return;
      content = parsed;
      _raw = text;
      lastChecked = checked;
      status = WeeklyStatus.ready;
    } catch (_) {
      if (_disposed) return;
      status = WeeklyStatus.failed;
    } finally {
      _loading = false;
      if (!_disposed) _emit();
    }
  }

  void _emit() {
    if (_disposed) return;
    _boundary?.cancel();
    final now = clock();
    final boundaries = [
      for (final p in content?.periods ?? <WeeklyPeriod>[]) ...[
        p.startsAt,
        p.endsAt,
      ],
    ].where((t) => t.isAfter(now)).toList()..sort();
    if (boundaries.isNotEmpty) {
      _boundary = Timer(boundaries.first.difference(now), _emit);
    }
    notifyListeners();
  }

  void onForeground() {
    _emit();
    unawaited(refresh());
  }

  @override
  void dispose() {
    _disposed = true;
    if (fetch == platform.fetchWeekly) platform.cancelWeeklyRequests();
    _boundary?.cancel();
    super.dispose();
  }
}
