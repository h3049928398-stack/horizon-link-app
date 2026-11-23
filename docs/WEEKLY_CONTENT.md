# 每周活动内容更新

2026-11-08 App 扩展：根级可选 `guideUrl` 可随同一 revision 更新小黑盒攻略网页地址，字段缺失/null 使用内置地址，非法字段拒收整份更新。完整网站对接契约和验收见 [攻略网页地址更新交接](WEEKLY_GUIDE_URL_HANDOFF.md)。本轮仅实现 App，不改变线上文件或内容源地址。

2026-11-04：用户要求迁移为 App → 自有域名 → 服务器 → COS。配置与切换流程见 [每周内容服务器入口](WEEKLY_GATEWAY.md)。已提供 Nginx 模板和生成工具；等待真实域名/服务器信息，当前构建配置仍指向 COS。下文直连 COS 说明保留为现有部署记录，不能视为新链路已上线。

第一版能力：攻略页增加季节赛事、宝箱和其他活动的定位按钮，切换到现有地图、居中并显示选点卡片。地图的日历按钮可开关活动图层。定位不自动开始导航、不替换当前路线；没有游戏车辆定位时仍可查看活动位置。小黑盒原攻略入口保持不变。

这是 JSON 内容更新。新增功能、原生插件、字体资源、底图或路网更新仍需要新安装包。本功能只需先安装一次带内容更新能力的 App，之后每周数据变化无需重新安装。

## 用户先准备什么

1. 腾讯云账号，开通 COS。建议单独创建标准存储桶，例如使用广州地域；不用购买云服务器或域名。COS 收取存储、请求和下载流量费用，在控制台设置预算提醒并查看实际账单，不假定永久免费。
2. 存储桶保持私有写入；通过只读策略，仅让匿名用户对 `weekly/*` 对象执行 `cos:GetObject`。不开放写入、删除或列桶权限，不把整个私人存储桶设为公有。
3. 使用默认 HTTPS 对象地址：`https://<BucketName-APPID>.cos.<Region>.myqcloud.com/weekly/weekly.json`。不要使用有短期签名的下载地址，不把 SecretId/SecretKey 发进聊天、源码或 App。
4. 首周活动清单及真实有效期，每个活动对应的地图截图、已有地点名称/ID或已确认的游戏世界坐标。每个位置保留来源及验证状态。宝箱线索还没有确定位置时发布为待补充，不猜测坐标。

