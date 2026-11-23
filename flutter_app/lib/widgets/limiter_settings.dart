import 'package:flutter/material.dart';

import '../app_controller.dart';
import '../l10n.dart';

class LimiterSettings extends StatelessWidget {
  final AppController app;
  const LimiterSettings({super.key, required this.app});
  @override
  Widget build(BuildContext context) {
    final state = app.limiter;
    final en = app.settings.language == 'en';
    final status = !state.available
        ? (en ? 'Waiting for driving data' : '等待驾驶数据')
        : state.limiterRpm == null
        ? (en ? 'Learning · ${state.bounces}/3' : '学习中 · ${state.bounces}/3')
        : (en
              ? 'Estimated limiter: ${state.limiterRpm!.round()} RPM'
              : '已标定限转估计：${state.limiterRpm!.round()} RPM');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LText('换挡灯自动标定', style: TextStyle(fontWeight: FontWeight.w600)),
        Text(
          state.vehicleKey == null ? status : '${state.vehicleKey} · $status',
          key: const ValueKey('limiter-status'),
        ),
        if (state.shiftTargetRpm != null)
          Text(
            en
                ? 'Shift cue: ${state.shiftTargetRpm!.round()} RPM'
                : '当前挡换挡提示：${state.shiftTargetRpm!.round()} RPM',
          ),
        const LText(
          '在游戏中保持同一挡全油门至限转反弹，自动学习；未标定时不提示。改装后可重新标定。',
          style: TextStyle(fontSize: 12),
        ),
        TextButton(
          key: const ValueKey('reset-limiter'),
          onPressed:
              state.available &&
                  app.ready &&
                  !app.storageReadFailed &&
                  !app.dataMutation
              ? app.resetCurrentLimiter
              : null,
          child: const LText('重新标定当前车辆'),
        ),
      ],
    );
  }
}
