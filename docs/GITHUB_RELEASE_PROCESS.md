# GitHub 发布流程

本文档只描述 Windows 正式版和 Android 手机正式版的 GitHub 发布。本轮测试版交付范围是桌面 Inno Setup EXE，不进入正式 Release；若以后恢复 Android 手机测试包，必须单独标注测试版和验收边界。Android TV 正式版、测试版和安装包无限期暂停，除非用户明确恢复，否则不得构建或发布 TV 产物。

## 0. 正式版与测试版边界

| 项目 | 正式版 | 测试版 |
| --- | --- | --- |
| Windows 产物 | `看影音-版本号-安装程序.exe` | `看影音-版本号-测试版-安装程序.exe` |
| GitHub Release | `prerelease=false`，可供普通用户下载 | 不得冒充正式版，不上传到正式 Release |
| 文案 | 只写已进入稳定版本的功能 | 明确测试版、未签名或未安装等验证边界 |
| Android | 仅发布已完成签名和实机验收的 APK/AAB | 仅同步版本配置时不得写成已交付安装包 |

## 1. 发布前检查

1. 确认工作目录为 `D:\KanYingYin`，先查看：

   ```powershell
   git status --short --branch
   git log -1 --oneline
   git fetch origin main
   ```

2. 查询 GitHub 最新正式版标签、`RELEASE_NOTES.md`、`lib/utils/version_history.dart` 和版本提交，确认正式版与本地测试版相差几代，再决定正式版版本号和更新范围。
3. 检查版本契约是否同步：`pubspec.yaml`、`lib/core/app_version.dart`、`android/app/build.gradle.kts`、Inno Setup 脚本、更新弹窗、`README.md`、发布说明和相关测试。
4. 正式版文案不得出现“测试版”“首次正式发布”或 Android TV 内容；只写实际进入该版本的功能。

## 2. 构建与验证

### Windows

使用 Inno Setup EXE，不生成 MSIX：

```powershell
& 'tool/windows/build_exe_release.ps1'
```

正式版安装器名称必须是：

```text
看影音-版本号-安装程序.exe
```

测试版安装器才使用：

```text
看影音-版本号-测试版-安装程序.exe
```

独立核对安装器产品版本、文件大小、SHA-256 和签名状态。未签名时明确记录 `NotSigned`，不能宣称已签名。测试版即使构建成功，也要单独注明未安装和未完成实机验收的项目。

### Android 手机

只构建 `mobile` flavor，不运行 `tvTest`：

```powershell
& 'tool/android/build_signed_release.ps1' -Flavor mobile
```

核对 APK/AAB 的版本名、versionCode、签名和三种 `libmpv` ABI（`arm64-v8a`、`armeabi-v7a`、`x86_64`）。

## 3. 提交并推送代码

只暂存本次正式版相关修改，提交前检查：

```powershell
git diff --check
git status --short
git add <本次正式版文件>
git diff --cached --stat
git commit -m '发布X.Y.Z正式版'
git push origin main
```

推送后确认远端 `main` 已指向本次提交。不要把测试版提交直接标记为正式版；Release 标签必须指向包含正式版版本文件和文案的提交。

## 4. 创建正式 Release 和上传资产

正式版资产统一使用 ASCII 文件名：

```text
KanYingYin-WINDOWS_VERSION.exe
KanYingYin-ANDROID_VERSION.apk
KanYingYin-ANDROID_VERSION.aab
```

实际 Android 版本号以当前版本契约为准，不要求与 Windows 版本号相同。创建 Release 时必须满足：

- 标签格式为 `vX.Y.Z`；
- `draft=false`、`prerelease=false`；
- 只上传 Windows EXE、Android APK、Android AAB；
- 不上传 Android TV、MSIX 或旧的跨设备安装 ZIP；
- Release 标签提交、远端 `main` 和正式版代码提交一致。

使用 GitHub CLI 或网页上传均可，但必须等待 API 显示资产状态为 `uploaded` 后才算完成。

## 5. Release 说明格式

正式版 Release 正文采用以下格式，不使用复杂标题层级，也不写测试版内容：

```markdown
更新内容

Android 版本说明：
- Android 应用版本：X.Y.Z
- Android versionCode：10000
- Android 安装包：APK / AAB
- 只列出本次实际发布的 Android 功能和近期 Android 功能更新。

Windows 版本说明：
- Windows 应用版本：X.Y.Z
- Windows 安装器版本：X.Y.Z
- 只列出本次实际发布的 Windows 功能和近期 Windows 功能更新。
- 本次更新不会修改或删除本地及网盘原始视频、字幕或其他文件。

下载包：
- Windows：`KanYingYin-WINDOWS_VERSION.exe`
- Android APK：`KanYingYin-ANDROID_VERSION.apk`
- Android AAB：`KanYingYin-ANDROID_VERSION.aab`
```

下载包列表必须与 Release 实际资产完全一致。删除旧资产后，不得在说明中继续列出已不存在的文件。

## 6. 发布后核验

```powershell
gh api repos/ddddd-ren/KanYingYin/releases/tags/vX.Y.Z --jq `
  '{tag_name,name,draft,prerelease,target_commitish,assets:[.assets[]|{name,size,state,digest}]}'
git ls-remote origin refs/heads/main refs/tags/vX.Y.Z
```

逐项确认：

1. Release 是正式版，不是 draft 或 prerelease。
2. 标签提交与远端 `main` 一致。
3. 资产名称和大小与本地文件一致；用本地 SHA-256 对照下载后的文件，并将 GitHub API 的 `digest` 视为服务端摘要记录，不能直接替代本地哈希复核。
4. 正文没有“测试版”“首次正式发布”或 Android TV 内容，也没有字面量 `` `n ``。
5. GitHub 仓库简介、README 下载链接和当前正式 Release 保持一致。

## 7. 旧资产清理规则

保留旧 Release 和标签，保留仍有历史价值且链接有效的 APK/AAB/EXE。只有在确认已被当前交付格式替代后，才删除旧资产：

- 旧 MSIX；
- 旧跨设备安装 ZIP；
- 旧 TV 安装包（若历史上存在且明确不再发布）。

删除前先列出 Release、资产 ID、名称和大小；删除后通过 Release API 再查一次，确认目标资产确实消失，且当前正式 Release 的三个资产未受影响。
