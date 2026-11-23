import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_controller.dart';
import 'privacy_bootstrap.dart';
import 'services/privacy_consent.dart';
import 'services/bundled_licenses.dart';
import 'widgets/app_theme.dart';
import 'widgets/ios_glass_controls.dart';
import 'widgets/liquid_glass.dart';
import 'pages/dashboard_library.dart';
import 'pages/map_page.dart';
import 'pages/guides_page.dart';
import 'pages/settings_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerBundledLicenses();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(PrivacyBootstrap(consent: PrivacyConsent()));
}

class HorizonApp extends StatelessWidget {
  final AppController controller;
  const HorizonApp({super.key, required this.controller});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([controller.language, controller.appearance]),
    builder: (context, _) => MaterialApp(
      title: 'Horizon Link',
      locale: Locale(controller.language.value),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: [
        AppCopy.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      debugShowCheckedModeBanner: false,
      theme: buildTheme(brightness: Brightness.light),
      darkTheme: buildTheme(),
      themeMode: switch (controller.appearance.value) {
        AppAppearance.dark => ThemeMode.dark,
        AppAppearance.light => ThemeMode.light,
        AppAppearance.system => ThemeMode.system,
      },
      builder: (context, child) => LiquidGlass(child: child!),
      home: AppShell(app: controller),
    ),
  );
}

