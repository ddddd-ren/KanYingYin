# 控制器边界优化综合交付实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在本地、网盘和播放器三个阶段完成后，统一锁定架构边界，更新双平台版本与普通用户文案，并生成经过独立验证的 Windows/Android 交付包。

**Architecture:** 交付阶段不再新增业务边界，只清理过渡兼容层、扩展架构测试、同步版本文档并执行完整质量门禁。Windows 与 Android 的版本、构建、签名和产物分别验证，不以一个平台的成功代替另一个平台。

**Tech Stack:** Flutter 3.41.9、Dart、flutter_test、PowerShell、MSIX/signtool、Gradle/apksigner/jarsigner、Git。

---

### Task 1: 完成架构边界总验收

**Files:**
- Modify: `test/architecture_dependency_test.dart`
- Modify: `README.md:136-207`
- Modify: `AGENTS.md:7-31`
- Delete only if unused: `cloud_playback_resolver.dart` 中旧 token 兼容导出和其他过渡包装。

- [ ] **Step 1: 增加最终失败断言**

```dart
test('三个页面控制器不构造已提取底层实现且不定位全局服务', () {
  final controllers = <File>[
    File('${libDirectory.path}/pages/local/local_controller.dart'),
    File('${libDirectory.path}/pages/cloud/resources/cloud_resources_controller.dart'),
    File('${libDirectory.path}/pages/player/player_controller.dart'),
    File('${libDirectory.path}/pages/video/local_video_controller.dart'),
  ];
  for (final file in controllers) {
    expect(file.readAsStringSync(), isNot(contains('Modular.get<')),
        reason: file.path);
  }
  final source = controllers.map((file) => file.readAsStringSync()).join('\n');
  for (final construction in const <String>[
    'LocalMediaScanner(',
    'LocalMediaIndexer(',
    'LocalMediaIndexRepository(',
    'CloudHiddenVideoRepository(',
    'CloudMediaIndexRepository(',
    'CloudMediaIndexer(',
    'Player(',
  ]) {
    expect(source, isNot(contains(construction)), reason: construction);
  }
});

test('media-kit Player 和 NativePlayer 只由播放器基础设施拥有', () {
  final guarded = <File>[
    File('${libDirectory.path}/pages/player/player_controller.dart'),
    File('${libDirectory.path}/pages/video/local_video_controller.dart'),
    ..._dartFiles(Directory('${libDirectory.path}/features/player/application')),
  ];
  for (final file in guarded) {
    final relative = file.path.replaceAll('\\', '/');
    final source = file.readAsStringSync();
    expect(source, isNot(contains('Player(')), reason: relative);
    expect(source, isNot(contains('as NativePlayer')), reason: relative);
  }
});
```

本测试只约束播放功能边界；`services/local_media_probe.dart` 为媒体探测创建短生命周期 Player，不属于播放会话运行时，不纳入该断言。

- [ ] **Step 2: 运行架构测试并修复所有过渡残留**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/architecture_dependency_test.dart`

Expected: PASS。

- [ ] **Step 3: 更新项目结构和双平台约束文档**

README 的项目结构必须列出 `app`、`core`、`features`、`pages`、`services`、`repositories`、`modules`、`platform`、`legacy`；AGENTS 项目定位改为 Windows/Android 双平台，不再保留“首版只支持 Windows”的失效表述。

```text
lib/
  app/             应用级依赖组合
  core/            无业务反向依赖的基础能力
  features/        可独立测试的应用、表现与播放器基础设施边界
  pages/           路由页面和状态门面
  services/        扫描、网盘协议、TMDB 与兼容服务
  repositories/    媒体来源、索引和元数据持久化
  modules/         媒体与播放领域模型
  platform/        Windows/Android 能力和原生桥
  legacy/          仅由持久化边界使用的旧数据兼容
```

- [ ] **Step 4: 提交架构总验收**

```powershell
git add test/architecture_dependency_test.dart README.md AGENTS.md lib
git commit -m "重构：锁定控制器架构边界"
```

### Task 2: 查询安装状态并同步双平台版本

**Files:**
- Modify: `pubspec.yaml:19,138`
- Modify: `lib/core/app_version.dart:5`
- Modify: `android/app/build.gradle.kts:29-30`
- Modify: `tool/android/build_signed_release.ps1:10-11`
- Modify: `README.md:90-106`
- Modify: `RELEASE_NOTES.md:1`
- Modify: `UPDATE_DIALOG_COPY.md:3`
- Modify: `lib/utils/version_history.dart:1`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 在任何版本写入前记录当前 Windows 安装版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name,Version,PackageFullName,Status
```

Expected: 记录已安装版本；若无输出，明确记录“未安装”，不能从 pubspec 推断。

- [ ] **Step 2: 先把版本测试改为下一版本并确认 RED**

```dart
const expectedVersion = '1.0.5';
const expectedBuildNumber = '10005';
const expectedMsixVersion = '1.0.5.0';
const expectedAndroidVersion = '1.0.2';
const expectedAndroidVersionCode = '10002';
```

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart`

Expected: FAIL，显示当前 `1.0.4/1.0.1`。

- [ ] **Step 3: 同步版本配置**

```yaml
version: 1.0.5+10005
msix_config:
  msix_version: 1.0.5.0
