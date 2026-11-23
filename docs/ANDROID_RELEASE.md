# Android 发布构建与迁移

GitHub 发行记录见 [GitHub 版本发布](GITHUB_RELEASE.md)。Android `v0.3.0`（构建号 `3`）已使用备案对应的正式签名发布。历史版本 `v0.2.0` 使用调试签名，从该版本迁移前请先完成备份验证。

应用名称为 Horizon Link，包名为 `com.horizonlink.horizon_link`，免费且无广告。腾讯云已确认 APP 备案号 `赣ICP备2026030532号-2A`，正式签名文件的公开证书指纹与备案信息一致。在线文本见 [隐私政策](PRIVACY.md)。

## 主体与签名

个人备案的主办者姓名应与个人证件及实名认证一致，公开开发者名称需用户决定并核对目标商店规则。参考 [腾讯云首次备案](https://cloud.tencent.com/document/product/243/37402)。身份证、联系电话、住址等材料私密保管，不写入源码。用户提供的支持邮箱已存本机 `.tools/release/public-metadata.json`；电话不进入 App 或公开文档。

正式签名密钥是安卓安装包的长期更新身份。用户须确定保管人、长期安全保存位置和两份独立加密备份；口令不得发聊天、写源码或放构建命令参数。此轮不生成或切换密钥。Android 官方说明：[应用签名](https://developer.android.com/studio/publish/app-signing)、[Flutter Android 发行](https://docs.flutter.dev/deployment/android)。

备案材料需要的是**正式证书**的公钥/指纹等特征，不是 APK 文件哈希，也不能拿本轮 debug 证书当正式身份。备案前可先在保管人电脑生成密钥并提取公开证书；不必为获取指纹而伪填备案号构建商店包。正式版本和首发商店未确定前不更改现有包名与版本。

## 本机配置与构建

1. 将 `config/release.example.json` 复制到 `.tools/release/public-metadata.json`，补齐真实开发者名称、支持/隐私邮箱、稳定 HTTPS 政策地址、生效日期及已取得的 APP 备案号。示例全为空，不伪造身份。此处只放准备公开的资料，绝不放口令。
2. 调试脚本默认读取该本机文件（允许空缺并在 App 明确显示待补充）。正式脚本会拒绝空缺、占位及不合规 URL。`config/weekly-content.json` 的真实 COS URL 自动并入 Dart defines，避免遗漏。
3. 由保管人在当前 PowerShell 会话私密设置 `HL_KEYSTORE`（绝对路径）、`HL_STORE_PASSWORD`、`HL_KEY_ALIAS`、`HL_KEY_PASSWORD`。不要打印这些值、截屏或记录到日志。密钥及 `key.properties` 已被 Git 忽略。
4. 运行 `./scripts/build_android_release.ps1 -CheckOnly` 做预检；`./scripts/build_android_release.ps1` 构建 APK，`-Format appbundle` 构建 AAB。预检只检查语法和文件存在，不能证明主体、备案号真实有效或政策公网可访问。
5. Profile/Release 通过 `prepare_android_build_workspace.ps1` 在现有 SDK 的英文目录新建源码副本、离线解析固定依赖，并仅在副本中禁用 Kotlin 增量编译以解决 C/D 跨盘缓存。原工程不移动或清理，锁文件须保持一致。
6. Gradle release 使用独立 production signing config，缺密钥/必要 metadata 时失败，无 debug 回退。脚本经英文路径暂存，APK 用 apksigner 校验并拒绝标准 Android Debug 证书，记录公有证书信息与 SHA-256；不会自动安装、卸载或提交商店。AAB 按最终商店是否要求决定，并需另核对上传证书。

默认完整 ABI APK，不擅自选择商店或改变版本。正式构建还需核对合并清单、ABI、min/target SDK、图标、OFL/MIT 许可、URL 生效及政策资料。不要以脚本“预检通过”代替发行验收。

## 数据保留与签名迁移

Android 不能用不同签名直接覆盖同包名应用。**不允许直接卸载当前 debug 版来试装。**

1. 每次操作前重新检查设备、授权、版本、签名及数据，保存新的只读基线，不能依赖历史“8 段”。本轮开发备份在忽略目录 `artifacts/release-prep/`，含私人游戏记录，不发布。
2. 新调试版在设置 → 数据备份与恢复中通过 Android 系统文件选择器导出 JSON，包含设置与最近八段记录（正在录制时导出快照），保存后立即读回核对字节。备份为明文；选择自己控制的目录，复制至电脑/独立介质。取消或 I/O 错误不视为成功。
3. 在测试设备或受控测试安装中导入该备份，逐项比较设置、记录 ID、采样、时间和回放。导入前完整验证 version 2、结构、数量、数值及时间；确认后替换，不静默截断超过上限的文件。写入失败不改内存；写入串行化。同意状态、周缓存、Cookie 不在备份内。
4. **只有备份读回、独立恢复及用户确认迁移步骤后**才安排同包名签名切换。本轮不执行此切换。当前手机上的同签名 round-trip 只能证明文件流程，不能替代正式签名迁移与独立安装恢复。
5. 之后再用同一正式密钥构建更高 versionCode 的更新，验证覆盖升级保留数据。不可重新生成密钥“解决”签名不匹配。

自动保存保留 version 2。录制期间每约五秒请求检查点，进入 inactive/paused 尝试立即保存，未结束的检查点以 `ended: null` 恢复为可查看记录，不自动宣称完赛。强杀/断电仍可能丢失最近未落盘样本，不能承诺零损失。写盘失败提示导出；损坏原存档阻止自动覆盖并显示持续告知。单条删除需确认，只删除所选记录。Android `allowBackup=false` 避免依赖不可控的系统云备份；不同 OEM 的设备迁移行为仍需核实。

## 隐私与网页

启动先读取独立同意版本，未同意前不创建 AppController，不监听 UDP、不扫描地址、不请求周内容、不实例化阅读 WebView。拒绝可继续阅读，政策版本变化重新告知。撤回前保存当前快照、清本应用 WebView Cookie/网页存储，然后释放控制器并返回告知；原设置/记录不删除，重新同意后恢复。系统浏览器数据需用户在浏览器管理。

App 内政策文本在 `lib/pages/privacy_page.dart`，包含中英文数据流、权限、第三方网站、COS 和备份说明。运行 `python scripts/export_privacy_policy.py` 生成与源码一致的静态 HTML 到 `artifacts/release-prep/privacy.html`；**只生成，不上传**。开发者和生效日期未补齐时仍是草案。托管后须检查 HTTPS 200、无需登录、手机浏览器可读、合适 Content-Type、不强制下载；COS 默认域名是否可供商店政策阅读需实际验证，不能假定上传 HTML 即完成。

原站 WebView 保留；仅允许来源站 HTTPS 导航，跨站 HTTPS 先确认再系统浏览器打开，HTTP/自定义 scheme/凭据 URL 被拦截。支持网页历史返回，验证登录/验证码不自动绕过。非预期跳转、手机断网重试仍按清单上机验收。

网络权限源码为 INTERNET、ACCESS_NETWORK_STATE，文件备份采用 [Android Storage Access Framework](https://developer.android.com/training/data-storage/shared/documents-files)，不申请广泛文件存储权限。最终以构建后的合并清单为准。APP 备案号入口在关于与隐私，未取得显示待补充，取得后链接 `https://beian.miit.gov.cn/`；参考 [工信部 APP 备案通知解读](https://www.miit.gov.cn/jgsj/xgj/hlwgl/art/2023/art_564bf0759d7e41d5b4aa8ce4996b9e84.html)。
