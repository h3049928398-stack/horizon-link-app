# GitHub 版本发布

公开项目与 Android 下载入口见 [GitHub Releases](https://github.com/h3049928398-stack/horizon-link-app/releases)。`horizon-link` 保存发布前的开发历史及 v0.2.0 调试预发布。

## v0.3.0 Android（2026-11-23）

- [v0.3.0](https://github.com/h3049928398-stack/horizon-link-app/releases/tag/v0.3.0) 已作为正式最新版发布。附件为 `Horizon-Link-v0.3.0-android.apk` 和 `SHA256SUMS.txt`。见 [Android 更新说明](releases/v0.3.0-android.md)。
- APK 使用备案对应证书签名。已核对 `com.horizonlink.horizon_link`、`0.3.0+3`、最低 API 24、目标 API 36、三种 ABI 及合并后的权限。APK 为 68,471,082 字节，SHA-256 为 `6111ea1110f4831efe2abd7ed30b12ec0776aea2645972bfd6d947479718d058`。
- 腾讯云已核对备案号 `赣ICP备2026030532号-2A`、包名和证书指纹。正式构建使用 [双语隐私政策](PRIVACY.md)。真机安装和从调试签名迁移单独验收。

## 发布流程

1. 检查工作区、远端分支及已有标签，保留本地开发成果。审查待提交清单，排除 `.tools/`、`artifacts/`、构建输出、本地资料、存档和签名密钥。
2. 更新 README 和版本说明，运行 App 测试、Dart 静态分析及涉及工具的检查；具体结果记录在开发交接中。
3. 使用 `scripts/build_android_release.ps1` 构建正式 APK。脚本读取公开周内容 URL，经英文路径构建并暂存 APK。另核对正式证书、包信息和 SHA-256。
4. 有手机时，覆盖安装前读取当前存档基线；安装后比对设置、驾驶记录和同意状态。签名不一致时停止安装，不通过卸载清数据解决。
5. 提交核对后的源码，以同一提交创建标签并推送。创建 GitHub 草稿 Release，上传 APK 与校验文件，核对标签、提交、附件大小与摘要后发布。不得覆盖已有标签或重复发布同名版本。

正式签名包使用 [Android 发行流程](ANDROID_RELEASE.md)，不能绕过该流程的资料和签名检查。上传 GitHub Release 不会更新 COS 每周内容，也不代表提交应用商店。