官方参考：[默认域名及 HTTPS](https://cloud.tencent.com/document/faq/436/56560)、[COS 计费](https://cloud.tencent.com/document/product/436/16871)。

建议通过 COS 控制台手动上传。不要把云账号凭据打包进手机。仅上传准备好的 `weekly.json`，不要上传原始截图、个人资料、完整源码、地图游戏素材或本地审计文件。

上传设置：`Content-Type: application/json; charset=utf-8`，`Cache-Control: no-cache`。App 只接受 HTTPS 直接返回 200 的内容，不跟随重定向。若测试 Web 预览，在 COS 配置 CORS：仅允许所用预览/正式站点 Origin 的 GET，允许 `Cache-Control` 请求头；安卓原生读取不需要 CORS。

## 内容格式

从 `docs/weekly-content.template.json` 复制到忽略目录如 `.tools/weekly/source.json`。空模板只表示没有已发布数据，不包含虚构赛事。以下仅是结构示例，不应作为真实本周数据发布：

```json
{
  "schemaVersion": 1,
  "revision": 1,
  "periods": [{
    "id": "series-week-id",
    "name": {"zh": "填写真实周次", "en": "Optional English title"},
    "startsAt": "2099-01-01T18:30:00+08:00",
    "endsAt": "2099-01-08T18:30:00+08:00",
    "events": [{
      "id": "event-id",
      "type": "treasure",
      "name": {"zh": "填写真实活动名"},
      "locations": [{
        "id": "location-id",
        "name": {"zh": "位置待确认"},
        "quality": "unknown",
        "source": "填写资料来源"
      }]
    }]
  }]
}
```

- `schemaVersion` 固定为 1；`revision` 是递增正整数，上限 2147483647。一次更改必须发布更高修订号，包括同周位置纠错。整个 JSON 上限 1 MiB，每个数组最多 1000 项。
- 周期、活动、位置 ID 在整个内容包中唯一，只使用字母、数字、点、下划线和连字符，最多 100 字符。周期不能重叠；时间格式为带明确时区的 ISO 时间，不默认每周某日固定切换。开始包含、结束不包含，可预先放入下一周期。
- `type` 为 `seasonal` / `treasure` / `other`。名称必填 `zh`，可选 `en`；英文缺失时展示中文。运行时新字使用系统字体回退，无需每周重建字库。
- 已有地点：在位置中增加 `"placeId": "实际的现有地点ID"`。ID 可查 `flutter_app/assets/map/places.json`，中文名称见同目录 `place_names.json`。不要把赛道几何首点当成已确认的赛事报名触发点。
- 新位置：增加 `"coordinates": {"x": 真实X, "y": 真实Y, "z": 真实Z}`，为游戏世界坐标，不是经纬度或截图像素。禁止同时提供 `placeId` 与 `coordinates`，禁止越出当前地图投影范围或非有限数。
- 有位置时 `quality` 必须为 `community`（待实测）或 `verified`（实际游戏核验）；无坐标时只能为 `unknown`，定位按钮禁用。已有地点的待实测状态不能仅通过引用就升级为已验证。
- 一项活动可以有多个位置，也可以暂时没有位置。`source` 始终必填，可填原资料 URL 和人工核对说明。不要把攻略正文复制进数据包。

## 每周发布

你提供每周资料后，由维护侧整理数据和核对坐标；无须你手写 JSON。工具只校验和生成文件，不自动上传、不读取云凭据。

```powershell
# 只校验，不写文件
python scripts/publish_weekly_content.py --input .tools/weekly/source.json

# 生成新修订和本地可读预览
python scripts/publish_weekly_content.py --input .tools/weekly/source.json --revision 2 --previous .tools/weekly/last-published.json --output artifacts/weekly/weekly.json --preview artifacts/weekly/review.md
```

首次发布省略 `--previous`，后续始终提供最新已发布文件，防止重复或倒退修订。检查预览中的时间、每个位置及来源，再在 COS 控制台覆盖 `weekly/weekly.json`。保存本次已发布文件为本地 `last-published.json`。修正错误或恢复上一份内容时，用旧内容配上**更高**修订号重新生成、发布。

App 启动先读独立本地缓存；联网检查不阻塞 UDP 或用户存档加载。进入地图/攻略以及返回前台时，距上次成功检查满 6 小时才联网检查；攻略页刷新按钮可以立即检查。失败保留缓存，可手动重试。过期后地图隐藏本周图层中的旧活动，攻略明确显示上期内容供参考；没有当前或上期内容则显示待发布。有效期按设备时间计算，手机应启用自动校时。

## 首次接入地址和验收

当前公开内容地址已登记在 `config/weekly-content.json`：

`https://horizon-link-content-1523285230.cos.ap-guangzhou.myqcloud.com/weekly/weekly.json`

普通安卓部署脚本构建时自动读取此配置，避免后续安装遗漏地址；显式 `-WeeklyContentUrl` 参数可覆盖，显式传入空字符串可构建未配置版本。`-SkipBuild` 只复用已有 APK，不重新应用配置。该文件仅存公开 URL，不包含云凭据。

正式构建增加 `--dart-define=WEEKLY_CONTENT_URL=https://.../weekly/weekly.json`。地址是公开读地址，不是密钥。安卓调试仍用原入口，保留英文 APK 暂存：

```powershell
./scripts/run_android_debug.ps1 -WeeklyContentUrl 'https://.../weekly/weekly.json'
```

`-SkipBuild` 不能用于更换地址或源码后生成新包。没有配置地址时，App 显示未配置提示，原地图和攻略仍可用。正式发行前还需完成项目已有的 Android 正式签名准备，本次不改变签名身份。

验收需要：同一安装包获取修订 1 → COS 发布修订 2 → 点击刷新看到位置变化 → 断网仍可定位缓存 → 关闭重开保留内容 → 原设置和驾驶记录不变。测试活动必须显式命名为测试，完成后撤下。单元测试与本地模拟响应不能代替真实 COS/游戏位置验收。


## 2026-11-02 发布准备核对

本轮只读 HTTPS 请求实际返回 200 / revision 3 / 一个周期，JSON 与手机缓存内容相同；Content-Type application/json、Cache-Control no-cache。本机 `.tools/weekly/last-published.json` 原先落后为 r2，已先留副本到 `artifacts/release-prep/local-last-published-before.json` 再同步为实际线上 r3。下一修订至少 r4，发布前仍须再次读线上。没有上传或覆盖 COS，没有声称 r3 的活动来源/坐标已经游戏实测。

最新启动流程在用户同意隐私告知后才初始化本地业务/周缓存与联网检查；撤回会释放服务并取消原生在途请求，保留缓存与记录。六小时触发节流/手动强刷规则不变。正式构建通过 `scripts/build_android_release.ps1` 自动保留 WEEKLY_CONTENT_URL，缺少地址或其他发行必需资料时失败，不能用遗漏配置的裸 build 命令代替。

## 设置页的应用版本清单

用户手动点击设置底部 Horizon Link 时，App 将构建时的 WEEKLY_CONTENT_URL 解析到同目录的 app-version.json，使用 HTTPS 获取清单，在手机上比较。此请求独立于周内容刷新及六小时间隔。

本地文件为 [app-version.json](../config/app-version.json)，COS 对象键为 `weekly/app-version.json`。由维护者自行上传并允许匿名 HTTPS 读取；保留同目录的 weekly.json。清单以 android 和 ios 为键，值使用对应平台实际可用安装包的「主版本.次版本.修订号+构建号」，例如 0.2.0+2。分平台更新对应值即可。清单缺失、版本格式无效或网络不可用时，设置行提示检查失败，可再次点击。
