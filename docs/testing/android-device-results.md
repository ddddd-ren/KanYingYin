# 看影音 Android 设备验收记录

## 2026-07-30 API 36 模拟器

### 环境

- AVD：`kanyingyin_api36`
- 设备：`sdk_gphone64_x86_64`
- Android：16（API 36）
- ABI：x86_64
- APK：Debug `2.1.82 (20182)`
- 虚拟化：AEHD 2.2

### 已取得证据

- Debug APK 安装成功。
- `dumpsys package` 返回包名 `com.kanyingyin.player`、
  `versionName=2.1.82`、`versionCode=20182`。
- 冷启动成功进入 Android 系统 SAF 目录选择器。
- SAF 根目录正确提示不能直接授权，允许用户选择子目录。
- 进入目录选择器后读取的日志中没有看影音相关 fatal exception。

### 未完成与停止原因

- 返回应用主页、导航、横竖屏、后台通知、画中画、WebView 和网络流程
  未形成稳定复测证据。
- 首次可用会话结束后，AVD 退出；无窗口重启停留在 offline 状态。
- 用户确认该任务触发了 `aehd.sys` 虚拟化驱动或相关存储链路的
  内核级问题。继续运行同一 AVD、AEHD 或 Android Studio 可能再次卡死。
- 自此停止启动 `kanyingyin_api36`，不再运行依赖该 AVD/AEHD 的命令。
  以上未完成项不得标记为通过。

## ARM64 真机

- 状态：未执行。
- 原因：当前没有连接可用于验收的 Android 真机。
- 后续要求：使用 API 24 以上 ARM64 真机，按
  `android-release-checklist.md` 逐项复测；不得记录账户、Token、完整媒体
  URI 或用户本地路径。
