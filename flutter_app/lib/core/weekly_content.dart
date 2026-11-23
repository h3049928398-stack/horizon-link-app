import 'dart:convert';

import 'road_graph.dart';
import 'web_navigation.dart';

const weeklyMaxBytes = 1024 * 1024;

class WeeklyName {
  final String zh;
  final String? en;
  const WeeklyName(this.zh, [this.en]);
  String display(String language) => language == 'en' ? en ?? zh : zh;
  factory WeeklyName.parse(dynamic value) {
    final j = _object(value);
    final zh = _text(j['zh']);
    final en = j['en'] == null ? null : _text(j['en']);
    return WeeklyName(zh, en);
  }
}

class WeeklyLocation {
  final String id, source, quality;
  final WeeklyName name;
  final String? placeId;
  final MapPoint? coordinates;
  const WeeklyLocation({
    required this.id,
    required this.name,
    required this.source,
    required this.quality,
    this.placeId,
    this.coordinates,
  });

  MapPlace? resolve(RoadGraph graph, WeeklyName eventName) {
    MapPoint? point = coordinates;
    MapPlace? base;
    if (placeId != null) {
      for (final p in graph.places) {
        if (p.id == placeId) {
          base = p;
          break;
        }
      }
      if (base == null) throw const FormatException('Unknown placeId');
      point = base.point;
    }
    if (point == null) return null;
    // An unverified base place cannot be promoted by a weekly reference.
    final verified =
        quality == 'verified' && (base == null || base.quality == 'verified');
    return MapPlace(
      'weekly:$id',
      name.zh,
      '本周活动',
      point,
      nameZh: name.zh,
      nameEn: name.en ?? name.zh,
      quality: verified ? 'verified' : 'community',
      note:
          '${eventName.zh} · ${verified ? '已实测位置' : '社区坐标 · 待游戏实测'} · $source',
    );
  }
}

class WeeklyEvent {
  final String id, type;
  final WeeklyName name;
  final List<WeeklyLocation> locations;
  const WeeklyEvent(this.id, this.type, this.name, this.locations);
}

class WeeklyPeriod {
  final String id;
  final WeeklyName name;
  final DateTime startsAt, endsAt;
  final List<WeeklyEvent> events;
  const WeeklyPeriod(
    this.id,
    this.name,
    this.startsAt,
    this.endsAt,
    this.events,
  );
  bool active(DateTime now) => !now.isBefore(startsAt) && now.isBefore(endsAt);
}

class WeeklyContent {
  final int revision;
  final List<WeeklyPeriod> periods;
  final String? guideUrl;
  const WeeklyContent(this.revision, this.periods, {this.guideUrl});

  WeeklyPeriod? current(DateTime now) {
    for (final p in periods) {
      if (p.active(now)) return p;
    }
    return null;
  }

  WeeklyPeriod? previous(DateTime now) {
    final past = periods.where((p) => !now.isBefore(p.endsAt)).toList()
      ..sort((a, b) => b.endsAt.compareTo(a.endsAt));
    return past.isEmpty ? null : past.first;
  }

