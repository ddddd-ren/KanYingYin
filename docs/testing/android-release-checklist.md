# 看影音 Android 发布验收清单

## 构建与包体

- [ ] Flutter SDK 为 `D:\flutter` 3.41.9。
- [ ] `flutter test --no-pub` 全部通过。
- [ ] `flutter analyze --no-pub` 无错误。
- [ ] Release APK 与 AAB 使用正式发布密钥签名。
- [ ] APK 的包名、`versionName`、`versionCode` 与 `pubspec.yaml` 一致。
- [ ] APK 通过 `apksigner verify`。
- [ ] AAB 通过 `jarsigner -verify -strict`。
- [ ] Android Manifest 不含 `MANAGE_EXTERNAL_STORAGE` 或
      `READ_MEDIA_VIDEO`。

## 模拟器基础验收

- [ ] API 36 设备在线，ABI 与 APK 架构兼容。
- [ ] APK 可安装，冷启动后进程保持存活。
- [ ] 首屏、安全区、底部导航、横竖屏和返回键正常。
- [ ] 无 TMDB Key 或断网时仍可进入本地媒体库。
- [ ] SAF 目录选择器能打开、取消和重新授权。
- [ ] 后台通知、系统画中画和 WebView 基础流程无崩溃。
- [ ] `logcat` 不含看影音相关 fatal exception。

## ARM64 真机验收

- [ ] 使用至少一台 API 24 以上 ARM64 设备。
- [ ] SAF 授权、撤销、失效提示和重新授权正常。
- [ ] `content://` 视频、同目录字幕、海报和缩略图正常。
- [ ] OpenList、夸克、百度和迅雷自有媒体可播放。
- [ ] 字幕、音轨、选集、进度和 MediaCodec 可用。
- [ ] 后台播放、通知、耳机拔出暂停和系统画中画可用。
- [ ] 截图写入系统图片库，外部播放器按安全策略工作。
- [ ] Anime4K 在支持的 GPU renderer 可用；不支持时有明确提示。
- [ ] 删除来源、索引或缓存不会删除用户原始视频文件。

## 证据要求

- 记录设备型号、Android 版本、ABI、APK 版本和逐项结果。
- 失败项记录复现步骤、日志分类与复测结论。
- 不记录账户、Token、完整媒体 URI 或用户本地路径。
- 如设备或虚拟化环境存在内核级风险，立即停止设备验收并记录，
  不得用自动化测试结果替代未执行的实机结论。
