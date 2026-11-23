import 'package:flutter/material.dart';

import 'ios_options.dart';

import '../app_controller.dart';
import 'app_theme.dart';

String dashboardName(
  BuildContext context,
  AppController app,
  DashboardRef ref,
) => ref.kind == 'custom'
    ? app.settings.customDashboards[ref.id]?.name ?? context.tr('基础仪表')
    : context.tr(DashboardStyle.values.byName(ref.id).title);

class RaceDashboardSelector extends StatelessWidget {
  final AppController app;
  const RaceDashboardSelector({super.key, required this.app});
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => ListTile(
      horizontalTitleGap: 12,
      title: Tooltip(
        message: app.settings.language == 'en'
            ? 'Next race; restores the previous dashboard on exit. Manual selection takes control.'
            : '下一场赛事生效，结束后恢复赛前仪表；手动选择会接管本场切换。',
        child: Text(
          app.settings.language == 'en'
              ? 'Dashboard on race entry'
              : '进入赛事后切换仪表盘',
          style: const TextStyle(fontSize: 14),
        ),
      ),
      trailing: SizedBox(
        width: (constraints.maxWidth * .4).clamp(80.0, 180.0),
        child:
            DropdownButton<DashboardRef>(
              key: const ValueKey('race-dashboard-selector'),
              isExpanded: true,
              underline: const SizedBox.shrink(),
              value: app.settings.raceDashboard,
              hint: Align(
                alignment: Alignment.centerRight,
                child: Text(
                  app.settings.language == 'en' ? 'Do not switch' : '不切换',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              selectedItemBuilder: (context) => [
                for (final ref in _options)
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      _label(context, ref),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              items: [
                for (final ref in _options)
                  DropdownMenuItem<DashboardRef>(
                    value: ref,
                    child: Text(
                      _label(context, ref),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: app.dataMutation
                  ? null
                  : (value) =>
                        app.updateSettings((s) => s.raceDashboard = value),
            ).forPhone(
              context,
              app.settings.language == 'en'
                  ? 'Dashboard on race entry'
                  : '进入赛事后切换仪表盘',
            ),
      ),
    ),
  );

  List<DashboardRef?> get _options => [
    null,
    for (final id in DashboardRef.builtinIds) DashboardRef.builtin(id),
    for (final id in app.settings.customDashboards.keys)
      DashboardRef.custom(id),
  ];
  String _label(BuildContext context, DashboardRef? ref) => ref == null
      ? (app.settings.language == 'en' ? 'Do not switch' : '不切换')
      : dashboardName(context, app, ref);
}
