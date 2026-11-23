part of 'dash_canvas.dart';

/// Original vector layouts; photographic references are documented in
/// docs/DASHBOARD_LAYOUTS.md. Only existing telemetry channels are displayed.
extension _RaceLayouts on DashboardPainter {
  static const _panel = Color(0xff11171b);
  static const _green = Color(0xff77ffab);
  static const _orange = Color(0xffffa348);
  String get _gear => f.gear == 0 ? 'R' : '${f.gear}';
  String get _unit => settings.mph ? 'MPH' : 'KM/H';
  String get _position => f.position > 0 ? 'P${f.position}' : '--';
  String get _lap => f.position > 0 ? '${f.lap + 1}'.padLeft(2, '0') : '--';

  void raceLayout() {
    shiftLights();
    switch (style) {
      case DashboardStyle.gt:
        _gt();
      case DashboardStyle.endurance:
        _endurance();
      case DashboardStyle.rally:
        _rally();
      default:
        break;
    }
    _footer();
  }

  void _header(String name, Color accent) {
    text('HORIZON / $name', 22, 63, 24, white, left: true, spacing: 3);
    text('${f.rpm.round()} RPM', 1130, 63, 30, accent, maxWidth: 260);
  }

  void _rpmBar(Color accent) {
    final ratio = (f.rpm / f.maxRpm.clamp(1, 100000)).clamp(0.0, 1.0);
    for (var i = 0; i < 60; i++) {
      box(
        18 + i * 20.8,
        90,
        17,
        10,
        i / 60 < ratio ? (i >= 49 ? raceRed : accent) : _panel,
      );
    }
  }

  void _gt() {
    _header('GT', raceYellow);
    _rpmBar(raceYellow);
    box(18, 118, 326, 278, _panel);
    text('CURRENT LAP', 38, 147, 22, muted, left: true, spacing: 2);
    text(lapTime(f.currentLap), 181, 200, 66, white, maxWidth: 300);
    line(38, 246, 324, 246, const Color(0xff30383d));
    text('BEST', 38, 279, 21, _green, left: true, spacing: 2);
    text(lapTime(f.bestLap), 238, 279, 36, _green, maxWidth: 190);
    text('LAST', 38, 346, 21, muted, left: true, spacing: 2);
    text(lapTime(f.lastLap), 238, 346, 36, white, maxWidth: 190);

    box(360, 118, 398, 278, raceYellow, radius: 4);
    text('GEAR', 559, 146, 22, const Color(0xff40461d), spacing: 6);
    text(_gear, 559, 273, 250, const Color(0xff080d02), maxWidth: 360);

    text('SPEED / $_unit', 1020, 145, 22, muted, spacing: 3);
    text('${speed.round()}', 1020, 246, 166, white, maxWidth: 480);
    line(784, 329, 1262, 329, const Color(0xff30383d));
    text('POS', 810, 367, 21, muted, left: true, spacing: 2);
    text(_position, 920, 367, 47, raceYellow);
    text('LAP', 1035, 367, 21, muted, left: true, spacing: 2);
    text(_lap, 1190, 367, 47, white);
  }

  void _endurance() {
    _header('ENDURANCE', raceCyan);
    const center = Offset(420, 263);
    _withUniformScale(center, () => _enduranceGauge(center));
    text(_position, 82, 157, 55, raceYellow);
    text('LAP $_lap', 82, 210, 24, muted);

    box(768, 104, 494, 104, _panel);
    text('CURRENT LAP', 788, 128, 21, muted, left: true, spacing: 2);
    text(lapTime(f.currentLap), 1015, 170, 58, white, maxWidth: 440);
    box(768, 220, 494, 82, const Color(0xff10271e));
    text('BEST', 788, 260, 23, _green, left: true, spacing: 2);
    text(lapTime(f.bestLap), 1110, 260, 46, _green, maxWidth: 270);
    box(768, 314, 494, 82, _panel);
    text('LAST', 788, 355, 23, muted, left: true, spacing: 2);
    text(lapTime(f.lastLap), 1110, 355, 46, white, maxWidth: 270);
  }

