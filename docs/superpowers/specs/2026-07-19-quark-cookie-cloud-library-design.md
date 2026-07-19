# 夸克 Cookie 原生网盘媒体库设计

## 目标与边界

看影音在不依赖 OpenList、WebView 或外部服务的前提下，使用用户粘贴的夸克网页版 Cookie 原生浏览、扫描和在线播放夸克网盘媒体，并支持用户手动检查分享内容、选择条目、转存到自己的夸克目录。既有 OpenList、本地扫描、本地播放、TMDB、字幕和来源筛选行为保持不变。

首版不提供二维码登录、自动追更、定时订阅、在线搜索、离线下载、分片缓存、上传或完整文件管理。夸克接口失败只使对应来源失败，不阻止本地媒体库或其他来源工作。

## 协议核对结论

夸克没有稳定公开的开发者 API。本设计只采用 2026-07-19 核对到的活跃开源实现所共同使用的协议形状，不复制其实现代码。主要证据为 OpenListTeam/OpenList 的 `drivers/quark_uc`（AGPL-3.0，仅作协议核对）和 Cp0204/quark-auto-save（AGPL-3.0，仅作交叉核对）；另用 Apache-2.0 的 ihmily/QuarkPanTool 交叉核对分享转存字段。

| 用途 | 方法 | 主机与路径 | 关键请求 | 关键响应 |
| --- | --- | --- | --- | --- |
| 账号验证 | GET | `pan.quark.cn/account/info` | `fr=pc&platform=pc`、Cookie | `data.nickname` |
| 目录分页 | GET | `drive.quark.cn/1/clouddrive/file/sort` | `pdir_fid`、`_page`、`_size`、`_fetch_total=1` | `data.list[]`、`metadata._page/_size/_total` |
| 文件详情 | 目录结果或 POST | `drive.quark.cn/1/clouddrive/file/info/path_list` | 路径列表只用于兼容/核对；正式播放按 `fid` | `fid`、`file_name`、`file`、`size`、时间字段 |
| 原画地址 | POST | `drive.quark.cn/1/clouddrive/file/download` | `fids: [fid]` | `data[].download_url` |
| 分享令牌 | POST | `drive-pc.quark.cn/1/clouddrive/share/sharepage/token` | `pwd_id`、`passcode` | `data.stoken` |
| 分享目录 | GET | `drive-pc.quark.cn/1/clouddrive/share/sharepage/detail` | `pwd_id`、`stoken`、`pdir_fid`、分页参数 | `data.list[]`、`share_fid_token`、分页元数据 |
| 分享转存 | POST | `drive-pc.quark.cn/1/clouddrive/share/sharepage/save` | `fid_list`、`fid_token_list`、`to_pdir_fid`、`pwd_id`、`stoken`、`scene=link` | `data.task_id` |
| 任务查询 | GET | `drive-pc.quark.cn/1/clouddrive/task` | `task_id`、`retry_index` | `data.status`、任务标题和失败信息 |

所有 API 请求使用 `pr=ucpro&fr=pc`，并发送桌面浏览器 User-Agent、JSON Accept/Content-Type、`https://pan.quark.cn` Referer。客户端必须配置连接、发送和接收超时。HTTP 401/403 或协议认证错误不自动指数重试；429 和暂时性 5xx 才执行有上限的指数退避，并服从 `Retry-After`。

公开实现确认原画请求需要 Cookie、Referer 与 User-Agent。下载地址的实际主机和跳转链由账号、区域和文件动态决定，无法在没有用户凭据时得到可靠静态域名清单。因此安全策略是：Cookie 可发送到已核对 API 主机；播放时只发送给夸克 HTTPS API 返回的首始下载 URL 主机；任何跨主机重定向都剥离 Cookie。若跳转后的新主机仍要求 Cookie，则明确报错而不扩大凭据域。该限制必须在最终报告中披露，并建议用测试账号实机核对。

响应必须同时检查 HTTP 状态、顶层 `code`、`status` 和关键 `data` 结构。缺少必需字段时报“当前版本暂不兼容夸克接口”，不能降级成网络错误。测试夹具全部脱敏，不含真实 Cookie、文件名、分享令牌或播放地址。

## 远程引用与持久化

新增不可变 `CloudRemoteRef(id, path)`。`CloudDriveClient.listDirectory/getFile/resolvePlayback` 全部接收该类型：OpenList 使用 `path`，夸克使用 `id`，二者都保留另一字段供持久化、展示和识别。

`CloudSource` 增加 `rootRefs` 和可选 `defaultTransferDirectory`，普通配置只保存 ID、路径、显示名与启用状态，不保存 Cookie。旧数据只有 `rootPaths` 时迁移为 `CloudRemoteRef(id: path, path: path)`，从而保持 OpenList 行为。

`CloudMediaIndexItem` 保持 `remoteId` 与 `remotePath`，字幕从单独的路径列表升级为包含 ID 与路径的强类型引用。读取旧索引时，缺失字幕 ID 的条目用路径作为回退 ID。`CloudPlaybackTarget` 同时携带视频和字幕的 ID、路径，重启后不依赖内存映射。

## 提供商边界

