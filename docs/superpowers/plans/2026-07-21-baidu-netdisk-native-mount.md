# 百度网盘原生挂载实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在看影音中增加官方 OAuth 的百度网盘只读来源，复用现有媒体库与 TMDB 能力，通过通用本机 Range 中转播放原文件，并交付带内置默认 TMDB Key 的 2.1.28 签名 MSIX 与异机安装 ZIP。

**Architecture:** 百度以 `CloudProviderRegistry` 中的独立提供方接入，`fs_id` 作为远程身份，OAuth 与令牌刷新封装在百度专属服务中。现有夸克 Range 中转被提取为提供方无关的公共层，夸克和百度分别提供安全的远程读取器；媒体索引、作品树、TMDB、海报墙和选集不复制。私人构建通过临时 `dart-define` 文件注入默认 TMDB Key，异机安装包仅包含签名 MSIX、公钥证书和验证后安装脚本。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、Dio、`dart:io`、Hive CE、flutter_secure_storage、media_kit/MPV、PowerShell、Windows MSIX/SignTool。

**执行约束:** 用户已明确禁止子代理，实施时只能使用 `superpowers:executing-plans` 在当前任务内执行。真实百度 API Key、Secret、令牌和 TMDB Key 不得出现在聊天、Git、测试输出或普通日志中。

---

## 文件结构

### 新增生产文件

- `lib/services/cloud/baidu/baidu_models.dart`：百度强类型账号、令牌、目录页和文件详情模型。
- `lib/services/cloud/baidu/baidu_response_parser.dart`：严格解析官方 JSON 和错误码。
- `lib/services/cloud/baidu/baidu_request_policy.dart`：官方 API 地址、下载重定向与敏感参数策略。
- `lib/services/cloud/baidu/baidu_oauth_client.dart`：授权 URL、授权码交换和令牌刷新。
- `lib/services/cloud/baidu/baidu_api_client.dart`：账号、目录分页和文件详情请求。
- `lib/services/cloud/baidu/baidu_drive_client.dart`：实现 `CloudDriveClient`。
- `lib/services/cloud/baidu/baidu_authorization_controller.dart`：编辑页授权会话、账号验证和临时凭据状态。
- `lib/services/cloud/baidu/baidu_range_remote_reader.dart`：百度 `dlink` 的安全分段读取与一次刷新。
- `lib/pages/cloud/baidu/baidu_source_editor.dart`：百度来源编辑与 OAuth 授权界面。
- `lib/pages/cloud/baidu/baidu_directory_picker.dart`：基于 `fs_id` 的多目录选择器。
- `lib/services/cloud/range/cloud_range_relay_protocol.dart`：HTTP 单 Range 解析。
- `lib/services/cloud/range/cloud_range_remote_reader.dart`：公共远程读取接口和错误类型。
- `lib/services/cloud/range/cloud_range_chunk_cache.dart`：通用 16 MiB/256 MiB LRU 缓存。
- `lib/services/cloud/range/cloud_range_relay_session.dart`：本机 HTTP、预取、调度与状态。
- `lib/services/cloud/range/cloud_range_relay_service.dart`：会话目录、租约和孤立缓存清理。
- `lib/pages/video/cloud_relay_status_presenter.dart`：提供方无关的播放状态文案。
- `lib/services/tmdb/tmdb_api_key_provider.dart`：用户 Key 与内置默认 Key 的统一读取。
- `tool/export_tmdb_build_define.dart`：从当前用户 Hive 设置导出临时 `dart-define` JSON，不打印 Key。
- `tool/windows/build_private_release.ps1`：Release、签名 MSIX、证书和 ZIP 的私密构建入口。
- `tool/windows/installer/安装看影音.ps1`：异机预检、导入公钥和安装。
- `tool/windows/installer/安装看影音.cmd`：一键调用 PowerShell。
- `tool/windows/installer/安装说明.txt`：UTF-8 私人安装说明。

### 新增测试与夹具

- `test/baidu_oauth_client_test.dart`
- `test/baidu_response_parser_test.dart`
- `test/baidu_api_client_test.dart`
- `test/baidu_drive_client_test.dart`
- `test/baidu_authorization_controller_test.dart`
- `test/baidu_source_editor_test.dart`
- `test/baidu_range_remote_reader_test.dart`
- `test/cloud_range_relay_protocol_test.dart`
- `test/cloud_range_chunk_cache_test.dart`
- `test/cloud_range_relay_session_test.dart`
- `test/cloud_range_relay_service_test.dart`
- `test/cloud_relay_status_ui_test.dart`
- `test/tmdb_api_key_provider_test.dart`
- `test/private_release_packaging_test.dart`
- `test/fixtures/baidu/account_success.json`
- `test/fixtures/baidu/token_success.json`
- `test/fixtures/baidu/directory_page_1.json`
- `test/fixtures/baidu/directory_empty.json`
- `test/fixtures/baidu/filemetas_success.json`

### 主要修改文件

- `lib/modules/cloud/cloud_source.dart`
- `lib/services/cloud/cloud_credential_store.dart`
- `lib/services/cloud/cloud_drive_client.dart`
- `lib/services/cloud/cloud_provider_registry.dart`
- `lib/services/cloud/cloud_playback_transport.dart`
- `lib/services/cloud/cloud_playback_resolver.dart`
- `lib/services/cloud/cloud_cache_directories.dart`
- `lib/services/cloud/quark/quark_range_remote_reader.dart`
- `lib/services/cloud/quark/quark_range_relay_service.dart`
- `lib/services/cloud/quark/quark_drive_client.dart`
- `lib/features/player/application/cloud_playback_cache_policy.dart`
- `lib/pages/video/video_page.dart`
- `lib/pages/settings/cloud_sources_settings.dart`
- `lib/pages/settings/settings_module.dart`
- `lib/pages/settings/tmdb_settings.dart`
- `lib/pages/index_module.dart`
- `lib/pages/local/local_controller.dart`
- `lib/services/poster_service.dart`
- `pubspec.yaml`
- `README.md`
- `RELEASE_NOTES.md`
- `UPDATE_DIALOG_COPY.md`
- `lib/core/app_version.dart`
- `lib/utils/version_history.dart`

---

### Task 1: 扩展来源类型与安全凭据模型

**Files:**
- Modify: `lib/modules/cloud/cloud_source.dart`
- Modify: `lib/services/cloud/cloud_credential_store.dart`
- Modify: `lib/services/cloud/cloud_provider_registry.dart`
- Modify: `test/cloud_source_repository_test.dart`
- Modify: `test/cloud_library_controller_test.dart`
- Modify: `test/cloud_provider_registry_test.dart`

- [ ] **Step 1: 写百度来源和凭据兼容的失败测试**

