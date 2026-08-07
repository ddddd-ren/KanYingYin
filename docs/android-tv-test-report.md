# Android TV 测试版验收报告

## 当前结论

2.1.143 的自动化、Windows Release、Inno 安装器构建和 Android TV 包验证已经通过。当前 ADB 设备列表为空，未安装到用户的海信电视，因此交付结论保持“构建与包验证通过，海信实机验收未完成”。

## 质量门禁

- Dart 格式：`677` 个文件检查完成，`0` 个文件需要修改。
- Flutter 测试：`1788/1788` 通过。
- Flutter Analyze：`No issues found!`。
- Windows Release：构建成功。
- Android `tvTest` Release：构建成功，随后独立包验证全部通过。

## Windows 交付证据

- 版本：`2.1.143`。
- Release 主程序：`D:\KanYingYin\build\windows\x64\runner\Release\kanyingyin.exe`。
- Release 主程序大小：`293376` 字节。
- Release 主程序产品版本：`2.1.143`。
- 桌面 Inno 安装器：`C:\Users\asus\Desktop\看影音-2.1.143-测试版-安装程序.exe`。
- 安装器大小：`69814273` 字节。
- 安装器产品版本：`2.1.143`。
- 安装器 SHA-256：`7D6D88D9A082E15FFF34E2DAD0151D205B655319BAA02BC92F9CF8D7F812F6A0`。
- Authenticode 状态：`NotSigned`，测试版安装器未签名。
- 本轮构建脚本未执行安装、卸载或启动操作；最终检查发现 Inno 版 `2.1.143` 已安装在 `D:\看影音`。

## Android TV 交付证据

- 版本：`2.1.143 (20143)`。
- Flavor：`tvTest`。
- 包名：`com.kanyingyin.player.tvtest`。
- 最低版本：Android 7.0，API 24；目标 API 36。
- 构建 APK：`D:\KanYingYin\build\app\outputs\flutter-apk\app-tvTest-release.apk`。
- 桌面 APK：`C:\Users\asus\Desktop\看影音-2.1.143-TV测试版.apk`。
- APK 大小：`134647154` 字节。
- 源 APK 与桌面副本 SHA-256：`495408AEC251EDB76E047BB741D4CA17A272046567CCD6852DFE774F8E8AB7CD`，两者一致。
- APK v2 签名：通过；签名者数量为 `1`，证书 SHA-256 为 `aec3af6f3ef68cd65d4e1906508ecae9dc8720c808602dff3d219777c0663a46`。
- Manifest：包含 `LEANBACK_LAUNCHER` 和 Banner；触摸屏声明为非必需。
- Full `libmpv`：`arm64-v8a`、`armeabi-v7a`、`x86_64` 三个 ABI 均通过固定资产哈希验证。
- 独立验证摘要：`tool/android/private-output/tv-test-20260807-102429-summary.json`，该目录为本机私有输出，不提交到仓库。

## 本轮自动化覆盖

- 本地媒体库内容区、路径输入框、搜索框和内层焦点范围按左键进入侧边导航栏；从侧栏按右键恢复内容焦点。
- TV 导入刮削资料和导入配置使用无初始文件 URI 的系统文件选择器通道；原生层流式复制到应用缓存，Dart 读取后删除缓存文件。
- 导入文件选择失败会返回明确错误；扩展名、大小和文件读取结果均在原生层与 Dart 层校验。
- 网盘目录页顶部“选择当前目录”和“确定”使用 TV 焦点表面；加载完成后默认聚焦前者，按确认选中后可按右键聚焦并确认后者。
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
| Windows Inno 安装 | 已安装 `2.1.143` | 注册表安装目录为 `D:\看影音`，主程序产品版本为 `2.1.143` |
| 旧 Windows MSIX | 未发现 | `com.kanyingyin.player` 的 Appx 查询结果为空 |

本轮构建脚本没有执行安装，最终安装状态检查如上。若海信设备为 VIDAA 原生系统而没有 Android 底层，则不能安装本 APK。

详细字段和记录规则见 [android-tv-test-matrix.md](android-tv-test-matrix.md)。

## 待完成项目

- 连接海信电视并记录 Android API、ABI、Leanback、WebView 和 SAF 证据。
- 安装 2.1.143 TV APK，重测本地媒体库左键进入侧栏、搜索框返回、根页面退出确认、导入文件选择和目录顶部焦点提示。
- 实测同一局域网手机扫码、电视确认或拒绝、四类网盘配置、手机成功页和 `.kyyconfig` 正确或错误密码导入。
- 完成 1080p、4K HEVC、字幕、音轨、硬件解码、Anime4K 和个人网盘播放矩阵后，才能把海信设备结果改为 `passed`。
