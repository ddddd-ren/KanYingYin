# Android TV 测试版验收报告

## 当前结论

当前版本可以安装并侧载到 Android TV/Google TV，代码和 APK 包验收已完成；真实 Android TV/海信设备的完整播放验收仍未完成，交付结论保持“可安装测试包，实机验收未完成”。

## 构建证据

- 版本：`2.1.141 (20141)`
- 包名：`com.kanyingyin.player.tvtest`
- 桌面 APK：`看影音-2.1.141-TV测试版.apk`
- APK SHA-256：`880a10a330366c6de26a3560d5a211d4a075c32212cf84eb6aa65f1759f2743b`
- APK v2 签名：通过；签名证书摘要记录在 `tool/android/private-output/` 的最新 `signature.txt`。
- Manifest：包含 `LEANBACK_LAUNCHER`、Banner，并将触摸屏和伪触摸屏声明为非必需。
- Full `libmpv`：`arm64-v8a`、`armeabi-v7a`、`x86_64` 三个 ABI 均与固定 Full 资产哈希一致。

## 用户反馈复现与修复

用户在海信电视上复验 2.1.140 后反馈：焦点仍停留在本地媒体库内容区，无法按左键进入侧边导航栏。

已加入自动化回归并修复：

- Android TV 外层为侧边导航栏和内容区建立独立焦点范围，并记录上次使用的内容焦点。
- 页面路由内部的焦点范围允许在方向边界继续进入父级范围，真实路径输入框和搜索框按左键可以回到侧边导航栏。
- 本地媒体卡片到达内容区左边界后会进入侧边导航栏，从侧栏按右键会恢复上次内容焦点。
- 搜索框有焦点时第一次返回只清除输入焦点。
- TV 根页面第一次返回显示退出确认；确认框内按返回只关闭对话框，需明确选择“退出”才关闭应用。

自动化验证覆盖页面内层焦点范围、真实路径输入框、本地媒体卡片、目录下拉和返回键行为。由于当前 ADB 设备列表为空，以上修复尚未在用户海信电视上重新安装并复验。

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
