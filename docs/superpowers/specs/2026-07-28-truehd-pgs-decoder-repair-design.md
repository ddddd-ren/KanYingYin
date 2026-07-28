# TrueHD 与 PGS 解码器修复设计

## 背景

当前 Windows 安装包使用 `media_kit_libs_windows_video` 提供的约 38 MB 精简版 `libmpv-2.dll`。播放器能够枚举 TrueHD 音轨和 PGS 字幕轨，但该 DLL 不包含对应的 FFmpeg 解码器，因此日志分别出现 `Failed to initialize a decoder for codec 'truehd'` 和 `Could not find subtitle decoder for format 'hdmv_pgs_subtitle'`。

项目曾接入经过真实媒体验证的完整 libmpv，但在恢复 4K 零拷贝渲染时将完整 DLL、强制 copy 模式和 Anime4K 限制一起撤回。此次只修复解码组件，不恢复强制 `d3d11va-copy`、`dxva2-copy` 或其他播放器行为改写。

## 目标

- 只有 TrueHD 音轨的视频也能正常输出声音。
- PGS 内嵌字幕能够正常显示。
- 保留当前 Windows 硬件解码选项、零拷贝渲染路径、Anime4K 行为和播放器交互。
- 无备用音轨或字幕解码失败时，现有日志和错误提示继续可用。
- 完整 DLL 下载固定版本并校验 SHA-256，保证构建可重复。

## 非目标

- 不增加播放时临时转码。
- 不修改音轨、字幕的自动选择优先级。
- 不重构播放器控制器或 media_kit。
- 不改变非 Windows 平台配置。

## 实现设计

在 Windows 顶层 CMake 中引入独立的完整 libmpv 下载配置。配置固定标准 x64 构建的版本、下载地址和 SHA-256；构建时验证缓存，解压后确认 `libmpv-2.dll` 存在。

生成插件列表后，从 `PLUGIN_BUNDLED_LIBRARIES` 中排除精简版 `libmpv-2.dll`，其他插件库保持不变。安装阶段再复制经过校验的完整 DLL，确保 Release 目录和 MSIX 中只有一份确定的 libmpv。

播放器 Dart 代码保持不变。当前用户选择 `d3d11va` 或 `dxva2` 时仍按原值传给 mpv，不恢复旧版强制映射到 copy 模式的行为。

## 测试与验收

先修改 Windows 构建契约测试并观察其因完整 DLL 配置缺失而失败，再实现 CMake 配置使测试通过。测试至少验证：固定归档名与 SHA-256、启用哈希校验、排除插件精简 DLL、完整 DLL 的安装顺序，以及播放器代码未加入强制 copy 映射。

完成后执行全量 `flutter test`、`flutter analyze` 和 Windows Release 构建。检查 Release 与 MSIX 内 `libmpv-2.dll` 的大小和 SHA-256一致，并使用真实媒体确认日志出现 TrueHD/PGS 解码器已选择，同时视频仍使用用户配置的硬件解码路径。

## 版本与交付

版本从 2.1.64 升级到 2.1.65，同步更新 `pubspec.yaml`、MSIX 版本、`RELEASE_NOTES.md` 和版本历史。验证后生成签名 MSIX，核对清单版本并复制到桌面为 `看影音-2.1.65.msix`。

## 回退条件

如果完整 DLL 在当前 media_kit 渲染链路中无法创建零拷贝视频输出，或真实 4K 硬件解码出现回归，则不通过强制 copy 模式掩盖问题；撤回该 DLL，转为基于当前 Predidit 构建补齐 TrueHD 与 PGS 解码器。
