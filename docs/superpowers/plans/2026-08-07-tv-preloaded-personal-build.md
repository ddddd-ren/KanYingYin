# TV 个人预置包实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 生成一份只供用户个人使用的 Android TV 测试包，安装后自动导入 Windows 的加密配置与刮削资料，并同步生成 Windows 2.1.146 测试版安装器。

**Architecture:** 构建脚本把工作区外的 `.kyyconfig`、`.kyymeta` 和清单临时复制到 Flutter 资源目录，并通过 `--dart-define` 传入自动导入密码；构建结束始终清理个人资源。TV 启动阶段由独立预置导入服务读取清单、校验哈希、先导入配置再刷新媒体源和导入刮削资料，用 Hive 保存清单哈希实现幂等；普通构建使用禁用清单，完全跳过该流程。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX/Hive、现有 `ConfigurationTransferService`、`ScrapedMetadataTransferService`、PowerShell、Android `tvTest` flavor、Windows Inno Setup。

---

### Task 1: 预置资源清单与安全读取边界

**Files:**
- Create: `lib/features/tv_preload/domain/tv_preload_manifest.dart`
- Create: `lib/features/tv_preload/data/tv_preload_asset_reader.dart`
- Create: `assets/tv_preload/manifest.json`
- Modify: `pubspec.yaml:157-160`
- Modify: `.gitignore`
- Test: `test/tv_preload_manifest_test.dart`

- [ ] **Step 1: Write failing manifest tests**

覆盖以下断言：禁用清单返回 `enabled == false`；启用清单必须包含固定的配置/资料资源路径、字节数和 64 位小写 SHA-256；路径不是清单允许路径、大小为负数、哈希格式错误或未知版本抛出 `TvPreloadManifestException`；清单对象的 `toString` 不包含任何秘密字段。

- [ ] **Step 2: Run the focused test and confirm failure**

Run: `D:\flutter\bin\flutter.bat test test/tv_preload_manifest_test.dart`

Expected: FAIL because the manifest model and asset reader do not exist.

- [ ] **Step 3: Implement the model and reader**

`TvPreloadManifest` 使用 `enabled`、`version`、`configurationAsset`、`metadataAsset`、`configurationBytes`、`metadataBytes`、`configurationSha256`、`metadataSha256` 字段；`fromJson` 只接受版本 `1` 和资源前缀 `assets/tv_preload/`。定义 `TvPreloadAssetPort` 的 `readManifest()` 与 `copyVerifiedAsset({required String assetPath, required int expectedBytes, required String expectedSha256, required String fileName})` 接口，`TvPreloadAssetReader` 使用 `rootBundle.load`、`crypto` 的流式 SHA-256 和 `getTemporaryDirectory` 实现接口，复制失败时删除半成品。

`assets/tv_preload/manifest.json` 固定为 `{"enabled":false,"version":1}`。在 `pubspec.yaml` 声明 `assets/tv_preload/`；在 `.gitignore` 忽略 `configuration.kyyconfig`、`metadata.kyymeta` 和除禁用清单外的生成文件。

- [ ] **Step 4: Run the focused test and confirm pass**

Run: `D:\flutter\bin\flutter.bat test test/tv_preload_manifest_test.dart`

Expected: all manifest parsing, path validation, hash validation and cleanup tests pass.

- [ ] **Step 5: Commit the isolated resource boundary**

```powershell
git add -- lib/features/tv_preload/domain/tv_preload_manifest.dart lib/features/tv_preload/data/tv_preload_asset_reader.dart assets/tv_preload/manifest.json pubspec.yaml .gitignore test/tv_preload_manifest_test.dart
git commit -m "feat(tv): 增加个人预置资源清单"
```

### Task 2: TV 启动自动导入协调器

**Files:**
- Create: `lib/features/tv_preload/application/tv_preload_import_service.dart`
- Create: `lib/features/tv_preload/application/tv_preload_import_ports.dart`
- Modify: `lib/features/settings/application/typed_settings.dart:40-106`
- Modify: `lib/app/bindings/app_bindings.dart`
- Modify: `lib/pages/init_page.dart`
- Test: `test/tv_preload_import_service_test.dart`
- Test: `test/init_page_test.dart`

- [ ] **Step 1: Write failing service tests**

使用内存 fake 资源读取器、配置导入端口、刮削资料导入端口和媒体源刷新端口，验证严格调用顺序为 `readManifest -> copy config -> configuration.apply -> loadSources -> scanEnabledSources -> copy metadata -> metadata.apply -> save marker`；配置失败时不刷新媒体源、不导入资料且不写成功标记；单个网盘扫描失败和资料部分匹配均返回 `partial` 并保存结果；同一清单哈希第二次直接返回 `skipped`。

- [ ] **Step 2: Run the focused tests and confirm failure**

