import 'dart:convert';

import 'package:flutter/material.dart';

import '../widgets/ios_options.dart';

import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../core/racing.dart';
import '../widgets/app_theme.dart';
import '../widgets/dash_canvas.dart';
import '../widgets/liquid_glass.dart';
import 'replay_page.dart';

class TelemetryPage extends StatefulWidget {
  final AppController app;
  const TelemetryPage({super.key, required this.app});
  @override
  State<TelemetryPage> createState() => _TelemetryPageState();
}

class _TelemetryPageState extends State<TelemetryPage> {
  int channel = 0;
  String? selected;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: widget.app,
    builder: (context, _) {
      final app = widget.app;
      final session =
          app.sessions.where((s) => s.id == selected).firstOrNull ??
          app.recording ??
          app.sessions.firstOrNull;
      final viewingRecording =
          session != null && identical(session, app.recording);
      return Scaffold(
        appBar: AppBar(
          title: const LText('驾驶遥测'),
          actions: [
            IconButton(
              tooltip: context.tr('导出 JSON'),
              onPressed: session == null ? null : () => _export(session),
              icon: const Icon(Icons.ios_share_rounded),
            ),
          ],
        ),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 600),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('open-replay'),
                  onPressed: session == null || session.effective.isEmpty
                      ? null
                      : () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ReplayPage(
                              session: session,
                              mph: app.settings.mph,
                            ),
                          ),
                        ),
                  icon: const Icon(Icons.route_rounded),
                  label: const LText('轨迹回放'),
                ),
                if (viewingRecording)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: LText(
                      '回放打开时的采样快照，录制继续进行。',
                      style: TextStyle(fontSize: 11, color: context.appMuted),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _metric(
                        '最高车速',
                        session?.topSpeed.round().toString() ?? '--',
                        'km/h',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _metric(
                        '平均车速',
                        session?.averageSpeed.round().toString() ?? '--',
                        'km/h',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(
                      child: LText(
                        '驾驶曲线',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    if (viewingRecording)
                      const Icon(
                        Icons.fiber_manual_record,
                        color: raceRed,
                        size: 10,
                      ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: LText(
                        viewingRecording
                            ? '录制中'
                            : session?.source == 'demo'
                            ? '历史测试记录'
                            : '本地记录',
                        style: TextStyle(fontSize: 11, color: context.appMuted),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: 0, label: LText('车速')),
                    ButtonSegment(value: 1, label: LText('转速')),
                    ButtonSegment(value: 2, label: LText('驾驶输入')),
                  ],
                  selected: {channel},
                  onSelectionChanged: (v) => setState(() => channel = v.first),
                ).forPhone(context, context.tr('驾驶遥测')),
                const SizedBox(height: 17),
                Container(
                  height: 235,
                  padding: const EdgeInsets.all(15),
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: (session?.effective.length ?? 0) > 1
                      ? CustomPaint(
                          painter: TelemetryPainter(session!, channel),
                        )
                      : Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.show_chart_rounded,
                                size: 35,
                                color: context.appMuted,
                              ),
                              SizedBox(height: 15),
                              LText(
                                '开始录制，记录你的每一段驾驶',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.appMuted,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
                if (session != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: LText(
                      '${session.samples.length} 个采样 · 回溯分段 ${session.rewinds} 次\n${session.finalPosition == null ? '最终名次未确认' : '已确认第 ${session.finalPosition} 名'}',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appMuted,
                        height: 1.9,
                      ),
                    ),
                  ),
                const SizedBox(height: 6),
                FilledButton.icon(
                  onPressed: () => app.recording == null
                      ? app.startRecording()
                      : app.stopRecording(),
                  icon: Icon(
                    app.recording == null
                        ? Icons.fiber_manual_record
                        : Icons.stop_rounded,
                    size: 18,
                  ),
                  label: LText(app.recording == null ? '开始录制' : '结束并保存'),
                ),
                const SectionLabel('驾驶记录', trailing: '最近 8 段'),
                if (app.sessions.isEmpty)
                  Padding(
                    padding: EdgeInsets.all(25),
                    child: Center(
                      child: LText(
                        '还没有驾驶记录',
                        style: TextStyle(color: context.appMuted, fontSize: 12),
                      ),
                    ),
                  ),
                ...app.sessions.map(
                  (s) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Material(
                      color: context.appSurface,
                      borderRadius: BorderRadius.circular(15),
                      child: ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        leading: Icon(
                          Icons.flag_rounded,
                          color: context.appAccent,
                        ),
                        title: LText(
                          s.source == 'demo' ? '历史测试记录' : 'FH6 驾驶记录',
                          style: const TextStyle(fontSize: 13),
                        ),
                        subtitle: LText(
                          '${s.started.month}/${s.started.day}  ${s.started.hour.toString().padLeft(2, '0')}:${s.started.minute.toString().padLeft(2, '0')} · ${s.samples.length} 采样',
                          style: TextStyle(
                            fontSize: 10,
                            color: context.appMuted,
                          ),
                        ),
                        trailing: LText(
                          s.finalPosition == null
                              ? '--'
                              : 'P${s.finalPosition}',
                          style: TextStyle(
                            fontFamily: 'Dashboard',
                            fontSize: 28,
                            color: context.appAccent,
                          ),
                        ),
                        selected: session?.id == s.id,
                        onTap: () => setState(() => selected = s.id),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  Widget _metric(String label, String value, String unit) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: context.appSurface,
      borderRadius: BorderRadius.circular(17),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LText(label, style: TextStyle(fontSize: 11, color: context.appMuted)),
        const SizedBox(height: 7),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              LText(
                value,
                style: const TextStyle(
                  fontFamily: 'Dashboard',
                  fontSize: 44,
                  height: 1.1,
                ),
              ),
              const SizedBox(width: 7),
              LText(
                unit,
                style: TextStyle(fontSize: 10, color: context.appMuted),
              ),
            ],
          ),
        ),
      ],
    ),
  );
  void _export(DrivingSession session) {
    final messenger = ScaffoldMessenger.of(context);
    final json = const JsonEncoder.withIndent('  ').convert({
      'format': 'horizon-link.session',
      'version': 2,
      ...session.toJson(),
    });
    showDialog<void>(
      context: context,
      builder: (context) => LiquidGlassAlertDialog(
        title: const LText('导出遥测 JSON'),
        content: SizedBox(
          width: 500,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(
              json,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 10),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const LText('关闭'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: json));
              if (context.mounted) {
                Navigator.pop(context);
                messenger.showSnackBar(
                  const SnackBar(content: LText('JSON 已复制，可粘贴保存为文件')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 17),
            label: const LText('复制 JSON'),
          ),
        ],
      ),
    );
  }
}

