import 'package:flutter/material.dart';

import '../services/app_version_check.dart';
import '../services/release_info.dart';
import 'app_theme.dart';

class VersionCheckTile extends StatefulWidget {
  const VersionCheckTile({
    super.key,
    this.installedVersion = ReleaseInfo.installedVersion,
    this.check = checkAppVersion,
  });

  final Future<String> Function() installedVersion;
  final Future<String?> Function(String) check;

  @override
  State<VersionCheckTile> createState() => _VersionCheckTileState();
}

class _VersionCheckTileState extends State<VersionCheckTile> {
  late final _installed = widget.installedVersion();
  bool _busy = false;
  String _status = '点击检查更新';
  String? _latest;

  Future<void> _check() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _latest = null;
      _status = '正在检查更新';
    });
    try {
      final installed = await _installed;
      if (!mounted) return;
      final latest = await widget.check(installed);
      if (!mounted) return;
      setState(() {
        _latest = latest;
        _status = latest == null ? '已是最新版本' : '发现新版本';
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _status = '检查失败，点击重试';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListTile(
    leading: const Icon(Icons.info_outline_rounded),
    title: const Text('Horizon Link', style: TextStyle(fontSize: 14)),
    subtitle: FutureBuilder<String>(
      future: _installed,
      builder: (context, snapshot) => Semantics(
        liveRegion: true,
        child: Text(
          '${snapshot.data ?? '…'} · ${context.tr(_status)}${_latest == null ? '' : ' $_latest'}',
          style: TextStyle(fontSize: 11, color: context.appMuted),
        ),
      ),
    ),
    trailing: const Icon(Icons.refresh_rounded),
    onTap: _busy ? null : _check,
  );
}
