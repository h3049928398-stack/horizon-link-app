# Horizon Link 字体来源与分发许可

更新：2026-11-01。本文只处理字体，不代表游戏地图、攻略或其他第三方内容已获授权。

## 已打包的字体

| Flutter 字体族 / 文件 | 上游与改动 | 许可 |
| --- | --- | --- |
| Chinese / `assets/chinese.ttf` | Noto Sans SC，400 字重；按现有界面和地图 JSON 提取字形，衍生字体名 Horizon Link Sans | SIL OFL 1.1 |
| GainLabel / `assets/gain_label.ttf` | Noto Sans SC，700 字重；仅保留中英文名次提升提示字形，衍生字体名 Horizon Link Gain | SIL OFL 1.1 |
| Dashboard / `assets/dashboard.ttf` | Barlow Condensed SemiBold，600 字重；衍生字体名 Horizon Link Dashboard，保留窄体仪表数字风格 | SIL OFL 1.1 |

已替换原 Windows 微软雅黑和等线粗体子集。生成脚本不再读取 Windows 字体或旧 Web 工程。Flutter 的 Chinese、GainLabel、Dashboard 是应用内部资源别名。

官方来源为 [Google Fonts Noto Sans SC](https://github.com/google/fonts/tree/main/ofl/notosanssc) 和 [Barlow Condensed](https://github.com/google/fonts/tree/main/ofl/barlowcondensed)。固定提交、每份字体及许可的 SHA-256 见 `scripts/font_sources.json`；输出字体指纹和 fontTools 版本见 `flutter_app/assets/licenses/font-build.json`。应用包内始终包含上游完整版权声明和 OFL 原文，并可通过「设置 → 关于与帮助 → 开源许可」查看 Noto Sans SC / Barlow Condensed 条目。

OFL 允许字体随免费或收费应用嵌入和分发，不需要为此购买字体授权；应继续保留版权声明和 OFL，衍生字体仍适用 OFL，不可单独出售字体，不得使用保留字体名给衍生字体命名或暗示原作者背书。该许可不要求应用自身源码使用 OFL 或开源。Noto 上游声明的保留名称为 Source，本项目衍生字体使用上述独立名称。

Material / Cupertino 图标字体仍由 Flutter SDK 和已锁定的 cupertino_icons 包提供，由 Flutter 标准许可证收集机制呈现各自声明；没有复制系统安装字体。

## 重建与检查

现有提交中的三个字体和许可文件可以直接构建应用；普通 Flutter 构建无需联网下载字体，也无需重新生成它们。

需要新增界面汉字或地点名称时，从工程根目录运行：

```powershell
# 首次准备来源；固定官方 URL + SHA-256。已缓存且校验通过则完全离线。
.\scripts\fetch_font_sources.ps1

# 使用已有 Python/fontTools，离线生成。
python scripts/prepare_flutter_fonts.py
python scripts/check_font_assets.py

# 兼容旧入口，只重建名次提升字体。
python scripts/prepare_gain_label_font.py
```

完整字体来源缓存在 Git 忽略的 `.tools/font-sources/`，不打包进 App。工具不读取或安装系统字体，不关闭 TLS 校验，不修改全局代理。下载失败即停止，按工程约定先与用户确认，再处理联网问题。

生成器保留字体版权和 OFL 元数据，使用固定上游时间戳，重复执行应得到相同字节。中文覆盖扫描当前 Dart 文件和解码后的地图 JSON，包括转义 Unicode；提示字体只供固定提示使用。地图未预置的新名称或用户任意输入可能使用系统字形回退，新增产品文案后必须重新生成。检查脚本核验输出哈希、名称、字重、许可和现有中英文所需字形覆盖，拒绝 Windows 字体身份信息。

## 验证入口

- `flutter_app/test/font_licenses_test.dart`：许可随包、注册不重复、中英文 320 像素真实字体布局及许可页打开/返回。
- `RENDER_FONTS=1` 可输出 `artifacts/font-home-{zh,en}.png`；已有 `RENDER_DASHBOARDS=1` 输出真实字体专业仪表。
- 完整 Flutter 回归必须继续包含 `connection_sheet_test.dart`；字体变化应同时检查仪表、地图、语言和主题布局。
