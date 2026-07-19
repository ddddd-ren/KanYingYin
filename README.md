# 看影音

<p align="center">
  <img src="assets/images/logo/logo_rounded.png" alt="看影音图标" width="160">
</p>

看影音是一款面向 Windows 的本地与个人网盘视频媒体库。它可以扫描、整理和播放用户自己的视频文件，并通过 TMDB 补充中文标题、简介、评分、海报、背景图和季集信息。

项目专注用户自有媒体的整理、元数据管理与播放体验。

## 主要功能

### 媒体库

- 添加本地文件夹并递归扫描常见视频格式。
- 根据文件名和目录结构识别剧名、季度、集数、特别篇及独立电影。
- 将同一系列的视频整理为媒体卡片和选集列表。
- 支持本地封面、自定义封面、视频缩略图和媒体来源筛选。
- 删除媒体源、索引或缓存时不会删除用户的原始视频文件。

### OpenList 网盘

> 网盘挂载目前仍在完善中，测试版请优先使用本地媒体库功能。

- 可试用添加和管理用户自己的 OpenList 数据源。
- 正在完善远程目录扫描、媒体库展示、链接解析与播放流程。
- 当前实现可能存在连接、扫描或播放兼容性问题，不建议作为唯一媒体来源。
- 删除网盘数据源时只会清理对应索引与缓存，不会删除远端原始文件。

OpenList 在本项目中仅作为用户自有媒体的数据入口，不是在线影视搜索服务。

### TMDB 刮削

- 获取中文标题、原始标题、简介、评分、海报和背景图。
- 支持电影、电视剧、季度和剧集信息。
- 支持自动匹配、手动选择候选、重新匹配和单独刮削。
- 可配置语言、地区、匹配阈值以及标题和图片覆盖策略。
- 没有 API Key、断网或 TMDB 不可用时，本地扫描和播放仍可使用。

### 播放器

- 基于 media-kit 与 mpv，支持常见本地和远程媒体格式。
- 支持硬件解码、视频渲染器选择、低内存模式和低延迟音频。
- 支持播放进度、倍速、快进快退、画面比例、选集和自动连播。
- 支持全屏、画中画、控制面板锁定、截图和外部播放器。
- 支持定时停止和后台播放。
- TrueHD 音轨播放失败时可尝试切换到已有的兼容音轨。
- 提供基于 Anime4K 的效率和质量两档实时超分辨率。

### 字幕与音轨

- 查看并切换内嵌音轨和字幕轨。
- 自动匹配同目录同名字幕，也可手动导入外部字幕。
- 支持网盘字幕下载和本地缓存。
- 可调整字幕字体、字号、颜色、描边、位置和时间偏移。
- 字幕延迟可按视频保存。

### 诊断

- 自动记录脱敏运行日志，最多保留 10 个日志文件。
- 支持导出脱敏诊断 ZIP，用于排查播放问题。

## 系统要求

| 项目 | 当前配置 |
| --- | --- |
| 操作系统 | Windows 10 / Windows 11，64 位 |
| 安装格式 | MSIX |
| 当前版本 | 2.1.2 |
| Dart 包名 | `kanyingyin` |
| Windows 包标识 | `com.kanyingyin.player` |
| Flutter | 3.41.9 |

首版仅支持 Windows。项目中的其他平台目录和依赖不代表提供对应平台的正式安装包。

## 安装

1. 从当前仓库的 [Releases](https://github.com/ddddd-ren/KanYingYin/releases) 下载最新的 `看影音-版本号.msix`。
2. 双击 MSIX 并按 Windows 提示完成安装。
3. 如果系统提示签名证书不受信任，需要先信任发布页提供的项目证书，再重新安装。
4. 新安装或首次启动时，如果桌面或开始菜单中没有快捷方式，应用会询问是否创建。

看影音使用专属的应用身份和数据目录。

## 使用说明

1. 打开“本地”页面并添加包含视频的文件夹。
2. 等待扫描完成后，从媒体库选择影片或剧集播放。
3. 如需 TMDB 信息，在“我的 > TMDB 刮削”中填写 API Key 并测试连接。
4. 如需访问个人网盘，在“我的 > 网盘数据源”中添加 OpenList 地址和目录。
5. 播放器的解码、渲染、Anime4K、字幕和快捷键选项位于“我的 > 播放设置”与“操作设置”。

当前版本仍为测试版，仅用于功能验证和问题反馈，不代表正式发布。

## 数据与隐私

- 应用不包含遥测或用户行为统计。
- 本地媒体索引、海报和字幕缓存保存在看影音自己的应用数据目录。
- 日志导出前会隐藏远程 URL 路径、请求头和常见凭据字段。
- 删除媒体源、媒体索引或缓存不会删除原始视频文件。
- OpenList 凭据通过系统安全存储保存，不应写入日志或仓库。
- TMDB 与 OpenList 请求只在用户启用对应功能时发生。

## 开发与构建

项目使用 Flutter Modular 组织模块，使用 MobX 管理状态。项目约定的 Flutter SDK 为 `D:\flutter`，版本为 3.41.9。

### 恢复依赖

```powershell
D:\flutter\bin\flutter.bat pub get
```

### 测试与静态分析

```powershell
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

### Windows Release

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

### 生成 MSIX

MSIX 必须基于本轮生成的 Windows Release 目录封装。签名密码通过命令行安全传入，不写入仓库。

```powershell
D:\flutter\bin\dart.bat run msix:create --build-windows false --sign-msix true --certificate-path <证书路径> --certificate-password <证书密码>
```

交付前应验证 `AppxManifest.xml` 中的版本、包身份和数字签名，并将最终安装包命名为 `看影音-版本号.msix`。

## 项目结构

```text
lib/
  pages/          页面、播放器界面与控制器
  services/       本地扫描、TMDB、OpenList、字幕和缓存服务
  repositories/   媒体源、索引和元数据持久化
  modules/        媒体、剧集、播放请求等领域模型
  utils/          日志、存储、窗口和通用工具
windows/          Windows Runner、窗口行为和原生集成
test/             单元测试、组件测试和身份一致性测试
```

## 开源来源与致谢

项目同时使用或参考以下开源项目和服务：

- 界面与操作参考 [Kazumi](https://github.com/Predidit/Kazumi)。
- [media-kit](https://github.com/media-kit/media-kit)：Flutter 媒体播放能力。
- [mpv](https://mpv.io/)：底层音视频播放与渲染。
- [Anime4K](https://github.com/bloc97/Anime4K)：实时动漫超分辨率着色器。
- [Mi Sans](https://hyperos.mi.com/font/en/details/sc/)：应用内嵌字体。
- [TMDB](https://www.themoviedb.org/)：影视元数据。看影音使用 TMDB API，但不受 TMDB 认可或认证。
- [OpenList](https://github.com/OpenListTeam/OpenList)：用户自有网盘文件访问接口。

## 许可证

本项目基于 [GNU General Public License v3.0](LICENSE) 发布。分发修改版或安装包时，需要继续遵守 GPL-3.0，并向接收者提供对应版本的完整源代码及许可证信息。

第三方组件、字体、图片和着色器可能适用各自的许可证，使用和再分发前请同时遵守对应项目的授权条款。
