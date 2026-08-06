# Android TV 测试版设备验收矩阵

当前交付结论：可安装测试包，实机验收未完成。

只有能够确认 Android API、ABI 和 TV 系统特性的设备，才进入兼容性测试。海信电视若无法通过系统设置或 ADB 证明运行 Android TV/Google TV，结果保持 `not_android_verified`；VIDAA 原生系统不属于 Android APK 支持范围。

## 结果状态

- `pending`：尚未执行该设备的实机测试。
- `passed`：纯遥控器主流程、真实视频播放和恢复测试全部通过。
- `failed`：已确认是 Android TV 设备，但存在有日志和复现步骤的失败项。
- `not_android_verified`：尚无 Android API、ABI 或 ADB 证据，不能判定兼容或不兼容。
- `not_supported_vidaa`：已确认是 VIDAA 原生系统，不能安装 Android APK。

## 设备记录

| 设备型号 | 系统类型 | API | ABI | Leanback | WebView | 安装方式 | 遥控器 | SAF | 1080p | 4K HEVC | 字幕 | 音轨 | 网盘 | 息屏恢复 | 结果 | 日志路径 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 用户海信电视（具体型号待记录） | 待确认 Android TV/Google TV 或 VIDAA | unknown | unknown | unknown | unknown | 待确认未知来源安装或 ADB | 未测试 | 未测试 | 未测试 | 未测试 | 未测试 | 未测试 | 未测试 | 未测试 | not_android_verified | 待实机验收 |
| 标准 Android TV/Google TV 设备（待提供） | 待确认 | unknown | unknown | unknown | unknown | ADB 或 U 盘侧载 | 未测试 | 未测试 | 未测试 | 未测试 | 未测试 | 未测试 | 未测试 | 未测试 | pending | 待实机验收 |

## 记录要求

1. 连接设备后记录 `ro.build.version.sdk`、`ro.product.cpu.abi`、Leanback/Television/Touchscreen feature 和 WebView provider。
2. 安装后只使用遥控器完成冷启动、媒体库浏览、选集、播放、返回和退出。
3. SAF 必须实际选择本地目录；网盘必须至少验证一个用户自有来源，失败不能影响本地播放。
4. 1080p 和 4K HEVC 使用已知编码样本，分别记录硬件解码、字幕、音轨和连续播放结果。
5. 每个失败项记录设备型号、操作步骤、样本信息、时间和脱敏日志路径；日志不得包含账号、Cookie、Refresh Token 或 TMDB Key。
6. 手机扫码配置需分别验证同一普通家庭 Wi-Fi 成功，以及访客网络或 AP 隔离下的失败提示和手动配置回退。
