# CLAUDE.md — KanYingYin 改造项目

## 项目概述

KanYingYin 是一个 Flutter 跨平台动漫播放客户端，我们要改造为**本地+在线资源播放器**。

## 工作环境

- **工作目录**：`D:/KanYingYin-src`
- **Flutter SDK**：`D:/flutter`
- **Flutter 版本**：3.41.9
- **Dart SDK**：>=3.3.4 <4.0.0
- **当前版本**：2.1.0+20100

## 技术栈

- **框架**：Flutter（跨平台：Android / Windows / macOS / Linux）
- **状态管理**：GetX（`lib/providers/`）
- **播放器**：media_kit
- **网络请求**：dio
- **本地存储**：hive
- **WebView**：webview_flutter
- **超分辨率**：Anime4K WebGL2 着色器（`lib/shaders/`）

## 目录结构

```
D:/KanYingYin-src/lib/
├── main.dart              # 入口
├── app_module.dart        # App 模块配置
├── app_widget.dart        # App Widget
├── bean/                  # 数据模型
├── modules/               # 功能模块
├── pages/                 # 页面
│   ├── about/             # 关于页
│   ├── bangumi/           # 番剧页
│   ├── collect/           # 追番页
│   ├── download/          # 下载页
│   ├── error/             # 错误页
│   ├── history/           # 历史页
│   ├── info/              # 番剧详情页
│   ├── logs/              # 日志页
│   ├── menu/              # 导航菜单
│   ├── my/                # 我的页面
│   ├── player/            # 播放器页
│   ├── plugin_editor/     # 插件编辑器
│   ├── popular/           # 推荐页
│   ├── search/            # 搜索页
│   ├── settings/          # 设置页
│   ├── timeline/          # 时间表页
│   ├── video/             # 视频页
│   └── webdav_editor/     # WebDAV 配置页
├── plugins/               # 插件系统
├── providers/             # 状态管理（GetX）
├── repositories/          # 数据仓库
├── request/               # 网络请求
├── shaders/               # 超分辨率着色器
├── utils/                 # 工具类
└── webview/               # WebView 封装
```

## 改造目标

### 保留
- ✅ 在线资源功能（插件规则引擎、WebView）
- ✅ 超分辨率（Anime4K 着色器）
- ✅ 本地播放（media_kit）

### 新增
- ➕ 本地文件浏览模块（浏览本地文件夹、筛选视频、直接播放）

## 任务分配

### ClawX（架构/核心）
1. 新增本地文件浏览模块
2. 集成播放器到本地文件模块

### Trae（UI/前端）
1. 改包名和应用名
2. 改图标
3. 改 UI 样式
4. 联调打包

## 编码规范

- 优先使用 Dart 强类型，避免 dynamic
- 组件保持单一职责
- 修改现有代码时匹配已有风格，不擅自重构
- 使用 GetX 状态管理，遵循项目现有模式
- 打包前确认版本号正确

## 验收标准

- `flutter analyze` 无错误
- 本地文件浏览模块功能正常
- 所有平台能正常打包（Android / Windows / macOS / Linux）
- UI 风格统一

## 版本迭代与更新弹窗记忆

- 每次完成代码修改并准备交付时，必须同步做版本迭代检查。
- 若修改会进入用户安装包，必须更新 `pubspec.yaml` 的 `version` 和 `msix_config.msix_version`，并同步 `lib/request/config/api_endpoints.dart` 中的版本常量。
- 每次完成修改都必须补充面向用户的更新弹窗文案：更新 `RELEASE_NOTES.md`，并同步 `lib/utils/version_history.dart`，确保应用启动后的“版本更新日志”能显示本次迭代重点。
- 更新弹窗文案必须面向普通用户，描述可感知功能、修复和体验变化，不写内部路径、构建命令或仅开发者可理解的细节。
- 打包前再次确认版本号、更新弹窗文案和安装包文件名一致。

## 新安装快捷方式弹窗记忆

- 每次新安装或首次启动时，必须提供“创建快捷方式”的用户确认弹窗。
- 快捷方式弹窗不能静默跳过；如果检测到桌面/开始菜单快捷方式不存在，应提示用户创建。
- 弹窗文案必须面向普通用户，说明会创建桌面或开始菜单入口，用户可确认或取消。
- 修改安装、首次启动、快捷方式、MSIX 或 Windows 启动流程时，必须回归检查这个弹窗是否仍会出现。

## 自动提交记忆

- 每次完成文件改动、验证通过并形成可交付结果后，默认自动执行 `git add` 和 `git commit`。
- 除非用户明确要求不要提交、只看 diff、继续修改或暂缓提交，否则不要把已完成改动长期留在未提交状态。
- 自动提交前必须先检查 `git status --short` 和关键 diff，确认只提交本轮相关改动。
- 提交信息使用简洁中文，概括本轮用户可感知改动或文档记忆更新。

## 安装包打包位置记忆

- 每次生成 Windows 安装包时，必须将最终可交付的 `.msix` 安装包复制到当前用户桌面。
- 桌面安装包文件名必须与当前版本一致，格式建议为 `就看-版本号.msix`，例如 `就看-2.3.15.msix`。
- 打包完成后必须确认桌面文件存在、文件大小正常，并在交付说明中写明桌面安装包的完整路径。