在 `test/cloud_provider_registry_test.dart` 增加：

```dart
test('百度来源固定使用官方地址且不支持分享写操作', () {
  final registry = CloudProviderRegistry();
  const source = CloudSource(
    id: 'baidu-a',
    type: CloudSourceType.baidu,
    name: '百度网盘',
    baseUrl: 'https://example.invalid',
    rootPaths: <String>[],
  );

  expect(registry.providerName(CloudSourceType.baidu), '百度网盘');
  expect(registry.normalizeSource(source).baseUrl, 'https://pan.baidu.com');
  expect(registry.supportsShareTransfer(CloudSourceType.baidu), isFalse);
});

test('百度凭据更新密钥时清除旧令牌', () {
  final registry = CloudProviderRegistry();
  const source = CloudSource(
    id: 'baidu-a',
    type: CloudSourceType.baidu,
    name: '百度网盘',
    baseUrl: 'https://pan.baidu.com',
    rootPaths: <String>[],
  );
  const existing = CloudCredential(
    clientId: 'old-id',
    clientSecret: 'old-secret',
    accessToken: 'old-access',
    refreshToken: 'old-refresh',
  );

  final merged = registry.mergeCredential(
    source: source,
    form: const CloudCredential(
      clientId: 'new-id',
      clientSecret: 'new-secret',
    ),
    existing: existing,
    endpointUnchanged: true,
  );

  expect(merged.clientId, 'new-id');
  expect(merged.accessToken, isNull);
  expect(merged.refreshToken, isNull);
});
```

在 `test/cloud_source_repository_test.dart` 增加百度 JSON 往返断言，并在 `test/cloud_library_controller_test.dart` 增加“多个百度来源凭据互不覆盖”的测试。

- [ ] **Step 2: 运行测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_provider_registry_test.dart test/cloud_source_repository_test.dart test/cloud_library_controller_test.dart
```

Expected: 编译失败，提示 `CloudSourceType.baidu`、`clientId` 或 `accessToken` 不存在。

- [ ] **Step 3: 实现来源枚举与强类型凭据字段**

将枚举改为：

```dart
enum CloudSourceType { openList, quark, baidu }
```

扩展 `CloudCredential`：

```dart
class CloudCredential {
  const CloudCredential({
    this.username,
    this.password,
    this.cookie,
    this.token,
    this.clientId,
    this.clientSecret,
    this.accessToken,
    this.refreshToken,
    this.accessTokenExpiresAt,
  });

  final String? username;
  final String? password;
  final String? cookie;
  final String? token;
  final String? clientId;
  final String? clientSecret;
  final String? accessToken;
  final String? refreshToken;
  final DateTime? accessTokenExpiresAt;
}
```

同步更新 `isEmpty`、`toJson` 和 `fromJson`；`toString()` 继续只返回 `CloudCredential(<redacted>)`。在注册器中加入百度名称、固定地址、错误文案和凭据合并。百度凭据只有在 API Key 与 Secret 均未变化时保留令牌。

- [ ] **Step 4: 运行目标测试和旧来源迁移测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_provider_registry_test.dart test/cloud_source_repository_test.dart test/cloud_library_controller_test.dart test/cloud_remote_ref_test.dart
```

Expected: 全部通过；旧 OpenList/夸克 JSON 仍可读取。

- [ ] **Step 5: 提交基础模型**

```powershell
git add lib/modules/cloud/cloud_source.dart lib/services/cloud/cloud_credential_store.dart lib/services/cloud/cloud_provider_registry.dart test/cloud_provider_registry_test.dart test/cloud_source_repository_test.dart test/cloud_library_controller_test.dart
git commit -m "增加百度网盘来源模型"
```

---

### Task 2: 实现百度 OAuth 授权与刷新

**Files:**
- Create: `lib/services/cloud/baidu/baidu_models.dart`
- Create: `lib/services/cloud/baidu/baidu_oauth_client.dart`
- Create: `test/baidu_oauth_client_test.dart`
- Create: `test/fixtures/baidu/token_success.json`

- [ ] **Step 1: 写授权 URL、令牌交换和刷新单飞的失败测试**

测试固定以下行为：

```dart
test('授权地址使用 oob、basic netdisk 和当前 state', () {
  final client = BaiduOAuthClient(
    clientId: 'client-id',
    clientSecret: 'client-secret',
    dio: Dio(),
  );
  final uri = client.buildAuthorizationUri(state: 'state-123');

  expect(uri.host, 'openapi.baidu.com');
  expect(uri.queryParameters['response_type'], 'code');
  expect(uri.queryParameters['redirect_uri'], 'oob');
  expect(uri.queryParameters['scope'], 'basic,netdisk');
  expect(uri.queryParameters['state'], 'state-123');
});

test('并发刷新只请求一次并原子返回新令牌', () async {
  final adapter = _TokenAdapter();
  final client = BaiduOAuthClient(
    clientId: 'client-id',
    clientSecret: 'client-secret',
    dio: Dio()..httpClientAdapter = adapter,
  );

  final results = await Future.wait(<Future<BaiduOAuthTokens>>[
    client.refresh('refresh-old'),
    client.refresh('refresh-old'),
  ]);

  expect(adapter.requestCount, 1);
  expect(results.map((value) => value.refreshToken).toSet(), {'refresh-new'});
});
```

令牌夹具只使用 `access-fixture`、`refresh-fixture` 和固定过期秒数。

- [ ] **Step 2: 运行测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_oauth_client_test.dart
```

Expected: 编译失败，提示 `BaiduOAuthClient` 与 `BaiduOAuthTokens` 不存在。

- [ ] **Step 3: 实现 OAuth 客户端**

核心接口固定为：

```dart
class BaiduOAuthClient {
  BaiduOAuthClient({
    required this.clientId,
    required this.clientSecret,
    required Dio dio,
    DateTime Function()? now,
  });

  final String clientId;
  final String clientSecret;

  Uri buildAuthorizationUri({required String state});

  Future<BaiduOAuthTokens> exchangeCode(String code);

  Future<BaiduOAuthTokens> refresh(String refreshToken);
}

