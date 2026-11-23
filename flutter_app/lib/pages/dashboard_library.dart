import 'package:flutter/material.dart';

import '../widgets/ios_options.dart';

import '../app_controller.dart';
import '../widgets/app_theme.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/dash_canvas.dart';
import 'dashboard_screen.dart';
import 'telemetry_page.dart';
import 'custom_dashboard_editor.dart';

import 'package:flutter/services.dart';

import 'settings_page.dart';

class DashboardLibrary extends StatelessWidget {
  final AppController app;
  const DashboardLibrary({super.key, required this.app});
  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      20,
      4,
      20,
      24 + LiquidGlass.bottomClearanceOf(context),
    ),
    children: [
      LText(
        '选择你的驾驶座舱',
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(color: context.appMuted, fontSize: 13),
      ),
      const SizedBox(height: 22),
      InkWell(
        customBorder: context.panelShape(14),
        onTap: () => showConnection(context, app),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: ShapeDecoration(
            color: context.appSurface,
            shape: context.panelShape(14),
          ),
          child: Row(
            children: [
              Container(
                width: 37,
                height: 37,
                decoration: BoxDecoration(
                  color: context.appAccent.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  Icons.wifi_rounded,
                  color: context.appAccent,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LText(
                      app.connected ? '已连接' : '未连接',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    LText(
                      '${app.status} · ${app.packets} 个数据包',
                      style: TextStyle(fontSize: 10, color: context.appMuted),
                    ),
                  ],
                ),
              ),
              LText(
                '连接',
                style: TextStyle(fontSize: 11, color: context.appAccent),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 17,
                color: context.appMuted,
              ),
            ],
          ),
        ),
      ),
      const SectionLabel('仪表样式'),
      _dashboardTile(
        context,
        DashboardStyle.basic,
        '基础仪表',
        'STREET / 01',
        '双表盘 · 车速 · 简洁导航',
        context.isDark ? raceCyan : const Color(0xff006c65),
      ),
      const SizedBox(height: 17),
      _dashboardTile(
        context,
        DashboardStyle.professional,
        '专业仪表',
        'RACE / 02',
        '换挡灯 · 圈速 · 驾驶输入',
        context.isDark ? raceYellow : const Color(0xff805600),
      ),
      const SizedBox(height: 17),
      _dashboardTile(
        context,
        DashboardStyle.gt,
        'GT 竞速',
        'GT / 03',
        '中央大挡位 · 圈速分区 · 高对比',
        context.isDark ? raceYellow : const Color(0xff805600),
      ),
      const SizedBox(height: 17),
      _dashboardTile(
        context,
        DashboardStyle.endurance,
        '耐力赛',
        'ENDURANCE / 04',
        '弧形转速 · 圈速对照 · 燃油',
        context.isDark ? raceCyan : const Color(0xff006c65),
      ),
      const SizedBox(height: 17),
      _dashboardTile(
        context,
        DashboardStyle.rally,
        '拉力赛',
        'RALLY / 05',
        '超大车速 · 醒目挡位 · 踏板输入',
        context.isDark ? const Color(0xffffa348) : const Color(0xff955000),
      ),
      SectionLabel(
        app.settings.language == 'en' ? 'Custom dashboards' : '自定义仪表盘',
      ),
      for (final entry in app.settings.customDashboards.entries) ...[
        Material(
          color: context.appSurface,
          shape: context.panelShape(16),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              InkWell(
                onTap: () => openDashboardSelection(
                  context,
                  app,
                  DashboardRef.custom(entry.key),
                ),
                child: AspectRatio(
                  aspectRatio: 1280 / 540,
                  child: IgnorePointer(
                    child: DashCanvas(
                      frame: app.frame,
                      shiftTargetRpm: app.limiter.shiftTargetRpm,
                      settings: app.settings,
                      style: DashboardStyle.professional,
                      customLayout: entry.value,
                      hasData: app.hasTelemetry,
                      navigation: app.navigation,
                    ),
                  ),
                ),
              ),
              ListTile(
                title: Text(entry.value.name),
                onTap: () => openDashboardSelection(
                  context,
                  app,
                  DashboardRef.custom(entry.key),
                ),
                trailing:
                    PopupMenuButton<String>(
                      key: ValueKey('custom-menu-${entry.key}'),
                      onSelected: (action) async {
                        if (action == 'edit') {
                          await showCustomDashboardEditor(
                            context,
                            app,
                            id: entry.key,
                          );
                        } else if (action == 'copy') {
                          await Clipboard.setData(
                            ClipboardData(text: entry.value.code),
                          );
                        } else {
                          final confirmed = await showDialog<bool>(
                            context: context,
                            builder: (dialog) => LiquidGlassAlertDialog(
                              title: Text(
                                app.settings.language == 'en'
                                    ? 'Delete layout?'
                                    : '删除自定义方案？',
                              ),
                              content: Text(
                                app.settings.language == 'en'
                                    ? 'The active layout returns to Basic. If this is the race target, automatic switching is disabled. Back up first.'
                                    : '若正在使用则回基础仪表；若为赛事目标则改为不切换。请先备份。',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, false),
                                  child: Text(
                                    app.settings.language == 'en'
                                        ? 'Cancel'
                                        : '取消',
                                  ),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(dialog, true),
                                  child: Text(
                                    app.settings.language == 'en'
                                        ? 'Delete'
                                        : '删除',
                                  ),
                                ),
                              ],
                            ),
                          );
                          if (confirmed == true) {
                            try {
                              await app.saveCustomDashboard(entry.key, null);
                            } catch (_) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      app.settings.language == 'en'
                                          ? 'Delete failed; original layout retained.'
                                          : '删除失败，原方案已保留。',
                                    ),
                                  ),
                                );
                              }
                            }
                          }
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'edit',
                          child: Text(
                            app.settings.language == 'en' ? 'Edit' : '编辑',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'copy',
                          child: Text(
                            app.settings.language == 'en'
                                ? 'Copy code'
                                : '复制代码',
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            app.settings.language == 'en' ? 'Delete' : '删除',
                          ),
                        ),
                      ],
                    ).forPhone(
                      context,
                      symbol: 'ellipsis.circle',
                      destructive: 2,
                      name: entry.value.name,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        key: const ValueKey('add-custom-dashboard'),
        onPressed:
            app.settings.customDashboards.length >= CustomDashboard.maxSchemes
            ? null
            : () => showCustomDashboardEditor(context, app),
        icon: const Icon(Icons.add),
        label: Text(
          app.settings.language == 'en' ? 'Add custom dashboard' : '新增自定义仪表盘',
        ),
      ),
      const SectionLabel('驾驶工具'),
      AppGroup(
        children: [
          ListTile(
            leading: Icon(
              Icons.show_chart_rounded,
              color: context.isDark ? raceCyan : const Color(0xff006c65),
            ),
            title: const LText('驾驶遥测', style: TextStyle(fontSize: 14)),
            subtitle: LText(
              '${app.sessions.length} 段本地记录',
              style: TextStyle(fontSize: 11, color: context.appMuted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => TelemetryPage(app: app)),
            ),
          ),
        ],
      ),
      const SizedBox(height: 20),
      const Center(
        child: LText(
          'HORIZON LINK  /  0.2',
          style: TextStyle(
            fontFamily: 'Dashboard',
            fontSize: 12,
            color: Color(0xff525661),
            letterSpacing: 3,
          ),
        ),
      ),
    ],
  );
  Widget _dashboardTile(
    BuildContext context,
    DashboardStyle style,
    String title,
    String code,
    String detail,
    Color color,
  ) => Material(
    color: context.appSurface,
    shape: context.panelShape(20),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => openDashboard(context, app, style),
      child: Column(
        children: [
          Container(
            color: Colors.black,
            padding: const EdgeInsets.fromLTRB(7, 10, 7, 2),
            child: AspectRatio(
              aspectRatio: 1280 / 540,
              child: IgnorePointer(
                child: DashCanvas(
                  frame: app.frame,
                  shiftTargetRpm: app.limiter.shiftTargetRpm,
                  settings: app.settings,
                  style: style,
                  destination: app.navigationLabel ?? app.destination,
                  navigation: app.navigation,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(17, 15, 15, 16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 9,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          LText(
                            title,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          LText(
                            code,
                            style: TextStyle(
                              fontFamily: 'Dashboard',
                              fontSize: 12,
                              color: color,
                              letterSpacing: 1,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 7),
                      LText(
                        detail,
                        style: TextStyle(fontSize: 10, color: context.appMuted),
                      ),
                    ],
                  ),
                ),
                Container(
                  width: 39,
                  height: 39,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: color,
                    size: 20,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
