# Horizon Link 开源声明

更新：2026-11-14。应用内入口：设置 → 关于与帮助 → 开源许可。

| 来源 | 使用范围 | 声明方式 |
| --- | --- | --- |
| [FH6 Scenic Navigator / atikhobaev](https://github.com/atikhobaev/fh6-scenic-navigator) | WVAN 提取/解析、图编译工具参考，世界坐标投影校准参考及选取的社区地点记录 | 源码保留 `scripts/vendor/fh6_nav/LICENSE`；完整 MIT 原文另随包放入 `assets/licenses/fh6-scenic-navigator-MIT.txt`；应用许可列表显示项目来源、使用范围、作者和完整许可 |
| [23sigma/forza-wheel-leds](https://github.com/23sigma/forza-wheel-leds) | 限转反弹检测及按车标定参考/移植，增加同挡与中断保护 | 保留 Copyright (c) 2026 forza-wheel-leds contributors 及完整 MIT 原文于 assets/licenses/forza-wheel-leds-MIT.txt，应用许可页注册展示 |
| Noto Sans SC、Barlow Condensed | 本地嵌入字体 | 两份完整 OFL 原文及来源记录，详见 [FONT_LICENSES.md](FONT_LICENSES.md) |
| Flutter SDK、Material/Cupertino 图标及 Pub 依赖 | App 框架、本地存储、URL 打开、WebView、Web 支持及其传递依赖 | 保留 Flutter 自动生成的 NOTICES/NOTICES.Z，通过同一应用许可页展示 |

MIT 原文声明 Copyright (c) 2026 atikhobaev，允许按许可条件使用、修改和分发相关软件，要求保留版权及许可声明。此处将声明随 App 一并提供，也保留提取工具源码中的原文；不会把本项目全部源码标为该作者作品。

`lib/services/bundled_licenses.dart` 在启动时注册手动随包声明，使用幂等保护避免重复注册；不替换或清空 Flutter 默认的依赖许可收集器。地图来源说明 `assets/map/NOTICE.txt` 指向实际随包许可位置。MIT 的适用范围是对应开源软件，并非对其他来源内容的许可声明。

新增/替换第三方代码时同时保留作者、原始许可和项目来源；不要只写 MIT 名称或只给外部链接。当前回归入口 `test/font_licenses_test.dart` 核对 MIT 原文与 vendor 源一致、作者/授权/免责声明可读、每种手动声明仅注册一次，以及中英文许可页面阅读和返回。