class BaiduOAuthTokens {
  const BaiduOAuthTokens({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.scopes,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final Set<String> scopes;
}
```

`exchangeCode` 请求 `grant_type=authorization_code`、`redirect_uri=oob`；`refresh` 请求 `grant_type=refresh_token`。响应缺少 `netdisk`、Access Token、Refresh Token 或正数 `expires_in` 时抛出 `CloudDriveException(CloudDriveErrorType.incompatible)`。Dio 错误响应映射为鉴权、网络、超时或限流，不包含响应中的令牌值。

- [ ] **Step 4: 运行 OAuth 与脱敏测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_oauth_client_test.dart test/log_sanitizer_test.dart
```

Expected: 全部通过，测试输出不含夹具令牌。

- [ ] **Step 5: 提交 OAuth 层**

```powershell
git add lib/services/cloud/baidu/baidu_models.dart lib/services/cloud/baidu/baidu_oauth_client.dart test/baidu_oauth_client_test.dart test/fixtures/baidu/token_success.json
git commit -m "实现百度网盘 OAuth 授权"
```

---

### Task 3: 实现百度账号、目录与文件详情协议

**Files:**
- Create: `lib/services/cloud/baidu/baidu_request_policy.dart`
- Create: `lib/services/cloud/baidu/baidu_response_parser.dart`
- Create: `lib/services/cloud/baidu/baidu_api_client.dart`
- Create: `test/baidu_response_parser_test.dart`
- Create: `test/baidu_api_client_test.dart`
- Create: `test/fixtures/baidu/account_success.json`
- Create: `test/fixtures/baidu/directory_page_1.json`
- Create: `test/fixtures/baidu/directory_empty.json`
- Create: `test/fixtures/baidu/filemetas_success.json`

- [ ] **Step 1: 写解析与分页失败测试**

固定模型与分页行为：

```dart
test('目录响应保留 fs_id、路径、大小和目录类型', () {
  final page = const BaiduResponseParser().parseDirectoryPage(<String, Object?>{
    'errno': 0,
    'list': <Object?>[
      <String, Object?>{
        'fs_id': 1001,
        'path': '/影视/示例.mkv',
        'server_filename': '示例.mkv',
        'size': 4096,
        'isdir': 0,
        'server_mtime': 1700000000,
      },
    ],
  });

  expect(page.entries.single.fsId, '1001');
  expect(page.entries.single.path, '/影视/示例.mkv');
  expect(page.entries.single.isDirectory, isFalse);
});

test('重复页游标不前进时报告接口不兼容', () async {
  final client = _fixtureClient(repeatFirstPage: true);
  await expectLater(
    client.listDirectory(const CloudRemoteRef(id: '0', path: '/')),
    throwsA(isA<CloudDriveException>().having(
      (value) => value.type,
      'type',
      CloudDriveErrorType.incompatible,
    )),
  );
});
```

文件详情测试要求 `dlink=1`、`fsids` 为 JSON 数组，并校验返回文件的 `fs_id` 与请求一致。

- [ ] **Step 2: 运行协议测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_response_parser_test.dart test/baidu_api_client_test.dart
```

Expected: 编译失败，提示百度解析器与 API 客户端不存在。

- [ ] **Step 3: 实现严格解析和官方请求**

请求入口固定为：

```dart
abstract final class BaiduEndpoints {
  static final account = Uri.https('pan.baidu.com', '/rest/2.0/xpan/nas');
  static final file = Uri.https('pan.baidu.com', '/rest/2.0/xpan/file');
  static final multimedia =
      Uri.https('pan.baidu.com', '/rest/2.0/xpan/multimedia');
}
```

API 客户端公开：

```dart
class BaiduApiClient {
  Future<BaiduAccount> account();

  Future<List<BaiduFileEntry>> listDirectory(CloudRemoteRef directory);

  Future<BaiduFileDetails> fileDetails(CloudRemoteRef file, {
    required bool includeDownloadLink,
  });
}
```

目录请求使用 `method=list`、`dir`、`start`、`limit=1000`，逐页按 `fs_id` 去重。空页结束；相同页指纹或 `start` 不前进时抛出不兼容。错误码映射到鉴权、权限、未找到、限流和不兼容，不将失败响应当作空列表。

- [ ] **Step 4: 运行协议、分页和敏感信息测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_response_parser_test.dart test/baidu_api_client_test.dart test/log_sanitizer_test.dart
```

Expected: 全部通过。

- [ ] **Step 5: 提交百度读取协议**

```powershell
git add lib/services/cloud/baidu/baidu_request_policy.dart lib/services/cloud/baidu/baidu_response_parser.dart lib/services/cloud/baidu/baidu_api_client.dart test/baidu_response_parser_test.dart test/baidu_api_client_test.dart test/fixtures/baidu
git commit -m "实现百度网盘读取协议"
```

---

### Task 4: 接入百度 DriveClient 与令牌生命周期

**Files:**
- Create: `lib/services/cloud/baidu/baidu_drive_client.dart`
- Create: `test/baidu_drive_client_test.dart`
- Modify: `lib/services/cloud/cloud_provider_registry.dart`
- Modify: `lib/services/cloud/cloud_drive_client.dart`
- Modify: `lib/services/cloud/cloud_playback_transport.dart`
- Modify: `lib/features/player/application/cloud_playback_cache_policy.dart`
- Modify: `test/cloud_provider_registry_test.dart`
- Modify: `test/cloud_playback_cache_policy_test.dart`

- [ ] **Step 1: 写目录映射、自动刷新与播放资源失败测试**

```dart
test('百度目录项使用 fs_id 作为稳定远程 ID', () async {
  final client = _fixtureDriveClient();
  final entries = await client.listDirectory(
    const CloudRemoteRef(id: '0', path: '/影视'),
  );

  expect(entries.single.id, '1001');
  expect(entries.single.remotePath, '/影视/示例.mkv');
});

test('百度原文件声明使用公共 Range 中转', () async {
  final client = _fixtureDriveClient();
  final resource = await client.resolvePlayback(
    const CloudRemoteRef(id: '1001', path: '/影视/示例.mkv'),
  );

  expect(resource.uri.scheme, 'https');
  expect(resource.transport, CloudPlaybackTransport.rangeRelay);
  expect(resource.networkRoute, PlaybackNetworkRoute.direct);
});
```

再增加“过期前五分钟刷新”“刷新后的 Access/Refresh Token 一起写入安全存储”“刷新失败保留旧凭据”的测试。

- [ ] **Step 2: 运行测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_drive_client_test.dart test/cloud_provider_registry_test.dart
```

Expected: 编译失败，提示 `BaiduDriveClient` 或 `rangeRelay` 不存在。

- [ ] **Step 3: 实现 DriveClient 和注册器工厂**

`BaiduDriveClient` 必须实现：

```dart
class BaiduDriveClient implements CloudDriveClient {
  BaiduDriveClient({
    required CloudSource source,
    required CloudCredentialStore credentialStore,
    Dio? dio,
    DateTime Function()? now,
  });

  @override
  Future<void> authenticate(CloudSource source, CloudCredential credential);

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory);

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file);

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file);

  @override
  Future<void> close();
}
```

先把 `CloudPlaybackTransport` 扩展为三态迁移模型：

```dart
enum CloudPlaybackTransport { direct, quarkRangeRelay, rangeRelay }
```

本任务只有百度原文件返回 `rangeRelay`；夸克原文件暂时保留
`quarkRangeRelay`，夸克转码与 OpenList 保持 `direct`。缓存策略把
`quarkRangeRelay` 与 `rangeRelay` 映射为相同 MPV 参数。Task 6 完成公共层迁移后再把
夸克切换到 `rangeRelay` 并删除临时枚举值。注册器增加百度工厂、名称、官方地址、
错误文案和不支持自签名/分享写操作声明。

- [ ] **Step 4: 运行客户端和公共接口回归**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_drive_client_test.dart test/cloud_provider_registry_test.dart test/quark_drive_client_test.dart test/cloud_playback_cache_policy_test.dart
```

