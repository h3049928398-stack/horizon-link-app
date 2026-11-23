import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

class AppCopy {
  final String language;
  const AppCopy(this.language);
  static const delegate = _AppCopyDelegate();
}

class _AppCopyDelegate extends LocalizationsDelegate<AppCopy> {
  const _AppCopyDelegate();
  @override
  bool isSupported(Locale locale) => ['zh', 'en'].contains(locale.languageCode);
  @override
  Future<AppCopy> load(Locale locale) =>
      SynchronousFuture(AppCopy(locale.languageCode));
  @override
  bool shouldReload(_AppCopyDelegate old) => false;
}

/// Display copy only. Data IDs, category keys and saved records stay stable.
String localize(String value, String language) {
  if (language != 'en') {
    return value == 'POSITION GAINED' ? '名次提升' : value;
  }
  var result = value;
  for (final entry in _templates) {
    result = result.replaceAllMapped(entry.$1, (match) {
      var text = entry.$2;
      for (var i = 1; i <= match.groupCount; i++) {
        text = text.replaceAll('{${i - 1}}', match.group(i)!);
      }
      return text;
    });
  }
  return result.replaceAllMapped(_copyPattern, (match) => _english[match[0]]!);
}

extension AppTranslation on BuildContext {
  String tr(String value) => localize(
    value,
    Localizations.of<AppCopy>(this, AppCopy)?.language ?? 'zh',
  );
}

// Sort longest first so complete sentences win over their component labels.
final _copyPattern = RegExp(
  (_english.keys.toList()..sort((a, b) => b.length.compareTo(a.length)))
      .map(RegExp.escape)
      .join('|'),
);
final _templates = _templateCopy.entries.map((entry) {
  final pattern = RegExp.escape(entry.key)
      .replaceAllMapped(RegExp(r'\\\{\d+\\\}'), (_) => r'([^\n]+?)');
  return (RegExp(pattern), entry.value);
}).toList();

