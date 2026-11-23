import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/navigation.dart';
import '../core/telemetry.dart';
import '../core/shift_lights.dart';
import 'expanded_navigation.dart';
import 'dashboard_text_cache.dart';

class CustomDashboardPainter extends CustomPainter {
  final CustomDashboard layout;
  final TelemetryFrame frame;
  final AppSettings settings;
  final NavigationState? navigation;
  final bool hasData, flashOn;
  final bool paintBackground;
  final double? shiftTargetRpm;
  final DashboardTextCache? textCache;
  CustomDashboardPainter({
    required this.layout,
    required this.frame,
    required this.settings,
    this.navigation,
    this.hasData = false,
    this.flashOn = true,
    this.shiftTargetRpm,
    this.paintBackground = true,
    this.textCache,
  });

  static Color color(String value) => Color(
    int.parse(value.substring(1), radix: 16) |
        (value.length == 7 ? 0xff000000 : 0),
  );
  Object? option(Map<String, dynamic> n, String key) =>
      n[key] ?? CustomDashboard.components[n['type']]?[key]?.fallback;
  double number(Map<String, dynamic> n, String key) =>
      (option(n, key) as num).toDouble();
  Color ink(Map<String, dynamic> n, [String key = 'color']) =>
      color(option(n, key) as String);
  bool sourceVisible(String source) =>
      (!source.startsWith('tire') || settings.tires) &&
      (!['throttle', 'brake', 'steer'].contains(source) || settings.inputs);
  double reading(String source) => switch (source) {
    'speed' => frame.speed * (settings.mph ? 2.236936 : 3.6),
    'gear' => frame.gear.toDouble(),
    'rpm' => frame.rpm,
    'maxRpm' => frame.maxRpm,
    'power' => frame.power,
    'torque' => frame.torque,
    'boost' => frame.boost,
    'fuel' => frame.fuel * 100,
    'throttle' => frame.throttle * 100,
    'brake' => frame.brake * 100,
    'steer' => frame.steer,
    'raceTime' => frame.raceTime,
    'currentLap' => frame.currentLap,
    'bestLap' => frame.bestLap,
    'lastLap' => frame.lastLap,
    'lap' => frame.lap.toDouble(),
    'position' => frame.position.toDouble(),
    'tireFL' => frame.tires[0],
    'tireFR' => frame.tires[1],
    'tireRL' => frame.tires[2],
    'tireRR' => frame.tires[3],
    _ => 0,
  };
  String formatted(String source) {
    if (!hasData) return '--';
    final value = reading(source);
    if (!value.isFinite) return '--';
    if (['raceTime', 'currentLap', 'bestLap', 'lastLap'].contains(source)) {
      return value > 0 ? lapTime(value) : '--';
    }
    if (source == 'position' && value <= 0) return '--';
    if (source == 'gear') return frame.gear == 0 ? 'R' : '${frame.gear}';
    if (source == 'lap') return '${frame.lap + 1}';
    final unit = switch (source) {
      'speed' => settings.mph ? ' mph' : ' km/h',
      'rpm' || 'maxRpm' => ' RPM',
      'power' => ' kW',
      'torque' => ' N·m',
      'boost' => ' PSI',
      'fuel' || 'throttle' || 'brake' => ' %',
      _ => source.startsWith('tire') ? ' RAW / UNIT UNVERIFIED' : '',
    };
    return '${value.toStringAsFixed(['boost', 'steer'].contains(source) ? 1 : 0)}$unit';
  }

