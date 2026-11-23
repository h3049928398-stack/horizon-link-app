# 性能检查与优化

## 2026-11-11：启动、切页和滑动

本轮在现有 Flutter 工程优化通用性能，不改变四栏、遥测/比赛判定、隐私或 version 2 保存格式。

- 空闲断流检测仍每 100 ms 检查，但仅在首次进入等待/中断状态时通知界面；不再空闲每秒重建十次。UDP 收包合并正常路径的重复通知，陈旧包仍更新收包连接状态；不丢弃比赛检测或录制所需帧。
- `initialize()` 恢复设置/记录后即置 `ready`，允许原隐私入口启动 UDP。路网独立加载，地图失败不阻塞其余页面。需要等待路网的调用方显式 `await app.mapLoaded`。原生平台通过 Flutter `compute` 在独立 isolate 完成路网 JSON、模型和空间索引，以及完整存档校验/模型恢复；Web 的 compute 不提供相同线程隔离，本轮没有构建或测量 Web。
- 四栏首次访问才创建，访问后继续保留地图视角、筛选和滚动状态。驾驶等不透明路由覆盖首页后，暂停首页控制器监听；设置/攻略只在其依赖状态变化时替换页面。
- 自带和自定义仪表共用每画布最多 256 条的文字排版 LRU，缓存键包含文本、样式、宽度、对齐及换行条件。淘汰/字体变化/画布销毁时释放 TextPainter，不无限累积变化读数。独立 painter 无缓存调用也显式释放文字资源。
- 地图有限类别图标异步生成 4 倍清晰度小纹理，完成前继续矢量绘制，分配失败保留矢量回退。图片就绪后让标记记录和选中覆盖层失效；地图销毁释放图片/绘制记录，迟到图片立即释放。地点数量、形状、尺寸规则、筛选、命中范围和来源不变。

## 测量方式和证据

同一台 M2104K10AC、同样原存档（本轮 8 段，约 5 MB）、同签名 Profile/AOT 构建，优化前后均使用 `scripts/run_android_debug.ps1 -DeviceId <device-id> -Mode profile` 重新构建、英文源码副本及英文 APK 暂存。没有用 debug/Profile 差异冒充代码收益，也没有使用 SkipBuild。没有注入遥测或添加运行时演示入口。

通过本轮 Flutter VM 服务时间线清空后取样，顺序执行静置首页 5 秒、首页三组上下滑动、首次进入地图、五次地图拖动、四栏来回切换、回首页静置 5 秒。原始 B/E、b/e 事件按名称、线程、ID 配对，忽略窗口边界不完整区段。`Frame` 是 Flutter 界面帧区段；`GPURasterizer::Draw` 是栅格线程区段，包含提交/等待，**不是 GPU 硬件计时或端到端触摸延迟**。

| 同一短时场景 | 优化前 | 优化后 |
| --- | ---: | ---: |
| 首页静置 5 秒完整 Frame 数 | 50 | 0 |
| 三次进程冷启动 TotalTime 中位数 | 928 ms | 747 ms |
| 首页滑动 Frame P95 | 16.356 ms | 2.128 ms |
| 首页滑动栅格区段 P95 | 9.912 ms | 7.900 ms |
| 地图拖动栅格区段中位数 | 40.686 ms | 7.818 ms |
| 地图拖动栅格区段 P95 | 44.525 ms | 9.109 ms |
| 切页 Frame P95 | 19.941 ms | 3.898 ms |
| 切页栅格区段 P95 | 19.383 ms | 9.697 ms |

首次地图仍有一次初始化长帧（优化后 Frame 最大 55.879 ms、栅格区段最大 82.222 ms）；首次纹理/道路准备未消除全部峰值。表格来自各一次固定短时场景，不代表所有设备或持续帧率保证。16.67 ms 仅可用作 60 Hz 参考预算，不能据此宣称设备恒定帧率。

冷启动使用 Android `am start -S -W`，前 1103/928/911 ms，后 773/747/740 ms。TotalTime 只衡量进程启动至首个 Activity 画面，不等于设置、地图、网页全部就绪；路网现已独立后台加载。日志 `performance-{before,after}-coldstart.json`。

真机复验基础驾驶横屏、全屏提示消失后画面完整、900 ms 短按保持、2200 ms 长按恢复、返回竖屏及地图图标；图片 `android-performance-{dashboard,fullscreen,map}.png` 已查看。完整 version 2 存档（全部设置、8 段记录及采样）和隐私同意文件前后逐字节一致，报告 `performance-phone-result.json`。构建/英文暂存 APK SHA-256 相等，apksigner 确认为 Android Debug 身份；手机最终保留本轮 Profile 包并停竖屏首页，冷启动已结束原调试连接。

本轮完整 **251 项 Flutter 测试通过**、同 SDK `dart analyze: No issues found`、969 所需中文字形/字体许可哈希审计通过。新增 7 项回归覆盖空闲通知、慢地图与错误隔离、迟到加载/销毁、延迟建页/状态保留/覆盖路由暂停、设置依赖、文字缓存淘汰及五款仪表缓存前后逐像素一致。原连接弹窗、全屏、画布裁剪、自定义协议/事务和存档测试保留。原测试中需要真实路网的调用改为显式等待 `mapLoaded`，未删减断言。

证据均在 Git 忽略的 `artifacts/`：`performance-{baseline,optimized}-deploy.log`、`performance-{before,after}-*-timeline.json`、`performance-{before,after}-frame-stats.json`、`performance-{before,after}-summary.json`、`performance-all-tests-final.log`、`performance-analyze-final.log`、`performance-font-audit.log`。测量脚本 `performance_probe.py` 也留在该目录，仅适用于本轮设备尺寸/本机服务地址，不当作跨机自动验收工具。

真实 FH6 连续 UDP/导航/录制、上限自定义布局长时间使用、内存压力、其他机型和 iOS 仍待专门测量。第三方攻略网页下载速度不由本地绘制优化保证；本轮未更改联网端点、缓存刷新周期或云内容。
