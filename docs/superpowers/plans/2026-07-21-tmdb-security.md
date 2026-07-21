# TMDB 网络与凭据安全 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将用户 TMDB 凭据迁移到系统安全存储，只向官方 TMDB 域名发送凭据，并保持私人构建流程可用。

**Architecture:** 新增内存缓存型 `TmdbCredentialManager`，启动时从安全存储读取并迁移 Hive 旧值，现有同步 `TmdbApiKeyProvider` 读取内存值；设置页通过管理器异步保存。私人构建不再读取应用 Hive，而从当前用户保护的 SecureString 文件导出临时构建参数。

**Tech Stack:** Flutter、Dart、flutter_secure_storage、Hive CE、Dio、PowerShell 5.1、flutter_test。

---

### Task 1: TMDB 凭据管理器

**Files:**
- Create: `lib/services/tmdb/tmdb_credential_manager.dart`
- Create: `test/tmdb_credential_manager_test.dart`

- [ ] **Step 1: 写入迁移优先级和失败回退测试**

测试必须覆盖：安全值优先、旧 Hive 值迁移后删除、安全写入失败保留旧值、保存新值、清空新旧值。使用内存存储和回调，不调用平台插件。

```dart
final store = MemoryTmdbCredentialStore();
var legacy = ' legacy-key ';
final manager = TmdbCredentialManager(
  store: store,
  legacyReader: () => legacy,
  legacyDelete: () async => legacy = '',
);
await manager.initialize();
expect(manager.read(), 'legacy-key');
expect(await store.read(), 'legacy-key');
expect(legacy, isEmpty);
```

失败存储通过实现 `TmdbCredentialStore` 的测试替身抛出 `FileSystemException`，断言 `initialize()` 不抛出且继续返回旧值。

- [ ] **Step 2: 运行测试并确认缺少实现**

```powershell
D:\flutter\bin\flutter.bat test test/tmdb_credential_manager_test.dart
```

预期：FAIL，找不到凭据管理器。

- [ ] **Step 3: 实现管理器与安全存储**

创建接口、Windows 安全存储实现和内存实现：

```dart
abstract interface class TmdbCredentialStore {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureTmdbCredentialStore implements TmdbCredentialStore {
  SecureTmdbCredentialStore({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const key = 'kanyingyin_tmdb_credential_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: key);

  @override
  Future<void> write(String value) => _storage.write(key: key, value: value);

  @override
  Future<void> delete() => _storage.delete(key: key);
}
```

`TmdbCredentialManager.initialize()` 先读安全存储；没有安全值时读取旧值，先把旧值放入内存，再尝试写安全存储并删除旧值。任何安全存储异常只记录不含凭据的警告，不向启动流程抛出。`save()` 成功写安全存储后更新内存并尽力删除旧值；空字符串删除新旧存储。

- [ ] **Step 4: 运行凭据测试**

```powershell
D:\flutter\bin\flutter.bat test test/tmdb_credential_manager_test.dart test/tmdb_api_key_provider_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/tmdb/tmdb_credential_manager.dart test/tmdb_credential_manager_test.dart
git commit -m "新增TMDB安全凭据管理"
```

### Task 2: 接入启动、模块和设置页

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/app_module.dart`
- Modify: `lib/pages/index_module.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `lib/pages/settings/tmdb_settings.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/services/poster_service.dart`
- Modify: `test/tmdb_settings_language_test.dart`
- Modify: `test/app_widget_lifecycle_test.dart`

- [ ] **Step 1: 写入设置页使用管理器的失败测试**

在 `test/tmdb_settings_language_test.dart` 初始化内存管理器并注入页面。新增测试：保存用户输入后安全存储收到新值，Hive 不再包含 `tmdbApiKey`；清空输入后安全存储为空。

```dart
final store = MemoryTmdbCredentialStore();
final manager = TmdbCredentialManager(
  store: store,
  legacyReader: () => '',
  legacyDelete: () => GStorage.setting.delete('tmdbApiKey'),
);
await manager.initialize();
final provider = TmdbApiKeyProvider(userKeyReader: manager.read);
await tester.pumpWidget(MaterialApp(
  home: TmdbSettingsPage(
    credentialManager: manager,
    apiKeyProvider: provider,
  ),
));
```

- [ ] **Step 2: 运行设置页测试并确认构造参数缺失**

```powershell
D:\flutter\bin\flutter.bat test test/tmdb_settings_language_test.dart
```

预期：FAIL，`TmdbSettingsPage` 不接受 `credentialManager`。

- [ ] **Step 3: 在启动时初始化管理器**

`main.dart` 在 `GStorage.init()` 后创建并初始化：

```dart
final tmdbCredentialManager = TmdbCredentialManager(
  store: SecureTmdbCredentialStore(),
  legacyReader: () => GStorage.setting
      .get('tmdbApiKey', defaultValue: '')
      .toString(),
  legacyDelete: () => GStorage.setting.delete('tmdbApiKey'),
);
await tmdbCredentialManager.initialize();
```

将管理器传入 `AppModule`，再传入 `IndexModule`。`IndexModule.binds` 注册同一实例，并让 `TmdbApiKeyProvider` 使用 `manager.read`。

- [ ] **Step 4: 设置页异步保存安全值**

`TmdbSettingsPage` 增加必需的 `TmdbCredentialManager credentialManager`。控制器初值读取 `manager.read()`；`_save()` 先调用 `await manager.save(...)`，失败显示“TMDB 凭据保存失败，请稍后重试”并不显示异常详情。自动刮削与刮削选项仍保存在 Hive。

