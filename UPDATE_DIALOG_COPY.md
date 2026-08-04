# 看影音更新弹窗文案

## 当前版本

- 应用版本：2.1.117
- 安装包版本：2.1.117.0
- 本轮交付：Windows 测试版 MSIX；Android 测试版 APK/AAB
- Android 应用版本：2.1.117
- Android versionCode：20117
- 日期：2026-08-05

## 弹窗标题

看影音 2.1.117 测试版

## Windows 弹窗正文

- 本轮修正版提升 Windows 与 Android 安装包版本，可从已安装的 2.1.116.0 正常升级。
- 海报卡片底部毛玻璃信息层现在与海报等宽，保留底部间距和悬浮交互。
- Android 版本继续直接跟随 Flutter 与 Windows 的统一版本配置。
- 诊断日志继续脱敏并隐藏本地文件路径和凭据，本机运行日志保留排查所需信息。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。

## Android 弹窗正文

### 弹窗标题

看影音 Android 2.1.117 测试版

- 本轮修正版提升 Windows 与 Android 安装包版本，Android 使用 APK 和 AAB 交付。
- Android 的 versionName 与 versionCode 直接读取 Flutter 统一版本，当前为 2.1.117 (20117)。
- 海报卡片底部毛玻璃信息层现在与海报等宽，保持海报内容清晰。
- 诊断日志继续脱敏并隐藏本地文件路径和凭据，本机运行日志保留排查所需信息。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。

## 按钮文字

知道了

## 维护要求

发布新版本时，本文件中的应用版本、安装包版本和弹窗正文必须与以下文件保持一致：

- `pubspec.yaml`
- `lib/core/app_version.dart`
- `lib/utils/version_history.dart`
- `RELEASE_NOTES.md`