  void text(
    Canvas c,
    String value,
    Rect box,
    double size,
    Color color, [
    String align = 'center',
  ]) {
    final textStyle = TextStyle(
      fontFamily: 'Dashboard',
      fontFamilyFallback: const ['Chinese'],
      fontSize: size,
      color: color,
    );
    final textAlign = switch (align) {
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      _ => TextAlign.center,
    };
    final p =
        textCache?.layout(
          value,
          textStyle,
          maxLines: 2,
          align: textAlign,
          maxWidth: box.width,
        ) ??
        (TextPainter(
          text: TextSpan(text: value, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: 2,
          textAlign: textAlign,
        )..layout(maxWidth: box.width));
    final scale = math.min(1.0, box.height / math.max(1, p.height));
    c.save();
    c.translate(box.left, box.top + (box.height - p.height * scale) / 2);
    c.scale(scale);
    p.paint(c, Offset.zero);
    c.restore();
    if (textCache == null) p.dispose();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.scale(size.width / 1280, size.height / 540);
    if (paintBackground) {
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 1280, 540),
        Paint()..color = color(layout.json['background']),
      );
    }
    for (final n in layout.nodes) {
      final type = n['type'] as String;
      final source = n['source'] as String?;
      if ((source != null && !sourceVisible(source)) ||
          (type == 'tires' && !settings.tires) ||
          (type == 'inputs' && !settings.inputs) ||
          (type == 'navigation' && !settings.miniNav)) {
        continue;
      }
      final r = Rect.fromLTWH(
        (n['x'] as num).toDouble(),
        (n['y'] as num).toDouble(),
        (n['width'] as num).toDouble(),
        (n['height'] as num).toDouble(),
      );
      canvas.save();
      canvas.clipRect(r);
      switch (type) {
        case 'rect':
          canvas.drawRRect(
            RRect.fromRectAndRadius(r, Radius.circular(number(n, 'radius'))),
            Paint()..color = ink(n),
          );
        case 'circle':
          canvas.drawCircle(
            r.center,
            math.min(r.width, r.height) / 2,
            Paint()..color = ink(n),
          );
        case 'line':
          canvas.drawLine(
            r.topLeft,
            r.bottomRight,
            Paint()
              ..color = ink(n)
              ..strokeWidth = number(n, 'lineWidth'),
          );
        case 'text':
        case 'value':
          text(
            canvas,
            type == 'text' ? n['text'] as String : formatted(source!),
            r,
            number(n, 'fontSize'),
            ink(n),
            option(n, 'align') as String,
          );
        case 'bar':
        case 'arc':
          final min = source == 'rpm' ? 0.0 : number(n, 'min');
          final max = source == 'rpm' ? frame.maxRpm : number(n, 'max');
          final raw = reading(source!);
          final ratio = hasData && raw.isFinite && max.isFinite && max > min
              ? ((raw - min) / (max - min)).clamp(0.0, 1.0)
              : 0.0;
          if (type == 'bar') {
            canvas.drawRect(r, Paint()..color = ink(n, 'trackColor'));
            canvas.drawRect(
              Rect.fromLTWH(r.left, r.top, r.width * ratio, r.height),
              Paint()..color = ink(n),
            );
          } else {
            final stroke = math.min(
              number(n, 'lineWidth'),
              math.min(r.width, r.height) / 2,
            );
            final arc = Rect.fromCircle(
              center: r.center,
              radius: (math.min(r.width, r.height) - stroke) / 2,
            );
            final p = Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = stroke;
            canvas.drawArc(
              arc,
              math.pi * .75,
              math.pi * 1.5,
              false,
              p..color = ink(n, 'trackColor'),
            );
            canvas.drawArc(
              arc,
              math.pi * .75,
              math.pi * 1.5 * ratio,
              false,
              p..color = ink(n),
            );
          }
        case 'shiftLights':
          final lights = ShiftLights(
            hasData ? frame.rpm : 0,
            shiftTargetRpm ?? 0,
          );
          final step = r.width / ShiftLights.count;
          for (var i = 0; i < ShiftLights.count; i++) {
            final lit = i < lights.litCount && (!lights.shiftNow || flashOn);
            final ledColor = !lit
                ? const Color(0xff263238)
                : lights.shiftNow
                ? const Color(0xff2196ff)
                : ink(n);
            canvas.drawRect(
              Rect.fromLTWH(
                r.left + i * step + 1,
                r.top,
                math.max(0, step - 2),
                r.height,
              ),
              Paint()..color = ledColor,
            );
          }
        case 'tires':
          for (var i = 0; i < 4; i++) {
            text(
              canvas,
              '${['FL', 'FR', 'RL', 'RR'][i]} ${hasData ? frame.tires[i].round() : '--'}',
              Rect.fromLTWH(
                r.left + i * r.width / 4,
                r.top,
                r.width / 4,
                r.height * .65,
              ),
              number(n, 'fontSize'),
              ink(n),
              option(n, 'align') as String,
            );
          }
          text(
            canvas,
            'RAW / UNIT UNVERIFIED',
            Rect.fromLTWH(
              r.left,
              r.top + r.height * .65,
              r.width,
              r.height * .35,
            ),
            18,
            ink(n),
            option(n, 'align') as String,
          );
        case 'inputs':
          for (var i = 0; i < 2; i++) {
            final row = Rect.fromLTWH(
              r.left,
              r.top + i * r.height / 2,
              r.width,
              r.height / 2,
            );
            text(
              canvas,
              i == 0 ? 'THROTTLE' : 'BRAKE',
              Rect.fromLTWH(row.left, row.top, row.width * .3, row.height),
              22,
              ink(n),
            );
            final track = Rect.fromLTWH(
              row.left + row.width * .32,
              row.top + row.height * .2,
              row.width * .68,
              row.height * .6,
            );
            canvas.drawRect(track, Paint()..color = const Color(0xff263238));
            final raw = i == 0 ? frame.throttle : frame.brake;
            final ratio = hasData && raw.isFinite ? raw.clamp(0.0, 1.0) : 0.0;
            canvas.drawRect(
              Rect.fromLTWH(
                track.left,
                track.top,
                track.width * ratio,
                track.height,
              ),
              Paint()..color = ink(n),
            );
          }
        case 'navigation':
          canvas.save();
          canvas.translate(r.left, r.top);
          ExpandedNavigationPainter(navigation).paint(canvas, r.size);
          canvas.restore();
          if (navigation?.location == null) {
            text(canvas, '--', r, 36, Colors.white);
          }
      }
      canvas.restore();
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomDashboardPainter oldDelegate) => true;
}
