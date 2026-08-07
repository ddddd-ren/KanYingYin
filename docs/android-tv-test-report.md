# Android TV 测试版验收报告

## 当前结论

2.1.142 的自动化、Windows Release、Inno 安装器构建和 Android TV 包验证已经通过。当前 ADB 设备列表为空，未安装到用户的海信电视，因此交付结论保持“构建与包验证通过，海信实机验收未完成”。

## 质量门禁

- Dart 格式：`675` 个文件检查完成，`0` 个文件需要修改。
- Flutter 测试：`1780/1780` 通过。
- Flutter Analyze：`No issues found!`。
- Windows Release：构建成功。
- Android `tvTest` Release：构建成功。Kotlin 增量缓存曾报告跨盘根目录警告，Gradle 自动回退到非增量编译后成功产出，后续独立包验证全部通过。

## Windows 交付证据

- 版本：`2.1.142`。
- Release 主程序：`D:\KanYingYin\build\windows\x64\runner\Release\kanyingyin.exe`。
- Release 主程序大小：`293376` 字节。
- Release 主程序产品版本：`2.1.142`。
- 桌面 Inno 安装器：`C:\Users\asus\Desktop\看影音-2.1.142-测试版-安装程序.exe`。
- 安装器大小：`69810473` 字节。
- 安装器产品版本：`2.1.142`。
- 安装器 SHA-256：`D8529245F06B6D89E7EFA3E82B65A26BB435F9133B0F6770FE37DAEC0A4E7EF7`。
- Authenticode 状态：`NotSigned`，测试版安装器未签名。
- 本轮未执行安装、卸载或启动操作。

## Android TV 交付证据

- 版本：`2.1.142 (20142)`。
- Flavor：`tvTest`。
- 包名：`com.kanyingyin.player.tvtest`。
- 最低版本：Android 7.0，API 24；目标 API 36。
- 构建 APK：`D:\KanYingYin\build\app\outputs\flutter-apk\app-tvTest-release.apk`。
- 桌面 APK：`C:\Users\asus\Desktop\看影音-2.1.142-TV测试版.apk`。
- APK 大小：`134647154` 字节。
- 源 APK 与桌面副本 SHA-256：`3E5A01181E3F2EE0B6977170A6A31C9AF719762D42EC8DA89899774162D83E1D`，两者一致。
- APK v2 签名：通过；签名者数量为 `1`，证书 SHA-256 为 `aec3af6f3ef68cd65d4e1906508ecae9dc8720c808602dff3d219777c0663a46`。
- Manifest：包含 `LEANBACK_LAUNCHER` 和 Banner；触摸屏声明为非必需。
- Full `libmpv`：`arm64-v8a`、`armeabi-v7a`、`x86_64` 三个 ABI 均通过固定资产哈希验证。
- 独立验证摘要：`tool/android/private-output/tv-test-20260807-085807-summary.json`，该目录为本机私有输出，不提交到仓库。

## 本轮自动化覆盖

- 本地媒体库内容区、路径输入框、搜索框和内层焦点范围按左键进入侧边导航栏；从侧栏按右键恢复内容焦点。
- TV 设置操作显示高对比边框、浅色背景、勾选和确认提示，中心键只触发一次。
- 手机扫码配对覆盖“手机已连接、等待电视确认、正在写入、成功、拒绝、超时和写入失败”状态。
- 手机页面可新增、编辑和删除 OpenList、夸克、百度和迅雷来源；新增非 OpenList 来源会提示在电视继续选择媒体目录。
- `.kyyconfig` 使用密码加密，覆盖正确密码、错误密码、篡改和文件大小限制。
- TMDB Key 和个人网盘来源按来源 ID 原子合并，写入失败会恢复原配置；不会修改或删除视频、字幕、索引、缓存和播放历史。

## 设备与安装状态

ADB 输出只有 `List of devices attached`，没有已连接或已授权设备。

| 项目 | 当前状态 | 备注 |
| --- | --- | --- |
| 用户海信电视 | `pending` | 未连接 ADB，Android API、ABI 和遥控器实机行为尚未取得证据 |
| 标准 Android TV/Google TV | `pending` | 包级兼容检查通过，尚未完成真实设备安装与播放 |
| Windows Inno 安装 | 未安装 | 注册表未发现看影音 Inno 记录，预期安装目录下没有 `kanyingyin.exe` |
| 旧 Windows MSIX | 未发现 | `com.kanyingyin.player` 的 Appx 查询结果为空 |

打包前后安装状态一致，已安装版本未由本次打包改变。若海信设备为 VIDAA 原生系统而没有 Android 底层，则不能安装本 APK。

详细字段和记录规则见 [android-tv-test-matrix.md](android-tv-test-matrix.md)。

## 待完成项目

- 连接海信电视并记录 Android API、ABI、Leanback、WebView 和 SAF 证据。
- 安装 2.1.142 TV APK，重测本地媒体库左键进入侧栏、搜索框返回、根页面退出确认和设置焦点提示。
- 实测同一局域网手机扫码、电视确认或拒绝、四类网盘配置、手机成功页和 `.kyyconfig` 正确或错误密码导入。
- 完成 1080p、4K HEVC、字幕、音轨、硬件解码、Anime4K 和个人网盘播放矩阵后，才能把海信设备结果改为 `passed`。
