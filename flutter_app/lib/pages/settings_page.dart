import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../widgets/ios_options.dart';

import '../app_controller.dart';
import '../widgets/race_dashboard_selector.dart';
import '../widgets/app_theme.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/ios_glass_controls.dart';
import 'dashboard_screen.dart';
import '../widgets/connection_tutorial.dart';
import '../services/release_info.dart';
import '../widgets/version_check_tile.dart';
import 'release_about_page.dart';
import 'data_management_page.dart';

class SettingsPage extends StatelessWidget {
  final AppController app;
  const SettingsPage({super.key, required this.app});
  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      20,
      0,
      20,
      30 + LiquidGlass.bottomClearanceOf(context),
    ),
    children: [
      const SectionLabel('游戏连接'),
      AppGroup(
        children: [
          ListTile(
            leading: Icon(Icons.wifi_rounded, color: context.appAccent),
            title: LText(app.connected ? '已连接' : '未连接'),
            subtitle: LText(
              app.status,
              style: TextStyle(fontSize: 11, color: context.appMuted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showConnection(context, app),
          ),
        ],
      ),
      const SectionLabel('语言'),
      AppGroup(
        children: [
          ListTile(
            leading: Icon(Icons.translate_rounded, color: context.appAccent),
            title: const LText('语言'),
            trailing: DropdownButton<String>(
              key: const ValueKey('language-selector'),
              value: app.settings.language,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: 'zh', child: Text('中文')),
                DropdownMenuItem(value: 'en', child: Text('English')),
              ],
              onChanged: (v) {
                if (v != null) app.updateSettings((s) => s.language = v);
              },
            ).forPhone(context, context.tr('语言')),
          ),
        ],
      ),
      const SectionLabel('外观'),
      AppGroup(
        children: [
          ListTile(
            leading: Icon(
              Icons.brightness_6_outlined,
              color: context.appAccent,
            ),
            title: const LText('主题'),
            trailing: DropdownButton<AppAppearance>(
              key: const ValueKey('appearance-selector'),
              value: app.settings.appearance,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(value: AppAppearance.dark, child: LText('深色')),
                DropdownMenuItem(
                  value: AppAppearance.light,
                  child: LText('浅色'),
                ),
                DropdownMenuItem(
                  value: AppAppearance.system,
                  child: LText('跟随系统'),
                ),
              ],
              onChanged: (value) {
                if (value != null) {
                  app.updateSettings((s) => s.appearance = value);
                }
              },
            ).forPhone(context, context.tr('主题')),
          ),
        ],
      ),
      const SectionLabel('驾驶偏好'),
      AppGroup(
        children: [
          RaceDashboardSelector(app: app),
          const Divider(indent: 16, endIndent: 16),
          SwitchListTile.adaptive(
            key: const ValueKey('auto-race-recording'),
            title: const LText('进入比赛自动开始数据记录', style: TextStyle(fontSize: 14)),
            subtitle: LText(
              '下一场比赛生效，不影响当前录制；关闭后仍可手动录制',
              style: TextStyle(fontSize: 10, color: context.appMuted),
            ),
            value: app.settings.autoRecord,
            onChanged: (v) => app.updateSettings((s) => s.autoRecord = v),
          ).forPhone(context),
          const Divider(indent: 16, endIndent: 16),
          SwitchListTile.adaptive(
            title: const LText('名次提升特效', style: TextStyle(fontSize: 14)),
            value: app.settings.effects,
            onChanged: (v) => app.updateSettings((s) => s.effects = v),
          ).forPhone(context),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            title: const LText('车速单位', style: TextStyle(fontSize: 14)),
            trailing: SegmentedButton<bool>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: false,
                  label: LText('km/h', style: TextStyle(fontSize: 11)),
                ),
                ButtonSegment(
                  value: true,
                  label: LText('mph', style: TextStyle(fontSize: 11)),
                ),
              ],
              selected: {app.settings.mph},
              onSelectionChanged: (v) =>
                  app.updateSettings((s) => s.mph = v.first),
            ).forPhone(context, context.tr('车速单位'), trailing: true),
          ),
          const Divider(indent: 16, endIndent: 16),
          ListTile(
            title: const LText('仪表组件与换挡灯', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => showDashSettings(context, app),
          ),
        ],
      ),
      const SectionLabel('关于与帮助'),
      AppGroup(
        children: [
          ListTile(
            key: const ValueKey('data-management'),
            leading: const Icon(Icons.save_alt),
            title: Text(
              app.settings.language == 'en' ? 'Backup & restore' : '数据备份与恢复',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => DataManagementPage(app: app),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('about-privacy'),
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(
              app.settings.language == 'en' ? 'About & privacy' : '关于与隐私',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => ReleaseAboutPage(app: app),
              ),
            ),
          ),
          ListTile(
            key: const ValueKey('open-source-licenses'),
            leading: const Icon(Icons.description_outlined),
            title: const LText('开源许可', style: TextStyle(fontSize: 14)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () async {
              final version = await ReleaseInfo.installedVersion();
              if (!context.mounted) return;
              showLicensePage(
                context: context,
                applicationName: 'Horizon Link',
                applicationVersion: version,
              );
            },
          ),
          const Divider(indent: 55),
          const VersionCheckTile(),
        ],
      ),
      Padding(
        padding: EdgeInsets.only(top: 25),
        child: LText(
          '驾驶数据优先保存在本机。暂停、回溯或断流不会直接判定为完赛。',
          style: TextStyle(fontSize: 10, color: context.appMuted, height: 1.8),
        ),
      ),
    ],
  );
}

