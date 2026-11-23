# 每周内容服务器入口

目标链路：`App → https://你的域名/weekly/weekly.json → 你的服务器 → COS`。

App 现有 `WEEKLY_CONTENT_URL` 支持这个 HTTPS 地址，无需增加手机端 SDK。服务器使用 Nginx 对固定对象进行反向代理，直接返回 JSON 字节，不将 App 重定向到 COS；客户端的格式/修订校验、独立缓存、6 小时触发节流及手动刷新继续生效。

## 当前进度

实际活动域名已纠正为 `horrizon-link.ninaaa.cloud`。服务器为 Windows Server 2022 / 宝塔 Windows 8.5.2 / Nginx 1.21.1，CA 路径为 C:/BtSoft/nginx/conf/cacert.pem。用户已完成代理和手动 DNS 验证的域名证书，服务器本机 HTTPS 测试200；公网、备案、正文逐字节及手机切换仍待验收，自动续期未验证。`config/weekly-content.json` 继续原 COS 地址。下方错误域名与早期进度保留作历史记录，后续以本段和最新补充为准。

## 生成配置

先确认域名 DNS 已指向服务器，HTTPS 证书有效，并提供最终内容 URL。以下域名仅用于说明，不要直接发布：

```powershell
python scripts/configure_weekly_gateway.py --endpoint 'https://content.example.com/weekly/weekly.json'
```

输出到忽略目录 `artifacts/weekly-gateway/`：

- `weekly-location.conf`：放入你域名现有 HTTPS `server {}` 内，不是独立的完整 Nginx 配置。
- `weekly-content.json`：核验成功后才复制到工程 `config/weekly-content.json`，用于后续 App 构建。

生成工具不部署、不连接服务器、不改当前 App 地址。不要把示例域名配置复制成正式地址。

默认 CA 证书包路径 `/etc/ssl/certs/ca-certificates.crt` 常见于 Debian/Ubuntu。其他系统先确认实际路径，可传 `--ca-bundle /etc/pki/tls/certs/ca-bundle.crt` 等真实路径；不能关闭上游证书校验。如果用宝塔，在网站 HTTPS 配置中加入生成的 location，保留原站点配置和证书，避免重复同路径 location。

部署前保留原配置副本，执行 `nginx -t`；成功后按服务器现有管理方式平滑重载。域名入口必须直接返回 HTTP 200 JSON，不得登录挑战或 302 到 COS；前置 CDN/WAF 同样不能缓存过期文件或重定向。服务器需要访问 COS 的 HTTPS 出站权限。

## 配置行为

仅代理固定 COS 对象 `horizon-link-content-1523285230/weekly/weekly.json`，不接收客户端提供的目标 URL。只开放 GET/HEAD，清除传入查询参数，不向 COS 转发 App 的 Cookie、Authorization、客户端 IP 或其他原始请求头。显式验证 COS TLS 证书、SNI 与 Host；禁用此 location 的代理缓存，返回 `Cache-Control: no-cache`。不改写 JSON、revision 或时间，因此同一修订的字节保持稳定。

本接口 Nginx access log 关闭以减少客户端 IP 留存；全站 error log、安全软件或负载均衡日志仍需按实际环境核对，不能因此声称服务器绝不处理 IP。原生 App 无需 CORS；如未来需要 Web，请在自己的服务器针对已知 Origin 单独配置并验证。

COS 源文件仍需允许服务器读取。该模板沿用现有公开读取对象，不需要云密钥。若改成私有桶，应另外配置服务器侧 COS 签名读取/实例角色；不能仅把桶改私有就认为该模板仍可使用，也不能把密钥放进 App。

## 切换与验收

1. 从域名入口匿名 GET，核对 200、JSON、无跳转，与 COS 原文件逐字节一致；使用 `scripts/publish_weekly_content.py --input 下载文件` 校验。
2. 成功后更新 `config/weekly-content.json` 为域名地址，并同步中英文隐私文案及政策版本：App 的连接对方变为你的服务器，服务器请求 COS；核对实际日志处理方式。发布政策公网正文也应同步。
3. 用原安卓部署脚本构建安装一次新地址基础包，保留英文 APK 暂存及当前签名。不使用 `-SkipBuild` 更改地址。后续改服务器 COS 上游可继续保持 App 域名地址稳定。
4. 现有周缓存按 URL 隔离，换域名后的第一次启动需要联网获取新入口；旧周缓存不会作为新入口的缓存直接加载。设置/驾驶记录不受影响。不通过删除应用数据解决切换问题。
5. 真机从域名刷新，核对地点及离线/冷启动缓存；同一安装包读取下一个实际发布修订，失败仍保留缓存，服务器请求失败不直接回退 COS。不要用 JSON 测试内容覆盖真实活动。