class AppShell extends StatefulWidget {
  final AppController app;
  const AppShell({super.key, required this.app});
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> with WidgetsBindingObserver {
  int _focusSerial = 0;
  int tab = 0;
  late List<Widget?> _pages;
  Object? _mapViewState;
  Object? _settingsViewState, _guidesViewState;
  Widget _updatedPage(int index) {
    if (index != tab) return _pages[index] ?? const SizedBox.shrink();
    if (index == 1) {
      final state = MapPage.viewState(widget.app);
      if (state == _mapViewState && _pages[index] != null) {
        return _pages[index]!;
      }
      _mapViewState = state;
    } else if (index == 2) {
      final state = (
        widget.app.settings.language,
        widget.app.guideUrl,
        widget.app.weekly.content,
        widget.app.weekly.displayed,
        widget.app.weekly.current,
        widget.app.weekly.status,
        widget.app.weekly.lastChecked,
      );
      if (state == _guidesViewState && _pages[index] != null) {
        return _pages[index]!;
      }
      _guidesViewState = state;
    } else if (index == 3) {
      final s = widget.app.settings;
      final state = (
        s,
        s.language,
        s.appearance,
        s.autoRecord,
        s.raceDashboard,
        s.effects,
        s.miniNav,
        s.expandedNav,
        s.tires,
        s.inputs,
        s.mph,
        s.port,
        widget.app.connected,
        widget.app.status,
      );
      if (state == _settingsViewState && _pages[index] != null) {
        return _pages[index]!;
      }
      _settingsViewState = state;
    }
    return _pages[index] = _page(index);
  }

  Widget _page(int index) => switch (index) {
    0 => DashboardLibrary(app: widget.app),
    1 => MapPage(app: widget.app),
    2 => GuidesPage(app: widget.app),
    _ => SettingsPage(app: widget.app),
  };
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _pages = List.filled(4, null);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    widget.app.setLimiterForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) widget.app.weekly.onForeground();
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      unawaited(
        widget.app.flushSaved().catchError((Object _) {
          widget.app.notifyMessage('本地保存失败，请先导出重要记录');
        }),
      );
    }
  }

  @override
  void didUpdateWidget(covariant AppShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.app != widget.app) {
      _focusSerial = 0;
      _pages = List.filled(4, null);
      _mapViewState = null;
      _settingsViewState = _guidesViewState = null;
    }
  }

  Widget _connectionButton(BuildContext context, bool glass) {
    final button = TextButton.icon(
      onPressed: () => showConnection(context, widget.app),
      icon: const Icon(Icons.circle, size: 8),
      label: LText(
        widget.app.connected ? '已连接' : '未连接',
        style: const TextStyle(fontSize: 10),
      ),
      style: TextButton.styleFrom(
        foregroundColor: widget.app.connected
            ? context.appAccent
            : glass
            ? Theme.of(context).colorScheme.onSurface
            : context.appMuted,
        minimumSize: glass ? const Size(44, 44) : null,
      ),
    );
    if (!glass) return button;
    return Center(
      widthFactor: 1,
      child: LiquidGlassSurface(capsule: true, child: button),
    );
  }

  void _selectTab(int value) {
    setState(() => tab = value);
    if (value == 1 || value == 2) unawaited(widget.app.weekly.refresh());
  }

  Widget? _navigationBar(BuildContext context, bool floating) {
    final labels = ['仪表盘', '地图', '攻略', '设置'].map(context.tr).toList();
    if (floating) {
      if (MediaQuery.viewInsetsOf(context).bottom > 0) return null;
      return IosGlassControls(
        key: const ValueKey('glass-navigation'),
        selectedIndex: tab,
        labels: labels,
        onAction: _selectTab,
      );
    }
    return NavigationBar(
      height: 74,
      selectedIndex: tab,
      onDestinationSelected: _selectTab,
      destinations: [
        NavigationDestination(
          icon: const Icon(Icons.speed_outlined),
          selectedIcon: const Icon(Icons.speed_rounded),
          label: labels[0],
        ),
        NavigationDestination(
          icon: const Icon(Icons.map_outlined),
          selectedIcon: const Icon(Icons.map_rounded),
          label: labels[1],
        ),
        NavigationDestination(
          icon: const Icon(Icons.menu_book_outlined),
          selectedIcon: const Icon(Icons.menu_book_rounded),
          label: labels[2],
        ),
        NavigationDestination(
          icon: const Icon(Icons.settings_outlined),
          selectedIcon: const Icon(Icons.settings_rounded),
          label: labels[3],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: Theme.of(context).scaffoldBackgroundColor,
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AnimatedBuilder(
          // Covered routes keep their state without rebuilding the library
          // behind the driving screen on every telemetry packet.
          animation: TickerMode.valuesOf(context).enabled
              ? widget.app
              : const AlwaysStoppedAnimation(0),
          builder: (context, _) {
            final glass = LiquidGlass.enabledOf(context);
            final focus = widget.app.mapFocus;
            if (focus != null && focus.serial != _focusSerial) {
              _focusSerial = focus.serial;
              tab = 1;
            }
            return Scaffold(
              extendBody: glass,
              appBar: AppBar(
                title: LText(['仪表盘', '地图', '攻略', '设置'][tab]),
                actions: [
                  if (tab != 3)
                    Padding(
                      padding: const EdgeInsets.only(right: 12),
                      child: _connectionButton(context, glass),
                    ),
                ],
              ),
              body: Column(
                children: [
                  if (widget.app.storageReadFailed)
                    MaterialBanner(
                      content: Text(
                        widget.app.settings.language == 'en'
                            ? 'Saved data could not be read. Automatic saving is paused to protect the original. Open Settings → Backup & restore.'
                            : '旧存档读取失败，已暂停自动保存以保护原文件。请前往设置 → 数据备份与恢复。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => setState(() => tab = 3),
                          child: Text(
                            widget.app.settings.language == 'en'
                                ? 'Settings'
                                : '设置',
                          ),
                        ),
                      ],
                    ),
                  Expanded(
                    child: IndexedStack(
                      index: tab,
                      // Preserve every page's state while only updating the visible
                      // page on the 10 Hz telemetry notifications.
                      children: List.generate(
                        4,
                        (index) => TickerMode(
                          enabled: index == tab,
                          child: _updatedPage(index),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              bottomNavigationBar: _navigationBar(context, glass),
            );
          },
        ),
      ),
    ),
  );
}
