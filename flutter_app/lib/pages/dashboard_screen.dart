import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../widgets/ios_options.dart';

import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../services/dashboard_display.dart';
import '../services/dashboard_hint.dart';
import '../widgets/race_dashboard_selector.dart';
import '../widgets/dash_canvas.dart';
import '../widgets/limiter_settings.dart';
import '../widgets/app_theme.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/overtake_glow.dart';
import '../widgets/expanded_navigation.dart';
import 'telemetry_page.dart';

Future<void> openDashboard(
  BuildContext context,
  AppController app,
  DashboardStyle style,
) async {
  await openDashboardSelection(context, app, DashboardRef.builtin(style.name));
}

Future<void> openDashboardSelection(
  BuildContext context,
  AppController app,
  DashboardRef selection,
) async {
  app.chooseDashboard(selection);
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => Theme(
        data: buildTheme(),
        child: DashboardScreen(app: app),
      ),
    ),
  );
}

class DashboardScreen extends StatefulWidget {
  final AppController app;
  const DashboardScreen({super.key, required this.app});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  AppController get app => widget.app;
  bool _fullscreen = false;
  bool _visible = false;
  bool _screenAwake = false;
  int _gestureRevision = 0;
  int _paintRevision = 0;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    );
    unawaited(
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final routeActive = ModalRoute.isActiveOf(context) ?? true;
    // Translucent controls still leave the dash visible. An opaque route
    // such as telemetry history turns off its ticker mode once it covers it.
    _visible = tickerEnabled && routeActive;
    _syncScreenAwake(WidgetsBinding.instance.lifecycleState);
  }

  void _syncScreenAwake(AppLifecycleState? state) {
    final awake = _visible && state == AppLifecycleState.resumed;
    if (_screenAwake == awake) return;
    _screenAwake = awake;
    unawaited(DashboardDisplay.setAwake(awake));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _syncScreenAwake(state);
    if (state != AppLifecycleState.resumed && _fullscreen) {
      // Replacing the recognizer cancels an unfinished hold across backgrounding.
      setState(() => _gestureRevision++);
      unawaited(DashboardHint.cancel());
    }
  }

  void _enterFullscreen() {
    setState(() => _fullscreen = true);
    unawaited(
      DashboardHint.show(
        context.tr('长按屏幕两秒返回'),
        onHidden: () {
          // Repaint after Android removes its Toast surface.
          if (mounted && _fullscreen) setState(() => _paintRevision++);
        },
      ),
    );
  }

  void _exitFullscreen() {
    if (!mounted || !_fullscreen) return;
    setState(() => _fullscreen = false);
    unawaited(DashboardHint.cancel());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncScreenAwake(null);
    unawaited(DashboardHint.cancel());
    unawaited(
      SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]),
    );
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => _buildDashboard(context),
  );

  Widget _buildDashboard(BuildContext context) {
    final fitViewport =
        !kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        MediaQuery.orientationOf(context) == Orientation.landscape;
    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: fitViewport
            ? DashCanvas.backdrop(app.customDashboard)
            : Colors.black,
        body: Stack(
          children: [
            SafeArea(
              child: Stack(
                children: [
                  Column(
                    children: [
                      if (!_fullscreen) _toolbar(context),
                      Expanded(
                        child: Row(
                          children: [
                            Expanded(child: _instrument(context, fitViewport)),
                            if (!_fullscreen &&
                                app.style == DashboardStyle.basic &&
                                !app.settings.expandedNav)
                              SizedBox(
                                width: 48,
                                child: Center(
                                  child: _navigationButton(context),
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (!_fullscreen &&
                          kIsWeb &&
                          MediaQuery.of(context).orientation ==
                              Orientation.portrait)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 24),
                          child: LText(
                            '横屏查看仪表效果更佳 · 手机安装版将自动横屏',
                            style: TextStyle(fontSize: 11, color: appMuted),
                          ),
                        ),
                    ],
                  ),
                  if (!_fullscreen && app.message.isNotEmpty)
                    Positioned(
                      bottom: 8,
                      left: 65,
                      right: 65,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xe6202529),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: LText(
                            app.message,
                            style: const TextStyle(
                              fontSize: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (!_fullscreen && app.style.isProfessional)
              Positioned.fill(child: OvertakeGlow(active: app.gain)),
            if (_fullscreen)
              Positioned.fill(
                child: Semantics(
                  key: const ValueKey('dashboard-fullscreen-surface'),
                  label: context.tr('长按屏幕两秒返回'),
                  child: RawGestureDetector(
                    key: ValueKey(_gestureRevision),
                    behavior: HitTestBehavior.opaque,
                    gestures: {
                      LongPressGestureRecognizer:
                          GestureRecognizerFactoryWithHandlers<
                            LongPressGestureRecognizer
                          >(
                            () => LongPressGestureRecognizer(
                              duration: const Duration(seconds: 2),
                            ),
                            (recognizer) =>
                                recognizer.onLongPress = _exitFullscreen,
                          ),
                    },
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _instrument(BuildContext context, bool fitViewport) {
    final canvas = RepaintBoundary(
      key: ValueKey(_paintRevision),
      child: LayoutBuilder(
        builder: (context, constraints) => Stack(
          fit: StackFit.expand,
          children: [
            DashCanvas(
              frame: app.frame,
              shiftTargetRpm: app.limiter.shiftTargetRpm,
              settings: app.settings,
              style: app.style,
              customLayout: app.customDashboard,
              hasData: app.hasTelemetry,
              destination: app.navigationLabel ?? app.destination,
              navigation: app.navigation,
              paintBackground: !fitViewport,
            ),
            if (!_fullscreen &&
                app.style == DashboardStyle.basic &&
                app.settings.expandedNav)
              Positioned(
                left:
                    constraints.maxWidth *
                        expandedNavigationCloseCenter.dx /
                        DashCanvas.designSize.width -
                    24,
                top:
                    constraints.maxHeight *
                        expandedNavigationCloseCenter.dy /
                        DashCanvas.designSize.height -
                    24,
                width: 48,
                height: 48,
                child: _navigationButton(context),
              ),
          ],
        ),
      ),
    );
    if (fitViewport && app.customDashboard == null) return canvas;
    return Center(
      child: AspectRatio(
        aspectRatio: DashCanvas.designSize.aspectRatio,
        child: canvas,
      ),
    );
  }

  Widget _toolbar(BuildContext context) => SizedBox(
    key: const ValueKey('dashboard-toolbar'),
    height: 48,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final controls = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 76,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: LText(
                  app.connected ? '已连接' : '未连接',
                  key: const ValueKey('dashboard-connection-status'),
                  style: TextStyle(
                    fontSize: 11,
                    color: app.connected ? raceCyan : appMuted,
                  ),
                ),
              ),
            ),
            _modeButton('基础', DashboardStyle.basic),
            _modeButton('专业', DashboardStyle.professional),
            PopupMenuButton<DashboardRef>(
              key: const ValueKey('race-layout-menu'),
              tooltip: context.tr('选择专业布局'),
              initialValue: app.currentDashboard,
              icon: const Icon(Icons.expand_more_rounded, size: 20),
              onSelected: app.chooseDashboard,
              itemBuilder: (_) => [
                for (final style in DashboardStyle.values.where(
                  (s) => s.isProfessional,
                ))
                  PopupMenuItem(
                    key: ValueKey('race-layout-${style.name}'),
                    value: DashboardRef.builtin(style.name),
                    child: LText(style.title),
                  ),
                for (final entry in app.settings.customDashboards.entries)
                  PopupMenuItem(
                    value: DashboardRef.custom(entry.key),
                    child: Text(entry.value.name),
                  ),
              ],
            ).forPhone(context, symbol: 'chevron.down'),
            if (app.customDashboard != null)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 100),
                child: Text(
                  app.customDashboard!.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: context.tr('仪表设置'),
              onPressed: () => showDashSettings(context, app),
              icon: const Icon(Icons.tune_rounded, size: 20),
            ),
            IconButton(
              tooltip: context.tr('驾驶控制'),
              onPressed: _controls,
              icon: const Icon(Icons.more_horiz_rounded, size: 22),
            ),
            const SizedBox(width: 4),
          ],
        );
        return Row(
          children: [
            IconButton(
              tooltip: context.tr('退出仪表'),
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
            ),
            if (constraints.maxWidth >= 600) ...[
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: app.gain && app.style.isProfessional
                      ? _gainHeading()
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: LText(
                            app.racing ? 'RACE ON' : 'FREE ROAM',
                            style: const TextStyle(
                              fontFamily: 'Dashboard',
                              fontSize: 14,
                              color: appMuted,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ),
                ),
              ),
              controls,
            ] else
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: controls,
                ),
              ),
            _fullscreenButton(context),
          ],
        );
      },
    ),
  );

  Widget _gainHeading() => IgnorePointer(
    child: const FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        key: ValueKey('position-gain-heading'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_upward_rounded, size: 28, color: raceYellow),
          SizedBox(width: 12),
          LText(
            'POSITION GAINED',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'GainLabel',
              fontSize: 28,
              height: 1.15,
              color: raceYellow,
              fontWeight: FontWeight.w700,
              letterSpacing: 5,
            ),
          ),
          SizedBox(width: 12),
          Icon(Icons.arrow_upward_rounded, size: 28, color: raceYellow),
        ],
      ),
    ),
  );

  Widget _fullscreenButton(BuildContext context) => IconButton(
    key: const ValueKey('dashboard-fullscreen-toggle'),
    tooltip: context.tr('全屏仪表'),
    onPressed: _enterFullscreen,
    icon: const Icon(Icons.fullscreen_rounded),
  );

  Widget _navigationButton(BuildContext context) => Semantics(
    toggled: app.settings.expandedNav,
    child: IconButton.filledTonal(
      key: const ValueKey('expanded-navigation-toggle'),
      tooltip: context.tr(app.settings.expandedNav ? '收起导航' : '打开导航'),
      onPressed: () =>
          app.updateSettings((s) => s.expandedNav = !s.expandedNav),
      icon: Icon(
        app.settings.expandedNav
            ? Icons.arrow_back_rounded
            : Icons.map_outlined,
      ),
      color: app.settings.expandedNav ? raceCyan : appMuted,
    ).forChoice(context, app.settings.expandedNav, 'map'),
  );

  Widget _modeButton(String title, DashboardStyle value) =>
      TextButton(
        onPressed: () => app.chooseStyle(value),
        style: TextButton.styleFrom(
          foregroundColor: app.customDashboard == null && app.style == value
              ? Colors.white
              : appMuted,
          backgroundColor: app.customDashboard == null && app.style == value
              ? const Color(0xff24272c)
              : Colors.transparent,
          minimumSize: const Size(54, 30),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 60),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: LText(title, style: const TextStyle(fontSize: 12)),
          ),
        ),
      ).forChoice(
        context,
        app.customDashboard == null && app.style == value,
        context.tr(title),
      );
  Future<void> _showTelemetry() async {
    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => TelemetryPage(app: app)),
    );
    if (mounted) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]);
    }
  }

  void _controls() => showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: LiquidGlassActions(
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _control(
                sheetContext,
                Icons.tune_rounded,
                '仪表设置',
                () => showDashSettings(context, app),
              ),
              _control(
                sheetContext,
                app.recording == null
                    ? Icons.fiber_manual_record
                    : Icons.stop_rounded,
                app.recording == null ? '开始录制' : '结束录制',
                () => app.recording == null
                    ? app.startRecording()
                    : app.stopRecording(),
              ),
              _control(
                sheetContext,
                Icons.show_chart_rounded,
                '查看遥测',
                () => unawaited(_showTelemetry()),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Widget _control(
    BuildContext sheetContext,
    IconData icon,
    String label,
    VoidCallback action,
  ) => ActionChip(
    avatar: Icon(icon, size: 18),
    label: LText(label),
    onPressed: () {
      Navigator.pop(sheetContext);
      action();
    },
  );
}

void showDashSettings(BuildContext context, AppController app) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: AnimatedBuilder(
          animation: app,
          builder: (context, _) => SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LText(
                    '仪表设置',
                    style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  RaceDashboardSelector(app: app),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const LText('名次提升发光'),
                    value: app.settings.effects,
                    onChanged: (v) => app.updateSettings((s) => s.effects = v),
                  ).forPhone(context),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const LText('基础仪表简洁导航'),
                    value: app.settings.miniNav,
                    onChanged: (v) => app.updateSettings((s) => s.miniNav = v),
                  ).forPhone(context),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const LText('轮胎数据'),
                    value: app.settings.tires,
                    onChanged: (v) => app.updateSettings((s) => s.tires = v),
                  ).forPhone(context),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const LText('油门与刹车'),
                    value: app.settings.inputs,
                    onChanged: (v) => app.updateSettings((s) => s.inputs = v),
                  ).forPhone(context),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    title: const LText('英里单位 mph'),
                    value: app.settings.mph,
                    onChanged: (v) => app.updateSettings((s) => s.mph = v),
                  ).forPhone(context),
                  LimiterSettings(app: app),
                  SizedBox(
                    width: double.infinity,
                    child: LiquidGlassActions(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const LText('完成'),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
