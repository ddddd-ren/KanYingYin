# Android TV 测试版验收报告

## 当前结论

当前版本可以安装并侧载到 Android TV/Google TV，代码和 APK 包验收已完成；真实 Android TV/海信设备的完整播放验收仍未完成，交付结论保持“可安装测试包，实机验收未完成”。

## 构建证据

- 版本：`2.1.140 (20140)`
- 包名：`com.kanyingyin.player.tvtest`
- 桌面 APK：`看影音-2.1.140-TV测试版.apk`
- APK SHA-256：`89e2255f252ae32658ad56802d2c1c818cd488f1ac6d678288f523fb69f1e106`
- APK v2 签名：通过；签名证书摘要记录在 `tool/android/private-output/` 的最新 `signature.txt`。
- Manifest：包含 `LEANBACK_LAUNCHER`、Banner，并将触摸屏和伪触摸屏声明为非必需。
- Full `libmpv`：`arm64-v8a`、`armeabi-v7a`、`x86_64` 三个 ABI 均与固定 Full 资产哈希一致。

## 用户反馈复现与修复

用户在海信电视上反馈：焦点停留在侧栏外，本地媒体库路径输入框吞掉方向键，第一次返回直接退出应用。

已加入自动化回归并修复：

- Android TV 搜索框的上下左右键先尝试离开输入框并进入方向焦点遍历，桌面和普通 Android 仍保留文本编辑行为。
- Android TV 本地媒体库路径输入框的上下左右键也先执行方向焦点遍历，左键可以回到侧边导航栏。
- 搜索框有焦点时第一次返回只清除输入焦点。
- TV 根页面第一次返回显示退出确认；确认框内按返回只关闭对话框，需明确选择“退出”才关闭应用。

自动化验证覆盖 `adaptive_navigation_android_test.dart`、`library_presentation_components_test.dart` 和 `tv_back_navigation_guard_test.dart`。由于当前 ADB 设备列表为空，以上修复尚未在用户海信电视上重新安装并复验。

## 设备状态

| 设备 | ADB/API 证据 | 当前状态 | 备注 |
| --- | --- | --- | --- |
| 用户海信电视 | 当前环境未连接 ADB；系统类型和 API 尚未取得 | `not_android_verified` | 若为 VIDAA 原生系统，不支持 Android APK；取得 Android API/ABI 前不判定兼容 |
| 标准 Android TV/Google TV | 未提供实机 | `pending` | 需要纯遥控器主流程和真实视频样本验收 |

详细字段和记录规则见 [android-tv-test-matrix.md](android-tv-test-matrix.md)。

## 待完成项目

- 连接设备并记录 Android API、ABI、Leanback、WebView 和 SAF 证据。
- 在海信或标准 Android TV 上重测搜索框方向键、两次返回、冷启动、媒体库、播放器和息屏恢复。
- 验证同一局域网手机扫码配置，以及访客网络/AP 隔离时的失败回退。
- 完成 1080p、4K HEVC、字幕、音轨和个人网盘播放矩阵后，才可把设备结果改为 `passed`。
