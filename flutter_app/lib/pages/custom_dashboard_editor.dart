import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_controller.dart';
import '../widgets/dash_canvas.dart';
import '../widgets/liquid_glass.dart';

Future<void> showCustomDashboardEditor(
  BuildContext context,
  AppController app, {
  String? id,
}) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => CustomDashboardEditor(app: app, id: id),
);

class CustomDashboardEditor extends StatefulWidget {
  final AppController app;
  final String? id;
  const CustomDashboardEditor({super.key, required this.app, this.id});
  @override
  State<CustomDashboardEditor> createState() => _CustomDashboardEditorState();
}

class _CustomDashboardEditorState extends State<CustomDashboardEditor> {
  late final TextEditingController code;
  CustomDashboard? checked;
  String? error;
  bool busy = false;
  ScrollController? _scroll;
  bool get en => widget.app.settings.language == 'en';
  String t(String zh, String english) => en ? english : zh;
  @override
  void initState() {
    super.initState();
    code = TextEditingController(
      text:
          widget.app.settings.customDashboards[widget.id]?.code ??
          CustomDashboard.example,
    );
    code.addListener(invalidate);
  }

  void invalidate() => setState(() {
    checked = null;
    error = null;
  });
  @override
  void dispose() {
    code.removeListener(invalidate);
    code.dispose();
    super.dispose();
  }

  void check() {
    FocusScope.of(context).unfocus();
    try {
      final result = CustomDashboard.parse(code.text);
      setState(() {
        checked = result;
        error = null;
      });
    } on FormatException catch (e) {
      setState(() {
        checked = null;
        error = e.message;
      });
    }
    revealResult();
  }

