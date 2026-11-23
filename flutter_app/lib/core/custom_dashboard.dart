import 'dart:convert';

/// The only language accepted by the dashboard editor. No executable expressions.
class DashboardRef {
  final String kind, id;
  const DashboardRef.builtin(this.id) : kind = 'builtin';
  const DashboardRef.custom(this.id) : kind = 'custom';
  Map<String, dynamic> toJson() => {'kind': kind, 'id': id};
  static const builtinIds = [
    'basic',
    'professional',
    'gt',
    'endurance',
    'rally',
  ];
  static DashboardRef parse(dynamic value) {
    if (value is! Map ||
        value.length != 2 ||
        value['id'] is! String ||
        !['builtin', 'custom'].contains(value['kind'])) {
      throw const FormatException('dashboard reference: expected {kind, id}');
    }
    final id = value['id'] as String;
    if (id.isEmpty ||
        id.length > 80 ||
        (value['kind'] == 'builtin' && !builtinIds.contains(id))) {
      throw const FormatException('dashboard reference: invalid id');
    }
    return value['kind'] == 'custom'
        ? DashboardRef.custom(id)
        : DashboardRef.builtin(id);
  }

  @override
  bool operator ==(Object other) =>
      other is DashboardRef && kind == other.kind && id == other.id;
  @override
  int get hashCode => Object.hash(kind, id);
}

class DashboardProperty {
  final String type, description;
  final num? min, max;
  final Object? fallback;
  const DashboardProperty(
    this.type,
    this.description, {
    this.min,
    this.max,
    this.fallback,
  });
  String get documentation =>
      '$type: $description${min == null ? '' : '; min=$min'}${max == null ? '' : '; max=$max'}${fallback == null ? '; required' : '; default=$fallback'}';
}

class CustomDashboard {
  static const maxBytes = 64 * 1024, maxNodes = 128, maxSchemes = 20;
  static const sources = {
    'speed': '车速 / speed (App km/h or mph)',
    'gear': '挡位 / gear (0=R)',
    'rpm': '转速 / RPM',
    'maxRpm': 'EngineMaxRpm (tachometer scale maximum, not limiter)',
    'power': 'kW',
    'torque': 'N·m',
    'boost': 'PSI (existing raw field)',
    'fuel': '%',
    'throttle': '%',
    'brake': '%',
    'steer': 'steering -1..1',
    'raceTime': 'race timer',
    'currentLap': 'current lap time',
    'bestLap': 'best lap time',
    'lastLap': 'last lap time',
    'lap': 'lap (existing display convention)',
    'position': 'race position',
    'tireFL': 'RAW / UNIT UNVERIFIED',
    'tireFR': 'RAW / UNIT UNVERIFIED',
    'tireRL': 'RAW / UNIT UNVERIFIED',
    'tireRR': 'RAW / UNIT UNVERIFIED',
  };
  static const geometry = {
    'x': DashboardProperty(
      'number',
      'left on 1280x540 canvas',
      min: 0,
      max: 1280,
    ),
    'y': DashboardProperty(
      'number',
      'top on 1280x540 canvas',
      min: 0,
      max: 540,
    ),
    'width': DashboardProperty('number', 'bounding width', min: 1, max: 1280),
    'height': DashboardProperty('number', 'bounding height', min: 1, max: 540),
  };
  static const color = DashboardProperty(
    'color',
    '#RRGGBB or #AARRGGBB',
    fallback: '#FFFFFF',
  );
  static const textProperties = {
    'color': color,
    'fontSize': DashboardProperty(
      'number',
      'font size in canvas units',
      min: 6,
      max: 300,
      fallback: 48,
    ),
    'align': DashboardProperty(
      'align',
      'left / center / right',
      fallback: 'center',
    ),
  };
  static const rangeProperties = {
    'source': DashboardProperty('source', 'one of sources below'),
    'min': DashboardProperty(
      'number',
      'range minimum; rpm always uses 0..EngineMaxRpm',
      min: -1000000,
      max: 1000000,
      fallback: 0,
    ),
    'max': DashboardProperty(
      'number',
      'range maximum; rpm follows EngineMaxRpm',
      min: -1000000,
      max: 1000000,
      fallback: 100,
    ),
    'color': color,
    'trackColor': DashboardProperty(
      'color',
      'unfilled track',
      fallback: '#263238',
    ),
  };
  static const components = <String, Map<String, DashboardProperty>>{
    'text': {
      'text': DashboardProperty('text', 'literal text, max 160 characters'),
      ...textProperties,
    },
    'value': {
      'source': DashboardProperty('source', 'one of sources below'),
      ...textProperties,
    },
    'rect': {
      'color': color,
      'radius': DashboardProperty(
        'number',
        'corner radius',
        min: 0,
        max: 270,
        fallback: 0,
      ),
    },
    'line': {
      'color': color,
      'lineWidth': DashboardProperty(
        'number',
        'diagonal top-left to bottom-right',
        min: 1,
        max: 40,
        fallback: 2,
      ),
    },
    'circle': {'color': color},
    'bar': {...rangeProperties},
    'arc': {
      ...rangeProperties,
      'lineWidth': DashboardProperty(
        'number',
        'stroke width',
        min: 1,
        max: 40,
        fallback: 12,
      ),
    },
    'shiftLights': {'color': color},
    'tires': {...textProperties},
    'inputs': {'color': color},
    'navigation': <String, DashboardProperty>{},
  };
  final Map<String, dynamic> json;
  CustomDashboard._(Map<String, dynamic> value)
    : json = _freeze(value) as Map<String, dynamic>;
  static dynamic _freeze(dynamic value) => value is Map<String, dynamic>
      ? Map<String, dynamic>.unmodifiable(
          value.map((k, v) => MapEntry(k, _freeze(v))),
        )
      : value is List
      ? List<dynamic>.unmodifiable(value.map(_freeze))
      : value;
  String get name => json['name'] as String;
  List<Map<String, dynamic>> get nodes =>
      (json['components'] as List).cast<Map<String, dynamic>>();
  String get code {
    final pretty = const JsonEncoder.withIndent('  ').convert(json);
    // A valid compact import must remain copyable and re-importable at the limit.
    return utf8.encode(pretty).length <= maxBytes ? pretty : jsonEncode(json);
  }

