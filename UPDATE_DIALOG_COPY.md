# 看影音更新弹窗文案

## 当前版本

- 应用版本：2.1.68
- 安装包版本：2.1.68.0
- 日期：2026-07-28

## 弹窗标题

看影音 2.1.68 测试版

## 弹窗正文

- TMDB 名称清理新增 `DSNP` 和 `HBOMax` 流媒体平台标记。
- 支持清理 `1080p.DSNP.WEB-DL.AAC.2.0.H.264-BlackTV` 和 `1080p.HBOMax.WEB-DL.DDP2.0.H.264-BlackTV` 等完整发布后缀。
- `BlackTV` 发布组以及画质、片源、音频和编码信息不再进入 TMDB 搜索词，作品标题保持干净。
- 本次更新只调整名称识别，不会修改或删除本地与网盘原始文件；TMDB 不可用或断网时，扫描和播放仍可使用。

## 按钮文字

知道了

## 维护要求

发布新版本时，本文件中的应用版本、安装包版本和弹窗正文必须与以下文件保持一致：

- `pubspec.yaml`
- `lib/core/app_version.dart`
- `lib/utils/version_history.dart`
- `RELEASE_NOTES.md`
