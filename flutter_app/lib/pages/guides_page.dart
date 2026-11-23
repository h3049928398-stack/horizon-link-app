import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../app_controller.dart';
import '../core/web_navigation.dart';
import '../widgets/app_theme.dart';
import '../widgets/liquid_glass.dart';
import '../widgets/weekly_activities.dart';

class GuidesPage extends StatelessWidget {
  final AppController app;
  const GuidesPage({super.key, required this.app});
  @override
  Widget build(BuildContext context) => ListView(
    padding: EdgeInsets.fromLTRB(
      20,
      5,
      20,
      25 + LiquidGlass.bottomClearanceOf(context),
    ),
    children: [
      Container(
        padding: const EdgeInsets.all(23),
        decoration: ShapeDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          shape: context.panelShape(22),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.sports_score_rounded,
              size: 37,
              color: context.appAccent,
            ),
            const SizedBox(height: 21),
            const LText(
              '本周，开出新成绩',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            LText(
              '季节赛、调校与探索攻略，\n在熟悉的作者页面里找到答案。',
              style: TextStyle(
                fontSize: 12,
                color: context.appMuted,
                height: 1.9,
              ),
            ),
            const SizedBox(height: 21),
            FilledButton.icon(
              onPressed: () => _open(context, app.guideUrl),
              icon: const Icon(Icons.open_in_new_rounded, size: 17),
              label: const LText('打开攻略网页'),
            ),
          ],
        ),
      ),
      WeeklyActivities(app: app),
      const SectionLabel('我的摄影作品'),
      AppGroup(
        children: [
          ListTile(
            key: const ValueKey('my-forza-photos'),
            leading: Icon(
              Icons.photo_library_outlined,
              color: context.appAccent,
            ),
            title: const LText('My Forza 摄影作品', style: TextStyle(fontSize: 15)),
            subtitle: LText(
              '在浏览器中查看你在游戏中拍摄的照片',
              style: TextStyle(fontSize: 10, color: context.appMuted),
            ),
            trailing: const Icon(Icons.open_in_new_rounded, size: 20),
            onTap: () => _openPhotos(context),
          ),
        ],
      ),
      const SectionLabel('我的攻略来源'),
      AppGroup(
        children: [
          ListTile(
            leading: Icon(Icons.language_rounded, color: context.appAccent),
            title: const LText('网页攻略', style: TextStyle(fontSize: 15)),
            subtitle: LText(
              app.guideUrl,
              style: TextStyle(fontSize: 10, color: context.appMuted),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(
              Icons.lock_outline_rounded,
              size: 20,
              semanticLabel: context.tr('网页地址不可编辑'),
            ),
          ),
          const Divider(indent: 55),
          ListTile(
            leading: const Icon(Icons.newspaper_rounded),
            title: const LText('Forza 官方新闻', style: TextStyle(fontSize: 15)),
            subtitle: LText(
              '游戏更新与社区动态',
              style: TextStyle(fontSize: 10, color: context.appMuted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _open(context, 'https://forza.net/news'),
          ),
          const Divider(indent: 55),
          ListTile(
            leading: const Icon(Icons.map_outlined),
            title: const LText('FH6 官方地图参考', style: TextStyle(fontSize: 15)),
            subtitle: LText(
              '查看游戏公开地图',
              style: TextStyle(fontSize: 10, color: context.appMuted),
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => _open(
              context,
              'https://forza.net/news/forza-horizon-6-full-map-reveal',
            ),
          ),
        ],
      ),
      Padding(
        padding: EdgeInsets.only(top: 22),
        child: LText(
          '攻略内容在小黑盒原站展示，版权归原作者所有，已获得作者的展示允许。活动位置来源及验证状态请查看地图说明。',
          style: TextStyle(fontSize: 11, color: context.appMuted, height: 1.9),
        ),
      ),
    ],
  );
  Future<void> _openPhotos(BuildContext context) async {
    var opened = false;
    try {
      opened = await launchUrl(
        Uri.parse('https://forza.net/myforza'),
        mode: LaunchMode.externalApplication,
        webOnlyWindowName: '_blank',
      );
    } catch (_) {
      // Keep the page usable if the browser cannot be started.
    }
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: LText('网页暂时无法打开')));
    }
  }

  void _open(BuildContext context, String url) {
    if (kIsWeb) {
      launchUrl(Uri.parse(url), webOnlyWindowName: '_blank');
    } else {
      Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => GuideReader(url: url)),
      );
    }
  }
}

class GuideReader extends StatefulWidget {
  final String url;
  const GuideReader({super.key, required this.url});
  @override
  State<GuideReader> createState() => _GuideReaderState();
}

class _GuideReaderState extends State<GuideReader> {
  late final WebViewController web;
  bool failed = false;
  int progress = 0;
  bool prompting = false;
  Future<NavigationDecision> _navigation(NavigationRequest request) async {
    final decision = guideNavigation(widget.url, request.url);
    if (decision == WebNavigation.internal) return NavigationDecision.navigate;
    if (decision == WebNavigation.blocked ||
        !request.isMainFrame ||
        prompting ||
        !mounted) {
      return NavigationDecision.prevent;
    }
    prompting = true;
    try {
      final en = Localizations.localeOf(context).languageCode == 'en';
      final yes = await showDialog<bool>(
        context: context,
        builder: (context) => LiquidGlassAlertDialog(
          title: Text(en ? 'Open another website?' : '打开其他网站？'),
          content: Text(
            '${en ? 'Continue in the system browser:' : '将在系统浏览器打开：'}\n${Uri.parse(request.url).host}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(en ? 'Cancel' : '取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(en ? 'Open' : '打开'),
            ),
          ],
        ),
      );
      if (yes == true) {
        await launchUrl(
          Uri.parse(request.url),
          mode: LaunchMode.externalApplication,
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: LText('网页暂时无法打开')));
      }
    } finally {
      prompting = false;
    }
    return NavigationDecision.prevent;
  }

  @override
  void initState() {
    super.initState();
    web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: _navigation,
          onProgress: (v) {
            if (mounted) setState(() => progress = v);
          },
          onWebResourceError: (e) {
            if (e.isForMainFrame == true && mounted) {
              setState(() => failed = true);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop) return;
      if (await web.canGoBack()) {
        await web.goBack();
      } else if (context.mounted) {
        Navigator.of(context).pop();
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const LText('攻略阅读'),
        actions: [
          IconButton(
            tooltip: context.tr('外部打开'),
            onPressed: () => launchUrl(
              Uri.parse(widget.url),
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.open_in_new_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          if (progress < 100) LinearProgressIndicator(value: progress / 100),
          Expanded(
            child: failed
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const LText('网页暂时无法打开'),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () {
                            setState(() => failed = false);
                            web.reload();
                          },
                          child: const LText('重新加载'),
                        ),
                      ],
                    ),
                  )
                : WebViewWidget(controller: web),
          ),
        ],
      ),
    ),
  );
}
