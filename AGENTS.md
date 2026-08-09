# AGENTS.md - 看影音项目

始终使用简体中文回复。

所有文件读写使用 UTF-8 编码，修改文件时不要改变原有编码。在 PowerShell 中读取含中文文件前执行 `chcp 65001`，并使用 `Get-Content -Encoding UTF8`。不要使用 sed 或 awk 处理含中文文件。代码注释使用中文。

## 项目定位

- 工作目录固定为 `D:\KanYingYin`。
- 应用显示名：看影音。
- Dart 包名：`kanyingyin`。
- Windows 包标识：`com.kanyingyin.player`。
- Windows 测试版使用 Inno Setup EXE 安装程序交付，不再生成 MSIX。
- 项目专注本地与个人网盘视频媒体库，个人网盘仅作为用户自有媒体入口；不包含公共在线影视搜索、插件规则、WebView 视频解析或在线评论。
- 使用 TMDB 为本地与个人网盘媒体刮削中文标题、简介、评分、海报、背景图和季集信息。

## 工程约束

- Flutter SDK：`D:\flutter`，版本 3.41.9。
- 使用 Flutter Modular 与 MobX，遵循现有代码风格。
- 优先使用强类型，避免 `dynamic`。
- 修改播放器表现层时保持现有控件层级、动画时长、动画曲线和交互行为。
- 删除媒体源、索引或缓存时不得删除用户原始视频文件。
- TMDB 不可用、无 API Key 或断网时，本地扫描和播放必须继续可用。

## 验收

- `flutter test` 通过。
- `flutter analyze` 无错误。
- Windows Release 构建通过。
- 播放器动画、全屏、字幕、选集、硬件解码和 Anime4K 实机可用。
- 应用数据保存在看影音专属目录。

## 版本与交付

- Android TV 版发布无限期暂停：不得构建或交付 Android TV 正式版、测试版或个人预置包，不得运行 `tvTest` 发布流程，也不得向 GitHub 推送 TV 安装包、TV 标签或 TV Release。Android TV 代码可以保留；除非用户以后明确恢复，否则 Windows 和手机版 Android 的常规发布不得生成 TV 产物。
- 每次版本更新开始前，必须查询并记录当前 Windows EXE 安装状态和 `kanyingyin.exe` 的产品版本；兼容检查时同时确认旧 MSIX 是否仍存在，不能只根据 `pubspec.yaml` 推断。生成安装包后再次核对安装器与 Release 主程序版本，若执行安装则再次检查已安装版本。
- 准备正式发布前，必须先根据 GitHub 最新正式版标签、`RELEASE_NOTES.md`、`lib/utils/version_history.dart` 和正式版标签后的版本提交统计正式版与本地测试版相差几代；确认代差及尚未进入正式版的测试版本后，再决定正式版版本号和综合更新弹窗范围，不能只比较版本号字符串。
- 每次完成可交付的版本迭代并通过测试、静态分析和 Windows Release 构建后，必须继续生成 Inno Setup EXE 安装程序、验证版本，并将安装程序复制到当前用户桌面；不能只完成 Release 构建，也不要生成 MSIX。
- 进入安装包的修改必须同步更新 `pubspec.yaml` 的 `version`；保留 `msix_config` 时只作为历史兼容配置同步版本，不进入交付流程。
- 每次交付更新 `RELEASE_NOTES.md` 和 `lib/utils/version_history.dart`，文案面向普通用户。
- 新安装或首次启动时，若桌面或开始菜单快捷方式不存在，必须弹窗询问是否创建，不能静默跳过。
- 生成 Windows 安装包时，最终 `.exe` 复制到当前用户桌面，文件名格式为 `看影音-版本号-测试版-安装程序.exe`。
- 完成可交付修改并验证后，默认执行 `git add` 和 `git commit`；提交信息使用简洁中文。
- 自动提交前检查 `git status --short` 和关键 diff，只提交本轮相关改动。