  void _enduranceGauge(Offset center) {
    text('RPM × 1000', 420, 390, 19, muted, spacing: 3);
    const start = math.pi * .8, sweep = math.pi * 1.4;
    final max = f.maxRpm.clamp(1, 100000);
    final fraction = (f.rpm / max).clamp(0.0, 1.0);
    for (var i = 0; i < 48; i++) {
      final angle = start + sweep * i / 48;
      c.drawArc(
        Rect.fromCircle(center: center, radius: 155),
        angle,
        sweep / 48 * .72,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 18
          ..color = i / 48 < fraction
              ? (i > 38 ? raceRed : raceCyan)
              : const Color(0xff202b30),
      );
    }
    for (var i = 0; i <= 8; i++) {
      final angle = start + sweep * i / 8;
      text(
        (max * i / 8000).toStringAsFixed(1).replaceFirst(RegExp(r'\.0$'), ''),
        center.dx + math.cos(angle) * 191,
        center.dy + math.sin(angle) * 191,
        23,
        muted,
      );
    }
    text('GEAR', 420, 176, 20, muted, spacing: 5);
    text(_gear, 420, 250, 150, white, maxWidth: 230);
    text('${speed.round()} $_unit', 420, 341, 42, raceCyan, maxWidth: 290);
  }

  void _rally() {
    _header('RALLY', _orange);
    _rpmBar(_orange);
    text('SPEED', 24, 142, 22, muted, left: true, spacing: 5);
    text('${speed.round()}', 415, 247, 238, white, maxWidth: 740);
    text(_unit, 760, 324, 30, _orange);
    line(18, 351, 820, 351, const Color(0xff30383d));
    text('RACE TIME  ${lapTime(f.raceTime)}', 24, 379, 28, muted, left: true);
    text('$_position  /  LAP $_lap', 660, 379, 30, white, maxWidth: 290);

    box(856, 118, 406, 278, _orange, radius: 4);
    text('GEAR', 1059, 145, 22, const Color(0xff573514), spacing: 6);
    text(_gear, 1059, 273, 250, const Color(0xff180c02), maxWidth: 370);
  }

  void _footer() {
    box(18, 412, 390, 90, _panel);
    if (settings.tires) {
      for (var i = 0; i < 4; i++) {
        final x = 66 + i * 98.0;
        text(['FL', 'FR', 'RL', 'RR'][i], x, 434, 18, muted);
        text(
          i < f.tires.length ? '${f.tires[i].round()}' : '--',
          x,
          474,
          37,
          raceCyan,
        );
      }
    } else {
      text('TORQUE', 38, 434, 18, muted, left: true, spacing: 2);
      text('${f.torque.round()} N·m', 213, 473, 37, white, maxWidth: 350);
    }

    box(424, 412, 404, 90, _panel);
    if (settings.inputs) {
      _pedal('THROTTLE', 438, 438, f.throttle, _green);
      _pedal('BRAKE', 438, 476, f.brake, raceRed);
    } else {
      text('BOOST', 444, 434, 18, muted, left: true, spacing: 2);
      text(
        '${f.boost.toStringAsFixed(1)} PSI',
        626,
        473,
        37,
        white,
        maxWidth: 360,
      );
    }

    box(844, 412, 418, 90, _panel);
    text('FUEL', 864, 434, 18, muted, left: true, spacing: 2);
    text('${(f.fuel * 100).round()} %', 936, 474, 37, white);
    line(1043, 428, 1043, 486, const Color(0xff30383d));
    text('POWER', 1065, 434, 18, muted, left: true, spacing: 2);
    text('${f.power.round()} kW', 1150, 474, 37, white, maxWidth: 190);

    text('HORIZON LINK', 22, 527, 16, muted, left: true, spacing: 3);
    text(
      settings.tires
          ? 'TIRE TEMP · RAW / UNIT UNVERIFIED'
          : 'DATA OUT · ONE WAY UDP',
      1000,
      527,
      16,
      muted,
      maxWidth: 520,
      spacing: 1,
    );
  }

  void _pedal(String label, double x, double y, double input, Color color) {
    final amount = input.clamp(0.0, 1.0);
    text(label, x, y, 18, muted, left: true);
    box(x + 105, y - 7, 198, 14, const Color(0xff263036));
    box(x + 105, y - 7, 198 * amount, 14, color);
    text('${(amount * 100).round()}', x + 350, y, 24, white);
  }
}
