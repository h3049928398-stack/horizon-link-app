# iPhone 本地自签测试准备

更新：2026-11-18。范围为个人 iPhone 开发测试。液体玻璃已接入源码，Windows Flutter 回归已通过。本轮 iOS 编译、签名和上机待验。

实际构建的 `ios` 提交须包含交接第 83 节的原生开关和选项。个人测试设备为 iPhone 16 Pro Max；手动工作流从私有仓库检出 `ios`。[手动构建入口](https://github.com/h3049928398-stack/horizon-link/blob/main/.github/workflows/ios-self-test.yml)

## 你需要准备什么

| 项目 | 要求 |
| --- | --- |
| Mac | 完整 Xcode，带 iPhoneOS SDK 26 或更新版本，同时支持目标手机的 iOS 版本。安装 iOS 平台支持并完成首次启动。Windows 无法使用官方工具链编译此 Flutter iOS 工程。 |
| Apple 账户 | 在 Mac 的 Xcode → Settings → Accounts 中本人登录。普通免费账户的 Personal Team 可以给自己的设备签名，无须为本次测试购买付费会员。密码、验证码、证书私钥不要发进聊天或仓库。 |
| iPhone | 当前工程最低 iOS 15.0；实际还取决于所用 Xcode 对该机型/系统的支持。首次用数据线连接、解锁、信任 Mac，并按系统要求开启开发者模式（iOS 16 及以上，开启后重启确认）。 |
| Mac 工具 | 建议与当前工程相同的 Flutter **3.47.8 / Dart 3.13.7**，Python 3.10+。工程已经集成 Swift Package Manager；现锁定的两个原生插件 url_launcher_ios / webview_flutter_wkwebview 带 Package.swift，path_provider_foundation 使用 Dart/FFI。先沿现有 SwiftPM 路径，若 Mac 实际构建要求 CocoaPods 再按官方流程补齐，不自行重建 ios 目录。 |
| 网络 | 首次获取 SDK/锁定依赖、Apple 自动签名需要联网。游戏和手机在可互通的局域网，游戏 Data Out 填 iPhone Wi-Fi IPv4 和 App 监听端口，默认 8000；USB 安装不会转发遥测。 |

Apple 当前免费 Personal Team 的描述文件有效期为 **7 天**，到期需重新构建签名并覆盖安装；还限制最多 10 个 App ID、3 台设备和每台设备 3 个应用。不要为续签卸载 App。保持同一 Team 和 Bundle ID，先从设置导出并独立保留备份，再覆盖安装并核对实际记录数量及采样。更换 Team/Bundle ID 不保证继承原沙盒；Android 数据也不会自动进入 iPhone，需通过 version 2 文件手动备份/恢复，隐私同意不迁移。

官方依据（2026-11-15 查询）：[Apple Personal Team 与期限](https://developer.apple.com/help/account/basics/about-your-developer-account)、[Flutter iOS 环境](https://docs.flutter.dev/platform-integration/ios/setup)、[开发者模式](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device)、[Flutter SwiftPM](https://docs.flutter.dev/packages-and-plugins/swift-package-manager/for-app-developers)。兼容性以届时实际 Xcode / iPhone 为准。

## 已准备的工程内容

- 保留现有 Runner/SceneDelegate、iOS 15 最低版本、图标和竖屏/左右横屏声明；Runner 三种配置显式使用自动签名，不写个人 Team、Apple 账户或私钥。
- `Runner/AppDelegate.swift` 注册 `horizon_link/documents`，接通已安装版本、系统 Files 导出/导入；64 MiB 有界读取、UTF-8、security-scoped URL、文件协调、导出读回比对、取消和忙碌保护。导入仍由原 Dart 整体验证及用户确认后写入，存档 version 2 不变；不迁移隐私同意。
- iOS 撤回同意也执行现有 WebView Cookie / localStorage 清理，与已有政策声明一致；未新增网络服务、隐私字段或政策主体内容，不提高 policyVersion。
- 保留 `NSLocalNetworkUsageDescription`，不增加任意 HTTP 放行、后台常驻、位置权限或组播 entitlement。游戏应向手机 IPv4 **单播**。Apple 说明接收入站 UDP 单播本身不要求本地网络权限，所以不弹权限框不等于无法接收；debug VM 服务可能另行触发局域网提示。广播/组播有额外权限条件，本轮不支持或申请它们。[Apple TN3179](https://developer.apple.com/documentation/technotes/tn3179-understanding-local-network-privacy)
- Android 系统 Toast 仍只在 Android 存在；iOS 当前全屏无 Toast，仍可持续长按两秒恢复工具栏。不要添加永久恢复图标。iPhone 安全区、手势和方向仍需实机确认。
- iOS 26+ 通过 UIKit `UIGlassEffect` 为四栏、主页连接入口、地图浮动控制和 App 内弹窗操作区绘制玻璃底板。系统「降低透明度」开启时实时回退现有样式。驾驶普通工具栏沿用赛车样式。玻璃底板由 Flutter 平台视图承载，按钮、语义和业务状态由 Flutter 管理。[Apple 原生材质](https://developer.apple.com/documentation/uikit/uiglasseffect)

## 从 Windows 转到 Mac

用户本轮确认目前只有 **Windows + iPhone**。可以选择后述「GitHub macOS 编译 → Windows 自签」路线，无须先购买 Mac；本轮仅准备流程，没有上传或执行。

在工程根目录执行：

```powershell
python scripts/prepare_ios.py export
```

输出 `artifacts/Horizon-Link-iOS-source-<时间>.zip`，是**当前工作树源码**，包含未提交的 App 改动、锁文件、字体/地图资源、测试、iOS 工程、本说明、准备脚本和公开每周 URL。它不是 IPA，不可直接安装。解压后有每文件 SHA-256 的 `source-manifest.json`。只通过可信方式传给 Mac，不公开发布游戏素材或整个私有工程。

导出采用明确目录/文件清单，不带 `.tools/`、手机存档、`config/` 其他配置、密钥/签名、Windows `.dart_tool/`、Flutter 生成路径、Pods、构建输出、Xcode 用户设置。不要直接 clone 当前 main 代替这个包：当前未提交功能会丢失。手动打包时遵守相同范围。此脚本不上传、提交或清理源工程。

## 在 Mac 首次签名运行

先安装并配置上述工具。运行 `flutter doctor -v`、`xcodebuild -version` 和 `xcrun --sdk iphoneos --show-sdk-version` 检查所选 Xcode 和平台支持。`prepare_ios.py` 会检查 iPhoneOS SDK 至少为 26。实际装机还需核对该 Xcode 对目标手机版本的支持。[Apple Xcode 与设备支持](https://developer.apple.com/xcode/system-requirements/)

下载失败先保留错误并处理，不跳过证书验证或改全局代理。解压到如 `~/Projects/Horizon-Link-iOS-source`，在该根目录执行：

```sh
python3 scripts/prepare_ios.py prepare --mode debug
open flutter_app/ios/Runner.xcworkspace
```

脚本在 Mac 重新执行 `flutter pub get --enforce-lockfile`，然后 `flutter build ios --config-only --no-codesign`，生成本机路径和编译配置。这一步**不编译、不签名、不证明构建成功**。默认保留 `config/weekly-content.json` 中现有 HTTPS URL；无须 COS 密钥。不强制填写中国大陆安卓商店资料。需要现有公开开发者资料时，可传 `--public-metadata /私密本机路径/public.json`（仅允许五个公开字符串字段，格式参考 ReleaseInfo）；不将 Apple 账户/证书口令放入 dart-define。

在 Xcode 中：

1. 选择 Runner 项目 → Runner target → Signing & Capabilities，启用 Automatically manage signing，Team 选择自己的 Personal Team。
2. 使用自己唯一且此后固定的 Bundle Identifier，例如 `com.yourname.horizonlink.local`（示例须替换）；项目原值不保证可由你的账户注册。Runner 的 Debug/Profile/Release 保持一致；运行原生单元测试前也为 RunnerTests 设置同一 Team 和对应的 `<应用ID>.RunnerTests`。
3. 顶部目标选已信任的真实 iPhone，点击 Run。按提示完成开发者模式/开发者证书信任（设置 → 通用 → VPN 与设备管理；有提示时处理）。账户登录和设备确认由本人操作。
4. 首次 debug 用于定位错误；Flutter debug 通常依赖调试器启动。要拔线后从桌面独立打开，使用下面的 **profile 或 release** 本地开发签名包；这两种模式不等于 App Store 发行，也不要求切换 Android 密钥。

```sh
flutter devices
# 替换设备 ID，明确选择 iPhone；脚本重新构建并保留每周内容 URL
python3 scripts/prepare_ios.py run --mode profile --device '<iPhone设备ID>'
# 可选：仅构建签名的设备 .app，不导出 IPA，不上传
python3 scripts/prepare_ios.py build --mode release
```

签名必须先在 Xcode 配置成功。脚本不自动获取/设置 Team 或强制更改 Bundle ID，失败即停止。默认模式为 profile；`prepare` 后在 Xcode 的 Run 操作仍取决于 Scheme 的 Run Build Configuration，默认 Debug。需要 Xcode 直接跑 Profile 时在 Edit Scheme → Run 修改为 Profile。不要把 `--no-codesign` 的 .app 当成可安装包，也不要把文件夹改名/压缩冒充有效签名 IPA。

## 只有 Windows：云端编译后本机自签

现有 `.github/workflows/ios-self-test.yml` 通过 **workflow_dispatch 手动触发**。使用 GitHub 的 macOS runner、锁定 Flutter 3.47.8，在私有源码上执行 `prepare_ios.py unsigned-ipa --mode release`，生成物理设备 Release/AOT 的未签名 IPA 和 SHA-256。仓库权限为只读，产物保留 3 天，签名在下载后由用户侧完成。

经用户明确授权后，将本次完整 App 源码、脚本和公开 weekly 配置同步到私有仓库的 `ios` 分支，核对 Actions 取用的提交及 iPhoneOS SDK 版本。到 Actions 选择该工作流 → Run workflow，成功后下载 artifact，解压得到 `Horizon-Link-unsigned.ipa`。GitHub 私有仓库 macOS 构建会使用账户额度，超出可能收费，执行前查看额度。工作流使用第三方 subosito/flutter-action 配置 Flutter。[GitHub 手动触发](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/trigger-a-workflow) · [runner 与私有仓库计费](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

也可由可信 Mac 在源码包根目录执行同一条命令生成未签名 IPA，再传回 Windows，不必在那台 Mac 登录 Apple 账户：

```sh
python3 scripts/prepare_ios.py unsigned-ipa --mode release
```

这条命令始终重新编译 `flutter build ios --release --no-codesign`，检查真机平台及可执行文件后用 macOS ditto 保留权限/框架链接，封装 Payload/Runner.app。未签名 IPA 不能直接装机，须下一步侧载工具重新签名。

Windows 可使用 [Sideloadly 官方站点](https://sideloadly.io/) 提供的工具。按其官方要求准备网站版 iTunes / iCloud 与设备驱动（具体安装条件先看官网），用数据线连接解锁的 iPhone 并信任电脑。选择 IPA、本人在该工具内登录 Apple 账户、完成双重认证并签名安装；不要把密码/验证码交给聊天、构建 runner 或代签商家。该工具是第三方，账户认证发生在工具中，使用前自行确认其信任范围。按设备提示开启开发者模式/信任开发者；免费签名通常七天，到期在同一账户和固定 Bundle ID 下续签覆盖，先保留有效备份。[Sideloadly 官方 FAQ](https://sideloadly.io/faq.html)

液体玻璃功能已完成 Windows 回归。云构建第 4 次运行在 Swift 圆角配置处失败，源码已按 UIKit API 修正。修正后的编译、IPA 生成与覆盖安装待验。[构建失败日志](https://github.com/h3049928398-stack/horizon-link/actions/runs/44243501741/job/134596762557#step:5:57)

## 第一次 iPhone 验收

- 首装先拒绝隐私：不启动 UDP/周内容/WebView；同意后才等待真实数据。查看版本、撤回并验证 WebView 数据清理和记录保留。
- 四栏、五款/自定义仪表、进入横屏/退出竖屏、全屏纯仪表、长按满两秒恢复、提前松手/移动/后台取消、安全区及系统手势。
- 轻点和按住横拖系统四栏，核对系统选中项、实际页面和攻略定位。检查地图背景变化时的折射、深浅主题和系统减弱动态效果。连接页长按「关闭」或「开始监听」再滑出取消，两按钮应能分别按压、聚焦和播报。用大字号英文弹出数字键盘，确认两个操作可达。
- 在 iOS 26+ 模拟器和 iPhone 16 Pro Max 上验收深色、浅色、跟随系统、中英文及 VoiceOver。检查四栏安全区、列表末项可点击、攻略定位后地图标签选中、地图拖动/缩放时玻璃采样和命中、地图搜索键盘让位。打开和关闭连接、筛选、自定义仪表、驾驶控制及确认弹窗，检查转场层级和操作区。切换「降低透明度」并返回 App，核对实时回退和恢复。可用旧版 iOS 运行时再核对兼容外观。
- Files 导出到本机及实际使用的文件提供者，读回校验；取消、非法/超大/非 UTF-8 文件拒收；确认恢复有效 version 2 备份。比较设置、实际记录和采样，不假定固定 8 段。新 Swift 测试见 RunnerTests，在 Xcode 执行 Product → Test。
- HTTPS 周内容/guideUrl、失败与离线缓存；攻略 WKWebView、外链确认、My Forza 系统浏览器；不可覆盖云内容来验收。
- 同一 LAN 向 iPhone IPv4 单播，区分监听成功、收到数据报、协议字段正确三层。真实 FH6 比赛/暂停/回溯/地图/换挡标定仍待游戏校准。iOS 后台不承诺持续接收 UDP，回前台和断流不得伪造完赛。
- 续签/同身份覆盖安装及 Profile/Release 脱离调试器冷启动。到期无法启动时先续签覆盖，不卸载清数据。

## 本轮证据边界

交接第 83 节记录设置和各页面原生选项的 277 项 Windows Flutter 回归及 Dart 分析。模拟器及真机请重点检查中英文菜单当前项、较大字号下单位选择、连续滚动开关列表、VoiceOver 切换，以及地图/回放多选的取消和应用。原生 XCTest、视觉与触摸须在 Apple 环境单独验收。

## 版本检查的 iPhone 验收

同身份覆盖安装并确认新版隐私告知后，打开设置，核对底部安装版本，轻点 Horizon Link，确认 VoiceOver 可读行内结果、页面停留在原位。用户上传清单后用其中 ios 值核对提示；离线失败后恢复联网再轻点。2026-11-18 本轮只完成 Windows 回归。

## 横屏仪表适配的 iPhone 验收

- 用包含交接第 85 节改动的包同身份覆盖安装。在 iPhone 16 Pro Max 左右两个横屏方向查看五款内置仪表的普通和全屏模式。确认背景延伸至屏幕边缘，内容填满可用安全区，灵动岛、圆角与底部系统手势区不会遮挡读数或操作。
- 检查基础圆表盘、耐力赛弧表及基础扩展导航的比例。在全屏边缘持续按住两秒，确认工具栏恢复，再退出驾驶确认恢复竖屏。自定义仪表组件应保持原比例，背景延伸至边缘。Windows 通过模拟屏幕大小及安全区验证布局，实际 Xcode 构建和 iPhone 显示待验。

## 驾驶仪表亮屏验收

使用包含交接第 86 节改动的包同身份覆盖安装。在普通驾驶和全屏驾驶各停留超过 iPhone 当前的自动锁定时长，期间无需触屏或收到 UDP，确认仪表持续显示。打开遥测记录、退出仪表或切后台后检查自动锁定是否恢复，再回到驾驶确认保持亮屏。iPhone 测试需要启用有限的系统自动锁定时长。应用使用 UIKit 的 `isIdleTimerDisabled`。[Apple 自动锁定 API](https://developer.apple.com/documentation/uikit/uiapplication/isidletimerdisabled)

## 问题反馈验收（2026-11-24）

Android 和 iOS 共用反馈页面与 HTTPS 契约。Windows Flutter 测试以 iOS 平台配置打开「设置 → 关于与帮助 → 问题反馈」。本轮没有 Xcode 构建、IPA 或 iPhone 安装。网站接口就绪后，在同身份安装包上确认新版隐私告知、中英文表单、键盘下的发送按钮、VoiceOver 对错误和成功回执的播报、断网重试和实际后台收件。见 [反馈协议](PROBLEM_FEEDBACK.md)。
