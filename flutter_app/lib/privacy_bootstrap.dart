import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'app_controller.dart';
import 'main.dart';
import 'pages/privacy_page.dart';
import 'services/privacy_consent.dart';
import 'widgets/app_theme.dart';

/// Owns the real runtime. No game/network controller exists before consent.
class PrivacyBootstrap extends StatefulWidget {
  const PrivacyBootstrap({
    super.key,
    required this.consent,
    this.createController,
  });
  final PrivacyConsent consent;
  final AppController Function()? createController;
  @override
  State<PrivacyBootstrap> createState() => _PrivacyBootstrapState();
}

class _PrivacyBootstrapState extends State<PrivacyBootstrap> {
  AppController? app;
  bool english = false, busy = false, declined = false;
  String? error;
  @override
  void initState() {
    super.initState();
    widget.consent.addListener(_changed);
    if (widget.consent.loaded) {
      _changed();
    } else {
      unawaited(widget.consent.load());
    }
  }

  void _changed() {
    if (!mounted) return;
    if (widget.consent.accepted && app == null) {
      final controller = widget.createController?.call() ?? AppController();
      app = controller;
      controller.withdrawConsent = _withdraw;
      unawaited(
        controller.initialize().then((_) async {
          if (mounted && identical(app, controller) && !kIsWeb) {
            await controller.connect();
          }
        }),
      );
    } else if (!widget.consent.accepted && app != null) {
      app!.dispose();
      app = null;
    }
    setState(() {});
  }

  Future<void> _withdraw() async {
    // Save the current recording and drain pending writes before disposal.
    await app!.flushSaved();
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS)) {
      await WebViewCookieManager().clearCookies();
      await WebViewController().clearLocalStorage();
    }
    await widget.consent.revoke();
  }

  Future<void> _accept() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.consent.accept();
    } catch (_) {
      if (mounted) {
        setState(
          () => error = english
              ? 'Could not save your choice. Please retry.'
              : '无法保存选择，请重试。',
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    widget.consent.removeListener(_changed);
    app?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (app != null) return HorizonApp(key: ObjectKey(app), controller: app!);
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Builder(
        builder: (context) => Scaffold(
          appBar: AppBar(
            title: const Text('Horizon Link'),
            actions: [
              TextButton(
                onPressed: () => setState(() => english = !english),
                child: Text(english ? '中文' : 'English'),
              ),
            ],
          ),
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  english ? 'Before you start' : '使用前请阅读',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 20),
                Text(
                  english
                      ? 'With your agreement, Horizon Link listens for local game UDP data, displays local network addresses and checks weekly content from Tencent Cloud COS. Recordings and settings stay on this device. Websites only open when you choose them. Game coordinates are not phone location.'
                      : '同意后，Horizon Link 将监听局域网游戏 UDP、显示本机局域网地址，并从腾讯云 COS 检查每周内容。驾驶记录与设置保存在本机；第三方网页仅在主动打开时加载。游戏坐标不是手机定位。',
                  style: const TextStyle(height: 1.8),
                ),
                TextButton(
                  key: const ValueKey('read-privacy'),
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => PrivacyPage(english: english),
                    ),
                  ),
                  child: Text(
                    english
                        ? 'Read privacy policy & usage notice'
                        : '阅读隐私政策与使用说明',
                  ),
                ),
                if (!widget.consent.loaded)
                  const Center(child: CircularProgressIndicator()),
                if (error != null) Text(error!),
                if (declined)
                  Text(
                    english
                        ? 'No network services started. You may read the policy or decide later; existing data is kept.'
                        : '尚未启动网络服务。可继续阅读或稍后决定，已有数据保留。',
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  key: const ValueKey('accept-privacy'),
                  onPressed: !widget.consent.loaded || busy ? null : _accept,
                  child: Text(english ? 'Agree and continue' : '同意并继续'),
                ),
                OutlinedButton(
                  key: const ValueKey('decline-privacy'),
                  onPressed: busy
                      ? null
                      : () => setState(() => declined = true),
                  child: Text(english ? 'Decline for now' : '暂不同意'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