Run: `D:\flutter\bin\flutter.bat test test/tv_preload_import_service_test.dart test/init_page_test.dart`

Expected: FAIL because the coordinator, settings key and startup hook do not exist.

- [ ] **Step 3: Implement the coordinator**

在 `tv_preload_import_ports.dart` 定义 `TvPreloadConfigurationPort.importEncrypted(File, password)`、`TvPreloadMetadataPort.importArchive(File)` 和 `TvPreloadMediaRefreshPort.loadAndScanEnabledSources()`，并用小型适配器分别调用现有 `ConfigurationTransferService`、`ScrapedMetadataTransferService` 与 `CloudLibraryController`。网盘刷新端口先 `load()`，再对已启用且已有媒体根目录的来源逐个执行 `scanSource`；单个来源失败只记录来源 ID 和错误类别，不记录凭据。

`TvPreloadImportService.run()` 只在 `AppPlatformCapabilities.isAndroidTv`、清单启用且 `const String.fromEnvironment('KYY_TV_PRELOAD_PASSWORD')` 非空时执行。它先验证资源，再调用配置端口、媒体刷新端口和资料端口；密码只传给配置端口，不进入异常文本或日志。Hive 使用 `SettingBoxKey.tvPreloadManifestHash`、`tvPreloadLastResult` 和 `tvPreloadLastError` 保存状态；结果类型明确区分 `skipped`、`success`、`partial`、`failed`。

在 `registerApplicationBindings` 注册该服务，并在 `runInitStartupSequence` 增加可选的 `runPreloadedImport` 回调，放在着色器准备后、默认路由前执行。异常只记录不含秘密的错误代码，并允许应用继续启动；初始化页在 TV 端显示一次短暂的“正在导入 Windows 配置和刮削资料”状态。

- [ ] **Step 4: Run focused tests and confirm pass**

Run: `D:\flutter\bin\flutter.bat test test/tv_preload_import_service_test.dart test/init_page_test.dart`

Expected: all sequence, failure isolation, idempotency and startup-continuation tests pass.

- [ ] **Step 5: Commit the runtime importer**

```powershell
git add -- lib/features/tv_preload/application/tv_preload_import_service.dart lib/features/tv_preload/application/tv_preload_import_ports.dart lib/features/settings/application/typed_settings.dart lib/app/bindings/app_bindings.dart lib/pages/init_page.dart test/tv_preload_import_service_test.dart test/init_page_test.dart
git commit -m "feat(tv): 启动时自动导入个人预置资料"
```

### Task 3: 个人 TV 构建入口与临时资源清理

**Files:**
- Create: `tool/android/build_personal_tv.ps1`
- Create: `tool/tv_preload/validate_and_write_manifest.dart`
- Modify: `tool/android/build_signed_release.ps1`
- Test: `test/tv_personal_build_contract_test.dart`

- [ ] **Step 1: Write failing build contract tests**

读取脚本文本确认它要求 `-ConfigurationPath`、`-MetadataPath`、`KYY_CONFIG_PASSWORD`，只调用 `tvTest`、传入 `KYY_TV_PRELOAD_PASSWORD`、使用 `try/finally` 清理 `assets/tv_preload/configuration.kyyconfig` 和 `assets/tv_preload/metadata.kyymeta`，并拒绝缺失输入、错误扩展名或空密码。测试还确认正常 `build_tv_test.ps1` 不需要个人文件。

- [ ] **Step 2: Run the contract test and confirm failure**

Run: `D:\flutter\bin\flutter.bat test test/tv_personal_build_contract_test.dart`

Expected: FAIL because the personal build entry and validation helper do not exist.

- [ ] **Step 3: Implement build-time validation and packaging**

`validate_and_write_manifest.dart` 接收三个路径参数和进程环境密码，使用 `ConfigurationArchiveCodec.decrypt` 验证密码，使用 `sha256.bind(file.openRead())` 计算哈希，并只写清单 JSON；不输出配置内容、密码或解密明文。

`build_personal_tv.ps1` 从当前 `pubspec.yaml` 读取版本，要求环境变量 `KYY_CONFIG_PASSWORD` 非空，复制两个文件到预置资源目录，调用 `dart run tool/tv_preload/validate_and_write_manifest.dart`，再在内存中构造 `$dartDefines = @("KYY_TV_PRELOAD_PASSWORD=$password")` 并调用 `build_signed_release.ps1 -Flavor tvTest -ApkOnly -DartDefines $dartDefines`。脚本用 `"$appName-$version-TV个人预置测试版.apk"` 作为桌面文件名，在 `finally` 删除个人资源、清理环境变量，并输出版本、文件大小和 SHA-256。`build_signed_release.ps1` 增加可选 `-DartDefines` 参数并把它传给 APK/AAB Flutter build；默认调用不变。

- [ ] **Step 4: Run the contract test and a negative build check**