Expected: 全部通过；百度原文件使用 `rangeRelay`，夸克原文件仍使用
`quarkRangeRelay`，两者采用相同缓存参数。

- [ ] **Step 5: 提交百度客户端**

```powershell
git add lib/services/cloud/baidu/baidu_drive_client.dart lib/services/cloud/cloud_provider_registry.dart lib/services/cloud/cloud_drive_client.dart lib/services/cloud/cloud_playback_transport.dart lib/features/player/application/cloud_playback_cache_policy.dart test/baidu_drive_client_test.dart test/cloud_provider_registry_test.dart test/quark_drive_client_test.dart test/cloud_playback_cache_policy_test.dart
git commit -m "接入百度网盘目录客户端"
```

---

### Task 5: 实现百度授权控制器、来源编辑和目录选择

**Files:**
- Create: `lib/services/cloud/baidu/baidu_authorization_controller.dart`
- Create: `lib/pages/cloud/baidu/baidu_source_editor.dart`
- Create: `lib/pages/cloud/baidu/baidu_directory_picker.dart`
- Create: `test/baidu_authorization_controller_test.dart`
- Create: `test/baidu_source_editor_test.dart`
- Modify: `lib/pages/settings/cloud_sources_settings.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `test/cloud_sources_ui_test.dart`

- [ ] **Step 1: 写授权会话和界面失败测试**

```dart
test('授权会话十分钟后拒绝粘贴的授权码', () async {
  final clock = _FakeClock(DateTime(2026, 7, 21, 10));
  final controller = BaiduAuthorizationController(
    oauthFactory: _oauthFactory,
    now: clock.call,
  );

  controller.begin(clientId: 'id', clientSecret: 'secret');
  clock.advance(const Duration(minutes: 11));

  await expectLater(
    controller.exchangeCode('fixture-code'),
    throwsA(isA<CloudDriveException>()),
  );
});

testWidgets('百度来源先授权再选择多个媒体目录', (tester) async {
  await tester.pumpWidget(_testApp(const BaiduSourceEditorPage()));

  expect(find.text('打开百度授权'), findsOneWidget);
  expect(find.text('选择目录'), findsOneWidget);
  expect(
    tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '选择目录'))
        .onPressed,
    isNull,
  );
});
```

`cloud_sources_ui_test.dart` 增加百度菜单、`/settings/cloud-sources/baidu/edit` 路由和“百度来源没有分享导入按钮”的断言。

- [ ] **Step 2: 运行界面测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_authorization_controller_test.dart test/baidu_source_editor_test.dart test/cloud_sources_ui_test.dart
```

Expected: 编译或查找失败，百度控制器、页面和路由尚不存在。

- [ ] **Step 3: 实现授权控制器和页面**

控制器公开状态：

```dart
class BaiduAuthorizationController extends ChangeNotifier {
  Uri? get authorizationUri;
  bool get authorizing;
  BaiduAccount? get account;
  CloudCredential? get authorizedCredential;
  String? get errorMessage;

  Uri begin({required String clientId, required String clientSecret});

  Future<void> exchangeCode(String code);

  void cancel();
}
```

页面使用 `url_launcher` 打开系统浏览器；授权成功前目录按钮禁用。新来源要求 API Key、Secret 与成功授权；编辑来源留空保留已有密钥，修改任一密钥会清除授权状态并要求重新授权。目录选择器按 `CloudRemoteRef.id` 导航，支持多选并返回 `List<CloudRemoteRef>`。

- [ ] **Step 4: 运行百度 UI 与夸克/OpenList 页面回归**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_authorization_controller_test.dart test/baidu_source_editor_test.dart test/cloud_sources_ui_test.dart test/quark_source_editor_test.dart
```

Expected: 全部通过。

- [ ] **Step 5: 提交百度设置界面**

```powershell
git add lib/services/cloud/baidu/baidu_authorization_controller.dart lib/pages/cloud/baidu lib/pages/settings/cloud_sources_settings.dart lib/pages/settings/settings_module.dart test/baidu_authorization_controller_test.dart test/baidu_source_editor_test.dart test/cloud_sources_ui_test.dart
git commit -m "增加百度网盘授权与目录选择"
```

---

### Task 6: 将夸克 Range 中转提取为公共层

**Files:**
- Create: `lib/services/cloud/range/cloud_range_relay_protocol.dart`
- Create: `lib/services/cloud/range/cloud_range_remote_reader.dart`
- Create: `lib/services/cloud/range/cloud_range_chunk_cache.dart`
- Create: `lib/services/cloud/range/cloud_range_relay_session.dart`
- Create: `lib/services/cloud/range/cloud_range_relay_service.dart`
- Create: `lib/pages/video/cloud_relay_status_presenter.dart`
- Modify: `lib/services/cloud/quark/quark_range_remote_reader.dart`
- Modify: `lib/services/cloud/quark/quark_range_relay_service.dart`
- Modify: `lib/services/cloud/quark/quark_drive_client.dart`
- Delete: `lib/services/cloud/quark/quark_range_relay_protocol.dart`
- Delete: `lib/services/cloud/quark/quark_range_chunk_cache.dart`
- Delete: `lib/services/cloud/quark/quark_range_relay_session.dart`
- Modify: `lib/services/cloud/cloud_playback_transport.dart`
- Modify: `lib/services/cloud/cloud_cache_directories.dart`
- Modify: `lib/features/player/application/cloud_playback_cache_policy.dart`
- Modify: `lib/pages/video/video_page.dart`
- Create: `test/cloud_range_relay_protocol_test.dart`
- Create: `test/cloud_range_chunk_cache_test.dart`
- Create: `test/cloud_range_relay_session_test.dart`
- Create: `test/cloud_range_relay_service_test.dart`
- Create: `test/cloud_relay_status_ui_test.dart`
- Modify: `test/quark_range_remote_reader_test.dart`
- Modify: `test/quark_relay_status_ui_test.dart`
- Delete: `test/quark_range_relay_protocol_test.dart`
- Delete: `test/quark_range_chunk_cache_test.dart`
- Delete: `test/quark_range_relay_session_test.dart`

- [ ] **Step 1: 写公共接口和夸克兼容失败测试**

公共读取器接口固定为：

```dart
abstract interface class CloudRangeRemoteReader {
  int? get totalLength;
  String get contentType;
  Stream<CloudRangeReaderEvent> get events;

