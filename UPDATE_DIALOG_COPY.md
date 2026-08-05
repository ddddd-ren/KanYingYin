# 看影音更新弹窗文案

## 当前版本

- 应用版本：2.1.136
- Windows EXE 安装器版本：2.1.136
- 本轮交付：Windows 测试版 EXE；Android 测试版仅同步版本配置，本轮未打包 APK/AAB
- Android 应用版本：2.1.136
- Android versionCode：20136
- 日期：2026-08-06

## 弹窗标题

看影音 2.1.136 测试版

## Windows 弹窗正文

- 修复个人网盘刮削名称已改为“回魂计”时，选集标题仍使用旧 TMDB 作品名的问题。
- 每集现在显示为“当前剧名 S01E01 TMDB 集名”，TMDB 集名不会再覆盖当前剧名。
- Windows 后续只提供默认安装到 D:\看影音 的 EXE 安装程序，也可以在安装界面选择其他目录；本轮不再生成 MSIX。
- 公共安装包不内置 TMDB Key；没有 Key 或断网时，扫描、浏览和播放仍可使用。
- Windows 与 Android 版本保持统一版本配置。
- 诊断日志继续脱敏并隐藏本地文件路径。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件，也不会改变远程路径和播放 ID。

## Android 弹窗正文

### 弹窗标题

看影音 Android 2.1.136 测试版

- 本轮同步 Windows 与 Android 版本配置，仅构建并交付 Windows EXE；Android APK/AAB 本轮未打包或实机验证。
- Android 的 versionName 与 versionCode 直接读取 Flutter 统一版本，当前为 2.1.136 (20136)。
- 个人网盘选集会使用当前有效剧名作为前缀，并继续显示 TMDB 逐集名称。
- 逐集名称只改变看影音中的展示，不会改变本地文件、网盘路径、字幕关联或播放入口。
- 公共安装包不内置 TMDB Key；没有 Key 或断网时，扫描、浏览和播放仍可使用。
- Windows 与 Android 版本保持统一版本配置，诊断日志继续脱敏并隐藏本地文件路径。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件，也不会改变远程路径和播放 ID。

## 按钮文字

知道了

## 维护要求

发布新版本时，本文件中的应用版本、EXE 安装器版本和弹窗正文必须与以下文件保持一致：

- `pubspec.yaml`
- `lib/core/app_version.dart`
- `lib/utils/version_history.dart`
- `RELEASE_NOTES.md`