`SettingsModule` 路由通过 `Modular.get` 注入管理器和 Provider。

- [ ] **Step 5: 删除运行时直接读取 Hive Key 的回退**

删除 `IndexModule._readTmdbUserApiKey`、`LocalController._readStoredTmdbUserKey` 和 `PosterService._readUserApiKey`。测试或非模块默认实例使用只包含构建时值的 Provider：

```dart
TmdbApiKeyProvider(userKeyReader: () => '')
```

- [ ] **Step 6: 运行启动、设置和本地控制器测试**

```powershell
D:\flutter\bin\flutter.bat test test/tmdb_settings_language_test.dart test/tmdb_api_key_provider_test.dart test/app_widget_lifecycle_test.dart test/local_controller_test.dart
```

预期：PASS。

- [ ] **Step 7: 提交**

```powershell
git add lib/main.dart lib/app_module.dart lib/pages/index_module.dart lib/pages/settings/settings_module.dart lib/pages/settings/tmdb_settings.dart lib/pages/local/local_controller.dart lib/services/poster_service.dart test/tmdb_settings_language_test.dart test/app_widget_lifecycle_test.dart
git commit -m "接入TMDB安全凭据迁移"
```

### Task 3: 只使用官方 TMDB API

**Files:**
- Modify: `lib/services/poster_service.dart`
- Modify: `test/poster_service_download_test.dart`

- [ ] **Step 1: 写入官方端点失败测试**

使用自定义 Dio `HttpClientAdapter` 记录请求。让 `/configuration` 返回连接错误，调用海报搜索后断言所有请求的 host 都是 `api.themoviedb.org`，且没有请求 `lsmcloud.cc` 或 `api.tmdb.org`。

- [ ] **Step 2: 运行测试并确认现状会请求回退域名**

```powershell
D:\flutter\bin\flutter.bat test test/poster_service_download_test.dart --plain-name "TMDB 主站失败时不向非官方域名发送凭据"
```

预期：FAIL，记录中包含非官方 host。

- [ ] **Step 3: 删除代理列表和回退循环**

`PosterService` 只保留 `_baseUrl`。`_ensureBaseUrl` 请求官方 `/configuration`，失败直接返回 `null`；移除 `_proxies`、`_workingProxy` 切换逻辑和异常后的代理重置。

- [ ] **Step 4: 运行海报与本地 TMDB 测试**

```powershell
D:\flutter\bin\flutter.bat test test/poster_service_download_test.dart test/local_poster_scraper_test.dart test/local_tmdb_integration_test.dart
```

预期：PASS。

- [ ] **Step 5: 提交**

```powershell
git add lib/services/poster_service.dart test/poster_service_download_test.dart
git commit -m "限制TMDB请求到官方端点"
```

### Task 4: 保持私人构建可用

**Files:**
- Modify: `tool/export_tmdb_build_define.dart`
- Modify: `tool/windows/build_private_release.ps1`
- Modify: `test/private_release_packaging_test.dart`

- [ ] **Step 1: 写入导出器行为失败测试**

测试临时输出文件，直接调用公开的 `exportTmdbBuildDefine(key:, outputPath:)`，断言 JSON 只包含 `KANYINGYIN_TMDB_API_KEY` 且日志不包含 Key。再断言空 Key 抛出状态错误。

- [ ] **Step 2: 重构导出器输入**

移除 Hive 依赖和 `--hive-directory`。CLI 从环境变量 `KANYINGYIN_TMDB_PRIVATE_BUILD_KEY` 读取 Key，只接受 `--output`。公开函数：

```dart
Future<void> exportTmdbBuildDefine({
  required String key,
  required String outputPath,
}) async {
  final normalized = key.trim();
  if (normalized.isEmpty) throw StateError('TMDB Key 不能为空');
  final output = File(outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsString(
    jsonEncode(<String, String>{
      'KANYINGYIN_TMDB_API_KEY': normalized,
    }),
    encoding: utf8,
    flush: true,
  );
}
```

- [ ] **Step 3: 私人脚本从用户保护文件读取 Key**

在签名目录增加 `tmdb-api-key.clixml`，格式与签名密码一样为当前用户可解密的 SecureString。脚本导入后临时设置 `KANYINGYIN_TMDB_PRIVATE_BUILD_KEY` 环境变量，运行导出器后立即删除环境变量；`finally` 中清零两个 BSTR 指针和明文变量。

- [ ] **Step 4: 运行私人打包测试**

```powershell
D:\flutter\bin\flutter.bat test test/private_release_packaging_test.dart
```

预期：PASS，临时 JSON 不进入 ZIP，脚本和输出不包含 Key。

- [ ] **Step 5: 提交**

```powershell
git add tool/export_tmdb_build_define.dart tool/windows/build_private_release.ps1 test/private_release_packaging_test.dart
git commit -m "更新私人构建密钥输入"
```

### Task 5: 第二批完整验证

**Files:**
- Verify only

- [ ] **Step 1: 格式检查**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed .
```

- [ ] **Step 2: 完整测试与分析**

```powershell
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

- [ ] **Step 3: Windows Release 构建**

```powershell
D:\flutter\bin\flutter.bat build windows --release
```

预期：全部命令 exit code 0；工作区只保留用户原有 `.learnings` 修改。