  Future<CloudRangeRemoteMetadata> probe();
  Future<void> readTo(ByteRange range, File destination);
  Future<void> streamAll(IOSink destination);
  Future<void> close();
}

class CloudRangeRemoteResource {
  CloudRangeRemoteResource({
    required this.uri,
    Map<String, String> headers = const <String, String>{},
    this.totalLength,
    this.contentType,
  }) : headers = Map<String, String>.unmodifiable(headers);

  final Uri uri;
  final Map<String, String> headers;
  final int? totalLength;
  final String? contentType;
}

class CloudRangeRemoteMetadata {
  const CloudRangeRemoteMetadata({
    required this.totalLength,
    required this.contentType,
    required this.supportsRanges,
  });

  final int totalLength;
  final String contentType;
  final bool supportsRanges;
}
```

状态测试固定提供方名称：

```dart
test('公共状态展示百度提供方名称和速度', () {
  final presentation = CloudRelayStatusPresenter.present(
    const CloudRangeRelayStatus(
      providerName: '百度网盘',
      phase: CloudRangeRelayPhase.ready,
      bytesPerSecond: 2 * 1024 * 1024,
    ),
  );

  expect(presentation.text, contains('百度网盘'));
  expect(presentation.text, contains('2.0 MB/s'));
});
```

把现有协议、缓存、会话和服务测试复制到公共测试文件，断言保持 16 MiB、16 段、最多两个远程请求、头尾与后续两段预取、128 位令牌和 24 小时孤立缓存清理。

- [ ] **Step 2: 运行公共测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_protocol_test.dart test/cloud_range_chunk_cache_test.dart test/cloud_range_relay_session_test.dart test/cloud_range_relay_service_test.dart test/cloud_relay_status_ui_test.dart
```

Expected: 编译失败，公共 Range 类型尚不存在。

- [ ] **Step 3: 提取公共实现并保留夸克薄适配器**

公共会话入口：

```dart
class CloudRangeRelaySession implements CloudPlaybackLease {
  static Future<CloudRangeRelaySession> start({
    required CloudRangeRemoteReader reader,
    required Directory directory,
    required String providerName,
    int chunkSize = 16 * 1024 * 1024,
    int maxChunks = 16,
  });
}

class CloudRangeRelayService {
  Future<CloudRangeRelayPlayback> start({
    required CloudRangeRemoteReader reader,
    required String providerKey,
    required String providerName,
  });
}

class CloudRangeRelayPlayback {
  const CloudRangeRelayPlayback({
    required this.uri,
    required this.lease,
    required this.totalLength,
  });

  final Uri uri;
  final CloudPlaybackLease lease;
  final int totalLength;
}

typedef CloudRangeRelayStarter = Future<CloudRangeRelayPlayback> Function({
  required CloudRangeRemoteReader reader,
  required String providerKey,
  required String providerName,
});
```

公共缓存目录改为 `cloud_range_relay/<providerKey>/cloud-relay-<32 hex>`。探测结果
`supportsRanges=true` 时使用分段缓存；为 `false` 时不创建分段缓存，不声明
`Accept-Ranges`，本机完整 GET 直接调用 `streamAll`，带非零 Range 的请求返回 416 并
提示拖动不可用。夸克服务只负责构造 `QuarkRangeRemoteReader` 并调用公共服务；旧夸克
测试迁移到公共测试后仍保留远程读取器安全回归。状态模型改为
`CloudRangeRelayStatus`，`CloudPlaybackLease` 使用公共状态流。完成迁移后把夸克原文件
改为 `rangeRelay`，删除 `quarkRangeRelay` 枚举值并修正所有穷举 switch。

- [ ] **Step 4: 运行公共与夸克完整中转回归**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_range_relay_protocol_test.dart test/cloud_range_chunk_cache_test.dart test/cloud_range_relay_session_test.dart test/cloud_range_relay_service_test.dart test/cloud_relay_status_ui_test.dart test/quark_range_remote_reader_test.dart test/quark_range_relay_service_test.dart test/quark_relay_status_ui_test.dart test/cloud_playback_cache_policy_test.dart
```

Expected: 全部通过，夸克播放参数和状态行为不变。

- [ ] **Step 5: 提交公共中转重构**

```powershell
git add lib/services/cloud/range lib/services/cloud/quark/quark_range_remote_reader.dart lib/services/cloud/quark/quark_range_relay_service.dart lib/services/cloud/quark/quark_drive_client.dart lib/services/cloud/quark/quark_range_relay_protocol.dart lib/services/cloud/quark/quark_range_chunk_cache.dart lib/services/cloud/quark/quark_range_relay_session.dart lib/services/cloud/cloud_playback_transport.dart lib/services/cloud/cloud_cache_directories.dart lib/features/player/application/cloud_playback_cache_policy.dart lib/pages/video/cloud_relay_status_presenter.dart lib/pages/video/video_page.dart test/cloud_range_relay_protocol_test.dart test/cloud_range_chunk_cache_test.dart test/cloud_range_relay_session_test.dart test/cloud_range_relay_service_test.dart test/cloud_relay_status_ui_test.dart test/quark_range_remote_reader_test.dart test/quark_range_relay_protocol_test.dart test/quark_range_chunk_cache_test.dart test/quark_range_relay_session_test.dart test/quark_range_relay_service_test.dart test/quark_relay_status_ui_test.dart test/cloud_playback_cache_policy_test.dart
git commit -m "提取通用云盘分段中转"
```

---

### Task 7: 实现百度远程分段读取与播放解析

**Files:**
- Create: `lib/services/cloud/baidu/baidu_range_remote_reader.dart`
- Create: `test/baidu_range_remote_reader_test.dart`
- Modify: `lib/services/cloud/cloud_provider_registry.dart`
- Modify: `lib/services/cloud/cloud_playback_resolver.dart`
- Modify: `test/cloud_playback_resolver_test.dart`
- Modify: `test/cloud_playback_cache_policy_test.dart`

- [ ] **Step 1: 写百度 Range、刷新和跨主机脱敏失败测试**

```dart
test('百度读取器只向首始官方地址附加 access_token', () async {
  final adapter = _RedirectingHttpFixture();
  final reader = BaiduRangeRemoteReader(
    resource: CloudRangeRemoteResource(
      uri: Uri.parse('https://pan.baidu.com/rest/2.0/xpan/file?fixture=1'),
      totalLength: 4,
    ),
    accessTokenProvider: () async => 'access-fixture',
    refreshResource: _refreshFixture,
    httpClientFactory: adapter.createClient,
  );

  final target = await File('${directory.path}/chunk').create();
  await reader.readTo(const ByteRange(0, 3), target);

  expect(adapter.firstRequestUri.queryParameters['access_token'],
      'access-fixture');
  expect(adapter.redirectRequestUri.queryParameters['access_token'], isNull);
  expect(adapter.redirectHeaders.keys, isNot(contains('authorization')));
});

