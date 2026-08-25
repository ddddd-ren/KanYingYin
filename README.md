# 看影音

<p align="center">
  <img src="assets/images/logo/logo_rounded.png" alt="看影音图标" width="160">
</p>

看影音是一款面向 Windows 和 Android 手机的个人视频媒体库。你可以整理和播放自己的本地及个人网盘视频，并通过 [TMDB](https://www.themoviedb.org/) 补充中文标题、简介、评分、海报和季集信息。

看影音只管理你自己的媒体，不包含公共在线影视搜索、插件规则、WebView 视频解析或在线评论。

## 下载正式版

当前正式版为 Windows 1.0.10 和 Android 1.0.6。你可以在 [看影音 v1.0.10 Release](https://github.com/ddddd-ren/KanYingYin/releases/tag/v1.0.10) 查看更新说明和文件校验信息。

| 平台 | 当前版本 | 下载文件 | 用途 |
| --- | --- | --- | --- |
| Windows 10/11 x64 | 1.0.10 | [KanYingYin-1.0.10.exe](https://github.com/ddddd-ren/KanYingYin/releases/download/v1.0.10/KanYingYin-1.0.10.exe) | 普通用户安装程序 |
| Android 7.0+ | 1.0.6 (10006) | [KanYingYin-1.0.6.apk](https://github.com/ddddd-ren/KanYingYin/releases/download/v1.0.10/KanYingYin-1.0.6.apk) | Android 手机安装包 |
| Android 应用商店 | 1.0.6 (10006) | [KanYingYin-1.0.6.aab](https://github.com/ddddd-ren/KanYingYin/releases/download/v1.0.10/KanYingYin-1.0.6.aab) | 应用商店交付包 |

> Android TV 正式版、测试版和 GitHub 发布已无限期暂停，不提供 TV 下载资产。

## 主要功能

看影音围绕媒体整理、元数据和播放体验设计，所有功能都以你的本地文件或个人网盘内容为基础。

### 本地与个人网盘媒体库

- 扫描本地文件夹，将电影、电视剧、季度、集数和特别篇整理成海报墙与选集
- 接入 OpenList、夸克、百度和迅雷个人网盘，汇总多个媒体目录
- 根据文件名和目录结构识别作品，支持重新识别和手动修正季集信息
- 在后台刷新网盘索引，刷新期间仍可浏览已有海报和播放视频
- 使用本地封面、自定义封面或视频缩略图，并按媒体来源筛选

> OpenList 功能仍在调试，当前不建议使用。远程服务接口变化也可能影响个人网盘的连接、扫描或播放。

### TMDB 中文元数据

- 获取中文标题、原始标题、简介、评分、海报、背景图和季集名称
- 自动匹配电影、电视剧和剧场版，也可修改搜索词并手动选择候选
- 本地和个人网盘共用匹配规则，减少发布标签和音视频规格对识别结果的干扰
- 支持单独重新识别剧集、修正季度与集数，并保留已确认的元数据
- 动画电影同时显示在动漫和电影入口，动画电视剧同时显示在动漫和电视剧入口

公共安装包不内置 TMDB Key。没有 Key 或断网时，本地扫描和播放仍可用；TMDB 请求失败也不会阻断本地媒体库。

### Windows 与 Android 播放器

- 基于 [media-kit](https://github.com/media-kit/media-kit) 和 [mpv](https://mpv.io/) 播放常见本地及远程媒体格式
- 支持 Windows 硬件解码回退、Android MediaCodec 和兼容音轨回退
- 支持自动、HDR 直通和 HDR 转 SDR 色彩方案，设备不支持时自动回退
- 支持倍速、快进快退、画面比例、选集、自动连播、全屏和画中画
- 支持截图、外部播放器、定时停止和后台播放
- 支持 [Anime4K](https://github.com/bloc97/Anime4K) 动画画质增强，并在画面需要放大时启用

### 字幕与音轨

- 查看并切换内嵌音轨、内嵌字幕和外挂字幕
- 自动关联同目录或网盘中的 ASS、SSA、SRT 和 VTT 字幕
- Android 支持通过图形处理器合成 PGS 图形字幕
- 调整字幕字体、字号、颜色、描边、位置和时间偏移
- 显示网盘外挂字幕的原始文件名，并修复部分重复 UTF-8 BOM 的 ASS 字幕

### 配置迁移与诊断

- Windows 和 Android 可通过加密的 `.kyyconfig` 文件迁移设置和个人网盘来源
- 导入写入失败时自动回滚，不改动视频、字幕、索引、缓存和播放历史
- 最多保留 10 个脱敏运行日志，并可导出诊断 ZIP
- Android 可通过系统分享面板保存或发送诊断文件

## 数据与隐私

看影音不会修改或删除原始视频、字幕，也不会因为你删除媒体来源、索引或缓存而删除、改名或移动原始文件。

- 本地媒体索引、海报和字幕缓存保存在看影音专属数据目录
- OpenList 凭据、夸克 Cookie、百度开放平台凭据和 OAuth 令牌通过系统安全存储保存
- 诊断日志会隐藏远程地址、请求头和常见凭据字段
- TMDB 和个人网盘请求只在你启用对应功能时发生
- 百度和迅雷来源按只读方式访问，不上传、移动、改名或删除远端文件
- 重要媒体和配置仍应保留独立备份

## 系统信息

| 项目 | 当前配置 |
| --- | --- |
| 支持平台 | Windows 10/11 x64；Android 7.0+（API 24+） |
| 安装格式 | EXE / APK |
| 当前版本 | 1.0.10 |
| Android 版本 | 1.0.6 (10006) |
| Dart 包名 | `kanyingyin` |
| Windows 包标识 | `com.kanyingyin.player` |
| Android 应用标识 | `com.kanyingyin.player` |
| Flutter | 3.41.9 |

Windows 安装目录、应用数据目录和缓存目录均可由你选择，不要求电脑存在 D 盘。

## 安装与快速开始

### Windows

1. 下载 [KanYingYin-1.0.10.exe](https://github.com/ddddd-ren/KanYingYin/releases/download/v1.0.10/KanYingYin-1.0.10.exe)
2. 运行安装程序，在安装向导中选择安装目录
3. 首次启动时，如桌面或开始菜单没有快捷方式，按弹窗提示决定是否创建

### Android 手机

1. 下载 [KanYingYin-1.0.6.apk](https://github.com/ddddd-ren/KanYingYin/releases/download/v1.0.10/KanYingYin-1.0.6.apk)
2. 允许当前文件管理器安装未知来源应用
3. 按 Android 系统提示完成安装

### 开始使用

1. 打开“本地”页面，添加包含视频的文件夹
2. 如需中文元数据，在“设置 > TMDB 刮削”中填写自己的 API Key
3. 如需访问个人网盘，在“设置 > 网盘数据源”中添加来源并选择媒体目录
4. 等待扫描完成，从海报墙选择作品播放

播放器的解码、HDR、Anime4K、字幕和快捷键选项位于“设置 > 播放设置”与“操作设置”。

## 开发与构建

项目使用 Flutter Modular 组织模块，使用 MobX 管理状态。项目约定使用 `D:\flutter` 中的 Flutter 3.41.9。

### 恢复依赖

```powershell
D:\flutter\bin\flutter.bat pub get
```

### 测试与静态分析

```powershell
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

### 构建 Windows Release

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
```

### 构建 Android 手机签名包

Android 发布脚本从当前用户的 `KANYINGYIN_ANDROID_*` 环境变量读取签名信息，生成并验证 APK 与 AAB。脚本不会把密钥或密码写入仓库。

```powershell
.\tool\android\build_signed_release.ps1 -Flavor mobile
```

### 生成 Windows EXE 安装程序

构建脚本会核对主程序和安装器版本，输出文件大小、SHA-256 与 Authenticode 状态，并将安装程序复制到当前用户桌面。

```powershell
.\tool\windows\build_exe_release.ps1
```

历史 MSIX 配置只用于旧版本追溯，不进入当前交付流程。

## 项目结构

```text
lib/
  pages/          页面、播放器界面与控制器
  services/       本地扫描、TMDB、个人网盘、字幕和缓存服务
  repositories/   媒体来源、索引和元数据持久化
  modules/        媒体、剧集和播放请求等领域模型
  utils/          日志、存储、窗口和通用工具
windows/          Windows Runner、窗口行为和原生集成
android/          Android Gradle、Kotlin、Manifest 和平台通道
test/             单元测试、组件测试和发布契约测试
```

## 开源来源与致谢

看影音使用或参考以下开源项目与服务：

- [media-kit](https://github.com/media-kit/media-kit)：Flutter 媒体播放能力
- [mpv](https://mpv.io/)：底层音视频播放与渲染
- [Anime4K](https://github.com/bloc97/Anime4K)：实时动漫画质增强着色器
- [Mi Sans](https://hyperos.mi.com/font/en/details/sc/)：应用内嵌字体
- [TMDB](https://www.themoviedb.org/)：影视元数据。看影音使用 TMDB API，但不受 TMDB 认可或认证
- [OpenList](https://github.com/OpenListTeam/OpenList)：用户自有网盘文件访问接口

## 许可证

本项目基于 [GNU 通用公共许可证 v3.0](LICENSE) 发布。分发修改版或安装包时，请继续遵守 GPL-3.0，并向接收者提供对应版本的完整源代码和许可证信息。

第三方组件、字体、图片和着色器可能适用各自的许可证。使用和再分发前，请同时遵守对应项目的授权条款。
