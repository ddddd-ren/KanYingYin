# Android TV 通用测试版设计

**日期：** 2026-08-06

**状态：** 待用户评审

## 目标

在现有看影音 Android 版本上增加一个可侧载的 Android TV/Google TV 测试包，复用现有本地媒体库、个人网盘、TMDB 刮削和 Full `libmpv` 播放能力，让用户仅使用电视遥控器完成媒体浏览、选集、播放和返回操作。

本设计只覆盖能够运行 Android APK 的电视和电视盒子。海信 VIDAA 或其他不能侧载 Android APK 的系统不属于本版本支持范围。

## 方案边界

- 最低 Android API：24（Android 7.0）。
- ABI：`arm64-v8a`、`armeabi-v7a`、`x86_64`。
- 首次交付形式：签名通用 APK，支持 USB、文件管理器或 ADB 侧载。
- TV 测试包使用独立包名 `com.kanyingyin.player.tvtest`，与手机 Android 数据隔离。
- TV 测试包沿用 Windows 当前测试版本的 `versionName/versionCode`，通过应用名称区分测试包，不建立第三条版本线。
- 首版不做 Google Play 上架、不做 VIDAA 原生应用、不做品牌专属适配。
- 首版允许使用电视系统键盘或外接键盘完成复杂账号输入；媒体浏览和播放主流程必须使用 D-pad 完成。

## 设备判定

### 运行时能力

现有 `AppPlatformKind` 继续只表示 Windows/Android 平台，在 `AppPlatformCapabilities` 中增加 Android TV 形态能力。TV 判定使用 Android 原生能力探测，不使用屏幕宽度单独推断：

1. 查询 `PackageManager.FEATURE_LEANBACK`。
2. 查询 `PackageManager.FEATURE_TELEVISION` 或 `uiMode` 的电视类型。
3. 记录 API 级别、CPU ABI、是否存在触摸屏和是否存在系统 WebView。
4. 原生通道不可用时返回普通 Android 能力，不能阻止手机和平板启动。

Flutter 启动流程保留同步的基础平台判定，再异步加载 Android 形态能力；能力探测失败只影响 TV 专属界面，不影响本地扫描和播放。

### 安装门槛

TV 测试包启动后记录一条不含账号、Token 和目录内容的设备诊断信息：API、ABI、电视特性、屏幕尺寸、WebView 可用性和媒体库能力。诊断信息用于兼容性报告，不以厂商名称作为硬编码分支。

## 构建与 Android 清单

### Flavor

Android 工程增加 `tvTest` flavor，并保留普通 Android flavor。为避免 Flutter 默认构建命令失效，现有 Android 构建脚本和测试命令统一明确传入对应 flavor。

TV flavor 的构建参数：

```text
applicationId: com.kanyingyin.player.tvtest
application label: 看影音 TV 测试版
versionName/versionCode: 与当前 Windows 测试版一致
```

TV 测试包使用现有 Android 签名环境和 Full `libmpv` 依赖；首版输出通用 APK，不输出 AAB。

### 清单声明

TV flavor 的 manifest 增加：

- `android.software.leanback`，`required=false`，避免影响混合设备安装。
- `android.hardware.touchscreen`，`required=false`。
- `android.hardware.faketouch`，`required=false`。
- `CATEGORY_LEANBACK_LAUNCHER` 与现有 `MAIN/LAUNCHER`。
- Activity 横屏声明和 TV Banner。

Banner 使用中文应用名，放入 `drawable-xhdpi`，尺寸为 320x180；启动图、图标和普通 Android 资源不互相覆盖。

### 版本合同前置修复

TV flavor 之前必须先统一以下来源：

- `pubspec.yaml` 的版本。
- `android/app/build.gradle.kts` 的版本校验和 Android 版本。
- `tool/android/build_signed_release.ps1` 的版本检查与构建命令。
- 版本一致性和 Android 打包合同测试。
- `RELEASE_NOTES.md` 与 `lib/utils/version_history.dart` 当前版本文案。

当前 Gradle 校验旧 `1.0.6+10006` 而根工程为 `2.1.138+20138`，该问题属于 TV 包的硬阻断，必须在 flavor 工作前解决。

## TV 界面与焦点系统

### 焦点组件

新增一个小型 TV 焦点表面组件，统一处理：

- `FocusNode` 生命周期。
- 焦点状态的描边、放大和阴影。
- Enter/Select/Space 的点击语义。
- disabled、loading 和不可播放状态。
- 焦点进入后的可见性滚动。

现有 `ImmersiveMediaCard`、侧栏目的地、网盘资源卡、季度卡、集数按钮和弹窗操作统一接入该组件。鼠标 Hover 仍保留给桌面端，但 TV 焦点不依赖 Hover。

### 布局策略

TV 使用横屏宽布局，但不直接套用桌面布局：

