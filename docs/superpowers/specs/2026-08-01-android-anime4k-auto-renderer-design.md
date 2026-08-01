# Android Anime4K 自动渲染器修复设计

## 现象

Android 新安装默认使用“自动选择”视频渲染器。此时超分辨率设置页会禁用 Anime4K，播放器内启用后也只显示当前渲染器不兼容。

## 根因

`PlayerRuntimePreferences` 将 Android 的 `auto` 转换为未显式指定 `VideoControllerConfiguration.vo`。项目当前锁定的 `media_kit_video 2.0.1` 在 Android 实现中会把未指定的 `vo` 解析为 `gpu`，该后端支持 mpv GLSL 着色器。

应用自己的 `AppPlatformCapabilities.supportsAnime4k` 却只接受显式的 `gpu` 和 `gpu-next`，错误拒绝了实际同样运行在 GPU 后端的 `auto`。因此故障发生在能力判断层，不是着色器文件、资源复制或 mpv 命令层。

## 修复

- Android 将 `auto`、`gpu` 和 `gpu-next` 都判定为支持 Anime4K。
- 保留 `auto` 到 `null` 的播放器配置映射，让 media-kit 继续选择其 Android 默认 GPU 后端。
- 不强制改写用户保存的渲染器，不增加重启播放器要求。
- 已被迁移为 `gpu` 的旧 `mediacodec_embed` 设置保持现状。
- Windows 能力判断和 Anime4K 自适应策略保持不变。

## 安全边界

- Anime4K 仍只在着色器目录可用、播放器为 `NativePlayer` 且画面实际放大超过 5% 时启用。
- 着色器加载失败仍清空 GLSL 列表并保持普通播放。
- 不修改 Android 硬件解码、字幕合成和网盘播放缓存。

## 测试

- 平台策略测试验证 Android `auto` 支持 Anime4K。
- 运行时偏好测试验证默认 `videoRenderer` 仍为 `null`，但 `anime4kSupported` 为真。
- 保留显式 `gpu`、`gpu-next`、旧 `mediacodec_embed` 以及 Windows 判断测试。
- 运行 Anime4K、播放器运行时偏好和 Android 播放兼容性测试，再执行完整测试与静态分析。