  static Never error(String path, String reason) =>
      throw FormatException('$path: $reason');
  static CustomDashboard parse(String input) {
    if (utf8.encode(input).length > maxBytes) {
      error(r'$', 'maximum 64 KiB UTF-8');
    }
    var text = input.trim();
    if (text.startsWith('```')) {
      final match = RegExp(
        r'^```(?:json)?\s*\n([\s\S]*?)\n```$',
        caseSensitive: false,
      ).firstMatch(text);
      if (match == null) {
        error(r'$', 'paste only JSON or one complete JSON code block');
      }
      text = match.group(1)!;
    }
    // Bound nesting before jsonDecode, including objects hidden in unknown fields.
    var depth = 0, quoted = false, escaped = false;
    for (final rune in text.runes) {
      if (quoted) {
        if (escaped) {
          escaped = false;
        } else if (rune == 92) {
          escaped = true;
        } else if (rune == 34) {
          quoted = false;
        }
      } else if (rune == 34) {
        quoted = true;
      } else if (rune == 123 || rune == 91) {
        if (++depth > 8) error(r'$', 'maximum JSON nesting depth is 8');
      } else if (rune == 125 || rune == 93) {
        depth--;
      }
    }
    final dynamic value;
    try {
      value = jsonDecode(text);
    } on FormatException catch (e) {
      final offset = (e.offset ?? 0).clamp(0, text.length);
      final before = text.substring(0, offset);
      error(
        r'$',
        'JSON line ${'\n'.allMatches(before).length + 1}, column ${offset - before.lastIndexOf('\n')}: ${e.message}',
      );
    }
    if (value is! Map<String, dynamic>) error(r'$', 'expected an object');
    final map = value;
    for (final k in map.keys) {
      if (!['schemaVersion', 'name', 'background', 'components'].contains(k)) {
        error(k, 'unknown property; remove it');
      }
    }
    if (map['schemaVersion'] != 1) error('schemaVersion', 'must be 1');
    if (map['name'] is! String ||
        (map['name'] as String).trim().isEmpty ||
        (map['name'] as String).length > 60) {
      error('name', 'expected 1..60 characters');
    }
    _property(
      map['background'],
      const DashboardProperty('color', 'background'),
      'background',
    );
    if (map['components'] is! List ||
        (map['components'] as List).isEmpty ||
        (map['components'] as List).length > maxNodes) {
      error('components', 'expected 1..128 components');
    }
    final nodes = map['components'] as List;
    for (var i = 0; i < nodes.length; i++) {
      final p = 'components[$i]';
      final n = nodes[i];
      if (n is! Map<String, dynamic> || !components.containsKey(n['type'])) {
        error(p, 'unsupported component type');
      }
      final node = n;
      final specs = {...geometry, ...components[node['type']]!};
      for (final k in node.keys) {
        if (k != 'type' && !specs.containsKey(k)) {
          error('$p.$k', 'unknown property; remove it');
        }
      }
      for (final entry in specs.entries) {
        if (!node.containsKey(entry.key) && entry.value.fallback != null) {
          continue;
        }
        _property(node[entry.key], entry.value, '$p.${entry.key}');
      }
      if (node['x'] + node['width'] > 1280 ||
          node['y'] + node['height'] > 540) {
        error(p, 'bounds must fit inside 1280x540');
      }
      if (['bar', 'arc'].contains(node['type']) &&
          (node['max'] ?? 100) <= (node['min'] ?? 0)) {
        error(p, 'max must be greater than min');
      }
    }
    return CustomDashboard._(map);
  }

  static void _property(dynamic v, DashboardProperty spec, String path) {
    final ok = switch (spec.type) {
      'number' => v is num && v.isFinite && v >= spec.min! && v <= spec.max!,
      'color' =>
        v is String &&
            RegExp(r'^#(?:[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$').hasMatch(v),
      'source' => v is String && sources.containsKey(v),
      'align' => ['left', 'center', 'right'].contains(v),
      'text' =>
        v is String &&
            v.length <= 160 &&
            !v.contains(RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f]')),
      _ => false,
    };
    if (!ok) error(path, 'expected ${spec.documentation}');
  }