```

```kotlin
val androidVersionName = "1.0.2"
val androidVersionCode = 10002
```

`AppVersion.current` 更新为 `1.0.5`；Android 构建脚本同步 `1.0.2/10002` 并把 Windows 配套版本检查更新为 `1.0.5+10005`。

- [ ] **Step 4: 写入普通用户发布文案和平台映射**

Windows 标题：`看影音 1.0.5 正式版`；Android 标题：`看影音 Android 1.0.2 正式版`。文案只描述可感知结果：媒体库切换与扫描更稳定、网盘来源刷新不会被旧请求覆盖、播放器切换和退出时资源释放更可靠；不得声称新增功能或性能提升。

`versionHistoryForCurrent('1.0.5', platform: AppPlatformKind.android)` 必须映射到 Android `1.0.2` 条目。

- [ ] **Step 5: 运行版本测试并提交**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/about_page_content_test.dart`

Expected: PASS。

```powershell
git add pubspec.yaml lib/core/app_version.dart android/app/build.gradle.kts tool/android/build_signed_release.ps1 README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "发布：准备1.0.5与安卓1.0.2正式版"
```

### Task 3: 完整格式、测试和静态分析门禁

**Files:**
- No product changes unless a gate exposes an in-scope regression.

- [ ] **Step 1: 检查工作树和提交范围**

```powershell
git status --short
git diff HEAD~8 --stat
git diff --check
```

Expected: 没有与控制器优化无关的用户文件被修改；`git diff --check` 无输出。

- [ ] **Step 2: 格式门禁**

Run: `D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test`

Expected: `Changed 0 files`。若格式器改写文件，检查 diff、提交格式修复后重新运行直到零改动。

- [ ] **Step 3: 完整测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub --reporter compact`

Expected: 所有测试通过；记录实际测试数量。任何失败都必须定位并重跑完整套件，不能用定向测试代替。

- [ ] **Step 4: 静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

### Task 4: Windows Release、MSIX 和安装验证

**Files:**
- Build outputs only; do not commit artifacts.

- [ ] **Step 1: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: `build\windows\x64\runner\Release\kanyingyin.exe` 新鲜生成。

- [ ] **Step 2: 生成签名 MSIX 和异机安装包**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File tool\windows\build_signed_release.ps1
```

Expected: 桌面存在 `看影音-1.0.5.msix` 与 `看影音-1.0.5-异机安装包.zip`；脚本验证签名、清单与哈希。

- [ ] **Step 3: 独立核对 MSIX**

解包读取 `AppxManifest.xml`，必须得到：Identity `com.kanyingyin.player`、Publisher `CN=KanYingYin`、Version `1.0.5.0`、ProcessorArchitecture `x64`。同时确认存在 `AppxSignature.p7x`，执行 `signtool verify /pa /v` 成功，并比较构建包与桌面包 SHA-256。

- [ ] **Step 4: 如执行安装，再次查询安装版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name,Version,PackageFullName,Status
```

Expected: 安装后为 `1.0.5.0`；若本轮未安装，交付报告必须明确写“未执行安装验证”。

### Task 5: Android Release、签名和包验证

**Files:**
- Build outputs only; do not commit artifacts or signing material.

- [ ] **Step 1: 构建并验证签名 APK/AAB**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool\android\build_signed_release.ps1`

Expected: 脚本读取 `KANYINGYIN_ANDROID_*` 环境变量，生成并验证 `1.0.2/10002` 的 APK 与 AAB，然后复制到桌面。

- [ ] **Step 2: 独立验证 APK**

使用 `apkanalyzer manifest print` 或 `aapt2 dump badging` 检查 package `com.kanyingyin.player`、versionName `1.0.2`、versionCode `10002`、minSdk 24、targetSdk 36；用 `apksigner verify --verbose --print-certs` 确认 v2+ 签名有效。

- [ ] **Step 3: 独立验证 AAB**

用 `jarsigner -verify -strict -verbose -certs` 检查签名；解读 manifest 验证相同包名和版本。记录 APK/AAB SHA-256。

- [ ] **Step 4: 有设备时执行 Android 冒烟**

通过 `adb install -r` 安装 APK，验证启动、本地 SAF 目录、一个网盘来源、播放、字幕、音轨、后台播放和画中画。若没有 ARM64 设备，不得把模拟器启动当成完整实机验收。

### Task 6: 完成状态审计和最终提交

**Files:**
- No new product changes unless audit finds a missing requirement.

- [ ] **Step 1: 逐项复核设计目标**

检查四个 Controller 无 Repository/Service 直连和 `Modular.get`；Coordinator 单测存在；页面、路由、动画和播放入口未改；删除逻辑不触碰原始媒体；本地、网盘、播放器、双平台门禁都有直接证据。

- [ ] **Step 2: 检查 Git 三类状态**

```powershell
git status --short
git diff
git diff --cached
```

Expected: 没有未提交修改、暂存修改或未跟踪文件；构建产物和证书不在 Git 状态中。

- [ ] **Step 3: 若验证修复产生最后改动，回到暴露问题的对应任务**

不得使用宽泛暂存命令掩盖归属。修复后重新执行该任务的定向测试和完整门禁，并使用该任务列出的精确文件路径提交；没有修复改动时不创建空提交。

- [ ] **Step 4: 输出交付证据**

最终报告列出：所有提交、测试数量、analyze 结果、Windows/Android 构建结果、MSIX/APK/AAB 路径与 SHA-256、签名/清单版本、安装或实机验证状态、最终 Git 状态。未执行项必须明确列为未验证，不能以计划或历史结果代替。
