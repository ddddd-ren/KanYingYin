# 看影音更新弹窗文案

## 当前版本

- 应用版本：2.1.196
- Windows EXE 安装器版本：2.1.196 测试版
- Android 手机和 Android TV：本轮不构建
- 本轮交付：Windows 测试版 EXE
- 日期：2026-08-28

## 弹窗标题

看影音 2.1.196 测试版

## Windows 弹窗正文

- 修复从其他标签页切换到网盘资源页时重复读取全部来源、清空海报墙并重新扫描导致的明显卡顿。
- 网盘资源页再次进入时复用已加载的媒体库和海报状态；只有首次进入或主动刷新才执行完整加载。
- 本轮只构建 Windows 测试版；不构建 Android 手机或 Android TV。
- 本次更新不会修改、删除、改名或移动本地及个人网盘原始视频、字幕和海报缓存。

## Android 弹窗正文

### 弹窗标题

看影音 Android 1.0.7 正式版

- 手机和平板增强资源标签识别，新增 Hami Video、Max、TVING、KKTV 等流媒体来源，以及 Hybrid、Proper、Repack、Remastered、Open Matte 等版本标签。
- 本地媒体库、个人网盘、播放历史和 TMDB 匹配等封面统一为 2:3，改善深色模式下原图白边，并统一无海报、加载中和加载失败时的占位显示。
- 本次更新不会修改、删除、改名或移动本地及个人网盘原始视频、字幕和海报缓存。

## 按钮文字

知道了

## 维护要求

发布新版本时，本文件中的应用版本、EXE 安装器版本和弹窗正文必须与以下文件保持一致：

- `pubspec.yaml`
- `lib/core/app_version.dart`
- `lib/utils/version_history.dart`
- `RELEASE_NOTES.md`
