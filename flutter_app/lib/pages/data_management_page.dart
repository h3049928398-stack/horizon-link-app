import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/backup.dart';
import '../services/release_info.dart';
import '../widgets/liquid_glass.dart';

class DataManagementPage extends StatefulWidget {
  const DataManagementPage({super.key, required this.app});
  final AppController app;
  @override
  State<DataManagementPage> createState() => _DataManagementPageState();
}

class _DataManagementPageState extends State<DataManagementPage> {
  bool busy = false;
  String? message;
  bool get en => widget.app.settings.language == 'en';
  String copy(String zh, String english) => en ? english : zh;
  Future<bool> confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => LiquidGlassAlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(copy('取消', 'Cancel')),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(copy('确认', 'Confirm')),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> run(Future<String?> Function() action) async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      final result = await action();
      if (mounted) setState(() => message = result);
    } catch (_) {
      if (mounted) {
        setState(
          () => message = copy(
            '操作失败。原有记录未被导入替换，请检查文件格式、存储空间及文件访问权限后重试。',
            'Operation failed. No imported data replaced your records. Check the file format, free space and document access, then retry.',
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(copy('数据备份与恢复', 'Backup & restore'))),
    body: AnimatedBuilder(
      animation: widget.app,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            copy(
              '备份包含设置、自定义仪表方案和最近八段记录（含正在录制的快照），不含周内容缓存、网页数据或隐私同意。文件为明文，请保存在可信位置。恢复会替换设置、自定义方案和记录；旧备份不含自定义方案，恢复后列表为空。请先导出当前备份。',
              'Backups contain settings, custom dashboard layouts and the latest eight recordings, including a snapshot of any active recording. Weekly cache, website data and privacy consent are excluded. Files are plain text; store them privately. Restore replaces settings, layouts and recordings. Old backups have no custom layouts and restore an empty layout list. Export your current data first.',
            ),
            style: const TextStyle(height: 1.7),
          ),
          if (widget.app.storageReadFailed)
            Text(
              copy(
                '旧存档读取失败，已暂停自动写入以保护原文件。请保留设备原文件后再恢复有效备份；此时无法导出完整旧数据。',
                'The old save could not be read. Automatic writes are blocked to protect it. Preserve the original device file before restoring a valid backup. Export cannot recover unreadable records.',
              ),
            ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('export-backup'),
            onPressed: busy || !widget.app.ready || widget.app.storageReadFailed
                ? null
                : () => run(() async {
                    final text = widget.app.exportBackup();
                    parseUserBackup(text);
                    final saved = await ReleaseInfo.channel.invokeMethod<bool>(
                      'export',
                      {'text': text},
                    );
                    return saved == true
                        ? copy(
                            '备份已保存并读回校验。',
                            'Backup saved and verified by reading it back.',
                          )
                        : null;
                  }),
            icon: const Icon(Icons.save_alt),
            label: Text(copy('导出备份文件', 'Export backup file')),
          ),
          OutlinedButton.icon(
            key: const ValueKey('import-backup'),
            onPressed: busy || !widget.app.ready || widget.app.recording != null
                ? null
                : () => run(() async {
                    final text = await ReleaseInfo.channel.invokeMethod<String>(
                      'import',
                    );
                    if (text == null) return null;
                    final data = parseUserBackup(text);
                    if (!mounted) return null;
                    if (!await confirm(
                      copy('恢复备份？', 'Restore backup?'),
                      copy(
                        '文件含 ${(data['sessions'] as List).length} 段记录、${((data['settings'] as Map)['customDashboards'] as List? ?? []).length} 套自定义仪表（旧备份为零套），将替换当前设置、自定义方案和 ${widget.app.sessions.length} 段记录。请确认已备份当前数据。周内容缓存不变。',
                        'This file contains ${(data['sessions'] as List).length} recordings and ${((data['settings'] as Map)['customDashboards'] as List? ?? []).length} custom layouts (zero for older backups) and will replace your settings, layouts and ${widget.app.sessions.length} current recordings. Confirm you have backed up the current data. Weekly cache is unchanged.',
                      ),
                    )) {
                      return null;
                    }
                    await widget.app.restoreBackup(text);
                    return copy('备份已恢复。', 'Backup restored.');
                  }),
            icon: const Icon(Icons.restore),
            label: Text(copy('选择文件并恢复', 'Choose file to restore')),
          ),
          if (widget.app.recording != null)
            Text(
              copy(
                '录制中：请停止录制后再恢复或删除。',
                'Recording: stop before restoring or deleting.',
              ),
            ),
          if (busy) const LinearProgressIndicator(),
          if (message != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(message!),
            ),
          const Divider(),
          Text(copy('本地记录', 'Local recordings')),
          for (final session in widget.app.sessions)
            ListTile(
              title: Text('${session.started.toLocal()}'.split('.').first),
              subtitle: Text(
                '${session.samples.length} ${copy('采样', 'samples')} · ${session.source}${session.ended == null ? copy(' · 未结束的恢复记录', ' · recovered unfinished recording') : ''}',
              ),
              trailing: IconButton(
                tooltip: copy('删除记录', 'Delete recording'),
                icon: const Icon(Icons.delete_outline),
                onPressed:
                    busy ||
                        widget.app.recording != null ||
                        widget.app.storageReadFailed
                    ? null
                    : () => run(() async {
                        if (!await confirm(
                          copy('删除这段记录？', 'Delete this recording?'),
                          copy(
                            '只删除所选记录，不改变设置。此操作无法撤销，请先备份。',
                            'Only this recording is deleted. Settings are kept. This cannot be undone; back up first.',
                          ),
                        )) {
                          return null;
                        }
                        await widget.app.deleteSession(session.id);
                        return copy('记录已删除。', 'Recording deleted.');
                      }),
              ),
            ),
        ],
      ),
    ),
  );
}
