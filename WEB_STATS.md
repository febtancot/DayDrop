# 官网下载与更新统计

状态：已于 2026-10-28 部署上线，正式入口为 https://daydrop.liveby.app/stats。入口为 `/stats`，官网不展示入口。页面与 `/api/stats` 同时受密码保护。现有 macOS 应用、签名 appcast 和安装包无需修改；统计起点为北京时间 2026-10-28 08:52:27，不能还原历史下载量。

## 统计口径

| 指标 | 记录条件 | 版本含义 |
| --- | --- | --- |
| 官网入口下载 | 官网按钮带 `source=website` 的安装包起始请求 | 目标版本 |
| 应用内更新包 | User-Agent 同时包含 DayDrop 和 Sparkle 的完整包或增量包起始请求 | 目标版本 |
| 更新检查 | DayDrop Sparkle 的 appcast 请求，响应为 200 或 304 | 客户端当前版本 |
| 其他直接下载 | 无官网标记且未识别为 Sparkle 的包请求 | 目标版本 |

- 以北京时间汇总近 7、30、90 天，统计库仅保存日期、请求类型、版本、包类型和计数。
- 仅对发行目录白名单中的文件计数。完整包返回 200 或初始 Range 返回 206 才计数。
- 不计入 HEAD、失败响应、常见爬虫、预取、带 `verify` 参数的校验请求和非零起点续传。默认不统计签名文件、校验文件或发行说明。
- 没有 IP、设备标识或原始 User-Agent 入库。无独立用户去重；重复下载、初始分段重试、增量失败后下载完整包可能重复计数。客户端缓存、未识别来源和非典型下载工具会影响计数。
- 数字不代表下载完成、安装成功、更新成功或活跃设备。没有客户端安装完成上报。
- D1 写入通过 `waitUntil` 异步执行，失败只记录固定错误码，不影响文件响应。此时计数可能缺失。读取失败显示不可用，不返回虚假的零计数。

## 访问保护

- Cloudflare Pages secret `STATS_PASSWORD` 至少 24 字符，部署时必须使用密码管理器生成的高熵随机密码（建议 32 随机字节）。不使用可猜测的短语。
- 登录签发有效期 12 小时的 HMAC 会话 Cookie，生产 HTTPS 使用 Secure、HttpOnly、SameSite=Strict。
- 页面与接口都校验会话；未配置密码时拒绝访问。所有私有响应不缓存，统计页禁止索引与 iframe 嵌入。
- 退出清除当前浏览器 Cookie。修改密码会立即使全部旧 Cookie 失效；退出本身不会在服务器撤销已复制的 Cookie。
- 密码、Cookie、完整请求头、登录请求体不得写入日志。不得将真实密码写进文档、命令参数或 Git。
- 本地 `.dev.vars` 已忽略，只用于本地测试，不等于线上 secret。网站导航不公开统计入口。

## 本地运行

使用仓库锁定的 Wrangler 4.121.0；兼容日期为 2026-08-11，与其 workerd 支持上限一致。没有升级项目依赖。

1. 在权限为 `600` 的 `.dev.vars` 文件中设置本地随机 `STATS_PASSWORD`，不要复用线上密码。
2. 运行 `npm run db:local` 初始化本地 D1。
3. 运行 `npm run dev:web`，访问 `http://127.0.0.1:8796/stats`。
4. 运行 `npm run test:web` 和 `npm run verify:web`。

`wrangler.jsonc` 已配置生产 D1 绑定；本地命令不带 `--remote`，测试数据保存在本地 `.wrangler/state`。发布脚本拒绝全零 database_id。

## 本次上线记录