  factory WeeklyContent.parse(String text, RoadGraph graph) {
    if (utf8.encode(text).length > weeklyMaxBytes) {
      throw const FormatException('Weekly content too large');
    }
    final j = _object(jsonDecode(text));
    if (j['schemaVersion'] != 1 ||
        j['revision'] is! int ||
        (j['revision'] < 1 || j['revision'] > 2147483647)) {
      throw const FormatException('Unsupported schema or revision');
    }
    final guideUrl = parseWeeklyGuideUrl(j['guideUrl']);
    final ids = <String>{};
    String id(dynamic value) {
      final s = _text(value);
      if (!RegExp(r'^[a-zA-Z0-9_.-]{1,100}$').hasMatch(s) || !ids.add(s)) {
        throw const FormatException('Invalid or duplicate ID');
      }
      return s;
    }

    final periods = <WeeklyPeriod>[];
    for (final rawPeriod in _list(j['periods'])) {
      final p = _object(rawPeriod);
      final periodId = id(p['id']);
      final start = _date(p['startsAt']), end = _date(p['endsAt']);
      if (!end.isAfter(start)) throw const FormatException('Invalid period');
      final events = <WeeklyEvent>[];
      for (final rawEvent in _list(p['events'])) {
        final e = _object(rawEvent);
        final eventId = id(e['id']), name = WeeklyName.parse(e['name']);
        final type = _text(e['type']);
        if (!['seasonal', 'treasure', 'other'].contains(type)) {
          throw const FormatException('Invalid event type');
        }
        final locations = <WeeklyLocation>[];
        for (final rawLocation in _list(e['locations'])) {
          final l = _object(rawLocation);
          final locationId = id(l['id']);
          final placeId = l['placeId'] == null ? null : _text(l['placeId']);
          MapPoint? point;
          if (l['coordinates'] != null) {
            if (placeId != null) {
              throw const FormatException('Ambiguous location');
            }
            final c = _object(l['coordinates']);
            double number(String key) {
              final n = c[key];
              if (n is! num || !n.isFinite) {
                throw const FormatException('Invalid coordinate');
              }
              return n.toDouble();
            }

            point = MapPoint(number('x'), number('y'), number('z'));
            final u = 582.896 + point.x * .046504;
            final v = 499.376 - point.z * .046504;
            if (u < 0 ||
                u > 1024 ||
                v < 0 ||
                v > 1024 ||
                point.y.abs() > 10000) {
              throw const FormatException('Coordinate outside map');
            }
          }
          final quality = _text(l['quality']);
          if (!['verified', 'community', 'unknown'].contains(quality) ||
              (point == null && placeId == null && quality != 'unknown') ||
              ((point != null || placeId != null) && quality == 'unknown')) {
            throw const FormatException('Invalid location quality');
          }
          final location = WeeklyLocation(
            id: locationId,
            name: WeeklyName.parse(l['name']),
            source: _text(l['source']),
            quality: quality,
            placeId: placeId,
            coordinates: point,
          );
          location.resolve(graph, name);
          locations.add(location);
        }
        events.add(
          WeeklyEvent(eventId, type, name, List.unmodifiable(locations)),
        );
      }
      periods.add(
        WeeklyPeriod(
          periodId,
          WeeklyName.parse(p['name']),
          start,
          end,
          List.unmodifiable(events),
        ),
      );
    }
    periods.sort((a, b) => a.startsAt.compareTo(b.startsAt));
    for (var i = 1; i < periods.length; i++) {
      if (periods[i].startsAt.isBefore(periods[i - 1].endsAt)) {
        throw const FormatException('Overlapping periods');
      }
    }
    return WeeklyContent(
      j['revision'],
      List.unmodifiable(periods),
      guideUrl: guideUrl,
    );
  }
}

Map<String, dynamic> _object(dynamic value) {
  if (value is! Map<String, dynamic>) {
    throw const FormatException('Expected object');
  }
  return value;
}

List<dynamic> _list(dynamic value) {
  if (value is! List || value.length > 1000) {
    throw const FormatException('Expected bounded list');
  }
  return value;
}

String _text(dynamic value) {
  if (value is! String || value.trim().isEmpty || value.length > 1000) {
    throw const FormatException('Expected nonempty text');
  }
  return value.trim();
}

DateTime _date(dynamic value) {
  final s = _text(value);
  final m = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})(?:\.\d{1,6})?(Z|[+-]\d{2}:\d{2})$',
  ).firstMatch(s);
  if (m == null) throw const FormatException('Explicit ISO timestamp required');
  final year = int.parse(m[1]!),
      month = int.parse(m[2]!),
      day = int.parse(m[3]!);
  final hour = int.parse(m[4]!),
      minute = int.parse(m[5]!),
      second = int.parse(m[6]!);
  final date = DateTime.utc(year, month, day);
  final zone = m[7]!;
  final offsetHours = zone == 'Z' ? 0 : int.parse(zone.substring(1, 3));
  final offsetMinutes = zone == 'Z' ? 0 : int.parse(zone.substring(4, 6));
  if (year < 1 ||
      date.year != year ||
      date.month != month ||
      date.day != day ||
      hour > 23 ||
      minute > 59 ||
      second > 59 ||
      offsetMinutes > 59 ||
      offsetHours > 14 ||
      (offsetHours == 14 && offsetMinutes != 0)) {
    throw const FormatException('Invalid calendar date or timezone');
  }
  return DateTime.parse(s).toUtc();
}
