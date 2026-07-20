# 夸克直连播放接口迁移设计

## 背景与证据

看影音 2.1.24 已停止向夸克转码 CDN 透传 API 专用请求头，但用户实测仍无法播放。最新日志显示播放器使用 `http-header-fields=[]` 后，夸克 CDN 仍返回 `HTTP 412 Precondition Failed`。

对日志中的完整签名链接进行脱敏结构检查后确认：链接包含 `auth_key` 和 `token`，签名时间尚未过期。使用独立 HTTP 客户端请求同一链接，分别测试无附加头、Range、User-Agent、Referer 及其组合，结果全部为 412。因此问题不在 MPV、硬件解码、请求头或链接过期，而在旧播放接口生成的链接本身。

当前应用直接调用夸克 `/1/clouddrive/file/v2/play`，并只声明 `supports=fmp4`。现行夸克驱动实现已使用 `/1/clouddrive/file/v2/play/project`，支持类型为 `fmp4_av,m3u8,dolby_vision`。

## 目标

- 看影音继续直接连接夸克网盘，不依赖 OpenList 或其他中转服务。
- 使用当前夸克项目播放接口获取可用转码地址。
- 优先播放最高可用清晰度的 fMP4，缺失时允许 m3u8。
- CDN 返回 401、403 或 412 时废弃当前链接并重新解析一次，不循环刷新。
- 项目播放接口没有任何可用转码地址时，回退夸克原文件下载直链。
- API Cookie 只发送给受信任的夸克主机，不进入普通转码 CDN 请求。
- 不修改网盘文件、目录、远程 ID、媒体索引或 TMDB 元数据。

## 方案

### 直接迁移项目播放接口

将 `QuarkApiClient` 的播放路径更新为：

`/1/clouddrive/file/v2/play/project`

请求体保持全部清晰度：

`low,normal,high,super,2k,4k`

支持类型更新为：

`fmp4_av,m3u8,dolby_vision`

API 请求继续使用 Cookie、夸克桌面 User-Agent 和 Referer。接口返回的转码 URL 交给播放器时不附带这些 API 请求头。

## 播放地址选择

`QuarkResponseParser` 继续拒绝非 HTTPS、空主机和结构不完整的地址。候选排序按以下优先级执行：

1. 清晰度：4K、2K、super、high、normal、low。
2. 同清晰度优先 fMP4 音视频地址。
3. fMP4 缺失时允许 m3u8。
4. 杜比视界候选仅作为接口支持能力，不覆盖更高优先级的普通兼容地址。

响应未提供明确格式字段时，保留现有按清晰度选择行为，避免因接口字段轻微变化拒绝有效 HTTPS 地址。

## 412 刷新

将 412 纳入明确的云链接刷新状态：

- `CloudPlaybackHttpException(412)` 可以触发刷新。
- MPV 日志中的 `HTTP error 412` 或 `status code 412` 可以触发刷新。
- 每个媒体只刷新一次，沿用现有 `CloudLinkRefreshGuard`，不增加无限重试。
- 刷新会重新调用项目播放接口，不能重复复用旧 URL；保留原播放进度、暂停状态和字幕。

## 原文件直链兜底

仅当项目播放接口成功响应但没有任何有效转码地址时，调用夸克 `/1/clouddrive/file/download` 获取原文件直链。

为播放链接增加明确类型：

- `transcode`：不携带 Cookie、Referer 或 JSON 请求头。
- `originalDownload`：仅在 URL 属于受信任的 `drive.quark.cn` 主机边界时携带 Cookie、Referer 和 User-Agent。

鉴权失败、权限错误、限流、网络超时等错误不降级为下载直链，继续显示对应错误，避免掩盖真实账号或网络问题。

## 安全边界

- Cookie 只能发送到 HTTPS 且主机为 `drive.quark.cn` 或其合法子域的原文件地址。
- `evilquark.cn`、`drive.quark.cn.example.com`、HTTP 地址和跨主机重定向均不得携带 Cookie。
- 日志继续只记录远程 URL 的协议和主机，不记录路径、查询签名或 Cookie。
- 转码 CDN 地址继续使用直连网络策略，不继承应用代理。

## 测试

- 先写失败测试，断言播放请求使用 `/file/v2/play/project` 和新的 `supports`。
- 测试同清晰度优先 fMP4、缺失时回退 m3u8。
- 测试无有效转码地址时请求原文件下载接口。
- 测试转码链接为空请求头，受信任原文件链接只携带必要头。
- 测试恶意相似域名和跨主机重定向不携带 Cookie。
- 测试 412 只触发一次刷新并保留进度、暂停状态和字幕。
- 完成定向测试后执行全量 `flutter test`、`flutter analyze`、Windows Release、MSIX 清单、签名和 SHA-256 验证。

## 交付

本修复优先作为 `2.1.25+20125`、MSIX `2.1.25.0` 交付，最终安装包复制为当前用户桌面的 `看影音-2.1.25.msix`。季度完整选集修复顺延至 2.1.26，避免在播放链路尚未恢复时合并两项行为变化。