  void revealResult() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final scroll = _scroll;
      if (mounted && scroll != null && scroll.hasClients) {
        unawaited(
          scroll.animateTo(
            scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          ),
        );
      }
    });
  }

  Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(t('已复制', 'Copied'))));
    }
  }

  Future<void> save() async {
    if (checked == null || busy) return;
    setState(() => busy = true);
    try {
      await widget.app.saveCustomDashboard(
        widget.id ?? 'custom-${DateTime.now().microsecondsSinceEpoch}',
        checked!,
      );
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) {
        setState(() {
          busy = false;
          error = t(
            '保存失败，原方案和输入已保留。请检查存储空间或先备份损坏存档。',
            'Save failed. Your previous layout and input are retained. Check storage or back up damaged data first.',
          );
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return PopScope(
      canPop: !busy,
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: .94,
        minChildSize: .6,
        maxChildSize: .98,
        builder: (context, scroll) {
          _scroll = scroll;
          return Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              4,
              20,
              MediaQuery.viewInsetsOf(context).bottom + 16,
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        t('自定义仪表盘', 'Custom dashboard'),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      key: const ValueKey('custom-editor-close'),
                      tooltip: t('关闭', 'Close'),
                      onPressed: busy ? null : () => Navigator.pop(context),
                      style: IconButton.styleFrom(
                        backgroundColor: colors.surfaceContainerHighest,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.close_rounded, size: 20),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView(
                    controller: scroll,
                    children: [
                      DecoratedBox(
                        decoration: BoxDecoration(
                          color: colors.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: ExpansionTile(
                          tilePadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                          ),
                          childrenPadding: const EdgeInsets.fromLTRB(
                            14,
                            0,
                            14,
                            14,
                          ),
                          shape: const Border(),
                          collapsedShape: const Border(),
                          leading: Icon(
                            Icons.info_outline_rounded,
                            size: 20,
                            color: colors.primary,
                          ),
                          title: Text(
                            t('使用说明', 'How it works'),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          children: [
                            Text(
                              t(
                                '复制提示词并补充效果要求，交给任意 AI；将生成的 JSON 粘贴到下方，检查预览后保存。仅改变外观，不执行脚本或联网。',
                                'Copy the prompt, append your design requirements and give it to any AI. Paste the JSON below, check the preview, then save. Layout only; no scripts or network.',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.6,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              t(
                                'AI 可能生成不兼容内容，可复制错误交回 AI 修正。最多 20 套，每套 128 个组件、64 KiB。预览使用当前遥测，无数据时显示占位。',
                                'AI output may need corrections; copy errors back to the AI. Up to 20 layouts, 128 components and 64 KiB each. Preview uses current telemetry or placeholders.',
                              ),
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.6,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: _EditorAction(
                              key: const ValueKey('copy-dashboard-prompt'),
                              onPressed: busy
                                  ? null
                                  : () => unawaited(
                                      copy(CustomDashboard.prompt(english: en)),
                                    ),
                              icon: Icons.copy_rounded,
                              label: t('复制 AI 提示词', 'Copy AI prompt'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _EditorAction(
                              key: const ValueKey('load-dashboard-example'),
                              onPressed: busy
                                  ? null
                                  : () => code.text = CustomDashboard.example,
                              icon: Icons.code_rounded,
                              label: t('载入示例', 'Load example'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        key: const ValueKey('custom-dashboard-code'),
                        controller: code,
                        enabled: !busy,
                        minLines: 8,
                        maxLines: 14,
                        autocorrect: false,
                        enableSuggestions: false,
                        style: const TextStyle(fontSize: 12, height: 1.5),
                        decoration: InputDecoration(
                          labelText: t('JSON 布局代码', 'JSON layout code'),
                          alignLabelWithHint: true,
                          fillColor: colors.surfaceContainerLow,
                          contentPadding: const EdgeInsets.all(16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: colors.outlineVariant,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide(
                              color: colors.outlineVariant,
                            ),
                          ),
                        ),
                      ),
                      if (error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colors.errorContainer,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: SelectableText(
                            error!,
                            key: const ValueKey('custom-dashboard-error'),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: colors.onErrorContainer,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _EditorAction(
                          key: const ValueKey('copy-dashboard-error'),
                          onPressed: busy
                              ? null
                              : () => unawaited(
                                  copy(
                                    'Fix this Horizon Link schemaVersion 1 layout. Return only valid JSON.\n$error\n${code.text}',
                                  ),
                                ),
                          icon: Icons.copy_rounded,
                          label: t('复制错误与代码', 'Copy errors & code'),
                        ),
                      ],
                      if (checked != null) ...[
                        const SizedBox(height: 20),
                        Text(
                          checked!.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(14),
                          child: AnimatedBuilder(
                            animation: widget.app,
                            builder: (context, _) => AspectRatio(
                              aspectRatio: 1280 / 540,
                              child: IgnorePointer(
                                child: DashCanvas(
                                  frame: widget.app.frame,
                                  shiftTargetRpm:
                                      widget.app.limiter.shiftTargetRpm,
                                  settings: widget.app.settings,
                                  style: DashboardStyle.professional,
                                  customLayout: checked,
                                  hasData: widget.app.hasTelemetry,
                                  navigation: widget.app.navigation,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Divider(height: 1, color: colors.outlineVariant),
                const SizedBox(height: 16),
                LiquidGlassActions(
                  child: Row(
                    children: [
                      Expanded(
                        child: _EditorAction(
                          key: const ValueKey('check-custom-dashboard'),
                          onPressed: busy ? null : check,
                          icon: Icons.fact_check_outlined,
                          label: t('检查并预览', 'Check & preview'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _EditorAction(
                          key: const ValueKey('save-custom-dashboard'),
                          primary: true,
                          onPressed: checked == null || busy ? null : save,
                          icon: Icons.check_rounded,
                          label: busy ? t('保存中', 'Saving') : t('保存', 'Save'),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// One geometry and typography for every labeled action in this sheet.
/// Only the final save action uses the primary fill.
class _EditorAction extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String label;
  final bool primary;
  const _EditorAction({
    super.key,
    required this.onPressed,
    required this.icon,
    required this.label,
    this.primary = false,
  });
  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final shared = ButtonStyle(
      minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
      maximumSize: const WidgetStatePropertyAll(Size(double.infinity, 48)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 12),
      ),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      textStyle: const WidgetStatePropertyAll(
        TextStyle(
          fontFamily: 'Chinese',
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    final content = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label, maxLines: 1),
          ),
        ),
      ],
    );
    return SizedBox(
      height: 48,
      child: primary
          ? FilledButton(onPressed: onPressed, style: shared, child: content)
          : OutlinedButton(
              onPressed: onPressed,
              style: shared.copyWith(
                side: WidgetStateProperty.resolveWith(
                  (states) => BorderSide(
                    color: states.contains(WidgetState.disabled)
                        ? colors.onSurface.withValues(alpha: .12)
                        : colors.outlineVariant,
                  ),
                ),
              ),
              child: content,
            ),
    );
  }
}
