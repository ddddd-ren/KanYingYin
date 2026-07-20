# 百度文件详情兼容与版本展示设计

## 问题

看影音 2.1.29 播放百度网盘视频时仍提示“网盘视频解析或加载失败”。脱敏日志显示失败发生在 `resolvePlayback` 获取文件详情阶段，尚未进入百度 dlink 远程探测、本机 Range 中转或播放器加载阶段。

使用当前来源中已索引的稳定 `fs_id` 对百度官方 `filemetas` 接口进行脱敏核验后确认：接口返回 HTTP 200、`errno=0`、唯一且匹配的 `fs_id` 以及有效 dlink，但文件名字段为 `filename`，没有目录列表接口使用的 `server_filename`。现有解析器复用目录条目规则并强制要求 `server_filename`，因此把有效文件详情误判为 `CloudDriveErrorType.incompatible`。

用户同时要求在“关于”页的“清除缓存”下方显示当前应用版本。

## 目标

- 兼容百度 `filemetas` 实际返回的 `filename` 字段，使有效 dlink 能继续进入现有安全中转和播放器流程。
- 保留对既有 `server_filename` 文件详情响应的兼容。
- 不放宽百度目录列表响应的字段校验。
- 在“清除缓存”下方以独立设置项显示当前版本号，并复用应用唯一版本来源。

## 百度响应解析

文件详情与目录列表使用不同的文件名字段规则：

- `parseDirectoryPage` 继续要求非空 `server_filename`。
- `parseFileDetails` 优先读取非空 `filename`，缺失时兼容读取非空 `server_filename`。
- 两个字段均不存在或为空时，仍抛出 `CloudDriveErrorType.incompatible`，不从路径猜测文件名。
- `fs_id`、路径、大小、目录标记、修改时间、dlink 协议与预期 ID 校验保持不变。

这样只修正已经确认存在差异的 `filemetas` 响应边界，不影响目录扫描、分页、索引稳定 ID、鉴权刷新、dlink 主机校验或后续 Range 中转安全策略。

## 播放流程

1. 使用索引中的百度 `fs_id` 请求 `filemetas`，并要求返回 dlink。
2. 文件详情解析器接受官方 `filename` 字段并完成原有严格校验。
3. 解析出的 dlink 继续交给 `BaiduRangeRemoteReader`。
4. 远程读取器继续携带百度要求的 Access Token 和固定 User-Agent，建立带随机令牌的本机中转。
5. MPV 继续只加载 `127.0.0.1` 地址，不接触百度凭据或完整 dlink。

本轮不改变百度 OAuth、凭据存储、重试次数、代理规则、限速行为和媒体文件索引。

## 当前版本展示

“关于”页在“清除缓存”设置项下方增加只读设置项：

- 标题：`当前版本`
- 右侧值：`AppVersion.current`

新设置项与“清除缓存”位于同一设置区块，保持现有卡片、字体和间距风格；不增加点击行为。版本号不写死在页面内，避免与 `pubspec.yaml`、MSIX 清单和应用版本常量发生漂移。

## 测试

- 文件详情仅含 `filename` 时能解析文件名和 dlink。
- 文件详情仅含 `server_filename` 时保持兼容。
- `filename` 与 `server_filename` 都缺失或为空时仍拒绝响应。
- 目录列表缺少 `server_filename` 时仍拒绝响应。
- 请求外的 `fs_id`、非法 dlink 和其他畸形字段仍被拒绝。
- 关于页读取 `AppVersion.current` 展示“当前版本”，不出现页面硬编码版本号。
- 现有百度 API、网盘播放、本地媒体和版本一致性测试继续通过。

## 版本与交付

本修改进入 2.1.30 安装包：

- `pubspec.yaml` 更新为 `2.1.30+20130`。
- `msix_config.msix_version` 更新为 `2.1.30.0`。
- 同步更新 `RELEASE_NOTES.md` 和 `lib/utils/version_history.dart`，文案面向普通用户。
- 依次通过完整测试、静态分析、Windows Release 构建和 MSIX 生成。
- 验证清单标识、版本、架构和签名，将 `看影音-2.1.30.msix` 及异机安装包复制到当前用户桌面。
- 仅提交本轮相关文件，不提交用户已有的 `.learnings` 修改。
