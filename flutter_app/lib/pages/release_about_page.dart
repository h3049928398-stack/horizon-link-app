import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_controller.dart';
import '../services/release_info.dart';
import '../widgets/liquid_glass.dart';
import 'privacy_page.dart';

class ReleaseAboutPage extends StatelessWidget {
  const ReleaseAboutPage({super.key, required this.app});
  final AppController app;
  @override
  Widget build(BuildContext context) {
    final en = app.settings.language == 'en';
    String copy(String zh, String english) => en ? english : zh;
    String info(String value) =>
        value.isEmpty ? copy('发布前待补充', 'Pending before release') : value;
    return Scaffold(
      appBar: AppBar(title: Text(copy('关于与隐私', 'About & privacy'))),
      body: ListView(
        children: [
          FutureBuilder<String>(
            future: ReleaseInfo.installedVersion(),
            builder: (context, snapshot) => ListTile(
              title: const Text('Horizon Link'),
              subtitle: Text(
                '${copy('安装版本', 'Installed version')}: ${snapshot.data ?? '…'}',
              ),
            ),
          ),
          ListTile(
            title: Text(copy('开发者', 'Developer')),
            subtitle: SelectableText(info(ReleaseInfo.developer)),
          ),
          ListTile(
            title: Text(copy('支持与隐私联系', 'Support & privacy contact')),
            subtitle: SelectableText(info(ReleaseInfo.email)),
          ),
          ListTile(
            title: Text(copy('费用与广告', 'Pricing & ads')),
            subtitle: Text(copy('免费，无广告', 'Free, no advertising')),
          ),
          ListTile(
            title: Text(copy('APP 备案号', 'APP filing number')),
            subtitle: Text(info(ReleaseInfo.filing)),
            trailing: const Icon(Icons.open_in_new),
            onTap: ReleaseInfo.filing.isEmpty
                ? null
                : () => launchUrl(
                    Uri.parse('https://beian.miit.gov.cn/'),
                    mode: LaunchMode.externalApplication,
                  ),
          ),
          ListTile(
            title: Text(copy('隐私政策与使用说明', 'Privacy & usage notice')),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => PrivacyPage(english: en)),
            ),
          ),
          if (app.withdrawConsent != null)
            ListTile(
              key: const ValueKey('withdraw-consent'),
              title: Text(copy('撤回隐私同意', 'Withdraw privacy consent')),
              subtitle: Text(
                copy(
                  '停止网络服务，保留设置和记录',
                  'Stop network services; keep settings and recordings',
                ),
              ),
              onTap: () async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (context) => LiquidGlassAlertDialog(
                    title: Text(copy('撤回同意？', 'Withdraw consent?')),
                    content: Text(
                      copy(
                        '保存当前记录快照，停止 UDP 和周内容服务，清除本应用网页 Cookie 与网页本地存储，返回使用前告知。设置和驾驶记录保留。',
                        'Save a snapshot, stop UDP and weekly content services, clear this app’s web cookies and local web storage, and return to the privacy notice. Settings and recordings are kept.',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: Text(copy('取消', 'Cancel')),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(copy('撤回', 'Withdraw')),
                      ),
                    ],
                  ),
                );
                if (yes != true) return;
                try {
                  await app.withdrawConsent!();
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          copy(
                            '撤回未完成，请检查存储后重试。',
                            'Withdrawal failed. Check storage and retry.',
                          ),
                        ),
                      ),
                    );
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}
