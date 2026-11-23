# 安卓 USB 真机开发

已在 M2104K10AC（Android 13，ARM64）完成 USB 安装与 Flutter 调试连接。实测基础/专业仪表全屏横屏、退出恢复竖屏、地图加载、地点选择和路线规划；热重载响应约 361 ms（无代码变更的重组验证）。截图保存为 `artifacts/android-*.png`。真实 FH6 UDP 收包和发布版性能仍需单独验证。

手机开启开发者选项与 USB 调试，使用支持数据传输的 USB 线连接电脑，并在手机上允许这台电脑调试。安装应用时如出现确认框，也需要在手机上允许安装。

双击项目根目录的 `启动安卓真机调试.cmd`，或运行：

```powershell
./scripts/run_android_debug.ps1
```

脚本自动选择唯一已授权的安卓设备；有多台设备时传入 `-DeviceId`。进入 Flutter 调试会话后，`r` 热重载、`R` 热重启、`q` 结束调试。修改 Kotlin、Gradle、清单或插件依赖时，通常需要重新构建安装。调试版用于功能验证，帧率评估应另用 profile 构建。

脚本按手机 ABI 构建，并把 APK 复制到开发工具目录的英文路径，再启动 Flutter 真机调试，避开 Windows Android 工具读取中文路径失败的问题。已有 APK 且源代码未变化时，可用 `./scripts/run_android_debug.ps1 -SkipBuild` 直接重试安装。小米手机若返回 `INSTALL_FAILED_USER_RESTRICTED`，需要用户在手机上允许 USB 安装并确认安装提示。

Android 工具位于本任务的开发工具目录；`android-env.ps1` 只为项目启动的命令设置 SDK、Java 和 Gradle 缓存，不更改系统 PATH 或手机开发者设置。使用从 Oracle 官方源下载并校验 SHA-256 的完整 JDK 25.0.5.0.3；IntelliJ 附带的运行环境缺少 `jlink`，无法完成 Android 的 Java 模块镜像任务。

本机启用了 `127.0.0.1:7890` 系统代理，Gradle 已在这个项目专用的缓存目录中配置同一代理。没有替换 Google、Maven Central 或 Gradle 的官方仓库，没有关闭 HTTPS 证书校验。首次依赖下载需要这个代理可用；全部依赖缓存之后，常规热重载不需要重复下载。

Java 下载器在部分官方依赖上仍有握手问题，因此增加了仅监听 `127.0.0.1:18765` 的本机下载缓存。它由 Windows .NET HTTPS 客户端通过已启用的代理读取固定官方仓库；Gradle 只读取本机缓存。`scripts/official-maven-cache.init.gradle` 只作用于本项目的 Gradle 缓存目录，入口脚本会自动检查并启动服务。没有开放给局域网，也不提供任意 URL 代理。

需要留存手机效果时运行 `scripts/capture_android_app.py --device <设备ID> --name home`。该脚本只在 Horizon Link 处于前台时截图，只保存本应用进程日志；输出位于 `artifacts/`。

SDK 网络安装器握手失败时，按用户批准的方案运行 `scripts/install_android_sdk.ps1`，使用官方清单的地址和校验值下载，再由 `install_android_packages.py --offline` 安全解压。下载与校验报告位于 `artifacts/android-sdk-installation.json`。

本项目要求 Android SDK Platform 36、Build Tools 36.0.0、NDK 28.2.13676358、Gradle 9.3.1；JNI 插件另需 Platform 35 和 CMake 3.22.1。Android APK 支持 Android 7.0 / API 24 及以上。

普通调试构建：

```powershell
cd flutter_app
../flutter.ps1 build apk --debug --no-pub --target-platform android-arm64
```

手机与运行 FH6 的电脑需要能通过局域网 UDP 通信。USB 用于安装与调试，不会自动把游戏遥测转发到手机。浏览器预览仍用于快速检查布局；手机安装版用于横竖屏、沉浸模式、触控、局域网 UDP 和性能验证。

