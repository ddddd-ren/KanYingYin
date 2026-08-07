# Android TV 测试版验收报告

## 当前结论

2.1.146 已完成自动化、Windows Release、Inno 安装器和 Android TV 个人预置包验证。当前 ADB 设备列表为空，本轮未安装到用户的海信电视，因此海信实机验收仍未完成。

## 质量门禁

- Dart 格式：`694` 个文件检查完成，`0` 个文件需要修改。
- Flutter 测试：`1820/1820` 通过。
- Flutter Analyze：`No issues found!`。
- Windows Release：构建成功。
- Android `tvTest` Release：构建成功，随后独立包验证全部通过。

## Windows 交付证据

- 版本：`2.1.146`。
- Release 主程序：`D:\KanYingYin\build\windows\x64\runner\Release\kanyingyin.exe`。
- Release 主程序大小：`293376` 字节。
- Release 主程序产品版本：`2.1.146`。
- Release 主程序 SHA-256：`F47E1AB3BA31E29300962CF31186FBA75008E4B6168923349281D9E8A8963E3A`。
- 桌面 Inno 安装器：`C:\Users\asus\Desktop\看影音-2.1.146-测试版-安装程序.exe`。
- 安装器大小：`69826931` 字节。
- 安装器产品版本：`2.1.146`。
- 安装器 SHA-256：`57CFC05ED1D24EDCC20A0673E40DCE49EF63904E46EBEBC4F3AEEBCAD07BA600`。
- Authenticode 状态：`NotSigned`，测试版安装器未签名。
- 本轮构建脚本未执行安装、卸载或启动操作；最终检查发现 Inno 版 `2.1.145` 已安装在 `D:\看影音`，主程序产品版本为 `2.1.145`。

## Android TV 交付证据

- 版本：`2.1.146 (20146)`。
- Flavor：`tvTest`。
- 包名：`com.kanyingyin.player.tvtest`。
- 最低版本：Android 7.0，API 24；目标 API 36。
- 构建 APK：`D:\KanYingYin\build\app\outputs\flutter-apk\app-tvTest-release.apk`。
- 桌面 APK：`C:\Users\asus\Desktop\看影音-2.1.146-TV个人预置测试版.apk`。
- APK 大小：`143686968` 字节。
- 源 APK 与桌面副本 SHA-256：`474ECC2CB8E89A0F07EEB1C4D79380649D369855FB5F55C7F087599D7FA2A1AC`，两者一致。
- APK v2 签名：通过；签名者数量为 `1`，证书 SHA-256 为 `aec3af6f3ef68cd65d4e1906508ecae9dc8720c808602dff3d219777c0663a46`。
- Manifest：包含 `LEANBACK_LAUNCHER` 和 Banner；触摸屏声明为非必需。
- Full `libmpv`：`arm64-v8a`、`armeabi-v7a`、`x86_64` 三个 ABI 均通过固定资产哈希验证。
- 包内预置清单已启用；配置资源为 `6033` 字节，SHA-256 为 `f004709d080e3a68b29a4858a8eb27e5244ddbffa4f3533e1a0190642708cbc5`；刮削资料资源为 `8969974` 字节，SHA-256 为 `c1cf122f6282a9dbdcdb2c5f3d74061ab63a29c43eab46fe4bd410c6c22099c8`。
- 构建结束后工作区只保留禁用的 `assets/tv_preload/manifest.json`，两个个人资源和两个密码环境变量均未残留。

## 本轮自动化覆盖

