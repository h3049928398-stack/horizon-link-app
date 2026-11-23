import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../widgets/ios_options.dart';

import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/racing.dart';
import '../core/replay.dart';
import '../core/telemetry.dart';
import '../widgets/app_theme.dart';
import '../widgets/dash_canvas.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/replay_chart.dart';

class ReplayPage extends StatefulWidget {
  final DrivingSession session;
  final bool mph;
  const ReplayPage({super.key, required this.session, this.mph = false});

  @override
  State<ReplayPage> createState() => _ReplayPageState();
}

class _ReplayPageState extends State<ReplayPage>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late final ReplayTimeline timeline;
  late final ReplayTrack track;
  late final ReplayChartData chart;
  Set<ReplayChannel> channels = {ReplayChannel.speed, ReplayChannel.throttle};
  late final Ticker ticker;
  ui.Image? map;
  Duration lastTick = Duration.zero;
  double seconds = 0, rate = 1;
  bool playing = false;

  @override
  void initState() {
    super.initState();
    timeline = ReplayTimeline(widget.session);
    track = ReplayTrack(timeline);
    chart = ReplayChartData(timeline, mph: widget.mph);
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
    ticker = createTicker((elapsed) {
      final delta = (elapsed - lastTick).inMicroseconds / 1000000;
      lastTick = elapsed;
      setState(() {
        seconds = math.min(timeline.duration, seconds + delta * rate);
        if (seconds >= timeline.duration) _pause();
      });
    });
    WidgetsBinding.instance.addObserver(this);
    _loadMap();
  }

  Future<void> _loadMap() async {
    try {
      final bytes = await rootBundle.load('assets/map/map_summer.jpg');
      final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
      final image = (await codec.getNextFrame()).image;
      codec.dispose();
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() => map = image);
    } catch (_) {
      // The coordinate track remains usable if the optional background fails.
    }
  }

  void _pause() {
    ticker.stop();
    playing = false;
  }

  void _seek(double value) => setState(() {
    _pause();
    seconds = value.clamp(0, timeline.duration);
  });

  void _toggle() => setState(() {
    if (playing) {
      _pause();
    } else if (timeline.duration > 0) {
      if (seconds >= timeline.duration) seconds = 0;
      lastTick = Duration.zero;
      playing = true;
      ticker.start();
    }
  });

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && playing) {
      setState(_pause);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ticker.dispose();
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    map?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final index = timeline.indexAt(seconds);
    final frame = timeline.frameAt(seconds);
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: Row(
                children: [
                  IconButton(
                    tooltip: context.tr('退出回放'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  ),
                  const Expanded(
                    child: LText(
                      '比赛轨迹回放',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  LText(
                    widget.session.source == 'demo'
                        ? '历史测试记录 · 回放'
                        : '本地记录 · 回放',
                    style: TextStyle(fontSize: 10, color: context.appAccent),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    index < 0
                        ? '0 / 0'
                        : '${index + 1} / ${timeline.samples.length}',
                    key: const ValueKey('replay-sample'),
                    style: TextStyle(fontSize: 10, color: context.appMuted),
                  ),
                  IconButton(
                    tooltip: context.tr('采样详情'),
                    onPressed: frame == null ? null : () => _showDetails(frame),
                    icon: const Icon(Icons.info_outline_rounded, size: 19),
                  ),
                ],
              ),
            ),
            Expanded(
              child: frame == null
                  ? const Center(child: LText('暂无可回放采样'))
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < constraints.maxHeight) {
                          return const Center(child: LText('请横屏查看回放'));
                        }
                        final inputHeight = (constraints.maxHeight * .37).clamp(
                          96.0,
                          142.0,
                        );
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 6,
                                child: ClipRRect(
                                  key: const ValueKey('replay-map-panel'),
                                  borderRadius: BorderRadius.circular(14),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      RepaintBoundary(
                                        child: CustomPaint(
                                          key: const ValueKey('replay-track'),
                                          painter: ReplayTrackPainter(
                                            track,
                                            index,
                                            map,
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        left: 10,
                                        top: 8,
                                        child: DecoratedBox(
                                          decoration: BoxDecoration(
                                            color: Colors.black54,
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            child: Text(
                                              '${(frame.speed * (widget.mph ? 2.236936 : 3.6)).round()} ${widget.mph ? 'mph' : 'km/h'}',
                                              key: const ValueKey(
                                                'replay-speed',
                                              ),
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontFamily: 'Dashboard',
                                                color: Colors.white,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                      if (track.points[index] == null ||
                                          !track.hasMovement)
                                        Center(
                                          child: Card(
                                            child: Padding(
                                              padding: const EdgeInsets.all(10),
                                              child: LText(
                                                track.points[index] == null
                                                    ? '此采样无有效驾驶位置'
                                                    : '轨迹位置未变化',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                flex: 4,
                                child: Column(
                                  children: [
                                    Expanded(child: _chartPanel(index, frame)),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      height: inputHeight,
                                      child: _inputs(frame),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            if (frame != null) _transport(index),
          ],
        ),
      ),
    );
  }

  Widget _transport(int index) => SizedBox(
    height: 54,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          IconButton(
            tooltip: context.tr('重新开始'),
            onPressed: () => _seek(0),
            icon: const Icon(Icons.replay_rounded, size: 21),
          ),
          IconButton(
            tooltip: context.tr('上一采样'),
            onPressed: index > 0
                ? () => _seek(timeline.times[index - 1])
                : null,
            icon: const Icon(Icons.skip_previous_rounded, size: 22),
          ),
          FilledButton(
            key: const ValueKey('replay-play'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 40),
              padding: EdgeInsets.zero,
            ),
            onPressed: timeline.duration > 0 ? _toggle : null,
            child: Tooltip(
              message: context.tr(playing ? '暂停回放' : '播放回放'),
              child: Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 24,
              ),
            ),
          ),
          IconButton(
            tooltip: context.tr('下一采样'),
            onPressed: index + 1 < timeline.samples.length
                ? () => _seek(timeline.times[index + 1])
                : null,
            icon: const Icon(Icons.skip_next_rounded, size: 22),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 76,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _clock(seconds),
                    key: const ValueKey('replay-time'),
                    maxLines: 1,
                    style: const TextStyle(
                      fontFamily: 'Dashboard',
                      fontSize: 17,
                    ),
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    _clock(timeline.duration),
                    maxLines: 1,
                    style: TextStyle(
                      fontFamily: 'Dashboard',
                      fontSize: 11,
                      color: context.appMuted,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Slider(
              key: const ValueKey('replay-progress'),
              value: seconds,
              max: math.max(timeline.duration, .001),
              onChanged: timeline.duration > 0 ? _seek : null,
              label: _clock(seconds),
            ),
          ),
          DropdownButton<double>(
            key: const ValueKey('replay-rate'),
            value: rate,
            underline: const SizedBox.shrink(),
            onChanged: (value) => setState(() => rate = value!),
            items: [
              for (final value in [.5, 1.0, 2.0, 4.0])
                DropdownMenuItem(
                  value: value,
                  child: Text(
                    '${value % 1 == 0 ? value.toInt() : value}×',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
            ],
          ).forPhone(
            context,
            Localizations.localeOf(context).languageCode == 'en'
                ? 'Playback speed'
                : '回放速度',
          ),
        ],
      ),
    ),
  );

  Widget _chartPanel(int index, TelemetryFrame frame) => Container(
    key: const ValueKey('replay-chart-panel'),
    padding: const EdgeInsets.fromLTRB(8, 2, 8, 5),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      children: [
        SizedBox(
          height: 30,
          child: Row(
            children: [
              const Expanded(
                child: LText(
                  '同步曲线',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                key: const ValueKey('replay-select-channels'),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 44, minHeight: 30),
                tooltip: context.tr('选择曲线数据'),
                onPressed: _selectChannels,
                icon: const Icon(Icons.tune_rounded, size: 17),
              ),
            ],
          ),
        ),
        SizedBox(
          height: 22,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final channel in channels)
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: Tooltip(
                      message: _rangeLabel(channel),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: context.isDark
                                  ? channel.color
                                  : Color.lerp(
                                      channel.color,
                                      Colors.black,
                                      .5,
                                    )!,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 4),
                          LText(
                            channel.label,
                            style: TextStyle(
                              fontSize: 10,
                              color: context.appMuted,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            channel.display(frame, widget.mph),
                            key: ValueKey('replay-chart-value-${channel.name}'),
                            style: TextStyle(
                              fontSize: 11,
                              color: context.isDark
                                  ? channel.color
                                  : Color.lerp(
                                      channel.color,
                                      Colors.black,
                                      .5,
                                    )!,
                              fontFamily: 'Dashboard',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Expanded(
          child: channels.isEmpty
              ? Center(
                  child: LText(
                    '请选择曲线数据',
                    style: TextStyle(color: context.appMuted, fontSize: 11),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    onTapDown: (details) =>
                        _seekChart(details.localPosition, constraints.biggest),
                    onHorizontalDragUpdate: (details) =>
                        _seekChart(details.localPosition, constraints.biggest),
                    child: RepaintBoundary(
                      child: CustomPaint(
                        key: const ValueKey('replay-chart'),
                        size: Size.infinite,
                        painter: ReplayChartPainter(
                          chart,
                          Set.of(channels),
                          index,
                        ),
                      ),
                    ),
                  ),
                ),
        ),
        LText(
          '纵轴：各自量程百分比 · 横轴：回放秒',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 8, color: context.appMuted),
        ),
      ],
    ),
  );

  void _seekChart(Offset point, Size size) {
    final rect = ReplayChartPainter.plotRect(size);
    _seek(
      ((point.dx - rect.left) / rect.width).clamp(0.0, 1.0) * timeline.duration,
    );
  }

  String _rangeLabel(ReplayChannel channel) {
    final (low, high) = chart.range(channel);
    return '${context.tr(channel.label)} · ${low.toStringAsFixed(0)}–${high.toStringAsFixed(0)} ${channel.unit(widget.mph)}';
  }

  Future<void> _selectChannels() async {
    setState(_pause);
    final pending = Set<ReplayChannel>.of(channels);
    final result = await showDialog<Set<ReplayChannel>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => LiquidGlassAlertDialog(
          title: const LText('选择曲线数据'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final channel in ReplayChannel.values)
                    CheckboxListTile(
                      key: ValueKey('replay-channel-${channel.name}'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      activeColor: channel.color,
                      title: LText(
                        channel.label,
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: Text(
                        _rangeLabel(channel),
                        style: TextStyle(fontSize: 10, color: context.appMuted),
                      ),
                      value: pending.contains(channel),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          pending.add(channel);
                        } else {
                          pending.remove(channel);
                        }
                      }),
                    ).forPhone(context),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const LText('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, pending),
              child: const LText('应用'),
            ),
          ],
        ),
      ),
    );
    if (mounted && result != null) setState(() => channels = result);
  }

  void _showDetails(TelemetryFrame frame) {
    setState(_pause);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .85,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LText(
                  '采样详情',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
                ),
                _details(frame),
                const SizedBox(height: 12),
                LText(
                  '轨迹来自记录坐标，底图对齐待实测；转向为归一化输入。',
                  style: TextStyle(fontSize: 10, color: context.appMuted),
                ),
                if (timeline.breaks.isNotEmpty || track.points.contains(null))
                  LText(
                    '分段、断流或非驾驶位置不连线；等待时间已压缩。',
                    style: TextStyle(fontSize: 10, color: context.appMuted),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _inputs(TelemetryFrame frame) => Container(
    key: const ValueKey('replay-input-panel'),
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 72,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Transform.rotate(
                angle: frame.steer.clamp(-1, 1) * math.pi * .75,
                child: const CustomPaint(
                  size: Size(32, 32),
                  painter: _SteeringWheelPainter(),
                ),
              ),
              const SizedBox(height: 2),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LText(
                      '转向',
                      style: TextStyle(fontSize: 9, color: context.appMuted),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${(frame.steer * 100).round()}%',
                      key: const ValueKey('replay-steer'),
                      style: const TextStyle(fontSize: 11, color: raceCyan),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              SizedBox(
                height: 4,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final value = frame.steer.clamp(-1.0, 1.0);
                    return Stack(
                      children: [
                        Container(
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: .1),
                        ),
                        Positioned(
                          left:
                              constraints.maxWidth *
                              (value < 0 ? (1 + value) / 2 : .5),
                          width: constraints.maxWidth * value.abs() / 2,
                          top: 0,
                          bottom: 0,
                          child: const ColoredBox(color: raceCyan),
                        ),
                        Align(
                          alignment: Alignment.center,
                          child: Container(
                            width: 1,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _pedal('油门', 'throttle', frame.throttle, context.appAccent),
              const SizedBox(height: 12),
              _pedal('刹车', 'brake', frame.brake, raceRed),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _pedal(String label, String id, double value, Color color) => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: LText(
              label,
              style: TextStyle(fontSize: 10, color: context.appMuted),
            ),
          ),
          Text(
            '${(value * 100).round()}%',
            key: ValueKey('replay-$id'),
            style: const TextStyle(fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 3),
      LinearProgressIndicator(
        value: value.clamp(0, 1),
        color: color,
        backgroundColor: Theme.of(context).colorScheme.onSurface
            .withValues(alpha: .1),
        minHeight: 6,
        borderRadius: BorderRadius.circular(4),
      ),
    ],
  );

  Widget _details(TelemetryFrame f) {
    final tires = [
      for (var i = 0; i < 4; i++)
        i < f.tires.length ? f.tires[i].toStringAsFixed(1) : '--',
    ];
    final fields = <(String, String, String)>[
      (
        '车速',
        '${(f.speed * (widget.mph ? 2.236936 : 3.6)).round()} ${widget.mph ? 'mph' : 'km/h'}',
        'speed',
      ),
      ('转速', '${f.rpm.round()} rpm', 'rpm'),
      ('挡位', f.gear == 0 ? 'R' : '${f.gear}', 'gear'),
      ('名次', f.position > 0 ? 'P${f.position}' : '--', 'position'),
      ('赛事计时', lapTime(f.raceTime), 'race-time'),
      ('当前圈速', lapTime(f.currentLap), 'lap-time'),
      ('圈数', '${f.lap + 1}', 'lap'),
      ('最佳圈速', lapTime(f.bestLap), 'best-lap'),
      ('上一圈速', lapTime(f.lastLap), 'last-lap'),
      ('功率', '${f.power.round()} kW', 'power'),
      ('扭矩', '${f.torque.round()} Nm', 'torque'),
      ('增压', f.boost.toStringAsFixed(2), 'boost'),
      ('燃油', '${(f.fuel * 100).round()}%', 'fuel'),
      ('轮胎前左 / 前右', '${tires[0]} / ${tires[1]}', 'tires-front'),
      ('轮胎后左 / 后右', '${tires[2]} / ${tires[3]}', 'tires-rear'),
      (
        '坐标 X / Y / Z',
        '${f.x.toStringAsFixed(1)} / ${f.y.toStringAsFixed(1)} / ${f.z.toStringAsFixed(1)}',
        'coordinates',
      ),
    ];
    return Column(
      children: [
        for (final field in fields)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: LText(
                    field.$1,
                    style: TextStyle(color: context.appMuted, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    field.$2,
                    key: ValueKey('replay-detail-${field.$3}'),
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 8),
        LText(
          '轮胎温度与增压显示记录原始值，单位待确认。',
          style: TextStyle(fontSize: 10, color: context.appMuted),
        ),
      ],
    );
  }
}

String _clock(double seconds) {
  final ms = (seconds * 1000).round();
  return '${ms ~/ 60000}:${(ms ~/ 1000 % 60).toString().padLeft(2, '0')}.${(ms % 1000).toString().padLeft(3, '0')}';
}

/// Geometry is built once, separate from the playback cursor.
class ReplayTrack {
  final List<Offset?> points;
  final Set<int> breaks;
  final path = Path();
  late final Rect bounds;
  late final bool hasMovement;
  ReplayTrack(ReplayTimeline timeline)
    : points = timeline.samples.map((s) {
        final f = s.frame;
        return f.driving && f.x.isFinite && f.z.isFinite
            ? Offset(582.896 + f.x * .046504, 499.376 - f.z * .046504)
            : null;
      }).toList(),
      breaks = timeline.breaks {
    Rect? rect;
    Offset? previous;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      if (p == null) {
        previous = null;
        continue;
      }
      rect = rect == null
          ? Rect.fromPoints(p, p)
          : rect.expandToInclude(Rect.fromPoints(p, p));
      if (previous == null || breaks.contains(i)) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
      previous = p;
    }
    hasMovement = rect != null && rect.longestSide > .05;
    final center = rect?.center ?? const Offset(512, 512);
    bounds = Rect.fromCenter(
      center: center,
      width: math.max(rect?.width ?? 0, 12) + 16,
      height: math.max(rect?.height ?? 0, 12) + 16,
    );
  }
}

class ReplayTrackPainter extends CustomPainter {
  final ReplayTrack track;
  final int index;
  final ui.Image? map;
  ReplayTrackPainter(this.track, this.index, this.map);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, Paint()..color = appSurface);
    final scale = math.min(
      size.width / track.bounds.width,
      size.height / track.bounds.height,
    );
    canvas.translate(size.width / 2, size.height / 2);
    canvas.scale(scale);
    canvas.translate(-track.bounds.center.dx, -track.bounds.center.dy);
    if (map != null) {
      canvas.drawImageRect(
        map!,
        Rect.fromLTWH(0, 0, map!.width.toDouble(), map!.height.toDouble()),
        const Rect.fromLTWH(0, 0, 1024, 1024),
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.drawRect(
        track.bounds.inflate(track.bounds.longestSide),
        Paint()..color = Colors.black38,
      );
    }
    canvas.drawPath(
      track.path,
      Paint()
        ..color = appAccent.withValues(alpha: .55)
        ..strokeWidth = 3 / scale
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    final trail = Path();
    Offset? previous;
    for (
      var i = math.max(0, index - 30);
      i <= index && i < track.points.length;
      i++
    ) {
      final point = track.points[i];
      if (point == null) {
        previous = null;
        continue;
      }
      if (previous == null || track.breaks.contains(i)) {
        trail.moveTo(point.dx, point.dy);
      } else {
        trail.lineTo(point.dx, point.dy);
      }
      previous = point;
    }
    canvas.drawPath(
      trail,
      Paint()
        ..color = raceCyan
        ..strokeWidth = 4 / scale
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    final start = track.points.whereType<Offset>().firstOrNull;
    if (start != null) {
      canvas.drawCircle(start, 4 / scale, Paint()..color = Colors.white);
    }
    final p = index >= 0 && index < track.points.length
        ? track.points[index]
        : null;
    if (p == null) return;
    canvas.drawCircle(
      p,
      13 / scale,
      Paint()..color = raceCyan.withValues(alpha: .25),
    );
    canvas.drawCircle(p, 6 / scale, Paint()..color = raceCyan);
    canvas.drawCircle(
      p,
      6 / scale,
      Paint()
        ..color = Colors.white
        ..strokeWidth = 2 / scale
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant ReplayTrackPainter old) =>
      old.track != track || old.index != index || old.map != map;
}

class _SteeringWheelPainter extends CustomPainter {
  const _SteeringWheelPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = raceCyan
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, 15, paint);
    canvas.drawCircle(center, 4, paint);
    for (final end in [
      const Offset(3, 15),
      const Offset(33, 15),
      const Offset(18, 33),
    ]) {
      canvas.drawLine(center, end, paint);
    }
    canvas.drawLine(
      const Offset(18, 1),
      const Offset(18, 7),
      Paint()
        ..color = Colors.white
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant _SteeringWheelPainter old) => false;
}
