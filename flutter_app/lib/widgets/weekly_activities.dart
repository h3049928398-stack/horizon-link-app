import 'dart:async';

import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../core/road_graph.dart';
import '../services/weekly_content_service.dart';
import 'app_theme.dart';

class WeeklyActivities extends StatelessWidget {
  final AppController app;
  const WeeklyActivities({super.key, required this.app});

  @override
  Widget build(BuildContext context) {
    final service = app.weekly;
    final period = service.displayed;
    final language = app.settings.language;
    final old = period != null && service.current == null;
    final status = switch (service.status) {
      WeeklyStatus.unconfigured => '每周内容尚未配置，等待发布',
      WeeklyStatus.checking => '正在检查每周内容',
      WeeklyStatus.failed => '更新失败，保留已缓存内容，可稍后重试',
      WeeklyStatus.ready => null,
      WeeklyStatus.idle => '等待发布本周活动',
    };
    String date(DateTime t) {
      final d = t.toLocal();
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')} '
          '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: SectionLabel(old ? '上期内容' : '本周活动')),
            IconButton(
              key: const ValueKey('weekly-refresh'),
              tooltip: context.tr('刷新每周内容'),
              onPressed: service.status == WeeklyStatus.checking
                  ? null
                  : () => unawaited(service.refresh(force: true)),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        if (status != null)
          LText(
            status,
            style: TextStyle(fontSize: 11, color: context.appMuted),
          ),
        if (period == null)
          const LText('暂无当周活动，请稍后刷新', style: TextStyle(fontSize: 12)),
        if (period != null) ...[
          Text(
            period.name.display(language),
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          Text(
            '${date(period.startsAt)} – ${date(period.endsAt)} (${context.tr('本机时间')})',
            style: TextStyle(fontSize: 10, color: context.appMuted),
          ),
          if (old) const LText('此内容已过期，仅供参考', style: TextStyle(fontSize: 12)),
          for (final group in const [
            ('seasonal', '季节赛事'),
            ('treasure', '每周宝箱'),
            ('other', '其他活动'),
          ])
            if (period.events.any((e) => e.type == group.$1)) ...[
              SectionLabel(group.$2),
              for (final event in period.events.where(
                (e) => e.type == group.$1,
              ))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: AppGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              event.name.display(language),
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (event.locations.isEmpty) const LText('位置待补充'),
                            for (final location in event.locations)
                              Builder(
                                builder: (context) {
                                  final graph = app.roadGraph;
                                  final place = graph == null
                                      ? null
                                      : location.resolve(graph, event.name);
                                  return Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: OutlinedButton.icon(
                                      key: ValueKey(
                                        'weekly-locate-${location.id}',
                                      ),
                                      onPressed: place == null
                                          ? null
                                          : () {
                                              final target = old
                                                  ? MapPlace(
                                                      place.id,
                                                      place.name,
                                                      '上期活动',
                                                      place.point,
                                                      nameZh: place.nameZh,
                                                      nameEn: place.nameEn,
                                                      quality: place.quality,
                                                      note:
                                                          '${context.tr('此内容已过期，仅供参考')} · ${place.note}',
                                                    )
                                                  : place;
                                              app.focusWeeklyPlace(target);
                                            },
                                      icon: const Icon(
                                        Icons.location_on_outlined,
                                        size: 18,
                                      ),
                                      label: Text(
                                        '${location.name.display(language)} · ${context.tr(place == null ? '位置待补充' : '地图定位')}',
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  );
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
        ],
      ],
    );
  }
}