const _english = <String, String>{
  '本周活动': 'This week',
  '上期内容': 'Previous activities',
  '上期活动': 'Previous activity',
  '季节赛事': 'Seasonal events',
  '每周宝箱': 'Weekly treasure',
  '其他活动': 'Other activities',
  '每周内容尚未配置，等待发布': 'Weekly content is not configured yet',
  '正在检查每周内容': 'Checking weekly content',
  '更新失败，保留已缓存内容，可稍后重试':
      'Update failed. Cached content is retained. Try again later.',
  '等待发布本周活动': 'Waiting for this week’s activities',
  '刷新每周内容': 'Refresh weekly content',
  '暂无当周活动，请稍后刷新': 'No activities available. Refresh later.',
  '本机时间': 'device time',
  '此内容已过期，仅供参考': 'Expired content, for reference only',
  '位置待补充': 'Location pending',
  '地图定位': 'Show on map',
  '隐藏本周活动': 'Hide weekly activities',
  '显示本周活动': 'Show weekly activities',
  '已实测位置': 'Verified location',
  '攻略内容在小黑盒原站展示，版权归原作者所有，已获得作者的展示允许。活动位置来源及验证状态请查看地图说明。': 'Guides are shown on Xiaoheihe, belong to their authors and are displayed with the author’s permission. See map notes for location sources and verification status.',

  '我的摄影作品': 'My photography',
  'My Forza 摄影作品': 'My Forza photos',
  '在浏览器中查看你在游戏中拍摄的照片': 'View your in-game photos in your browser',

  '进入比赛自动开始数据记录': 'Auto-record when a race starts',
  '下一场比赛生效，不影响当前录制；关闭后仍可手动录制': 'Applies to the next race. Keeps the current recording. Manual recording remains available when off.',

  '连接教程': 'Connection tutorial',
  '开启数据输出': 'Enable Data Out',
  '填写手机 IP': 'Enter your phone IP',
  '设置相同端口': 'Match the UDP port',
  '游戏内打开「设置 → 抬头显示与游戏」，找到「遥测」，将「数据输出」设为「开启」。': 'In the game, open Settings → HUD and Gameplay. Find Telemetry and turn Data Out On.',
  '打开「数据输出 IP 地址」，填写本弹窗显示的手机局域网地址。截图中的个人 IP 已遮盖，请勿照抄截图或游戏中的示例地址。': 'Open Data Out IP Address and enter the phone LAN address shown in this sheet. The personal IP in the screenshot is hidden. Do not copy the screenshot or the game example address.',
  '打开「数据输出 IP 端口」，填写与本 App 接收端口相同的数值，默认 8000。返回游戏驾驶，收到数据包后右上角会亮起「已连接」。': 'Open Data Out IP Port and match this app receive port (8000 by default). Return to driving. The status lights up Connected when packets arrive.',
  '放大教程图片': 'Enlarge tutorial image',
  '点击图片放大，可双指缩放': 'Tap to enlarge, then pinch to zoom',
  '上一步': 'Previous',
  '下一步': 'Next',

  'GT 竞速': 'GT Race',
  '耐力赛': 'Endurance',
  '拉力赛': 'Rally',
  '选择专业布局': 'Choose race layout',
  '中央大挡位 · 圈速分区 · 高对比': 'Central gear · Lap timing · High contrast',
  '弧形转速 · 圈速对照 · 燃油': 'Arc tachometer · Lap times · Fuel',
  '超大车速 · 醒目挡位 · 踏板输入': 'Large speed · Bold gear · Pedal inputs',
  '外观': 'Appearance',
  '深色模式': 'Dark mode',
  '主题': 'Theme',
  '深色': 'Dark',
  '浅色': 'Light',
  '跟随系统': 'System',
  '拓展导航': 'Expanded navigation',
  '打开导航': 'Show navigation',
  '收起导航': 'Hide navigation',
  '退出回放': 'Exit replay',
  '采样详情': 'Sample details',
  '请横屏查看回放': 'Rotate to landscape for replay',
  '同步曲线': 'Synchronized chart',
  '选择曲线数据': 'Choose chart data',
  '请选择曲线数据': 'Choose data to display',
  '纵轴：各自量程百分比 · 横轴：回放秒': 'Y: % of each range · X: replay seconds',
  '应用': 'Apply',
  '轮胎前左': 'Tire FL',
  '轮胎前右': 'Tire FR',
  '轮胎后左': 'Tire RL',
  '轮胎后右': 'Tire RR',
  '比赛轨迹回放': 'Race replay',
  '播放回放': 'Play replay',
  '暂停回放': 'Pause replay',
  '轨迹回放': 'Trajectory replay',
  '暂无可回放采样': 'No samples to replay',
  '本地记录 · 回放': 'Local recording · Replay',
  '轨迹位置未变化': 'Recorded position is stationary',
  '此采样无有效驾驶位置': 'No valid driving position in this sample',
  '轨迹来自记录坐标，底图对齐待实测；转向为归一化输入。': 'Recorded coordinates; map alignment needs validation. Steering is normalized input.',
  '分段、断流或非驾驶位置不连线；等待时间已压缩。': 'Segments, gaps and non-driving positions are not connected. Waiting time is compressed.',
  '已连接': 'Connected',
  '未连接': 'Disconnected',
  '历史测试记录': 'Historical test recording',
  '历史测试记录 · 回放': 'Historical test recording · Replay',
  '回放打开时的采样快照，录制继续进行。':
      'Replay uses a snapshot taken when opened. Recording continues.',
  '重新开始': 'Restart',
  '上一采样': 'Previous sample',
  '下一采样': 'Next sample',
  '转向': 'Steering',
  '油门': 'Throttle',
  '刹车': 'Brake',
  '挡位': 'Gear',
  '名次': 'Position',
  '赛事计时': 'Race time',
  '当前圈速': 'Current lap',
  '圈数': 'Lap',
  '最佳圈速': 'Best lap',
  '上一圈速': 'Last lap',
  '功率': 'Power',
  '扭矩': 'Torque',
  '增压': 'Boost',
  '燃油': 'Fuel',
  '轮胎前左 / 前右': 'Tires FL / FR',
  '轮胎后左 / 后右': 'Tires RL / RR',
  '坐标 X / Y / Z': 'Position X / Y / Z',
  '轮胎温度与增压显示记录原始值，单位待确认。': 'Tire temperatures and boost use recorded raw values; units are unverified.',
  '筛选地点': 'Filter places',
  '可多选，地图与列表仅显示勾选类别':
      'Select multiple categories to show on the map and in lists',
  '全选': 'Select all',
  '清空': 'Clear',
  '应用筛选': 'Apply filters',
  '公开地图坐标 · 待游戏实测': 'Public map coordinates · In-game validation pending',
  '社区地图坐标 · 待游戏实测': 'Community map coordinates · In-game validation pending',
  "仪表盘": "Dashboard",
  "地图": "Map",
  "攻略": "Guides",
  "设置": "Settings",
  "UDP 连接": "UDP connection",
  "游戏连接": "Game connection",
  "UDP 遥测": "UDP telemetry",
  "驾驶偏好": "Driving preferences",
  "自动切换仪表": "Auto-switch dashboard",
  "进入比赛后使用专业仪表": "Use the pro dashboard during races",
  "名次提升特效": "Position gain effect",
  "车速单位": "Speed units",
  "仪表组件与换挡灯": "Widgets & shift lights",
  "关于与帮助": "About & help",
  "横屏驾驶": "Landscape driving",
  "进入仪表后横屏全屏，退出恢复竖屏": "Landscape in the dashboard; portrait on exit",
  "手机安装版会在进入仪表后请求横屏并隐藏系统栏，退出后恢复竖屏。浏览器预览无法改变设备方向，可调整预览窗口查看横屏效果。": "The mobile app opens dashboards in full-screen landscape and restores portrait on exit. Resize the browser preview to see a landscape layout.",
  "Flutter 原生 App 框架。仪表采用原创赛车显示器风格。地图使用游戏原始底图与路网，社区地点坐标及真实 UDP 字段仍待实测，轮胎温度显示原始值。": "Built with Flutter and original racing displays. Maps use game textures and roads. Community coordinates and UDP fields still need in-game validation. Tire temperatures show raw values.",
  "驾驶数据优先保存在本机。暂停、回溯或断流不会直接判定为完赛。": "Driving data is saved locally. Pausing, rewinding or losing data does not confirm a race finish.",
  "知道了": "OK",
  "连接游戏": "Connect to game",
  "手机与游戏设备连接同一局域网。游戏中打开 Data Out，目标 IP 填手机的局域网地址，端口与下方一致。": "Connect your phone and game device to the same LAN. Enable Data Out in the game, enter your phone's LAN IP and use the port below.",
  "UDP 接收端口": "UDP receive port",
  "默认 8000，避开 5200–5300": "Default: 8000. Avoid 5200–5300.",
  "浏览器仅预览仪表，不能直接接收 UDP。安卓/iOS 安装版由 Dart 原生套接字接收。": "The browser preview cannot receive UDP. Use the installed Android/iOS app for telemetry.",
  "手机地址：": "Phone IP: ",
  "数据包 ": "Packets ",
  " · 无效 ": " · rejected ",
  "请输入有效端口并避开 5200–5300": "Enter a valid port and avoid 5200–5300",
  "开始监听": "Start listening",
  "语言": "Language",
  "选择你的驾驶座舱": "Choose your cockpit",
  "游戏遥测": "Game telemetry",
  " 个数据包": " packets",
  "连接": "Connect",
  "仪表样式": "Dashboard styles",
  "进入后自动横屏": "Landscape on entry",
  "基础仪表": "Basic dashboard",
  "专业仪表": "Pro dashboard",
  "双表盘 · 车速 · 简洁导航": "Twin dials · Speed · Navigation",
  "换挡灯 · 圈速 · 驾驶输入": "Shift lights · Lap times · Inputs",
  "驾驶工具": "Driving tools",
  "驾驶遥测": "Driving telemetry",
  " 段本地记录": " local sessions",
  "自动切换、名次特效与赛后记录": "Auto-switching, position effects & recordings",
  "退出仪表": "Exit dashboard",
  "全屏仪表": "Fullscreen dashboard",
  "长按屏幕两秒返回": "Hold the screen for two seconds to return",
  "仪表设置": "Dashboard settings",
  "驾驶控制": "Driving controls",
  "横屏查看仪表效果更佳 · 手机安装版将自动横屏":
      "Best in landscape · Mobile app rotates automatically",
  "继续驾驶": "Keep driving",
  "查看遥测": "View telemetry",
  "名次提升": "Gain a position",
  "回溯 6 秒": "Rewind 6 seconds",
  "开始录制": "Start recording",
  "结束录制": "Stop recording",
  "自动切换赛事仪表": "Auto-switch race dashboard",
  "名次提升发光": "Glow on position gain",
  "基础仪表简洁导航": "Basic dashboard navigation",
  "轮胎数据": "Tire data",
  "油门与刹车": "Throttle & brake",
  "英里单位 mph": "Use mph",
  "换挡提醒：": "Shift reminder: ",
  "换挡提醒：自动跟随 EngineMaxRpm": "Shift reminder: follows EngineMaxRpm",
  "换挡灯自动标定": "Automatic shift-light calibration",
  "重新标定当前车辆": "Recalibrate current car",
  "在游戏中保持同一挡全油门至限转反弹，自动学习；未标定时不提示。改装后可重新标定。": "In game, hold full throttle in one gear until the limiter bounces to learn. No cue before calibration. Recalibrate after upgrades.",
  "完成": "Done",
  "基础": "Basic",
  "专业": "Pro",
  "未设置目的地": "No destination",
  "本周，开出新成绩": "Make this week's drive count",
  "季节赛、调校与探索攻略，\n在熟悉的作者页面里找到答案。": "Seasonal events, tunes and exploration guides\nfrom your favorite creators.",
  "打开攻略网页": "Open guide website",
  "我的攻略来源": "My guide sources",
  "网页攻略": "Web guides",
  "Forza 官方新闻": "Official Forza news",
  "游戏更新与社区动态": "Game updates & community news",
  "FH6 官方地图参考": "Official FH6 map",
  "查看游戏公开地图": "View the published game map",
  "攻略内容在小黑盒原站展示，版权归原作者所有。当前尚未接入本周真实季节赛事数据。": "Guides are displayed on the original Xiaoheihe site and belong to their creators. Live weekly seasonal events are not connected yet.",
  "网页地址不可编辑": "Website address cannot be edited",
  "攻略来源": "Guide source",
  "HTTPS 网页地址": "HTTPS URL",
  "取消": "Cancel",
  "请输入有效的 HTTPS 地址": "Enter a valid HTTPS URL",
  "保存": "Save",
  "攻略阅读": "Guide reader",
  "外部打开": "Open externally",
  "网页暂时无法打开": "Could not load this page",
  "重新加载": "Reload",
  "地图数据": "Map data",
  "游戏本体 · 四季原始地图\n38,473 个道路节点 · 71,222 条有向路段\n75,626 条允许通行的路段连接": "Original game maps · Four seasons\n38,473 road nodes · 71,222 directed segments\n75,626 permitted connections",
  "路线根据原始道路连接、单行线和已解析转向限制计算。底图使用图像对齐；导航坐标直接使用游戏三维坐标。尚未完成实车验证。": "Routes use original road connections, one-way rules and parsed turn restrictions. Map images are aligned visually; navigation uses game 3D coordinates. In-game driving validation is pending.",
  "隐藏道路图层": "Hide roads",
  "显示道路图层": "Show roads",
  "正在读取离线地图": "Loading offline map",
  "搜索赛道、车房与座驾": "Search places, tracks & cars",
  "收起地点列表": "Hide place list",
  "显示地点列表": "Show place list",
  "地图数据说明": "About map data",
  "全部": "All",
  "赛事": "Events",
  "广告牌": "Bonus boards",
  "吉祥物": "Mascots",
  "地标": "Landmarks",
  "特技": "PR stunts",
  "房屋": "Houses",
  "赛道": "Tracks",
  "车房宝物": "Barn finds",
  "秘藏座驾": "Treasure cars",
  "嘉年华": "Festival",
  "拍照点": "Photo spots",
  "车聚": "Car meets",
  "其他": "Other",
  "此处没有可导航道路": "No navigable road here",
  "地图选点": "Map pin",
  "自定义": "Custom",
  "游戏原图 · UDP 定位": "Game map · UDP position",
  "切换季节": "Change season",
  "夏季": "Summer",
  "秋季": "Autumn",
  "冬季": "Winter",
  "春季": "Spring",
  "跟随车辆": "Follow car",
  "查看全图": "Show full map",
  "没有找到匹配地点\n可以更换类别或搜索名称": "No places found\nTry another category or name",
  "直线 ": "Direct ",
  "社区坐标 · 待实测": "Community coordinates · Unverified",
  "游戏赛道几何": "Game track geometry",
  " 剩余 · ": " remaining · ",
  "结束导航": "Stop navigation",
  "取消选点": "Clear selection",
  "导航到这里": "Navigate here",
  "探索地平线": "Explore Horizon",
  "点击地点或长按地图，规划你的下一段旅程": "Tap a place or hold the map to plan your next drive",
  "定位中": "Locating",
  "最高车速": "Top speed",
  "平均车速": "Average speed",
  "驾驶曲线": "Driving charts",
  "录制中": "Recording",
  "本地记录": "Local session",
  "车速": "Speed",
  "转速": "RPM",
  "驾驶输入": "Inputs",
  "开始录制，记录你的每一段驾驶": "Start recording to capture your drive",
  "最终名次未确认": "Final position unconfirmed",
  "结束并保存": "Stop & save",
  "驾驶记录": "Driving sessions",
  "最近 8 段": "Latest 8 sessions",
  "还没有驾驶记录": "No driving sessions yet",
  "FH6 驾驶记录": "FH6 driving session",
  " 采样": " samples",
  "导出遥测 JSON": "Export telemetry JSON",
  "导出 JSON": "Export JSON",
  "关闭": "Close",
  "JSON 已复制，可粘贴保存为文件": "JSON copied. Paste it into a file to save.",
  "复制 JSON": "Copy JSON",
  "地图加载失败：": "Map loading failed: ",
  "无法读取旧设置，已使用默认设置": "Could not read saved settings. Using defaults.",
  "本地保存失败，请先导出重要记录": "Could not save locally. Export important sessions.",
  "等待游戏数据": "Waiting for game data",
  "数据中断 · 暂停或回溯待判断": "Data interrupted · Pause/rewind not confirmed",
  "已达到单段录制上限，记录已保存": "Session limit reached. Recording saved.",
  "请先连接游戏": "Connect to the game first",
  "已回溯 6 秒，已删除后续遥测": "Rewound 6 seconds. Later telemetry deleted.",
  "正在开启 UDP": "Starting UDP",
  "实验协议 · 正在接收": "Experimental protocol · Receiving",
  "数据格式待校准": "Packet format needs calibration",
  "连接未建立": "Connection failed",
  "选择目的地": "Choose a destination",
  "等待车辆定位": "Waiting for car position",
  "车辆离道路太远，请先返回道路": "Car too far from roads. Return to a road.",
  "未找到符合道路限制的路线": "No route meets the road restrictions",
  "沿路线行驶": "Follow the route",
  "导航已结束": "Navigation stopped",
  "车辆离道路较远": "Car is far from roads",
  "已定位到游戏道路": "Position matched to game road",
  "已到达道路入口": "Road access reached",
  "目的地附近 · 留意实际入口": "Near destination · Check the actual entrance",
  "已偏离路线": "Off route",
  "无可用路线，请返回道路": "No route available. Return to a road.",
  "路线已重新规划": "Route recalculated",
  "未找到可用路线": "No route found",
  "继续行驶": "Continue driving",
  "前方急右转": "Sharp right ahead",
  "前方急左转": "Sharp left ahead",
  "向右前方行驶": "Bear right",
  "向左前方行驶": "Bear left",
  "前方右转": "Turn right ahead",
  "前方左转": "Turn left ahead",
  "即将到达道路入口": "Approaching road access",
  "自定义坐标": "Custom coordinates",
  "社区坐标 · 待游戏实测": "Community coordinates · In-game validation pending",
  "游戏赛道几何起点，赛事触发点待实测":
      "Game track geometry start; event activation point unverified",
  "端口须在 1024–65535 之间，并避开 5200–5300":
      "Port must be 1024–65535, excluding 5200–5300",
  "浏览器不能直接接收 UDP，请在手机安装版中连接。": "UDP requires the installed mobile app.",
  "当前实验协议要求 324 字节": "Experimental protocol requires 324 bytes",
  "字段超出合理范围，请核对协议": "Fields out of range. Check the protocol.",
  "仪表，车速 ": " dashboard, speed ",
  "，挡位 ": ", gear ",
  "，转速 ": ", RPM ",
  "POSITION GAINED": "POSITION GAINED",
  "点击检查更新": "Tap to check for updates",
  "正在检查更新": "Checking for updates",
  "已是最新版本": "Up to date",
  "发现新版本": "Update available",
  "检查失败，点击重试": "Could not check. Tap to retry",
  "开源许可": "Open-source licenses",
};
const _templateCopy = <String, String>{
  "已确认第 {0} 名": "Confirmed P{0}",
  "{0} 个采样 · 回溯分段 {1} 次": "{0} samples · {1} rewind segments",
  "浏览 {0} 个地点": "Browse {0} places",
  "170 个赛道几何起点来自游戏文件，尚未核对赛事触发点。另有 {0} 个公开地图地点，包含赛事与收藏品，来源为 Forza Horizon Hub 等社区地图；坐标和邻近道路高度尚待游戏实测。": "170 track geometry starts come from game files; event activation points are unverified. Another {0} places, including events and collectibles, come from Forza Horizon Hub and other community maps. Coordinates and road elevations need in-game validation.",
  "字段 {0} 无效": "Invalid field: {0}",
  "赛道入口 {0}": "Track geometry start {0}",
};

/// Uses the current MaterialApp locale, including in dialogs and cached pages.
class LText extends StatelessWidget {
  final String data;
  final TextStyle? style;
  final TextAlign? textAlign;
  final TextOverflow? overflow;
  final int? maxLines;
  final bool? softWrap;
  const LText(
    this.data, {
    super.key,
    this.style,
    this.textAlign,
    this.overflow,
    this.maxLines,
    this.softWrap,
  });
  @override
  Widget build(BuildContext context) => Text(
    context.tr(data),
    style: style,
    textAlign: textAlign,
    overflow: overflow,
    maxLines: maxLines,
    softWrap: softWrap,
  );
}