- 侧栏项目保留文字标签，最小焦点命中尺寸不低于 48dp。
- 海报卡使用更大的固定宽度和间距，避免一屏出现过多小卡片。
- 详情、季集和选集页面保持明确的上下级关系。
- 弹窗默认居中，焦点进入弹窗后不逃逸到背景。
- 页面重新显示时恢复上一次焦点，而不是回到第一个控件。

### D-pad 规则

- 上下左右：交给当前 FocusTraversalGroup 导航；不在页面级别全局吞掉。
- 中心键：触发当前焦点项的主要动作。
- 返回键：由页面层级、弹窗层级和播放器层级依次处理。
- 菜单键：打开当前媒体或播放操作菜单；无菜单时保持系统默认行为。

## 播放器 TV 控制

播放器增加独立的 TV 遥控器策略，不修改现有桌面快捷键含义：

| 遥控器输入 | TV 行为 |
| --- | --- |
| 中心键、Enter、Select | 播放/暂停或确认当前焦点 |
| 播放/暂停媒体键 | 播放/暂停 |
| 左键 | 快退；控制栏可见时移动焦点 |
| 右键 | 快进；控制栏可见时移动焦点 |
| 上/下键 | 控制栏可见时切换控件；隐藏时调节音量 |
| 返回键 | 关闭菜单/控制栏、退出播放器或返回上级 |
| 菜单键 | 打开播放菜单 |

控制栏获得焦点后，视频画面上的快捷键 Focus 不得拦截 D-pad 导航。控制栏自动隐藏时焦点回到视频表面；重新显示时恢复最近的控制项。

## 局域网手机配置（可选辅助能力）

该能力不依赖云服务器，仅在 TV 的“配置”页面打开：

1. TV 在本地启动临时 HTTP 服务，只绑定局域网接口。
2. TV 生成一次性随机配对令牌，5 分钟有效，成功使用一次后立即失效。
3. 二维码包含 TV 局域网地址、临时端口和一次性配对令牌；不包含账号密码、Refresh Token、Cookie 或 TMDB Key 等长期凭据。
4. 手机与 TV 必须连接同一个局域网；手机浏览器打开配置页。
5. 手机提交配置前，TV 显示待写入项目摘要并要求遥控器确认。
6. 配置写入 TV 专属安全存储后关闭本地服务。

局域网配对失败时必须保留手动配置入口。路由器开启 AP 隔离、TV 使用访客网络、多个网卡地址或手机不在同一 Wi-Fi 时，配对可能失败；这些情况不能阻塞正常 APK 启动。

首版只实现配置传输，不实现云端中继、远程配对或跨网络账号同步。账号、密码、Refresh Token、Cookie 和 TMDB Key 不得写入日志或二维码内容。

## 测试设计

### Flutter 测试

- TV 能力探测成功、失败和非 TV Android 回退。
- TV flavor 的包名、版本和 manifest 合同。
- 海报卡焦点状态、Enter/Select 操作和禁用状态。
- 网格 D-pad 上下左右移动与自动滚动。
- 弹窗焦点陷阱和返回键层级。
- 播放器中心键、媒体播放键、左右键和返回键。
- 局域网配对令牌过期、重复使用、错误令牌和确认取消。
- 配置传输不记录敏感字段。

### 构建验证

```text
D:\flutter\bin\flutter.bat pub get --offline --enforce-lockfile
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
D:\flutter\bin\flutter.bat build apk --release --flavor tvTest
aapt dump badging <tvTest-apk>
```

APK 验证必须检查：包名、版本、`LEANBACK_LAUNCHER`、触摸屏声明、Banner、ABI、签名和 Full `libmpv` 内容。

### 实机验收

至少验证一台标准 Android TV/Google TV 设备和用户的海信电视（仅在其确实支持 Android APK 时）。验收必须包含：

- 冷启动、首次配置和局域网配对。
- 纯遥控器浏览媒体库、网盘、电影、动漫、电视剧、季度和集数。
- 本地视频、网盘视频、外挂字幕、内嵌字幕和音轨切换。
- 1080p 和 4K H.264/HEVC 硬件解码。
- 播放/暂停、快进、快退、返回、长时间播放和息屏恢复。

没有真实电视通过上述验收时，只能称为“可安装测试包”，不能称为“Android TV 兼容版”。

## 非目标

- 不支持 VIDAA 原生安装。
- 不为每个电视品牌写独立 UI。
- 不承诺所有 Android 电视都能使用同一套硬件解码能力。
- 不在首版引入服务器、云端配对或远程控制。
- 不改动用户原始视频和网盘文件。

## 通过条件

只有同时满足以下条件，才进入正式 Android TV 发布评估：

1. 标准 Android TV 设备能安装并进入 TV launcher。
2. 主浏览、选集和播放器流程可用遥控器完成。
3. 播放器常用格式、字幕和音轨在真实设备上通过。
4. 局域网配对可用，但配对失败仍能手动配置。
5. Android 版本、签名、ABI 和 Full `libmpv` 验证通过。
6. 海信电视明确归类为 Android 可运行或 VIDAA 不支持，不保留模糊的“安卓底层兼容”结论。
