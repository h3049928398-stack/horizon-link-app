import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n.dart';
import '../core/navigation.dart';
import '../core/telemetry.dart';
import '../core/shift_lights.dart';
import 'expanded_navigation.dart';
import 'custom_dashboard_canvas.dart';
import 'dashboard_text_cache.dart';

part 'race_layouts.dart';

const raceYellow = Color(0xffe5ff43),
    raceCyan = Color(0xff59e5f3),
    raceRed = Color(0xffff4f50);

class DashCanvas extends StatefulWidget {
  static const designSize = Size(1280, 540);

  static Color backdrop(CustomDashboard? layout) => layout == null
      ? DashboardPainter.background
      : Color.alphaBlend(
          CustomDashboardPainter.color(layout.json['background']),
          Colors.black,
        );

  final CustomDashboard? customLayout;
  final bool hasData;
  final bool paintBackground;
  final double? shiftTargetRpm;
  final TelemetryFrame frame;
  final AppSettings settings;
  final DashboardStyle style;
  final String? destination;
  final NavigationState? navigation;
  const DashCanvas({
    super.key,
    required this.frame,
    required this.settings,
    required this.style,
    this.destination,
    this.navigation,
    this.customLayout,
    this.hasData = true,
    this.shiftTargetRpm,
    this.paintBackground = true,
  });
  @override
  State<DashCanvas> createState() => _DashCanvasState();
}

class _DashCanvasState extends State<DashCanvas> with WidgetsBindingObserver {
  final _textCache = DashboardTextCache();
  Timer? _flashTimer;
  bool _flashOn = true;
  bool _tickerEnabled = true;
  bool _foreground = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  void _fontsChanged() {
    _textCache.clear();
    if (mounted) setState(() {});
  }

  void _syncFlash() {
    final flashing =
        _foreground &&
        _tickerEnabled &&
        widget.style.isProfessional &&
        (widget.customLayout == null ||
            (widget.hasData &&
                widget.customLayout!.nodes.any(
                  (n) => n['type'] == 'shiftLights',
                ))) &&
        widget.hasData &&
        ShiftLights(widget.frame.rpm, widget.shiftTargetRpm ?? 0).shiftNow;
    if (flashing && _flashTimer == null) {
      _flashOn = true;
      // 125 ms on + 125 ms off = four complete flashes per second.
      _flashTimer = Timer.periodic(const Duration(milliseconds: 125), (_) {
        setState(() => _flashOn = !_flashOn);
      });
    } else if (!flashing) {
      _flashTimer?.cancel();
      _flashTimer = null;
      _flashOn = true;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    _syncFlash();
  }

  @override
  void didUpdateWidget(DashCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFlash();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    setState(_syncFlash);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _textCache.clear();
    _flashTimer?.cancel();
    super.dispose();
  }

  TelemetryFrame get frame => widget.frame;
  AppSettings get settings => widget.settings;
  DashboardStyle get style => widget.style;

  @override
  Widget build(BuildContext context) => Semantics(
    label: widget.customLayout != null && !widget.hasData
        ? '${widget.customLayout!.name} · ${localize('等待游戏数据', settings.language)}'
        : localize(
            '${style.shortTitle}仪表，车速 ${(frame.speed * (settings.mph ? 2.236936 : 3.6)).round()} ${settings.mph ? 'mph' : 'km/h'}，挡位 ${frame.gear == 0 ? 'R' : frame.gear}，转速 ${frame.rpm.round()}',
            settings.language,
          ),
    child: CustomPaint(
      painter: widget.customLayout != null
          ? CustomDashboardPainter(
              layout: widget.customLayout!,
              frame: frame,
              settings: settings,
              navigation: widget.navigation,
              hasData: widget.hasData,
              flashOn: _flashOn,
              textCache: _textCache,
              shiftTargetRpm: widget.shiftTargetRpm,
              paintBackground: widget.paintBackground,
            )
          : DashboardPainter(
              frame,
              settings,
              style,
              widget.destination,
              widget.navigation,
              _flashOn,
              _textCache,
              widget.hasData ? widget.shiftTargetRpm : null,
              widget.paintBackground,
            ),
      size: DashCanvas.designSize,
    ),
  );
}

class DashboardPainter extends CustomPainter {
  static const background = Color(0xff030405);
  final TelemetryFrame f;
  final AppSettings settings;
  final DashboardStyle style;
  final String? destination;
  final NavigationState? navigation;
  final bool shiftFlashOn;
  final DashboardTextCache? textCache;
  final double? shiftTargetRpm;
  final bool paintBackground;
  late Canvas c;
  Offset _shapeScale = const Offset(1, 1);
  DashboardPainter(
    this.f,
    this.settings,
    this.style,
    this.destination, [
    this.navigation,
    this.shiftFlashOn = true,
    this.textCache,
    this.shiftTargetRpm,
    this.paintBackground = true,
  ]);
  final white = const Color(0xfff4f5f1), muted = const Color(0xff92999c);
  double get speed => f.speed * (settings.mph ? 2.236936 : 3.6);
  void text(
    String value,
    double x,
    double y,
    double size,
    Color color, {
    bool left = false,
    double spacing = 0,
    String? family,
    double maxWidth = double.infinity,
  }) {
    final textStyle = TextStyle(
      fontFamily: family ?? 'Dashboard',
      fontFamilyFallback: const ['Chinese'],
      fontSize: size,
      fontWeight: FontWeight.w600,
      color: color,
      letterSpacing: spacing,
      height: 1,
    );
    final translated = localize(value, settings.language);
    final p =
        textCache?.layout(
          translated,
          textStyle,
          maxWidth: maxWidth,
          ellipsis: maxWidth.isFinite ? '…' : null,
        ) ??
        (TextPainter(
          text: TextSpan(text: translated, style: textStyle),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: maxWidth.isFinite ? '…' : null,
        )..layout(maxWidth: maxWidth));
    _withUniformScale(Offset(x, y), () {
      p.paint(c, Offset(left ? x : x - p.width / 2, y - p.height / 2));
    });
    if (textCache == null) p.dispose();
  }