  static final example = const JsonEncoder.withIndent('  ').convert({
    'schemaVersion': 1,
    'name': 'My cockpit',
    'background': '#05090D',
    'components': [
      {
        'type': 'rect',
        'x': 20,
        'y': 20,
        'width': 1240,
        'height': 500,
        'color': '#101D26',
        'radius': 20,
      },
      {'type': 'shiftLights', 'x': 60, 'y': 40, 'width': 1160, 'height': 35},
      {
        'type': 'text',
        'x': 60,
        'y': 100,
        'width': 400,
        'height': 50,
        'text': 'SPEED',
        'fontSize': 36,
      },
      {
        'type': 'value',
        'x': 60,
        'y': 160,
        'width': 400,
        'height': 180,
        'source': 'speed',
        'fontSize': 100,
      },
      {
        'type': 'value',
        'x': 490,
        'y': 120,
        'width': 220,
        'height': 220,
        'source': 'gear',
        'fontSize': 180,
        'color': '#E5FF43',
      },
      {'type': 'navigation', 'x': 830, 'y': 100, 'width': 330, 'height': 330},
      {
        'type': 'bar',
        'x': 60,
        'y': 360,
        'width': 650,
        'height': 24,
        'source': 'rpm',
        'color': '#59E5F3',
      },
      {'type': 'inputs', 'x': 60, 'y': 410, 'width': 650, 'height': 80},
    ],
  });
  static String prompt({bool english = false}) =>
      '''${english ? 'Create a Horizon Link native dashboard JSON. Append my design requirements below.' : '请为 Horizon Link 生成原生仪表盘 JSON。我会在末尾补充设计要求。'}
Return ONLY one JSON object, no explanations, Dart, HTML, JavaScript, markdown, formulas, URLs or external assets. This is a declarative layout, never executable code.
Root: schemaVersion=1, name (1..60 characters), background (#RRGGBB or #AARRGGBB), components (1..128). Canvas is 1280x540, aspect ratio fixed. Maximum UTF-8 64 KiB, nesting 8. Only documented properties are allowed. Components paint in array order; overlapping is allowed. Each component and its text is clipped to its box. Use large readable racing DDU typography. App handles fonts and safe rendering. No fake readings or unsupported telemetry.
Every component requires type and:
${geometry.entries.map((e) => '${e.key}: ${e.value.documentation}').join('\n')}
x+width<=1280, y+height<=540. Optional parameters use documented defaults.
Components:
${components.entries.map((e) => '${e.key}: ${e.value.entries.map((p) => '${p.key} (${p.value.documentation})').join('; ')}').join('\n')}
Sources:
${sources.entries.map((e) => '${e.key}: ${e.value}').join('\n')}
value includes App-controlled units and time formatting. Missing race position/times show --. Tire temperatures MUST retain RAW / UNIT UNVERIFIED; tire components respect tires setting; throttle/brake/steer and inputs respect inputs setting. Navigation respects miniNav and uses existing road navigation. Hidden components leave blank space. Colors and layout cannot override settings. arc is a 270-degree gauge; circle fits its bounding box; bar fills left to right. RPM range always uses live EngineMaxRpm; fuel/throttle/brake are 0..100. shiftLights uses 20 lamps and the App-calibrated shift target, starting 1500 RPM before it and flashing blue at 4 Hz at target; no lamps before calibration. The target is learned limiter minus 750 RPM in gears 1-3 or 500 RPM in gears 4-10; reverse/unknown gears have no cue. It needs no source/min/max. No scripts, arbitrary animations or interaction. No network or AI API calls in App. Use only existing telemetry; no oil/water temperature, tire pressure or invented delta.
Valid example:
$example
${english ? 'My design requirements:' : '我的设计要求：'}
''';
}

/// Strict extension validation, shared by backups and settings loading.
void validateCustomSettings(Map<String, dynamic> settings) {
  final list = settings['customDashboards'];
  final ids = <String>{};
  if (list != null) {
    if (list is! List || list.length > CustomDashboard.maxSchemes) {
      throw const FormatException('customDashboards: maximum 20 schemes');
    }
    for (final item in list) {
      if (item is! Map ||
          item.length != 2 ||
          item['id'] is! String ||
          (item['id'] as String).isEmpty ||
          (item['id'] as String).length > 80 ||
          !ids.add(item['id'])) {
        throw const FormatException(
          'customDashboards: invalid or duplicate id',
        );
      }
      CustomDashboard.parse(jsonEncode(item['layout']));
    }
  } else if (settings.containsKey('customDashboards')) {
    throw const FormatException('customDashboards: expected list');
  }
  if (settings['raceDashboard'] != null) {
    final ref = DashboardRef.parse(settings['raceDashboard']);
    if (ref.kind == 'custom' && !ids.contains(ref.id)) {
      throw const FormatException('raceDashboard: missing custom scheme');
    }
  }
}