校验活动 JSON 后上传 COS；服务器下次接到 App 请求时读取最新对象。更新文件需递增 revision。App 六小时节流仍可能延后自动获取，手动刷新可立即请求服务器。

配置依据：[Nginx 官方代理模块文档](https://nginx.org/en/docs/http/ngx_http_proxy_module.html)。本机生成工具测试不等于目标服务器 `nginx -t` 或真实代理链路验收。

## 用户域名配置（2026-11-04）

最终拟用地址 `https://horrizon-link.ninaaa666.cloud/weekly/weekly.json`。专用文件已生成在 `artifacts/weekly-gateway/`，用户自行配置宝塔。HTTPS 当前检查失败，不能归因为备案或具体证书问题，需用户配置就绪后复查。当前 App 地址暂不切换，避免更新请求指向不可用接口。


## Windows 宝塔实机配置进度（2026-11-04）

用户服务器为上海 Windows Server 2022，宝塔 Windows 8.5.2，Nginx 1.21.1。用户已自行安装 Nginx、创建 horrizon-link.ninaaa666.cloud 静态站点和代理；本站根目录 C:/wwwroot/horrizon-link.ninaaa666.cloud，当前仅 listen 80，域名 SSL 尚未部署、备案中。

宝塔界面创建 location /weekly/ 时会给目标 URL 补 /，导致根路径替换：目标必须包含 /weekly/ 才保留正确目录。最终用户已用精确 location = /weekly/weekly.json 全文替换 C:/BtSoft/nginx/conf/proxy/horrizon-link.ninaaa666.cloud/1793800729637.conf，启用 SNI/Host/TLS 验证，CA 文件 C:/BtSoft/nginx/conf/cacert.pem；关闭 proxy_cache 与 expires，清除客户端查询和请求头，仅读取固定 COS 对象。原先自动生成的 expires 12h、转发客户端 IP 等已移除。自定义配置后不要直接在宝塔代理表单点确认覆盖它，变更后需复查。

用户提供 nginx -t 的成功输出；普通及管理员 PowerShell -s reload 都出现 OpenEvent Access denied。经宝塔软件商店 Nginx → 设置 → 服务 → 重载配置，用户报告重载成功；代理正文已在 UI 只读核对。未修改服务权限或关闭证书校验。

当前公网只读检查未读到服务器 JSON；COS 返回 200/r3，hash及错误见 artifacts/gateway-network-check.json。不能根据本机公网失败认定是备案、防火墙或代理配置错误；下一步让用户在服务器本机对 127.0.0.1 携带正确 Host 测试。App 仍为原 COS 地址，HTTPS/真实域名/同包下个修订/手机缓存链路待完成。

生成器现支持安全的 Windows 正斜杠绝对 CA 路径，4 项生成器测试通过；重新生成的 artifacts/weekly-gateway/weekly-location.conf 已使用 Windows CA 路径。服务器实际配置继承站点日志设置，未关闭 access log；后续隐私说明需按真实日志处理方式更新。没有 Flutter 业务修改、手机安装或云内容上传。

2026-11-04 域名纠正（以后续为准）：用户确认最终域名是 horrizon-link.ninaaa.cloud，非 ninaaa666.cloud。DNSPod 已有 horrizon-link A→43.142.106.143；宝塔待追加正确绑定并重新申请证书，不复用错误域名挑战值。待切换生成文件已更新，App 仍连接 COS。详见交接62。


2026-11-04 HTTPS 配置验收进度：用户为正确域名 horrizon-link.ninaaa.cloud 使用 Let's Encrypt DNS 手动验证，DNS TXT 已由本机解析核对，宝塔显示申请成功并部署，剩余 89 天。DNS 手动验证不代表已配置自动续期，后续需使用可验证的 DNS API 自动续期或及时手动更新；不得将旧 TXT 视为永久可复用。

腾讯云轻量服务器防火墙 UI 确认 TCP 443 对 IPv4 允许；用户在服务器运行 curl.exe --resolve horrizon-link.ninaaa.cloud:443:127.0.0.1 -I https://horrizon-link.ninaaa.cloud/weekly/weekly.json，提供 HTTP/1.1 200、application/json、Cache-Control no-cache。curl 正常证书验证且域名匹配，证明服务器本机 HTTPS→Nginx→COS 链路工作；此前 localhost HTTP GET 显示 r3。此检查不证明公网连通或正文逐字节一致。

本机独立对正确 HTTPS 域名请求仍报告 TLS EOF，公共网页读取工具无法访问；原因未定，不能直接归结备案、证书或防火墙。域名备案仍由用户处理。需使用独立外网/手机流量访问并调查服务器 Windows 防火墙、运营商网络、备案状态等，确认公网 200、字节一致后，再更新 App 配置及隐私政策/版本并构建真机验收。目前 App 未切换，仍用 COS；未上传云内容或完成公网/真机验收。