class TelemetryPainter extends CustomPainter {
  final DrivingSession session;
  final int channel;
  TelemetryPainter(this.session, this.channel);
  @override
  void paint(Canvas c, Size size) {
    // CustomPaint shares its ancestor canvas. Clip every chart operation so
    // its background cannot cover the replay entry or surrounding controls.
    c.save();
    c.clipRect(Offset.zero & size);
    try {
      _paintChart(c, size);
    } finally {
      c.restore();
    }
  }

  void _paintChart(Canvas c, Size size) {
    c.drawRect(Offset.zero & size, Paint()..color = appSurface);
    final samples = session.effective;
    if (samples.isEmpty) return;
    final rect = Rect.fromLTRB(28, 14, size.width - 5, size.height - 25);
    final maximum = channel == 0
        ? (session.topSpeed * 1.15).clamp(200.0, 1000.0)
        : channel == 1
        ? 9000.0
        : 100.0;
    for (var i = 0; i <= 4; i++) {
      final y = rect.top + rect.height * i / 4;
      c.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        Paint()
          ..color = const Color(0xff30343c)
          ..strokeWidth = 1,
      );
      final label = TextPainter(
        text: TextSpan(
          text: '${(maximum * (1 - i / 4)).round()}',
          style: const TextStyle(
            fontFamily: 'Dashboard',
            fontSize: 11,
            color: appMuted,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(c, Offset(0, y - 6));
    }
    void series(double Function(Sample) value, Color color) {
      final path = Path();
      bool first = true;
      Sample? prior;
      final step = (samples.length / 500).floor().clamp(1, 1000);
      for (var i = 0; i < samples.length; i += step) {
        final sample = samples[i];
        final x =
                rect.left +
                i / (samples.length - 1).clamp(1, 100000) * rect.width,
            y =
                rect.bottom -
                (value(sample) / maximum).clamp(0.0, 1.0) * rect.height;
        if (first ||
            prior!.segment != sample.segment ||
            sample.frame.receivedAt
                    .difference(prior.frame.receivedAt)
                    .inMilliseconds >
                2000) {
          path.moveTo(x, y);
          first = false;
        } else {
          path.lineTo(x, y);
        }
        prior = sample;
      }
      c.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }

    series(
      (s) => channel == 0
          ? s.frame.speed * 3.6
          : channel == 1
          ? s.frame.rpm
          : s.frame.throttle * 100,
      appAccent,
    );
    if (channel == 2) series((s) => s.frame.brake * 100, raceRed);
  }

  @override
  bool shouldRepaint(covariant TelemetryPainter oldDelegate) => true;
}
