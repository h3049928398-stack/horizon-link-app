# Horizon Link 隐私政策与使用说明

- 政策版本：2026-11-23.1
- 生效日期：2026-11-23
- 开发者：黄家欣
- 隐私与支持联系邮箱：h3049928398@gmail.com

## 一、本地游戏数据

同意后，本应用读取本机局域网 IPv4 地址以帮助配置游戏，并在指定端口监听 UDP。游戏遥测包含车辆状态、游戏世界坐标、赛事计时与名次；游戏坐标不是手机地理位置。设置、最近八段记录（每段最多 12,000 点）与内容缓存保存在本应用本地目录，未结束的记录可在重启后恢复查看。本应用不向开发者上传这些记录。

## 二、每周内容

同意后通过 HTTPS 从腾讯云 COS 请求公开活动 JSON。COS 为提供内容会接收网络 IP 地址和常规请求信息；基础设施访问日志可能按腾讯云规则处理。请求不附带遥测或设置。启动、进入相关页面或返回前台触发检查，成功检查后六小时内通常跳过，手动刷新可强制检查。没有云推送或持续轮询。点击设置中的版本行时，应用从同一服务器读取公开版本清单，在本机比较版本。

## 三、第三方网页

只有主动打开攻略时才创建 WebView。小黑盒和 Forza 网站会收到网络请求，并可能按其自身政策使用 Cookie、网页存储及您主动输入的账号信息；本应用不读取密码。跨站 HTTPS 链接经确认后交由系统浏览器打开，My Forza 同样在系统浏览器打开。浏览器数据由浏览器管理。撤回同意会清除本应用 WebView 的 Cookie 和网页本地存储。

## 四、权限、导出与保存

安卓网络权限用于 UDP、内容及网页读取。不申请手机定位、通讯录、麦克风、相机或广泛存储权限；当前未集成广告或统计 SDK。主动复制 JSON 会把该记录写入系统剪贴板。文件备份与恢复使用安卓系统文件选择器，您选择的目标也可能是云盘。备份以明文包含设置及驾驶记录，请妥善保管；不含周内容缓存、网页 Cookie 或隐私同意，导入不会代替同意。

## 五、您的选择

同意前不启动 UDP、地址扫描、周内容请求或 WebView。您可拒绝、阅读政策或稍后再决定。在设置可再次查看并撤回；撤回停止上述服务并返回告知页，不删除设置和记录。数据管理可备份、恢复或删除记录。系统清除应用数据或卸载会删除本地数据，请先导出并验证备份。政策版本变化时再次征求同意。隐私请求请联系上述邮箱。

## 使用说明

本应用提供游戏内驾驶辅助。实验 UDP 字段及游戏地图对应关系仍待实测，暂停、回溯或断流可能影响赛事判断。攻略版权归原作者所有。本应用免费且无广告。

---

## Horizon Link Privacy Notice

- Policy version: 2026-11-23.1
- Effective date: 2026-11-23
- Developer: 黄家欣
- Privacy / support contact: h3049928398@gmail.com

### 1. Local game data

After you agree, the app reads local IPv4 addresses to help configure the game and listens for UDP on your selected port. Game telemetry includes vehicle status, game world coordinates, race timers and positions. These are not your phone's geographic location. Telemetry, up to eight recordings (12,000 samples each), preferences and content cache stay in the app's local storage. An unfinished recording may be recovered after restart. This app does not upload these records to the developer.

### 2. Weekly content

After agreement, the app requests public JSON from Tencent Cloud COS over HTTPS. COS receives the network IP address and normal request information to serve content; infrastructure access logs may be processed under Tencent Cloud's rules. No telemetry or settings are attached to these requests. Checks triggered by startup, selected pages or returning to the app are limited to once per six hours after success; manual refresh can bypass this interval. There is no cloud push or continuous polling. Tapping the version in Settings requests a separate public version list from the same server. The app compares versions on your device.

### 3. Websites and browser

WebView is created only when you choose to open a guide. Xiaoheihe and Forza websites receive network requests and may use cookies, web storage and account information you enter under their own policies. The app does not read your passwords. Other HTTPS sites require confirmation before opening in your system browser. My Forza also opens in the system browser. Browser data is managed by that browser. Withdrawing consent clears this app's WebView cookies and local web storage.

### 4. Permissions, export and retention

Android internet/network access supports UDP and content/web reading. The app does not request phone location, contacts, microphone, camera or broad storage permissions. It contains no advertising or analytics SDK. Copying JSON writes the selected record to the system clipboard. File backup/restore uses the Android document picker; the destination provider you choose may be a cloud drive. Backup files contain settings and recordings in plain text: keep them private. Weekly cache, web cookies and privacy consent are excluded. Imported backups never grant consent.

### 5. Your choices

Before agreement, no UDP listener, address scan, weekly request or WebView is started. You can decline, read this notice, or return later. Review this notice and withdraw in Settings; withdrawal stops these services and returns to the notice without deleting settings or recordings. Data management lets you back up, restore or delete recordings. Android app-data clearing/uninstall removes local data; export and verify a backup first. A changed policy version requires agreement again. Contact the address above for privacy requests.

### Usage notice

This app supports in-game driving and navigation. Experimental UDP fields and game map alignment still require real-game validation. Pause, rewind and interruptions may affect race detection. Third-party guide copyright remains with its authors. This app is free and has no advertising.