- 本地媒体库内容区、路径输入框、搜索框和内层焦点范围按左键进入侧边导航栏；从侧栏按右键恢复内容焦点。
- TV 海报墙固定五列、首屏两行，使用 0.78 紧凑卡片比例、16dp 间距和安全边距，电影、动漫、电视剧与本地媒体库共用该布局策略。
- 子页面的闭环焦点组在最左侧按左键仍进入侧边导航栏；弹窗、底部面板和输入框的 TV 返回快捷键会先退出编辑，再关闭当前路由。
- 播放页系统返回与遥控器返回共用控制层关闭路径，反向动画完成后才恢复视频焦点；Android TV 退出不提前切换全屏模式。
- TV 导入刮削资料和导入配置使用无初始文件 URI 的系统文件选择器通道；原生层流式复制到应用缓存，Dart 读取后删除缓存文件。
- 导入文件选择失败会返回明确错误；扩展名、大小和文件读取结果均在原生层与 Dart 层校验；电视文件管理器缺少显示名时从 URI 或唯一允许格式恢复 `.kyymeta`/`.kyyconfig`。
- 网盘目录页顶部“选择当前目录”和“确定”使用 TV 焦点表面；加载完成后默认聚焦前者，按确认选中后可按右键聚焦并确认后者。
- TV 设置操作显示高对比边框、浅色背景、勾选和确认提示，中心键只触发一次。
- 手机扫码配对覆盖“手机已连接、等待电视确认、正在写入、成功、拒绝、超时和写入失败”状态。
- 手机页面可新增、编辑和删除 OpenList、夸克、百度和迅雷来源；新增非 OpenList 来源会提示在电视继续选择媒体目录。
- 手机扫码页面可选择并流式上传 `.kyyconfig` 和 `.kyymeta`；配置导入使用密码解密，刮削资料在配置导入后重新匹配，手机端显示上传和导入结果。
- `.kyyconfig` 使用密码加密，覆盖正确密码、错误密码、篡改和文件大小限制。
- 个人 TV 构建前使用纯 Dart 校验器验证配置加密封套和刮削资料 ZIP 清单，不加载 Flutter `dart:ui`，错误密码、危险路径、缺失声明、大小和哈希错误都会在编译前中止。
- Windows PowerShell 5.1 下个人 APK 的中文桌面文件名由运行时 Unicode 字符码生成，避免 UTF-8 无 BOM 脚本被系统代码页误解码为非法路径。
- TMDB Key 和个人网盘来源按来源 ID 原子合并，写入失败会恢复原配置；不会修改或删除视频、字幕、索引、缓存和播放历史。

## 设备与安装状态

ADB 输出只有 `List of devices attached`，没有已连接或已授权设备。

| 项目 | 当前状态 | 备注 |
| --- | --- | --- |
| 用户海信电视 | `pending` | 未连接 ADB，Android API、ABI 和遥控器实机行为尚未取得证据 |
| 标准 Android TV/Google TV | `pending` | 包级兼容检查通过，尚未完成真实设备安装与播放 |
| Windows Inno 安装 | 已安装 `2.1.145` | 注册表安装目录为 `D:\看影音`，主程序产品版本为 `2.1.145`；本轮构建脚本未执行安装 |
| 旧 Windows MSIX | 未安装；历史文件存在 | `Get-AppxPackage` 未发现看影音 MSIX；工作区和桌面共保留 `165` 个历史 MSIX 文件，本轮未生成或交付 MSIX |

本轮构建脚本没有执行安装，最终安装状态检查如上。若海信设备为 VIDAA 原生系统而没有 Android 底层，则不能安装本 APK。

详细字段和记录规则见 [android-tv-test-matrix.md](android-tv-test-matrix.md)。

## 待完成项目

- 连接海信电视并记录 Android API、ABI、Leanback、WebView 和 SAF 证据。
- 安装 2.1.146 TV 个人预置 APK，重测首次自动导入、五列两行海报墙、所有子页面左键进入侧栏、弹窗与输入框返回、播放控制层返回和目录顶部焦点提示。
- 实测同一局域网手机扫码、两个文件上传、电视确认或拒绝、四类网盘配置、手机成功页和 `.kyyconfig` 正确或错误密码导入。
- 完成 1080p、4K HEVC、字幕、音轨、硬件解码、Anime4K 和个人网盘播放矩阵后，才能把海信设备结果改为 `passed`。
