import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../core/replay.dart';
import '../core/telemetry.dart';
import 'app_theme.dart';
import 'dash_canvas.dart';

enum ReplayChannel {
  speed('车速', raceCyan),
  throttle('油门', appAccent),
  brake('刹车', raceRed),
  steer('转向', Color(0xffffb75e)),
  rpm('转速', Color(0xffc59bff)),
  gear('挡位', Colors.white),
  power('功率', Color(0xff67b5ff)),
  torque('扭矩', Color(0xffff86bd)),
  boost('增压', Color(0xffffdb78)),
  fuel('燃油', Color(0xff68dfb1)),
  position('名次', Color(0xffc5bcff)),
  tireFL('轮胎前左', Color(0xff4dcdd1)),
  tireFR('轮胎前右', Color(0xff76a8ff)),
  tireRL('轮胎后左', Color(0xffe3a5f5)),
  tireRR('轮胎后右', Color(0xfff7a38f));

  final String label;
  final Color color;
  const ReplayChannel(this.label, this.color);

  String unit(bool mph) => switch (this) {
    speed => mph ? 'mph' : 'km/h',
    throttle || brake || steer || fuel => '%',
    rpm => 'rpm',
    power => 'kW',
    torque => 'Nm',
    _ => '',
  };

  double value(TelemetryFrame f, bool mph) => switch (this) {
    speed => f.speed * (mph ? 2.236936 : 3.6),
    throttle => f.throttle * 100,
    brake => f.brake * 100,
    steer => f.steer * 100,
    rpm => f.rpm,
    gear => f.gear.toDouble(),
    power => f.power,
    torque => f.torque,
    boost => f.boost,
    fuel => f.fuel * 100,
    position => f.position.toDouble(),
    tireFL => f.tires.elementAtOrNull(0) ?? 0,
    tireFR => f.tires.elementAtOrNull(1) ?? 0,
    tireRL => f.tires.elementAtOrNull(2) ?? 0,
    tireRR => f.tires.elementAtOrNull(3) ?? 0,
  };

  String display(TelemetryFrame f, bool mph) {
    final v = value(f, mph);
    if (!v.isFinite) return '--';
    if (this == gear && v == 0) return 'R';
    if (this == position && v <= 0) return '--';
    return '${this == boost ? v.toStringAsFixed(2) : v.round()}${unit(mph).isEmpty ? '' : ' ${unit(mph)}'}';
  }
}

/// Stable per-channel ranges and paths are computed from the detached snapshot.
/// Playback only moves a clip and cursor, avoiding rebuilding 12,000-point paths.
class ReplayChartData {
  final ReplayTimeline timeline;
  final bool mph;
  final Map<ReplayChannel, (double, double)> _ranges = {};
  final Map<ReplayChannel, Path> _paths = {};
  Size? _pathSize;
  ReplayChartData(this.timeline, {this.mph = false});

  (double, double) range(ReplayChannel channel) =>
      _ranges.putIfAbsent(channel, () {
        if ([
          ReplayChannel.throttle,
          ReplayChannel.brake,
          ReplayChannel.fuel,
        ].contains(channel)) {
          return (0, 100);
        }
        if (channel == ReplayChannel.steer) return (-100, 100);
        var low = 0.0,
            high = channel == ReplayChannel.speed ? (mph ? 120.0 : 200.0) : 1.0;
        for (final sample in timeline.samples) {
          final value = channel.value(sample.frame, mph);
          if (value.isFinite) {
            low = math.min(low, value);
            high = math.max(high, value);
          }
        }
        return (low, high);
      });

  double normalized(ReplayChannel channel, TelemetryFrame frame) {
    final (low, high) = range(channel);
    return ((channel.value(frame, mph) - low) / (high - low)).clamp(0.0, 1.0);
  }

  Path path(ReplayChannel channel, Size size) {
    if (_pathSize != size) {
      _paths.clear();
      _pathSize = size;
    }
    return _paths.putIfAbsent(channel, () {
      final result = Path();
      var connected = false;
      for (var i = 0; i < timeline.samples.length; i++) {
        final frame = timeline.samples[i].frame;
        if (!channel.value(frame, mph).isFinite) {
          connected = false;
          continue;
        }
        final x =
            timeline.times[i] / math.max(timeline.duration, .001) * size.width;
        final y = (1 - normalized(channel, frame)) * size.height;
        if (!connected || timeline.breaks.contains(i)) {
          result.moveTo(x, y);
        } else {
          result.lineTo(x, y);
        }
        connected = true;
      }
      return result;
    });
  }
}

class ReplayChartPainter extends CustomPainter {
  final ReplayChartData data;
  final Set<ReplayChannel> channels;
  final int index;
  ReplayChartPainter(this.data, this.channels, this.index);

  static Rect plotRect(Size size) => Rect.fromLTRB(
    30,
    6,
    math.max(31, size.width - 8),
    math.max(7, size.height - 18),
  );

  @override
  void paint(Canvas canvas, Size size) {
    // CustomPaint may share a canvas with the header and map. Never clear
    // the ancestor canvas or let plot labels draw over sibling controls.
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    try {
      _paintChart(canvas, size);
    } finally {
      canvas.restore();
    }
  }

  void _paintChart(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = appSurface);
    final rect = plotRect(size);
    final grid = Paint()
      ..color = const Color(0xff343944)
      ..strokeWidth = .7;
    for (final percent in [0, 50, 100]) {
      final y = rect.bottom - rect.height * percent / 100;
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), grid);
      _label(canvas, '$percent%', Offset(0, y - 5));
    }
    _label(canvas, '0s', Offset(rect.left, rect.bottom + 4));
    final durationLabel = '${data.timeline.duration.toStringAsFixed(1)}s';
    _label(
      canvas,
      durationLabel,
      Offset(rect.right, rect.bottom + 4),
      right: true,
    );
    if (index < 0 || channels.isEmpty) return;
    final frame = data.timeline.samples[index].frame;
    final x =
        rect.left +
        data.timeline.times[index] /
            math.max(data.timeline.duration, .001) *
            rect.width;
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        rect.left - 2,
        rect.top - 2,
        math.min(rect.right + 2, x + .01),
        rect.bottom + 2,
      ),
    );
    canvas.translate(rect.left, rect.top);
    for (final channel in channels) {
      canvas.drawPath(
        data.path(channel, rect.size),
        Paint()
          ..color = channel.color
          ..strokeWidth = 1.6
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round,
      );
    }
    canvas.restore();
    canvas.drawLine(
      Offset(x, rect.top),
      Offset(x, rect.bottom),
      Paint()
        ..color = Colors.white54
        ..strokeWidth = 1,
    );
    for (final channel in channels) {
      if (!channel.value(frame, data.mph).isFinite) continue;
      final y = rect.bottom - data.normalized(channel, frame) * rect.height;
      canvas.drawCircle(Offset(x, y), 2.5, Paint()..color = channel.color);
    }
  }

  void _label(
    Canvas canvas,
    String text,
    Offset position, {
    bool right = false,
  }) {
    final label = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          fontSize: 9,
          color: appMuted,
          fontFamily: 'Dashboard',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, position - Offset(right ? label.width : 0, 0));
  }

  @override
  bool shouldRepaint(covariant ReplayChartPainter old) =>
      old.data != data ||
      old.index != index ||
      !setEquals(old.channels, channels);
}
