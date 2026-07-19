# 夸克网盘专属直连播放设计

## 目标

修复夸克网盘资源已成功解析播放地址、但 MPV 请求夸克 CDN 时返回 `HTTP 403 Forbidden` 的问题。夸克账号、目录浏览和官方客户端播放均正常，因此本轮只调整看影音内部的网络路由和失败恢复，不改变文件、媒体元数据或 TMDB 功能。

## 已确认现象

- `QuarkApiClient` 直接创建 Dio 客户端，没有读取看影音的 HTTP 代理设置。
- 播放器对所有在线媒体统一设置 `http-proxy`，夸克 CDN 请求会进入本机 VPN 端口。
- VPN 使用规则模式时，夸克 API 域名和 CDN 域名可能命中不同规则，导致地址解析与媒体读取采用不同网络路径。
- 日志确认播放地址已解析、Cookie、Referer 和 User-Agent 已传入，失败点位于夸克 CDN 返回 403，而不是 TMDB、字幕、解码器或媒体格式。

## 方案

采用“夸克专属直连”：夸克地址解析和夸克媒体读取都绕过看影音配置的 HTTP 代理。TMDB、普通在线来源和 OpenList 保持现有代理行为。

不采用以下方案：

- 不把夸克 API 与播放器统一交给本机代理，因为规则模式仍可能按 API/CDN 域名选择不同出口。
- 不接入夸克未公开的播放或转码接口，避免接口变化和账号风控风险。
- 不按域名在播放器中硬编码判断，以免夸克 CDN 域名变化后再次失效。

## 类型与边界

新增强类型播放器网络路由，至少包含：

- `inheritProxy`：沿用看影音的 HTTP 代理设置。
- `direct`：明确不向 MPV 设置 HTTP 代理。

路由信息由网盘提供方在解析结果中声明，并随 `CloudResolvedPlayback` 传入 `PlaybackInitParams`。`QuarkDriveClient` 返回的播放资源标记为 `direct`；OpenList 和现有在线来源默认使用 `inheritProxy`，保持兼容。

播放器只消费路由信息，不识别夸克域名，也不依赖来源名称。刷新播放地址时必须保留新解析结果携带的路由策略。

## 数据流

1. 用户点击夸克网盘视频。
2. `CloudPlaybackResolver` 使用现有凭据解析下载地址与请求头。
3. `QuarkDriveClient` 为播放资源附加 `direct` 网络路由。
4. `LocalVideoController` 将地址、请求头和网络路由一起构造为 `PlaybackInitParams`。
5. `PlayerController` 创建 MPV：只有 `inheritProxy` 才设置 `http-proxy`，`direct` 不设置该属性。
6. MPV 使用夸克请求头直连 CDN，并继续使用现有缓存、字幕、硬件解码和 Anime4K 流程。

## 403 与失败恢复

- 夸克链接首次出现 401、403、链接过期，或 MPV 只上报 `Failed to open` 时，重新解析一次当前资源。
- 每个媒体会话最多自动刷新一次，沿用现有 `CloudLinkRefreshGuard` 防止循环。
- 刷新成功后保留播放进度、暂停状态、字幕路径和稳定媒体键。
- 刷新后仍失败时停止重试，并提示“夸克播放地址不可用，请重新登录或稍后重试”。
- 日志记录来源类型、路由策略和脱敏后的主机名，不记录 Cookie、完整下载地址或签名参数。

## 兼容性与安全

- 本地视频不经过该路由策略。
- OpenList 默认行为不变，仍可使用应用代理访问私有或远程服务。
- TMDB 继续使用现有应用代理，不受夸克直连影响。
- 不修改、移动、重命名或删除任何夸克文件。
- Cookie 仍通过现有凭据存储读取，日志继续脱敏。

## 测试与验收

- 模型测试：网络路由默认值为 `inheritProxy`，复制和刷新合并后保持正确路由。
- 夸克客户端测试：夸克播放资源明确返回 `direct`。
- OpenList 回归测试：播放资源保持 `inheritProxy`。
- 播放策略测试：`direct` 时不应用 MPV HTTP 代理，`inheritProxy` 时仍应用有效代理。
- 刷新判断测试：401、403、`Failed to open` 触发一次刷新，普通解码错误不触发。
- 全量执行 `flutter test`、`flutter analyze` 和 Windows Release 构建。
- 版本更新为 `2.1.8+20108`、MSIX `2.1.8.0`，同步更新用户发布说明和版本历史。
- 生成并验证 MSIX 清单，将最终安装包复制为当前用户桌面的 `看影音-2.1.8.msix`。