test('百度 401 或 403 只刷新令牌和 dlink 一次', () async {
  final fixture = _AuthenticationFailureFixture();
  final reader = fixture.reader;

  await reader.readTo(
    const ByteRange(0, 3),
    await File('${directory.path}/chunk').create(),
  );

  expect(fixture.refreshCount, 1);
});
```

增加私网、回环、非 HTTPS 重定向拒绝，206/`Content-Range`/长度校验，关闭取消请求
测试。顺序流夹具让探测请求返回 200，断言 `supportsRanges=false`，随后
`streamAll` 只发起一次无 Range 的完整 GET；不得把完整文件写入临时缓存。

- [ ] **Step 2: 运行百度读取器和解析器测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_range_remote_reader_test.dart test/cloud_playback_resolver_test.dart
```

Expected: 编译失败，百度读取器和注册器 Range 工厂尚不存在。

- [ ] **Step 3: 实现读取器并让注册器创建提供方适配器**

百度读取器实现公共接口：

```dart
class BaiduRangeRemoteReader implements CloudRangeRemoteReader {
  BaiduRangeRemoteReader({
    required CloudRangeRemoteResource resource,
    required Future<String> Function() accessTokenProvider,
    required Future<CloudRangeRemoteResource> Function() refreshResource,
    HttpClient Function()? httpClientFactory,
    Future<void> Function(Duration)? delay,
    Duration requestTimeout = const Duration(seconds: 15),
  });

  @override
  Future<CloudRangeRemoteMetadata> probe();

  @override
  Future<void> readTo(ByteRange range, File destination);

  @override
  Future<void> streamAll(IOSink destination);
}
```

注册器增加：

```dart
CloudRangeRemoteReader createRangeReader({
  required CloudSource source,
  required CloudPlaybackResource resource,
  required Future<CloudPlaybackResource> Function() refreshResource,
  required CloudCredentialStore credentialStore,
});
```

解析器不再判断 `source.type == quark`。当 `resource.transport == rangeRelay` 时，由注册器
创建对应读取器并启动公共服务。百度读取器通过 `credentialStore` 在请求前读取当前
Access Token，Token 不放入 `CloudPlaybackResource`；刷新闭包重新创建该来源客户端并按
同一个 `remoteId` 获取新播放资源。播放器只接收本机 URI 和空请求头。解析器构造参数
从 `QuarkRangeRelayStarter?` 改为 `CloudRangeRelayStarter?`，测试注入点同步迁移。

- [ ] **Step 4: 运行百度、夸克、OpenList 和选集播放测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/baidu_range_remote_reader_test.dart test/cloud_playback_resolver_test.dart test/baidu_drive_client_test.dart test/quark_range_remote_reader_test.dart test/cloud_resources_page_test.dart test/cloud_playback_cache_policy_test.dart
```

Expected: 全部通过；百度和夸克使用公共中转，OpenList 仍直连，季度选集完整。

- [ ] **Step 5: 提交百度播放链路**

```powershell
git add lib/services/cloud/baidu/baidu_range_remote_reader.dart lib/services/cloud/cloud_provider_registry.dart lib/services/cloud/cloud_playback_resolver.dart test/baidu_range_remote_reader_test.dart test/cloud_playback_resolver_test.dart test/cloud_playback_cache_policy_test.dart
git commit -m "实现百度原文件分段播放"
```

---

### Task 8: 验证百度复用媒体识别与 TMDB 作品树

**Files:**
- Modify: `test/cloud_media_indexer_test.dart`
- Modify: `test/cloud_media_tree_resolver_test.dart`
- Modify: `test/cloud_resource_collection_test.dart`
- Modify: `test/cloud_resources_flat_library_test.dart`
- Modify: `test/cloud_source_root_refresh_coordinator_test.dart`

- [ ] **Step 1: 添加百度来源端到端媒体测试**

```dart
test('百度纯集号视频继承目录剧名季度并保留多个版本', () async {
  final result = resolver.resolve(
    sourceId: 'baidu-a',
    items: <CloudMediaIndexItem>[
      _item('baidu-a', '1001', '/回魂计/第二季/01.2160p.mkv'),
      _item('baidu-a', '1002', '/回魂计/第二季/01.1080p.mkv'),
      _item('baidu-a', '1003', '/回魂计/第二季/02.mkv'),
    ],
  );

  final season = result.works.single.seasons.single;
  expect(season.seasonNumber, 2);
  expect(season.uniqueEpisodeCount, 2);
  expect(season.episodes.first.variants, hasLength(2));
});
```

增加百度多根目录重叠去重、季度海报目标、外部字幕和修改根目录实时隐藏旧资源测试。

- [ ] **Step 2: 运行测试观察是否存在提供方硬编码**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_media_indexer_test.dart test/cloud_media_tree_resolver_test.dart test/cloud_resource_collection_test.dart test/cloud_resources_flat_library_test.dart test/cloud_source_root_refresh_coordinator_test.dart
```

Expected: 若公共层已完全按来源 ID 工作则直接通过；若失败，只允许修复 `CloudSourceType` 穷举和夸克硬编码，不修改媒体识别规则。

- [ ] **Step 3: 移除发现的提供方硬编码**

所有来源名称展示使用注册器；作品稳定键继续使用 `sourceId|work|...`，不得把 `baidu` 写入通用解析器分支。媒体索引条目只依赖 `sourceId`、远程 ID、路径、大小和时间。

