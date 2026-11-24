# Horizon Link

Horizon Link 是面向《极限竞速：地平线 6》（FH6）玩家的手机仪表盘、地图与遥测伴侣。用手机查看实时挡位、转速和驾驶数据，也可以查地点、规划游戏内路线并回放驾驶记录。

应用免费、无广告，以 Flutter 开发，提供简体中文和 English。Android 安装包通过 GitHub Releases 分发。底部提供仪表盘、地图、攻略、设置四个入口。

## 下载与连接

**[下载最新 Android 版](https://github.com/h3049928398-stack/horizon-link-app/releases/latest)** · 同页提供更新说明与 SHA-256 校验文件。

正式签名版需要 **Android 7.0（API 24）或以上版本**，支持 `arm64-v8a`、`armeabi-v7a` 和 `x86_64`。可用 Release 提供的 `SHA256SUMS.txt` 核对 APK 完整性。Windows 可运行 `Get-FileHash .\文件名.apk -Algorithm SHA256`。

从 `v0.2.0` 调试预发布迁移时，请先在「设置 → 数据备份与恢复」导出 JSON，并将备份另外保存一份。Android 要求同包名的覆盖更新使用同一签名，因此正式签名包需要在确认备份可恢复后再安排迁移。已使用正式签名版本的用户可按发布说明覆盖升级。

1. 将手机和运行 FH6 的电脑或主机接入可互通的同一局域网。
2. 打开 App 的连接面板，记下手机在该局域网的 IP 和 App 接收端口，默认 `8000`。
3. 在游戏设置中打开「数据输出 / Data Out」，填入手机的 IP 和相同端口，返回游戏开始驾驶。收到数据后 App 会显示「已连接」。

一直显示等待时，先核对 IP、端口及局域网设备之间是否互通。App 的连接面板也提供图文教程。

## 能做什么

- **五款驾驶仪表**：基础、专业、GT 竞速、耐力赛、拉力赛。驾驶时横屏并保持亮屏，退出后恢复竖屏和系统熄屏行为。全屏时长按两秒或按 Android 返回键恢复工具栏。
- **换挡提示**：按车辆及 PI 从驾驶遥测学习限转估计，未学到有效估计时换挡灯保持暗色。可在仪表设置查看状态并重新标定。估计可能因车辆和驾驶工况而偏低。
- **自定义仪表**：复制 App 提供的 AI 提示词，生成并粘贴 JSON 布局，经过本地检查和预览后保存多套外观。不执行脚本，也不接入 AI 服务；详见 [自定义仪表说明](docs/CUSTOM_DASHBOARDS.md)。
- **赛事仪表切换**：在驾驶偏好选择进入赛事时使用的仪表，默认专业仪表；可不切换，也可选择自定义方案。赛事结束恢复赛前仪表，手动切换会接管。
- **地图和路线**：四季底图、三维路网、地点分类与中英文搜索，支持 A* 寻路、转弯提示和偏航重算。选点会放大并隐藏其他标记，取消后恢复筛选。
- **驾驶记录**：手动录制和独立的自动录制开关，本地保存最近 8 段记录，每段最多 12,000 个采样。可以看统计、曲线，以及横屏轨迹与驾驶输入同步回放。
- **攻略和每周活动**：小黑盒原站阅读器、My Forza 浏览器入口、远端 JSON 活动更新与离线缓存。攻略地址可以随每周快照更新，活动可定位到地图。
- **设置与本地数据**：自定义方案、驾驶记录及设置可导出至 JSON 并恢复。设置支持手动检查版本、查看隐私说明及选择浅色、深色或跟随系统。撤回隐私同意后保留本地记录。

仪表依赖真实 UDP 遥测。比赛识别、换挡标定和游戏地图坐标仍在验证中。暂停、回溯和断流会影响实时数据和比赛状态的判断。

## 地图与数据说明

地图包含 38,473 个道路节点、71,222 条有向路段、795 个社区地点，以及 170 个赛道几何起点。社区地点和底图投影仍需游戏实测，赛道几何首点也不等于已确认的赛事报名点。来源与精度见 [地图数据说明](docs/MAP_DATA.md)。

每周内容通过公开 HTTPS JSON 读取并独立缓存。启动、进入相关页面和恢复前台时，按上次成功检查后的 6 小时间隔检查；手动刷新可立即请求。它没有后台推送，也不会在页面驻留时定时轮询。维护方式见 [每周内容](docs/WEEKLY_CONTENT.md)。

## 从源码运行

手机工程位于 `flutter_app/`。本机工具链为 Flutter 3.47.8 / Dart 3.13.7；其他电脑需自行准备兼容的 Flutter、Android SDK 和 JDK，再安装锁文件中的依赖。

```powershell
cd flutter_app
flutter pub get
flutter test --no-pub
dart analyze
flutter run --dart-define=WEEKLY_CONTENT_URL=<公开的HTTPS内容地址>
```

公开内容地址保存在 [`config/weekly-content.json`](config/weekly-content.json)。直接运行或构建时需要通过 `WEEKLY_CONTENT_URL` 传入；没有配置时，每周内容显示未配置，其他功能仍可使用。

已有 Windows 本机环境使用根目录 `flutter.ps1` 和 `android-env.ps1`。安卓部署入口会读取每周内容配置，并经英文路径暂存 APK：

```powershell
./scripts/run_android_debug.ps1
```

详细步骤见 [Android 调试](docs/ANDROID_DEBUG.md) 和 [Android 签名发布](docs/ANDROID_RELEASE.md)。仓库还包含 [iOS 自签测试说明](docs/IOS_TESTING.md)；公开安装包以 Releases 的附件为准。Flutter Web 支持界面预览，UDP 遥测需使用手机端。

## 反馈、开发文档与素材来源

请在 [GitHub Issues](https://github.com/h3049928398-stack/horizon-link-app/issues) 提供 App 版本、手机型号、Android 版本和复现步骤。发送截图前请遮挡局域网 IP，驾驶记录备份请留在本机。

APP 备案号 [赣ICP备2026030532号-2A](https://beian.miit.gov.cn/) · [隐私政策](docs/PRIVACY.md)

[文档目录](docs/README.md) · [仪表布局](docs/DASHBOARD_LAYOUTS.md) · [Android 发行准备](docs/ANDROID_RELEASE.md)

Horizon Link 由玩家独立开发，与 Microsoft、Xbox、Playground Games 和 Turn 10 无隶属或背书关系。Forza 相关名称及素材的权利归各权利人所有。第三方代码、字体和地图资料的来源见 [开源声明](docs/OPEN_SOURCE_NOTICES.md)、[字体许可](docs/FONT_LICENSES.md) 和 [地图素材来源](flutter_app/assets/map/NOTICE.txt)。