Run: `D:\flutter\bin\flutter.bat test test/tv_personal_build_contract_test.dart`

Then run with a temporary missing file path and no password:

```powershell
& .\tool\android\build_personal_tv.ps1 -ConfigurationPath "$env:TEMP\missing.kyyconfig" -MetadataPath "$env:TEMP\missing.kyymeta"
```

Expected: the command fails before Flutter compilation and the generated resource directory contains only the tracked disabled manifest.

- [ ] **Step 5: Commit the personal build tooling**

```powershell
git add -- tool/android/build_personal_tv.ps1 tool/tv_preload/validate_and_write_manifest.dart tool/android/build_signed_release.ps1 test/tv_personal_build_contract_test.dart
git commit -m "build(tv): 增加个人预置包构建入口"
```

### Task 4: 版本、用户文案和验收记录

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `README.md`
- Modify: `docs/android-tv-test-report.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/release_config_contract_test.dart`
- Modify: `test/android_tv_release_contract_test.dart`
- Modify: `test/android_tv_acceptance_contract_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: Add the 2.1.146 release entry**

Set `version: 2.1.146+20146` and `msix_version: 2.1.146.0` for historical compatibility. Update the current version constants, release notes, update dialog copy and version history with user-facing text explaining the personal TV preload, automatic first-start import, retry/partial-match behavior and the fact that the package is not for public distribution.

- [ ] **Step 2: Update contract fixtures and tests**

Replace only the current-version assertions from `2.1.145/20145` to `2.1.146/20146`; add a contract assertion that the normal TV manifest is disabled and the personal APK filename contains `TV个人预置测试版`.

- [ ] **Step 3: Run version and focused regression tests**

Run: `D:\flutter\bin\flutter.bat test test/version_consistency_test.dart test/release_config_contract_test.dart test/android_tv_release_contract_test.dart test/android_tv_acceptance_contract_test.dart test/identity_v2_zero_residue_test.dart test/version_history_current_test.dart`

Expected: all tests pass and no test reads or embeds the private password.

- [ ] **Step 4: Commit the version and release documentation**

```powershell
git add -- pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md UPDATE_DIALOG_COPY.md README.md docs/android-tv-test-report.md test/version_consistency_test.dart test/release_config_contract_test.dart test/android_tv_release_contract_test.dart test/android_tv_acceptance_contract_test.dart test/identity_v2_zero_residue_test.dart test/version_history_current_test.dart
git commit -m "chore(release): 更新个人 TV 预置包版本"
```

### Task 5: Full verification and package delivery

**Files:**
- Verify: `build/app/outputs/flutter-apk/app-tvTest-release.apk`
- Verify: `C:/Users/asus/Desktop/看影音-2.1.146-TV个人预置测试版.apk`
- Verify: `C:/Users/asus/Desktop/看影音-2.1.146-测试版-安装程序.exe`
- Modify: `docs/android-tv-test-report.md`

- [ ] **Step 1: Run static analysis, formatting and all tests**

Run:

```powershell
& D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test tool
& D:\flutter\bin\flutter.bat analyze
& D:\flutter\bin\flutter.bat test
git diff --check
```

Expected: format reports zero changed files, Analyze reports `No issues found!`, and the complete suite reports `All tests passed!`.

- [ ] **Step 2: Build the personal TV APK with the password only in the process environment**

Run in the same PowerShell process after the build operator has set the secret environment variable, without printing it:

```powershell
if ([string]::IsNullOrWhiteSpace($env:KYY_CONFIG_PASSWORD)) { throw '缺少个人配置构建密码' }
& .\tool\android\build_personal_tv.ps1 -ConfigurationPath 'C:\Users\asus\Desktop\看影音配置-20260807.kyyconfig' -MetadataPath 'C:\Users\asus\Desktop\看影音刮削资料-20260807.kyymeta'
```

Expected: config password validation succeeds, APK version is `2.1.146`, package is `com.kanyingyin.player.tvtest`, the personal resources are removed after build, and the desktop APK hash equals the build APK hash.

- [ ] **Step 3: Build Windows Release and Inno EXE**

Run: `& .\tool\windows\build_exe_release.ps1`

Expected: Release `kanyingyin.exe` and Inno installer product versions report `2.1.146`; no MSIX is generated or delivered.

- [ ] **Step 4: Update the report with fresh evidence**

Record APK and installer sizes, SHA-256 values, `aapt` versionName/versionCode, signing summary, Windows product version and the fact that ADB/Hisense real-device acceptance remains pending. Do not record the password or private resource contents.

- [ ] **Step 5: Final clean-state check and commit**

Run:

```powershell
git status --short
git diff --check
git diff --stat
```

Expected: only the intended source, tests and documentation are staged; no generated personal resource or secret file is present. Commit with `feat(tv): 打包个人配置与刮削资料测试版`.