- [ ] **Step 4: 重跑媒体树与本地/网盘海报墙回归**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/cloud_media_indexer_test.dart test/cloud_media_tree_resolver_test.dart test/cloud_resource_collection_test.dart test/cloud_resources_flat_library_test.dart test/cloud_library_integration_test.dart test/local_video_controller_test.dart
```

Expected: 全部通过。

- [ ] **Step 5: 提交百度媒体库覆盖**

```powershell
git add test/cloud_media_indexer_test.dart test/cloud_media_tree_resolver_test.dart test/cloud_resource_collection_test.dart test/cloud_resources_flat_library_test.dart test/cloud_source_root_refresh_coordinator_test.dart
git commit -m "覆盖百度网盘媒体识别场景"
```

---

### Task 9: 加入内置默认 TMDB Key

**Files:**
- Create: `lib/services/tmdb/tmdb_api_key_provider.dart`
- Create: `test/tmdb_api_key_provider_test.dart`
- Modify: `lib/pages/settings/tmdb_settings.dart`
- Modify: `lib/pages/index_module.dart`
- Modify: `lib/pages/local/local_controller.dart`
- Modify: `lib/services/poster_service.dart`
- Modify: `test/tmdb_settings_language_test.dart`

- [ ] **Step 1: 写用户 Key 优先和内置回退失败测试**

```dart
test('用户 TMDB Key 优先于内置默认值', () {
  final provider = TmdbApiKeyProvider(
    userKeyReader: () => 'user-key',
    builtinKey: 'builtin-key',
  );

  expect(provider.read(), 'user-key');
  expect(provider.source, TmdbApiKeySource.user);
});

test('用户 Key 为空时使用内置默认值', () {
  final provider = TmdbApiKeyProvider(
    userKeyReader: () => '',
    builtinKey: 'builtin-key',
  );

  expect(provider.read(), 'builtin-key');
  expect(provider.source, TmdbApiKeySource.builtin);
});
```

页面测试要求空输入时显示“当前使用内置默认 Key”，保存用户值后显示“当前使用用户 Key”，两种提示都不包含 Key 内容。

- [ ] **Step 2: 运行测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/tmdb_api_key_provider_test.dart test/tmdb_settings_language_test.dart
```

Expected: 编译失败，统一 Key 提供器不存在。

- [ ] **Step 3: 实现统一 Key 提供器并替换直接读取**

```dart
enum TmdbApiKeySource { none, builtin, user }

class TmdbApiKeyProvider {
  TmdbApiKeyProvider({
    required String Function() userKeyReader,
    String builtinKey = const String.fromEnvironment(
      'KANYINGYIN_TMDB_API_KEY',
    ),
  });

  String read();
  TmdbApiKeySource get source;
}
```

`index_module.dart`、`local_controller.dart` 和 `poster_service.dart` 统一调用提供器。设置页只编辑用户 Key，并根据 `source` 显示来源提示；连接测试使用 `provider.read()`，因此用户输入为空但内置值存在时仍可测试。

- [ ] **Step 4: 运行 TMDB 全链路回归**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/tmdb_api_key_provider_test.dart test/tmdb_settings_language_test.dart test/tmdb_client_test.dart test/local_tmdb_integration_test.dart test/cloud_resource_tmdb_coordinator_test.dart test/cloud_work_tmdb_coordinator_test.dart
```

Expected: 全部通过；无 `dart-define` 的普通测试仍以空内置 Key 运行。

- [ ] **Step 5: 提交默认 TMDB Key 支持**

```powershell
git add lib/services/tmdb/tmdb_api_key_provider.dart lib/pages/settings/tmdb_settings.dart lib/pages/index_module.dart lib/pages/local/local_controller.dart lib/services/poster_service.dart test/tmdb_api_key_provider_test.dart test/tmdb_settings_language_test.dart
git commit -m "支持构建时内置 TMDB 密钥"
```

---

### Task 10: 创建私密构建和异机安装脚本

**Files:**
- Create: `tool/export_tmdb_build_define.dart`
- Create: `tool/windows/build_private_release.ps1`
- Create: `tool/windows/installer/安装看影音.ps1`
- Create: `tool/windows/installer/安装看影音.cmd`
- Create: `tool/windows/installer/安装说明.txt`
- Create: `test/private_release_packaging_test.dart`
- Modify: `.gitignore`

- [ ] **Step 1: 写静态安全和安装包内容失败测试**

```dart
test('私人构建脚本使用临时 define 文件且 finally 删除', () async {
  final script = await File('tool/windows/build_private_release.ps1')
      .readAsString(encoding: utf8);

  expect(script, contains('--dart-define-from-file'));
  expect(script, contains('finally'));
  expect(script, contains('Remove-Item'));
  expect(script, isNot(contains('KANYINGYIN_TMDB_API_KEY=')));
});

test('异机安装脚本只导入当前用户 TrustedPeople', () async {
  final script = await File('tool/windows/installer/安装看影音.ps1')
      .readAsString(encoding: utf8);

  expect(script, contains(r'Cert:\CurrentUser\TrustedPeople'));
  expect(script, isNot(contains(r'Cert:\LocalMachine')));
  expect(script, contains('Get-FileHash'));
  expect(script, contains('Add-AppxPackage'));
});
```

测试还要拒绝 `.pfx`、`clientSecret`、`accessToken`、`refreshToken` 和可编辑 TMDB Key 文件出现在 ZIP 文件清单中。

- [ ] **Step 2: 运行脚本测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/private_release_packaging_test.dart
```

Expected: 文件读取失败，构建和安装脚本尚不存在。

- [ ] **Step 3: 实现密钥导出和私人 Release 构建脚本**

`export_tmdb_build_define.dart` 接收：

```text
--hive-directory <当前应用 setting.hive 所在目录>
--output <临时 JSON 路径>
```

它用 Hive CE 只读 `setting` box，要求 `tmdbApiKey` 为非空字符串，并使用 Dart
`jsonEncode` 写出以下映射，代码不得包含任何真实 Key 字面量：

```dart
await output.writeAsString(
  jsonEncode(<String, String>{
    'KANYINGYIN_TMDB_API_KEY': tmdbApiKey,
  }),
  encoding: utf8,
  flush: true,
);
```

工具只输出“已生成私密构建参数”，绝不输出长度、前缀或 Key。PowerShell 脚本先确认
`kanyingyin.exe` 未运行，避免 Hive 写锁与读取不一致；随后在当前用户临时目录创建随机
子目录，限制 ACL，调用：

```powershell
& 'D:\flutter\bin\flutter.bat' build windows --release --no-pub `
  "--dart-define-from-file=$defineFile"
```

随后只封装该 Release。整个流程使用 `try/finally`，在 `finally` 删除临时目录并确认不存在。

- [ ] **Step 4: 实现异机预检与安装脚本**

`安装看影音.ps1` 必须：

```powershell
$actualHash = (Get-FileHash -LiteralPath $msixPath -Algorithm SHA256).Hash
if ($actualHash -ne $expectedHash) { throw 'MSIX 哈希校验失败' }

$signature = Get-AuthenticodeSignature -LiteralPath $msixPath
$certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($cerPath)
if ($signature.SignerCertificate.Thumbprint -ne $certificate.Thumbprint) {
  throw 'MSIX 签名证书与安装包证书不一致'
}