  // Let the dashboard grid fill the viewport while keeping glyphs, gauges
  // and maps proportional around their layout anchors.
  void _withUniformScale(Offset anchor, VoidCallback draw) {
    const identity = Offset(1, 1);
    final scale = _shapeScale;
    if (scale == identity) {
      draw();
      return;
    }
    c.save();
    c.translate(anchor.dx, anchor.dy);
    c.scale(scale.dx, scale.dy);
    c.translate(-anchor.dx, -anchor.dy);
    _shapeScale = identity;
    draw();
    _shapeScale = scale;
    c.restore();
  }

  void box(
    double x,
    double y,
    double w,
    double h,
    Color color, {
    double radius = 0,
  }) {
    final rect = Rect.fromLTWH(x, y, w, h);
    final paint = Paint()..color = color;
    if (radius > 0) {
      c.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        paint,
      );
    } else {
      c.drawRect(rect, paint);
    }
  }

  void line(
    double x1,
    double y1,
    double x2,
    double y2,
    Color color, [
    double width = 1,
  ]) => c.drawLine(
    Offset(x1, y1),
    Offset(x2, y2),
    Paint()
      ..color = color
      ..strokeWidth = width,
  );
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    c = canvas;
    c.save();
    final bounds = Offset.zero & size;
    c.clipRect(bounds);
    if (paintBackground) c.drawRect(bounds, Paint()..color = background);
    final scaleX = size.width / DashCanvas.designSize.width;
    final scaleY = size.height / DashCanvas.designSize.height;
    final uniform = math.min(scaleX, scaleY);
    _shapeScale = (scaleX - scaleY).abs() < 1e-9
        ? const Offset(1, 1)
        : Offset(uniform / scaleX, uniform / scaleY);
    c.scale(scaleX, scaleY);
    if (style == DashboardStyle.basic) {
      if (settings.expandedNav) {
        c.save();
        c.translate(0, 70.2);
        c.scale(.74);
        basic();
        c.restore();
        _withUniformScale(expandedNavigationRect.center, () {
          c.save();
          c.translate(expandedNavigationRect.left, expandedNavigationRect.top);
          ExpandedNavigationPainter(navigation)
              .paint(c, expandedNavigationRect.size);
          c.restore();
        });
        if (navigation?.location == null) {
          text('等待车辆定位', 1115, 270, 20, muted, family: 'Chinese');
        }
      } else {
        basic();
      }
    } else if (style == DashboardStyle.professional) {
      professional();
    } else {
      raceLayout();
    }
    c.restore();
  }

  void dial(
    double x,
    double y,
    double radius,
    double value,
    double max,
    String label,
    String unit,
    Color accent, {
    bool rpm = false,
  }) => _withUniformScale(Offset(x, y), () {
    const start = math.pi * .75, sweep = math.pi * 1.5;
    c.drawArc(
      Rect.fromCircle(center: Offset(x, y), radius: radius),
      start,
      sweep,
      false,
      Paint()
        ..color = const Color(0xff1a1e21)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke,
    );
    final fraction = (value / max).clamp(0.0, 1.0);
    c.drawArc(
      Rect.fromCircle(center: Offset(x, y), radius: radius - 5),
      start,
      sweep * fraction,
      false,
      Paint()
        ..color = accent.withValues(alpha: .55)
        ..strokeWidth = 4
        ..style = PaintingStyle.stroke,
    );
    final ticks = rpm ? 45 : 64, major = rpm ? 5 : 8;
    for (var i = 0; i <= ticks; i++) {
      final angle = start + sweep * i / ticks, large = i % major == 0;
      final red = i / ticks > .8 && rpm;
      final outer = radius - 14, inner = outer - (large ? 23 : 11);
      final color = red
          ? raceRed
          : large
          ? white
          : const Color(0xff626a70);
      line(
        x + math.cos(angle) * inner,
        y + math.sin(angle) * inner,
        x + math.cos(angle) * outer,
        y + math.sin(angle) * outer,
        color,
        large ? 3 : 1.5,
      );
      if (large) {
        final number = rpm
            ? (i / major).round().toString()
            : (max * i / ticks).round().toString();
        text(
          number,
          x + math.cos(angle) * (radius - 58),
          y + math.sin(angle) * (radius - 58),
          29,
          red ? raceRed : white,
        );
      }
    }
    final angle = start + sweep * fraction;
    final tip = Offset(
      x + math.cos(angle) * (radius - 35),
      y + math.sin(angle) * (radius - 35),
    );
    c.drawLine(
      Offset(x - math.cos(angle) * 17, y - math.sin(angle) * 17),
      tip,
      Paint()
        ..color = accent
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round,
    );
    c.drawCircle(Offset(x, y), 8, Paint()..color = white);
    text(
      rpm ? value.toStringAsFixed(1) : value.round().toString(),
      x,
      y + 68,
      76,
      white,
    );
    text(unit, x, y + 118, 22, muted, spacing: 2);
    text(label, x, y - 74, 19, muted, spacing: 3);
  });

  void basic() {
    text('HORIZON', 42, 29, 20, muted, left: true, spacing: 4);
    text('STREET / 01', 1238, 29, 19, muted);
    dial(
      282,
      258,
      205,
      f.rpm / 1000,
      9,
      'ENGINE',
      '×1000 RPM',
      raceRed,
      rpm: true,
    );
    // Digital engine RPM is printed below the gauge for an exact reading.
    text('${f.rpm.round()} RPM', 282, 450, 23, muted, spacing: 1);
    dial(
      998,
      258,
      205,
      speed,
      settings.mph ? 200 : 320,
      'SPEED',
      settings.mph ? 'MPH' : 'KM/H',
      raceCyan,
    );
    text('GEAR', 640, 141, 23, muted, spacing: 5);
    text(f.gear == 0 ? 'R' : '${f.gear}', 640, 265, 194, white);
    for (var i = 0; i < 12; i++) {
      final target = shiftTargetRpm ?? 0;
      final active =
          target.isFinite && target > 0 && f.rpm > 0 && i / 12 < f.rpm / target;
      box(
        526 + i * 20,
        76,
        13,
        8,
        active ? (i > 8 ? raceRed : raceYellow) : const Color(0xff262b2f),
        radius: 2,
      );
    }
    if (settings.miniNav && !settings.expandedNav) {
      _withUniformScale(const Offset(640, 432), _miniNavigation);
    } else {
      text('FUEL', 640, 391, 18, muted, spacing: 2);
      text('${(f.fuel * 100).round()} %', 640, 426, 34, white);
    }
    line(45, 477, 1235, 477, const Color(0xff303439));
    final entries = [
      ('POWER', '${f.power.round()}', 'kW'),
      ('TORQUE', '${f.torque.round()}', 'N·m'),
      ('BOOST', f.boost.toStringAsFixed(1), 'PSI'),
      ('FUEL', '${(f.fuel * 100).round()}', '%'),
    ];
    for (var i = 0; i < entries.length; i++) {
      final x = 92 + i * 315.0;
      text(entries[i].$1, x, 505, 17, muted, left: true, spacing: 2);
      text(entries[i].$2, x + 139, 505, 36, white);
      text(entries[i].$3, x + 195, 509, 17, muted);
    }
  }

  void _miniNavigation() {
    if (navigation?.route != null) {
      final n = navigation!,
          r = n.route!,
          origin = n.location ?? r.at(n.progress),
          heading = n.heading ?? 0;
      final path = Path();
      // Preview up to 1.2 km in the larger, heading-up window.
      for (var i = 0; i <= 60; i++) {
        final p = r.at(math.min(r.length, n.progress + i * 20));
        final dx = p.x - origin.x, dz = p.z - origin.z;
        final x = 640 + (dx * math.cos(heading) - dz * math.sin(heading)) * .08;
        final y = 432 - (dx * math.sin(heading) + dz * math.cos(heading)) * .08;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      c.save();
      c.clipRect(const Rect.fromLTWH(530, 337, 220, 108));
      c.drawPath(
        path,
        Paint()
          ..color = raceCyan
          ..strokeWidth = 4.5
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
      c.restore();
    } else {
      text(destination ?? '未设置目的地', 640, 460, 18, muted, family: 'Chinese');
    }
    // Heading-up view: rotate only the route, never the vehicle marker.
    final arrow = Path()
      ..moveTo(640, 419)
      ..lineTo(649, 441)
      ..lineTo(640, 437)
      ..lineTo(631, 441)
      ..close();
    c.drawPath(
      arrow,
      Paint()
        ..color = const Color(0xff030405)
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = 3,
    );
    c.drawPath(arrow, Paint()..color = white);
    if (navigation?.route != null) {
      text(destination ?? '', 640, 460, 17, muted, family: 'Chinese');
    }
  }

  void shiftLights() {
    final lights = ShiftLights(f.rpm, shiftTargetRpm ?? 0);
    for (var i = 0; i < 20; i++) {
      final color = lights.shiftNow
          ? const Color(0xff308bff)
          : i < 9
          ? const Color(0xff5eff67)
          : i < 14
          ? raceYellow
          : raceRed;
      final on = i < lights.litCount && (!lights.shiftNow || shiftFlashOn);
      box(
        21 + i * 62,
        12,
        48,
        18,
        on ? color : color.withValues(alpha: .13),
        radius: 3,
      );
    }
  }

  void professional() {
    shiftLights();
    text('HORIZON  /  RACE', 24, 63, 24, white, left: true, spacing: 3);
    text('${f.rpm.round()} RPM', 650, 62, 33, raceYellow);
    text('LIVE TELEMETRY', 1120, 63, 20, muted, spacing: 2);
    for (var i = 0; i < 80; i++) {
      box(
        18 + i * 15.6,
        86,
        12,
        8,
        i / 80 < f.rpm / f.maxRpm.clamp(1, 100000)
            ? (i > 65 ? raceRed : raceCyan)
            : const Color(0xff22292b),
      );
    }

    box(18, 114, 292, 235, white);
    text('SPEED', 43, 144, 24, const Color(0xff444a4e), left: true, spacing: 3);
    text(speed.round().toString(), 164, 244, 160, const Color(0xff070909));
    text(settings.mph ? 'MPH' : 'KM/H', 267, 323, 21, const Color(0xff444a4e));
    line(328, 114, 328, 493, const Color(0xff394047));
    text('GEAR', 584, 135, 23, muted, spacing: 6);
    text(f.gear == 0 ? 'R' : '${f.gear}', 582, 255, 246, white);
    text('POWER  ${f.power.round()} kW', 582, 369, 28, raceCyan, spacing: 1);
    line(837, 114, 837, 493, const Color(0xff394047));

    text('CURRENT LAP', 863, 140, 22, muted, left: true, spacing: 3);
    text(lapTime(f.currentLap), 1058, 201, 72, white);
    box(857, 256, 403, 66, const Color(0xff192e20));
    text('BEST', 873, 290, 22, const Color(0xff8aa993), left: true, spacing: 2);
    text(lapTime(f.bestLap), 1124, 291, 41, const Color(0xff77ffab));
    text('LAST', 874, 349, 22, muted, left: true, spacing: 2);
    text(lapTime(f.lastLap), 1123, 351, 38, white);

    box(18, 365, 139, 128, raceYellow);
    text('POSITION', 87, 389, 20, const Color(0xff465019), spacing: 1);
    text(
      f.position > 0 ? 'P${f.position}' : '--',
      87,
      445,
      72,
      const Color(0xff0b1000),
    );
    box(172, 365, 138, 128, const Color(0xff20272a));
    text('LAP', 241, 389, 20, muted, spacing: 2);
    text(
      f.position > 0 ? '${f.lap + 1}'.padLeft(2, '0') : '--',
      241,
      445,
      72,
      white,
    );
    if (settings.inputs) {
      text('THROTTLE', 350, 422, 18, muted, left: true);
      box(459, 412, 335, 12, const Color(0xff202b27));
      box(459, 412, 335 * f.throttle.clamp(0, 1), 12, const Color(0xff55f897));
      text('BRAKE', 350, 459, 18, muted, left: true);
      box(459, 450, 335, 12, const Color(0xff302020));
      box(459, 450, 335 * f.brake.clamp(0, 1), 12, raceRed);
    } else {
      text('TORQUE', 582, 420, 20, muted, spacing: 3);
      text('${f.torque.round()} N·m', 582, 459, 42, white);
    }
    if (settings.tires) {
      for (var i = 0; i < 4; i++) {
        final x = 857 + i * 103.0;
        box(x, 392, 94, 101, const Color(0xff151c1f));
        text(['FL', 'FR', 'RL', 'RR'][i], x + 47, 413, 19, muted);
        text('${f.tires[i].round()}', x + 47, 455, 43, raceCyan);
      }
    } else {
      text(
        'FUEL ${(f.fuel * 100).round()} %   /   BOOST ${f.boost.toStringAsFixed(1)} PSI',
        1056,
        444,
        28,
        white,
      );
    }
    line(18, 510, 1262, 510, const Color(0xff3b4145));
    text(
      'RACE TIME  ${lapTime(f.raceTime)}',
      22,
      530,
      18,
      muted,
      left: true,
      spacing: 1,
    );
    text(
      settings.tires
          ? 'TIRE TEMP · RAW / UNIT UNVERIFIED'
          : 'DATA OUT · ONE WAY UDP',
      1063,
      530,
      16,
      muted,
      spacing: 1,
    );
  }

  @override
  bool shouldRepaint(covariant DashboardPainter oldDelegate) => true;
}
