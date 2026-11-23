import 'package:flutter/material.dart';

import 'app_theme.dart';

const connectionTutorialImages = [
  'assets/connection/data-out.png',
  'assets/connection/ip-address.png',
  'assets/connection/port.png',
];

const _titles = ['开启数据输出', '填写手机 IP', '设置相同端口'];
const _instructions = [
  '游戏内打开「设置 → 抬头显示与游戏」，找到「遥测」，将「数据输出」设为「开启」。',
  '打开「数据输出 IP 地址」，填写本弹窗显示的手机局域网地址。截图中的个人 IP 已遮盖，请勿照抄截图或游戏中的示例地址。',
  '打开「数据输出 IP 端口」，填写与本 App 接收端口相同的数值，默认 8000。返回游戏驾驶，收到数据包后右上角会亮起「已连接」。',
];

class ConnectionTutorial extends StatefulWidget {
  const ConnectionTutorial({super.key});

  @override
  State<ConnectionTutorial> createState() => _ConnectionTutorialState();
}

class _ConnectionTutorialState extends State<ConnectionTutorial> {
  int step = 0;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          const Expanded(
            child: LText('连接教程', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          Text(
            '${step + 1} / 3',
            style: TextStyle(color: context.appMuted, fontSize: 12),
          ),
        ],
      ),
      const SizedBox(height: 10),
      LText(
        _titles[step],
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
      ),
      const SizedBox(height: 8),
      LText(
        _instructions[step],
        style: TextStyle(fontSize: 12, height: 1.7, color: context.appMuted),
      ),
      const SizedBox(height: 10),
      Semantics(
        button: true,
        label: context.tr('放大教程图片'),
        child: InkWell(
          key: const ValueKey('connection-tutorial-image'),
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showImage(context, step),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.asset(
                connectionTutorialImages[step],
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      LText(
        '点击图片放大，可双指缩放',
        style: TextStyle(fontSize: 10, color: context.appMuted),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: TextButton.icon(
              key: const ValueKey('connection-tutorial-previous'),
              onPressed: step == 0 ? null : () => setState(() => step--),
              icon: const Icon(Icons.chevron_left_rounded, size: 18),
              label: const LText('上一步'),
            ),
          ),
          Expanded(
            child: TextButton.icon(
              key: const ValueKey('connection-tutorial-next'),
              onPressed: step == 2 ? null : () => setState(() => step++),
              icon: const Icon(Icons.chevron_right_rounded, size: 18),
              label: const LText('下一步'),
            ),
          ),
        ],
      ),
    ],
  );

  void _showImage(BuildContext context, int index) =>
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(title: LText(_titles[index])),
            body: SafeArea(
              child: InteractiveViewer(
                key: const ValueKey('connection-tutorial-viewer'),
                minScale: 1,
                maxScale: 6,
                child: Center(
                  child: Image.asset(
                    connectionTutorialImages[index],
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}
