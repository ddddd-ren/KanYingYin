# 看影音更新弹窗文案

## 当前版本

- 应用版本：2.1.116
- 安装包版本：2.1.116.0
- 本轮交付：Windows 测试版 MSIX；Android 测试版 APK/AAB
- Android 应用版本：2.1.116
- Android versionCode：20116
- 日期：2026-08-05

## 弹窗标题

看影音 2.1.116 测试版

## Windows 弹窗正文

- 本轮同步提供 Windows 与 Android 2.1.116 测试版，Windows 使用 MSIX 交付。
- Android 版本现在直接跟随 Flutter 与 Windows 的统一版本配置，避免安装包版本号与应用版本不一致。
- 导出的诊断日志使用更严格的脱敏，隐藏本地文件路径、多段 Cookie、Authorization 和结构化密钥，分享日志时更好地保护隐私。
- 本机运行日志仍保留必要的本地路径信息，便于用户自行排查扫描和播放问题。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。

## Android 弹窗正文

### 弹窗标题

看影音 Android 2.1.116 测试版

- 本轮同步提供 Windows 与 Android 2.1.116 测试版，Android 使用 APK 和 AAB 交付。
- Android 的 versionName 与 versionCode 直接读取 Flutter 统一版本，当前为 2.1.116 (20116)。
- 导出的诊断日志使用更严格的脱敏，隐藏本地文件路径、多段 Cookie、Authorization 和结构化密钥，分享日志时更好地保护隐私。
- 本机运行日志仍保留必要的本地路径信息，便于用户自行排查扫描和播放问题。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。

## 按钮文字

知道了

## 维护要求

发布新版本时，本文件中的应用版本、安装包版本和弹窗正文必须与以下文件保持一致：

- `pubspec.yaml`
- `lib/core/app_version.dart`
- `lib/utils/version_history.dart`
- `RELEASE_NOTES.md`