Import-Certificate -FilePath $cerPath `
  -CertStoreLocation 'Cert:\CurrentUser\TrustedPeople' | Out-Null

if ((Get-AuthenticodeSignature -LiteralPath $msixPath).Status -ne 'Valid') {
  throw 'MSIX 签名验证失败'
}

Add-AppxPackage -Path $msixPath
```

在导入证书前用 ZIP API 读取 `AppxManifest.xml`，验证身份、版本、发布者和 x64。CMD 入口使用 `%~dp0` 定位脚本，并以 UTF-8 PowerShell 运行，不拼接用户输入命令。

- [ ] **Step 5: 运行脚本安全测试并提交**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/private_release_packaging_test.dart
```

Expected: 全部通过。

Commit:

```powershell
git add .gitignore tool/export_tmdb_build_define.dart tool/windows test/private_release_packaging_test.dart
git commit -m "增加私人异机安装包构建流程"
```

---

### Task 11: 更新 2.1.28 版本与用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1: 先把版本测试期望提升到 2.1.28**

```dart
expect(pubspec, contains('version: 2.1.28+20128'));
expect(pubspec, contains('msix_version: 2.1.28.0'));
expect(AppVersion.current, '2.1.28');
```

版本历史测试要求文案包含“百度网盘”“官方授权”“分段播放”“内置默认 TMDB Key”“私人安装包”和“不修改百度网盘文件”。

- [ ] **Step 2: 运行版本测试确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
```

Expected: 失败，当前生产版本仍为 2.1.27。

- [ ] **Step 3: 更新版本与普通用户发布说明**

设置：

```yaml
version: 2.1.28+20128
msix_config:
  msix_version: 2.1.28.0
```

更新说明明确：百度使用用户自己的开放平台凭据和官方 OAuth；可选多个目录；复用海报墙和季度识别；原文件分段边下边播；第一版只读；私人包含可提取的默认 TMDB Key 且不得公开分发。

- [ ] **Step 4: 运行版本门禁**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
```

Expected: 全部通过。

- [ ] **Step 5: 提交发布信息**

```powershell
git add pubspec.yaml README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md lib/core/app_version.dart lib/utils/version_history.dart test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git commit -m "发布二点一二十八测试版"
```

---

### Task 12: 完整验证、签名 MSIX 和异机 ZIP

**Files:**
- Verify: all files changed in Tasks 1-11
- Output: `C:\Users\asus\Desktop\看影音-2.1.28.msix`
- Output: `C:\Users\asus\Desktop\看影音-2.1.28-异机安装包.zip`

- [ ] **Step 1: 检查工作区与敏感信息**

Run:

```powershell
git status --short
git diff --check
rg -n --hidden --glob '!build/**' --glob '!.dart_tool/**' `
  'access-fixture|refresh-fixture|client-secret|KANYINGYIN_TMDB_API_KEY=' .
```

Expected: 只剩用户原有 `.learnings` 修改；敏感扫描只命中明确的测试夹具或环境变量名称，不命中真实 Key。

- [ ] **Step 2: 运行完整测试和静态分析**

Run:

```powershell
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: 所有测试通过；静态分析输出 `No issues found!`。

- [ ] **Step 3: 使用私密入口构建 Release、签名 MSIX 和 ZIP**

Run:

```powershell
& '.\tool\windows\build_private_release.ps1'
```

Expected:

- 成功读取当前看影音设置中的 TMDB Key，但输出不显示 Key。
- Windows Release 构建成功。
- MSIX 清单为 `com.kanyingyin.player / 2.1.28.0 / CN=KanYingYin / x64`。
- MSIX 签名状态为 `Valid`。
- 桌面生成 MSIX 和异机 ZIP。
- 临时 `dart-define` 文件和目录不存在。

- [ ] **Step 4: 审计 ZIP 内容和哈希**

Run:

```powershell
$zip = 'C:\Users\asus\Desktop\看影音-2.1.28-异机安装包.zip'
$extract = Join-Path $env:TEMP 'kanyingyin-2.1.28-package-audit'
Expand-Archive -LiteralPath $zip -DestinationPath $extract -Force
Get-ChildItem -LiteralPath $extract -Recurse | Select-Object FullName, Length
Get-FileHash -LiteralPath $zip -Algorithm SHA256
Get-FileHash -LiteralPath 'C:\Users\asus\Desktop\看影音-2.1.28.msix' -Algorithm SHA256
```

Expected: ZIP 只包含 MSIX、CER、PS1、CMD、TXT 和 SHA256 文件；不含 PFX、JSON 密钥文件、百度凭据或 TMDB Key 文件。

- [ ] **Step 5: 在主电脑做真实百度账号验收**

用户在应用设置中输入自己的百度 API Key 与 Secret，不通过聊天传递。依次验证：

1. 系统浏览器 `oob` 授权。
2. 选择两个媒体根目录。
3. 扫描电影、电视剧、季度、纯集号和字幕。
4. 播放普通视频和 4K 原文件。
5. 拖动进度、切集和重启后自动续期。
6. 夸克、OpenList、本地播放、字幕、全屏、硬件解码和 Anime4K 回归。

Expected: 全部通过；若真实开放平台凭据尚未可用，明确记录“自动化和安装包已完成，真实百度账号验收待用户凭据”，不得宣称实机通过。

- [ ] **Step 6: 在另一台 Windows x64 电脑验证安装包**

把 ZIP 复制到目标电脑，运行 `安装看影音.cmd`。验证：

1. 当前用户公钥证书导入成功。
2. MSIX 安装成功。
3. 首次启动快捷方式提示正常。
4. 未填写 TMDB Key 时可以使用内置默认 Key 搜索。
5. 百度 OAuth、目录扫描和视频播放正常。

Expected: 全部通过后才标记异机包交付完成。

- [ ] **Step 7: 最终 Git 审计与提交范围确认**

Run:

```powershell
git status --short
git log --oneline --max-count=15
```

Expected: 所有实现与发布文件已按任务提交；只保留 `.learnings/ERRORS.md` 和 `.learnings/LEARNINGS.md` 的用户修改；不推送远端。

---

## 完成定义

只有同时满足以下条件才能宣布 2.1.28 完成：

- 百度官方 OAuth、多个账号和多个媒体目录可用。
- 百度媒体进入现有作品树、季度海报和选集。
- 百度原文件通过公共 Range 中转边下边播。
- 夸克公共中转重构无回归。
- 内置默认 TMDB Key 生效且未进入 Git 或明文交付文件。
- 完整测试、静态分析、Windows Release 和签名 MSIX 通过。
- 桌面存在签名 MSIX 与异机安装 ZIP。
- ZIP 不含私钥或明文凭据。
- 真实账号与异机验收结果如实记录。
- `.learnings` 用户改动未暂存、未提交。