- 用户已明确授权上线；Cloudflare OAuth 已重新授权成功。
- D1：`daydrop-stats`，绑定 `STATS_DB`，数据库 ID 为 `74859a09-07bb-4532-82f3-eba6f167f78c`；远端迁移已完成。
- Pages 生产部署：`de399f29-dd5b-43f7-a646-11234a14a930`，地址为 https://de399f29.liveby-web.pages.dev。
- 生产 `STATS_PASSWORD` 已设置。密码保存在本机 `~/Library/Application Support/DayDrop Website/stats-password.txt`，文件权限为 `600`；未写入仓库或聊天。该文件是受文件权限保护的明文文件，尚未导入密码管理器。
- 正式域名与部署域名均通过私有页面、接口访问保护及发行内容一致性检查。
- 线上受控请求验证：官网完整包 1 次、Sparkle 完整包 1 次、Sparkle 增量包 1 次、Sparkle 更新检查 1 次，均正确计数。已精确扣除这 4 次测试增量并移除对应的零计数测试行；读回总数为 0。
- 线上浏览器已验证登录、近 7／30／90 天切换、指标切换、空状态及退出；退出后接口返回 401。已保存桌面和 390 px 手机截图，手机页面无横向溢出。
- 未验证真实 Sparkle 客户端下载并安装更新；受控 HTTP 请求不代表实际应用升级完成。

## 后续部署步骤

后续部署仍需用户明确授权，已有同一任务授权持续有效。以下流程复用现有数据库；不要重复创建或重置统计数据。

1. 检查 Cloudflare 授权；仅在权限失效时由用户在浏览器完成 `npx wrangler login`。不要通过聊天传递凭证。
2. 使用 `npx wrangler d1 list` 核实目标账号与已有数据库；如不存在，则执行 `npx wrangler d1 create daydrop-stats`。将返回的 database_id 填入 `wrangler.jsonc`，保留绑定名 `STATS_DB`。
3. 执行 `npx wrangler d1 migrations apply daydrop-stats --remote`。远端迁移只建汇总表和统计起点，不导入本地测试数据。
4. 保留现有 `STATS_PASSWORD`；仅在明确需要轮换时，用 `npx wrangler pages secret put STATS_PASSWORD --project-name daydrop` 的安全交互输入或受保护文件重定向设置新随机密码。轮换会使旧会话失效。
5. 执行 `npm run publish:web`。它会重新生成发行白名单、运行统计测试和本地发行验证，然后部署并读回两个域名的发行文件与访问保护。
6. 在生产 `/stats` 登录，确认初始统计为空或已有真实请求，测试范围切换与退出。确认发行验证产生的 `verify` 请求未增加计数；若测试真实统计请求，会计入生产数据，需事先说明。

生产入口为 `https://daydrop.liveby.app/stats`。需要同时验证不可变部署域名和正式域名的 `/stats`、`/stats.html`、`/stats/` 未登录只返回登录页，`/api/stats` 返回 401。不得只保护正式域名或只隐藏页面入口。

## 实现与验证

- `Product_Site/_worker.js`：资产转发、请求分类、D1 原子增量和查询。
- `Product_Site/stats-auth.js`：登录、Cookie 签名与验证。
- `scripts/generate-stats-catalog.py`：读取 appcast 与保留安装包生成有界白名单，不修改签名文件。
- `migrations/0001_download_stats.sql`：D1 数据结构。
- `tests/web/stats.test.mjs`：真实内存 SQLite、分类过滤、权限、过期和故障降级测试。
- 已验证本地 Pages + D1 的计数，以及 appcast、DMG、delta 的 SHA-256 保持一致。
- 已在 Ego Browser 验证登录失败、登录成功、空状态、7/90 天切换、指标切换、明细、网络错误、恢复与退出，桌面与 390 px 手机布局通过。生产受控请求和线上浏览器验证见「本次上线记录」；真实 Sparkle 客户端升级尚未验证。

实现依据：[Cloudflare Pages advanced mode](https://developers.cloudflare.com/pages/functions/advanced-mode/)、[D1 prepared statements](https://developers.cloudflare.com/d1/worker-api/prepared-statements/)、[Sparkle User-Agent 源码](https://github.com/sparkle-project/Sparkle/blob/2.x/Sparkle/SPUUserAgent%2BPrivate.m)。