参考：[Flutter Android 设置](https://docs.flutter.dev/platform-integration/android/setup)、[Android Platform Tools](https://developer.android.com/tools/releases/platform-tools)。


## 2026-11-02 发布准备更新

首次或政策版本更新后先进入隐私告知；同意前不初始化 UDP/周内容业务。设置 → 数据备份与恢复可通过系统文件选择器导出并读回校验，或确认后导入。切换正式签名之前必须完成独立恢复验证，不能卸载清数据绕过；细节见 [发行与迁移](ANDROID_RELEASE.md)。

原脚本仍默认 debug，新增 `./scripts/run_android_debug.ps1 -Mode profile`。Profile/Release 的 AOT 编译在当前 Windows SDK 无法读取中文路径下的 app.dill，故使用 `prepare_android_build_workspace.ps1` 在既有 SDK 目录的 `horizon-builds/` 下创建全新英文源码副本。只复制 App 的 lib/assets/android 与锁文件，排除构建缓存和密钥，使用 `pub get --offline` 并核对锁文件未改变。Kotlin 的跨 C/D 盘增量缓存问题仅在副本中通过 `kotlin.incremental=false` 解决，不改原项目或全局 Gradle 配置。构建后仍经 `horizon-artifacts/` 英文 APK 路径安装。

副本和产物只留本机，不提交、不上传、不自动清理；下一次构建创建新副本，不将副本反向覆盖原工程。公开发行字段从 `.tools/release/public-metadata.json` 读取，COS URL 从原配置读取。Profile 是性能检查模式，仍使用调试身份，**不是正式签名发行包**。默认 debug 的原流程不变。`-SkipBuild` 不应用新源码/配置，且不能与显式 WeeklyContentUrl 一起使用（包括显式空串）。


## 2026-11-10 仪表全屏界面验证

本轮重新检查 M2104K10AC 已授权且解锁，使用原脚本重新构建 debug、读取既有公开配置、英文 APK 暂存并同签名覆盖安装，无 `-SkipBuild`。五款仪表实际触摸全屏/恢复、返回先恢复工具栏/再退出竖屏、恢复图标避开转速灯通过；不注入遥测，不作为 FH6 校准或 Profile 性能证据。安装前实际 8 段记录，结束后完整存档和隐私同意文件逐字节不变。日志 `artifacts/dashboard-fullscreen-deploy-final.log`，截图/几何/存档一致性报告见交接第 68 节。全屏仅驾驶页临时状态；重新进入恢复工具栏。


2026-11-10 交互修正（以后续第 69 节为准）：全屏隐藏所有控件/消息/特效，无恢复图标和顶部占位。进入显示 Android 标准 Toast「长按屏幕两秒返回」，自动消失后纯仪表显示；任意区域持续长按两秒恢复，安卓返回键也可恢复。使用原脚本重新构建/英文暂存/同签名覆盖安装，最终 215 项 Flutter 回归和 Dart 静态分析通过，中文字体审计 956 字形。Toast 消失后的本机重绘补偿见第 69 节；不使用 SkipBuild 或卸载清数据。


## 2026-11-11 自定义仪表

按原脚本重新构建 ARM64 debug，带既有公开 COS 配置，经英文 APK 暂存同签名覆盖安装 M2104K10AC；最后源码修正亦重新构建，无 SkipBuild、卸载或清数据。最终部署日志 artifacts/custom-dashboard-deploy-complete.log，交互/数据报告 custom-dashboard-phone-result-final.json、最后重建包复验 custom-dashboard-phone-complete.json 及交接第 71 节。

实机验证新增/错误/预览/编辑、提示词复制、存档重启恢复、赛事目标选择、全屏与长按/退出方向、键盘弹起后检查及确认删除。测试文本/临时目标通过 VM 辅助，其余主要动作用 Android 实际触摸；无遥测注入，不是 FH6 或 Profile 验收。测试方案已移除，全部原设置键/记录采样相等，同意文件字节相同；新增 schema 扩展使整个存档字节不再相同。完整 244 项测试、同 SDK Dart 分析、969 字形及许可审计通过。


2026-11-11 自定义仪表弹窗样式更新：带文案操作统一 48 高/14 圆角/一致图标字号，次级描边、保存主色填充，说明折叠及错误/预览分组。相关 45 项测试、Dart 分析及字体审计通过，真机按钮等高/等宽/对齐和错误/预览已验，完整存档与同意文件字节不变；本轮未重跑历史 244 项全量。详见交接第 72 节。


2026-11-11 赛事仪表选择排布：设置名称左、当前选项和下拉入口右，与语言/主题行一致；说明移至名称长按提示。设置页/驾驶页共用，行为与存档不变。相关 43 项测试、静态分析和字体审计通过，真机左右排布/下拉已验，完整存档及同意字节不变，见交接第 73 节。


## 2026-11-11 性能对照

按原脚本分别重新构建优化前/后的 ARM64 Profile，英文源码副本、离线依赖和英文 APK 暂存后同 Android Debug 身份覆盖安装 M2104K10AC，未用 SkipBuild。最终手机留优化后的 Profile 包；完整设置/8 段记录全部采样/隐私文件字节一致。首页滑动、四栏切换、地图拖动、全屏/长按/方向和三次进程冷启动已测；251 项测试、静态分析及字体审计通过。详细样本和未验范围见 [性能记录](PERFORMANCE.md) 及交接第 76 节，不用 debug 帧耗时代替 Profile，也不将本轮短时场景当持续 FH6 验收。

## 2026-11-14 自动限转标定

按原脚本重新构建debug，经英文APK暂存同签名安装，原Profile包已替换为本次功能验证debug包。267项全量测试、Dart分析和974字形审计通过；手机合成帧验证学习/按挡提前/真实触摸重置/中英文/重启加载，随后清理合成标定，恢复等待真实UDP。原设置已有键及8段全部采样相等，同意文件字节相同。详见交接77及 artifacts/rev-limiter-phone-final-result.json；用户选择稍后自行真实游戏验证，不将本轮当作实际游戏或性能验收。

## 2026-11-20 驾驶仪表亮屏验收

覆盖安装包含交接第 86 节改动的包后，观察设备当前的熄屏时间。进入普通及全屏驾驶，在没有触摸且等待 UDP 的情况下各停留超过该时长。再退出驾驶或打开遥测记录，确认恢复自动熄屏。切后台并返回驾驶时再次检查。计时验收可在拔掉 USB 后进行，避免开发者选项的充电时保持唤醒影响结果。应用通过窗口的 `FLAG_KEEP_SCREEN_ON` 请求亮屏。[Android 屏幕常亮说明](https://developer.android.com/develop/background-work/background-tasks/awake/screen-on)
