# CLAUDE.md - 看影音项目

## 项目概述

看影音是面向 Windows 的本地与个人网盘视频媒体库和播放器。项目使用 Flutter Modular 与 MobX，支持本地媒体扫描、OpenList、TMDB 元数据、字幕、硬件解码和 Anime4K，并通过 MSIX 交付。

## 工作环境

- 工作目录：`D:/KanYingYin`
- Flutter SDK：`D:/flutter`
- Flutter 版本：3.41.9
- Dart 包名：`kanyingyin`
- Windows 包标识：`com.kanyingyin.player`
- 应用数据目录：看影音专属目录

## 工程要求

- 始终使用简体中文回复，文件使用 UTF-8 编码，代码注释使用中文。
- 首版只支持 Windows，不添加在线影视搜索、插件规则、WebView 视频解析或在线评论。
- TMDB 不可用、无 API Key 或断网时，本地扫描和播放必须继续可用。
- 删除媒体源、索引或缓存时不得删除用户原始视频文件。
- 修改播放器表现层时保持现有控件层级、动画时长、动画曲线和交互行为。
- 验收必须通过 `flutter test`、`flutter analyze` 和 Windows Release 构建。
- 可交付修改必须同步版本号、发布说明和应用内版本历史，生成并验证 MSIX 后复制到桌面。
- 验证通过后检查关键 diff，只提交本轮相关改动，提交信息使用简洁中文。

## 安装包

- MSIX 文件名使用 `看影音-版本号.msix`。
- 清单版本必须与 `pubspec.yaml` 中的 `msix_config.msix_version` 一致。
- 桌面安装包必须检查签名、大小和 SHA-256。