void showConnection(BuildContext context, AppController app) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _ConnectionSheet(app: app),
  );
}

class _ConnectionSheet extends StatefulWidget {
  final AppController app;
  const _ConnectionSheet({required this.app});

  @override
  State<_ConnectionSheet> createState() => _ConnectionSheetState();
}

class _ConnectionSheetState extends State<_ConnectionSheet> {
  AppController get app => widget.app;
  late final TextEditingController port;
  String? error;

  @override
  void initState() {
    super.initState();
    port = TextEditingController(text: '${app.settings.port}');
  }

  @override
  void dispose() {
    // The modal's pop Future completes before its exit animation finishes.
    // Keep the controller alive until the text field is actually unmounted.
    port.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: app,
    builder: (context, _) => SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          0,
          24,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight:
                (MediaQuery.sizeOf(context).height * .86 -
                        MediaQuery.viewInsetsOf(context).bottom -
                        24)
                    .clamp(120, double.infinity),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final content = Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const LText(
                    '连接游戏',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LText(
                            '手机与游戏设备连接同一局域网。游戏中打开 Data Out，目标 IP 填手机的局域网地址，端口与下方一致。',
                            style: TextStyle(
                              fontSize: 12,
                              color: context.appMuted,
                              height: 1.9,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const ConnectionTutorial(),
                          const SizedBox(height: 20),
                          TextField(
                            controller: port,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: context.tr('UDP 接收端口'),
                              helperText: context.tr('默认 8000，避开 5200–5300'),
                              errorText: error == null
                                  ? null
                                  : context.tr(error!),
                            ),
                          ),
                          const SizedBox(height: 18),
                          if (kIsWeb)
                            LText(
                              '浏览器仅预览仪表，不能直接接收 UDP。安卓/iOS 安装版由 Dart 原生套接字接收。',
                              style: TextStyle(
                                fontSize: 11,
                                color: context.appAccent,
                                height: 1.8,
                              ),
                            ),
                          if (app.addresses.isNotEmpty)
                            SelectableText(
                              context.tr('手机地址：') + app.addresses.join(' / '),
                              style: TextStyle(
                                fontSize: 12,
                                color: context.appAccent,
                              ),
                            ),
                          const SizedBox(height: 12),
                          LText(
                            '${app.status}\n数据包 ${app.packets} · 无效 ${app.rejected}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.appMuted,
                              height: 1.8,
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (LiquidGlass.enabledOf(context))
                    IosGlassControls(
                      labels: [context.tr('关闭'), context.tr('开始监听')],
                      onAction: (index) {
                        if (index == 0) {
                          Navigator.pop(context);
                        } else {
                          _startListening();
                        }
                      },
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const LText('关闭'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: kIsWeb ? null : _startListening,
                            child: const LText('开始监听'),
                          ),
                        ),
                      ],
                    ),
                ],
              );
              final scaler = MediaQuery.textScalerOf(context);
              final compactHeight =
                  144 + scaler.scale(22) + 2 * scaler.scale(17);
              if (LiquidGlass.enabledOf(context) &&
                  constraints.maxHeight < compactHeight) {
                return SingleChildScrollView(child: content);
              }
              return content;
            },
          ),
        ),
      ),
    ),
  );

  Future<void> _startListening() async {
    final value = int.tryParse(port.text);
    if (value == null ||
        value < 1024 ||
        value > 65535 ||
        (value >= 5200 && value <= 5300)) {
      setState(() => error = '请输入有效端口并避开 5200–5300');
      return;
    }
    app.updateSettings((s) => s.port = value);
    await app.connect();
  }
}