新增 `CloudProviderRegistry`，集中完成客户端创建、凭据合并、来源规范化、提供商名称、错误文案、是否支持自签名证书和是否支持分享转存。`CloudLibraryController` 与 `CloudPlaybackResolver` 不再包含来源 `switch`，也不再知道 OpenList 地址、用户名密码或专属错误。

`OpenListClient` 通过远程引用继续按路径工作。`QuarkApiClient` 只负责 HTTP、超时、限速、重试、重定向和错误映射；`QuarkResponseParser` 只做强类型解析；`QuarkDriveClient` 只实现只读 `CloudDriveClient`；`QuarkShareTransferService` 独立提供写入性的分享转存，禁止把写操作加入通用驱动接口。

## 凭据生命周期

`CloudCredential` 和 `SecureCloudCredentialStore` 继续作为唯一安全存储。夸克编辑页永不回显旧 Cookie。测试登录使用临时 `MemoryCloudCredentialStore`；只有验证成功且用户确认保存后，控制器才写安全存储。

保存时纯 Cookie 也算有效凭据。编辑来源而 Cookie 留空时保留现有 Cookie；输入新 Cookie 时替换 Cookie 并清除客户端会话状态。删除来源时删除安全凭据、普通来源配置、媒体索引、海报和字幕缓存，但不调用任何远端删除 API。

## 扫描、播放与字幕

扫描器队列改为 `CloudRemoteRef`，目录条目同时保留 `fid` 和规范化路径。分页解析防止空页死循环、重复页、重复条目和总数漂移；超过页数/条目上限时报限流或结构不兼容。视频和字幕继续使用现有扩展名、大小阈值、系列识别与 TMDB 流程。

播放解析按持久化 `remoteId` 请求临时直链，将 Cookie、Referer 和 User-Agent 作为 media-kit 请求头透传。每个播放会话拥有一次性刷新门：首次 401/403 或明确的链接过期错误刷新一次；刷新后仍失败则停止。字幕下载同样使用强类型引用与受限请求头，并继续进入看影音专属缓存目录。

## 分享转存与幂等

分享 URL 只接受 `https://pan.quark.cn/s/<pwd_id>` 及其可选 `pwd` 参数。检查分享先获取短期 `stoken`，再分页浏览分享条目；`stoken` 只存在内存。用户选择文件或目录并确认后，调用 `saveShare()`，随后用 `queryTask()` 轮询到成功、失败、取消或超时。

幂等键为 `sourceId + shareId + sharedFileId + targetDirectoryId`。`QuarkImportHistoryRepository` 只持久化幂等键、公开显示信息、状态和时间，不保存 Cookie、`stoken`、直链或请求头。进行中或已成功记录阻止重复提交；失败、超时或取消可由用户重新发起。转存成功后调用现有完整来源扫描并刷新媒体库，不做局部索引合并。

## UI 与路由

设置路由拆为：

- `/settings/cloud-sources/add`
- `/settings/cloud-sources/openlist/edit`
- `/settings/cloud-sources/quark/edit`
- `/settings/cloud-sources/quark/import`

旧 `/settings/cloud-sources/edit` 继续跳转或渲染 OpenList 编辑页。网盘来源页的添加按钮改为选择菜单。夸克编辑页包含名称、默认隐藏的 Cookie、测试登录、多媒体根目录、默认转存目录和启用开关。媒体库只有存在已启用且凭据可用的夸克来源时显示“导入夸克分享”。所有新页面沿用现有 Material 导航、间距、动画和反馈方式，不向 `local_page.dart`、`local_controller.dart` 或 `player_controller.dart` 堆入提供商逻辑。

## 错误、安全与日志

夸克错误类型区分 Cookie 失效、权限不足、文件不存在、分享失效、提取码错误、空间不足、任务失败/超时/取消、链接过期、网络超时、结构不兼容和限流。提供商注册器负责映射面向用户的中文文案。

`LogSanitizer` 必须把 `Cookie:` 后包含分号、空格的完整值一次性替换，并继续清除授权头、token、密码、URL 路径和查询参数。所有相关对象的 `toString()` 只输出脱敏摘要。日志禁止打印完整 URL、请求头、Cookie、`stoken` 和任务响应原文。

## 测试与验收

每个生产行为先添加失败测试，再写最小实现。目标测试覆盖远程引用迁移、OpenList 回归、注册器、Cookie 生命周期、日志脱敏、主机策略、分页、重启播放、索引与字幕、请求头、单次刷新、分享解析、转存状态与幂等、刷新媒体库、来源删除和本地隔离。

最终依次执行全量格式检查、`flutter test --no-pub`、`flutter analyze --no-pub`、Windows Release 构建、MSIX 生成、清单版本/身份/签名状态核对和桌面复制。版本、MSIX 版本、发布说明和应用内版本历史必须同步。

## 已知限制与停用条件

- 夸克私有接口可随时变更；结构变化会显式停用对应操作。
- 无真实测试 Cookie 时只能完成脱敏夹具与模拟协议测试，不能声称账号、播放或转存实机可用。
- 未知跨主机跳转绝不携带 Cookie，安全优先于兼容。
- 夸克限流或故障不会阻止本地扫描、OpenList 或本地播放。
