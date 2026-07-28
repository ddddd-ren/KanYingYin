# 迅雷网盘原生接入与 OpenList 快捷入口 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为看影音增加只读的迅雷个人网盘登录、目录扫描、TMDB 与原画播放能力，并在网盘资源页补齐 OpenList 快捷入口。

**Architecture:** 迅雷实现限定在 `services/cloud/xunlei` 和对应页面目录中，通过现有 `CloudDriveClient`、`CloudProviderRegistry`、`CloudMediaIndexer` 与 Range Relay 接入公共媒体链路。首次登录使用账号密码和系统浏览器验证，但只把 Refresh Token、Device ID、Captcha Token 与脱敏账号信息写入 Windows 安全存储；播放只使用原始文件地址，不回退迅雷转码。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、Dio、`dart:io`、`crypto`、`flutter_secure_storage`、现有 Cloud Range Relay、Windows MSIX、SignTool。

---

## 文件结构

### 新建文件

- `lib/services/cloud/xunlei/xunlei_models.dart`：迅雷令牌、账号、分页、文件与验证挑战强类型模型。
- `lib/services/cloud/xunlei/xunlei_response_parser.dart`：解析并验证迅雷 JSON，禁止响应正文进入异常。
- `lib/services/cloud/xunlei/xunlei_request_policy.dart`：协议端点、客户端标识、验证码签名、可信验证与下载主机。
- `lib/services/cloud/xunlei/xunlei_api_client.dart`：首次登录、Refresh Token、用户、目录和文件详情请求。
- `lib/services/cloud/xunlei/xunlei_authorization_controller.dart`：登录及系统浏览器验证状态机。
- `lib/services/cloud/xunlei/xunlei_drive_client.dart`：`CloudDriveClient` 只读适配、分页去重和原画地址解析。
- `lib/services/cloud/xunlei/xunlei_range_remote_reader.dart`：迅雷原画 Range 读取、重定向校验和单次鉴权恢复。
- `lib/pages/cloud/xunlei/xunlei_directory_picker.dart`：统一目录选择页包装。
- `lib/pages/cloud/xunlei/xunlei_source_editor.dart`：迅雷登录、验证、根目录和保存界面。
- `test/fixtures/xunlei/login_success.json`、`verification_required.json`、`refresh_success.json`、`account.json`、`directory_page_1.json`、`directory_page_2.json`、`file_detail.json`：脱敏协议响应夹具。
- `test/xunlei_response_parser_test.dart`、`xunlei_request_policy_test.dart`、`xunlei_api_client_test.dart`、`xunlei_authorization_controller_test.dart`、`xunlei_drive_client_test.dart`、`xunlei_range_remote_reader_test.dart`、`xunlei_source_editor_test.dart`：新增行为测试。

### 修改文件

- `lib/modules/cloud/cloud_source.dart`：增加 `CloudSourceType.xunlei`。
- `lib/services/cloud/cloud_credential_store.dart`：增加迅雷允许持久化的凭据字段。
- `lib/services/cloud/cloud_drive_client.dart`：增加“需要验证”错误类型。
- `lib/services/cloud/cloud_provider_registry.dart`：注册迅雷客户端、Range 读取器、名称、规范地址和错误文案。
- `lib/pages/settings/settings_module.dart`、`lib/pages/settings/cloud_sources_settings.dart`：迅雷路由、来源管理入口和类型标签。
- `lib/pages/cloud/resources/cloud_resources_page.dart`：迅雷及 OpenList 顶部菜单与空状态入口。
- `lib/features/player/application/cloud_playback_cache_policy.dart`：Range Relay 命名从夸克专用改成云盘通用，行为不变。
- 现有来源、播放、诊断和架构测试：覆盖新枚举分支与敏感信息边界。
- `pubspec.yaml`、`lib/core/app_version.dart`、`README.md`、`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md`、`lib/utils/version_history.dart` 和版本测试：测试版升级为 `2.1.69+20169` / MSIX `2.1.69.0`，正式版保持 `1.0.2`。

## Task 1：来源类型与安全凭据契约

**Files:**
- Modify: `lib/modules/cloud/cloud_source.dart`
- Modify: `lib/services/cloud/cloud_credential_store.dart`
- Modify: `lib/services/cloud/cloud_drive_client.dart`
- Create: `test/xunlei_credential_test.dart`
- Modify: `test/cloud_source_repository_test.dart`

- [ ] **Step 1：写失败测试，固定迅雷来源序列化和允许持久化字段**

```dart
test('迅雷来源和凭据安全往返且不包含登录秘密', () {
  const source = CloudSource(
    id: 'xunlei-a',
    type: CloudSourceType.xunlei,
    name: '迅雷网盘',
    baseUrl: 'https://pan.xunlei.com',
    rootPaths: <String>['/影视'],
  );
  const credential = CloudCredential(
    refreshToken: 'refresh-fixture',
    deviceId: '0123456789abcdef0123456789abcdef',
    captchaToken: 'captcha-fixture',
    userId: 'user-fixture',
    accountLabel: '138****0000',
  );

  expect(CloudSource.fromJson(source.toJson()), source);
  expect(credential.toJson(), isNot(contains('password')));
  expect(credential.toJson(), isNot(contains('accessToken')));
  expect(credential.toJson(), isNot(contains('creditKey')));
  final restored = CloudCredential.fromJson(credential.toJson());
  expect(restored.refreshToken, credential.refreshToken);
  expect(restored.deviceId, credential.deviceId);
  expect(restored.captchaToken, credential.captchaToken);
  expect(restored.userId, credential.userId);
  expect(restored.accountLabel, credential.accountLabel);
});
```

- [ ] **Step 2：运行测试并确认因枚举与字段不存在而失败**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_credential_test.dart test\cloud_source_repository_test.dart`

Expected: FAIL，错误包含 `xunlei` 或 `deviceId` 未定义。

- [ ] **Step 3：实现最小领域扩展**

在 `cloud_source.dart` 增加：

```dart
enum CloudSourceType { openList, quark, baidu, xunlei }
```

在 `CloudDriveErrorType` 增加 `verificationRequired`。在 `CloudCredential` 增加以下字段，并同步构造器、`isEmpty`、`toJson`、`fromJson` 与值相等测试：

```dart
final String? deviceId;
final String? captchaToken;
final String? userId;
final String? accountLabel;
```

不得新增 `creditKey`、验证网址或迅雷密码持久化字段。

- [ ] **Step 4：运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_credential_test.dart test\cloud_source_repository_test.dart`

Expected: PASS。

- [ ] **Step 5：提交**

```powershell
git add lib/modules/cloud/cloud_source.dart lib/services/cloud/cloud_credential_store.dart lib/services/cloud/cloud_drive_client.dart test/xunlei_credential_test.dart test/cloud_source_repository_test.dart
git commit -m "添加迅雷来源安全凭据模型"
```

## Task 2：协议模型、响应解析与请求策略

**Files:**
- Create: `lib/services/cloud/xunlei/xunlei_models.dart`
- Create: `lib/services/cloud/xunlei/xunlei_response_parser.dart`
- Create: `lib/services/cloud/xunlei/xunlei_request_policy.dart`
- Create: `test/fixtures/xunlei/login_success.json`
- Create: `test/fixtures/xunlei/verification_required.json`
- Create: `test/fixtures/xunlei/refresh_success.json`
- Create: `test/fixtures/xunlei/account.json`
- Create: `test/fixtures/xunlei/directory_page_1.json`
- Create: `test/fixtures/xunlei/directory_page_2.json`
- Create: `test/fixtures/xunlei/file_detail.json`
- Create: `test/xunlei_response_parser_test.dart`
- Create: `test/xunlei_request_policy_test.dart`

- [ ] **Step 1：写失败测试，固定强类型解析和脱敏错误**

```dart
test('解析令牌目录分页和原始文件地址', () {
  const parser = XunleiResponseParser();
  final session = parser.parseSession(_fixture('refresh_success.json'));
  final page = parser.parseDirectoryPage(_fixture('directory_page_1.json'));
  final detail = parser.parseFileDetail(_fixture('file_detail.json'));

  expect(session.refreshToken, 'refresh-next-fixture');
  expect(page.nextPageToken, 'page-2');
  expect(page.files.map((file) => file.id), <String>['folder-a', 'video-a']);
  expect(detail.originalUri.scheme, 'https');
  expect(detail.transcodeUris, isNotEmpty);
});

test('畸形响应只报告类型不泄露响应内容', () {
  const secret = 'access-token-secret-fixture';
  expect(
    () => const XunleiResponseParser().parseSession(<String, Object?>{
      'access_token': secret,
    }),
    throwsA(
      isA<CloudDriveException>().having(
        (error) => error.toString(),
        '脱敏错误',
        isNot(contains(secret)),
      ),
    ),
  );
});
```

- [ ] **Step 2：写失败测试，固定验证码签名和 URL 信任边界**

```dart
test('只信任迅雷 HTTPS 验证和原画地址', () {
  const policy = XunleiRequestPolicy();
  expect(policy.isTrustedVerificationUri(
    Uri.parse('https://i.xunlei.com/verify?id=fixture'),
  ), isTrue);
  expect(policy.isTrustedVerificationUri(
    Uri.parse('http://i.xunlei.com/verify'),
  ), isFalse);
  expect(policy.isTrustedDownloadUri(Uri.parse('https://127.0.0.1/file')), isFalse);
  expect(policy.isTrustedDownloadUri(Uri.parse('https://192.168.1.2/file')), isFalse);
  expect(policy.captchaSign(timestamp: '1700000000000'), startsWith('1.'));
});
```

- [ ] **Step 3：运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_response_parser_test.dart test\xunlei_request_policy_test.dart`

Expected: FAIL，新增类型和解析器尚不存在。

- [ ] **Step 4：实现强类型模型与解析器**

模型至少包含：

```dart
class XunleiSession {
  const XunleiSession({
    required this.tokenType,
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.userId,
  });
  final String tokenType;
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String userId;
  String get authorization => '$tokenType $accessToken';
}

class XunleiDirectoryPage {
  const XunleiDirectoryPage({required this.files, this.nextPageToken});
  final List<XunleiFile> files;
  final String? nextPageToken;
}

class XunleiFileDetail {
  const XunleiFileDetail({
    required this.file,
    required this.originalUri,
    required this.transcodeUris,
  });
  final XunleiFile file;
  final Uri originalUri;
  final List<Uri> transcodeUris;
}

class XunleiVerificationRequired implements Exception {
  const XunleiVerificationRequired({
    required this.uri,
    required this.creditKey,
  });
  final Uri uri;
  final String creditKey;
  @override
  String toString() => 'XunleiVerificationRequired(<redacted>)';
}
```

解析器对必填空值、负数大小、无效时间、未知 `kind`、非 HTTPS 原画地址和缺失原画地址抛出 `CloudDriveException(CloudDriveErrorType.incompatible)`。

- [ ] **Step 5：实现请求策略**

`XunleiRequestPolicy` 集中定义 `xluser-ssl.xunlei.com`、`api-pan.xunlei.com` 和受信任的迅雷验证/下载主机。使用 `crypto` 的 MD5/SHA1 实现 Device Sign 和验证码签名。客户端 profile 固定为已验证的 Android 迅雷 profile；将 Client ID、Client Version、Package Name、User-Agent 和签名盐放在该文件私有常量中，并在文件头注明协议来源和非官方兼容风险。任何允许的下载主机必须是精确主机或 `.xunlei.com`、`.sandai.net` 的子域，不能用字符串包含判断。

生产 profile 使用下列明确值，不读取用户输入，也不写入日志：

```dart
static const String clientId = 'Xp6vsxz_7IYVw2BB';
static const String clientSecret = 'Xp6vsy4tN9toTVdMSpomVdXpRmES';
static const String clientVersion = '8.31.0.9726';
static const String packageName = 'com.xunlei.downloadprovider';
static const String userAgent =
    'ANDROID-com.xunlei.downloadprovider/8.31.0.9726 '
    'netWorkType/5G appid/40 deviceName/Xiaomi_M2004j7ac '
    'deviceModel/M2004J7AC OSVersion/12 protocolVersion/301 '
    'platformVersion/10 sdkVersion/512000 Oauth2Client/0.9 '
    '(Linux 4_14_186-perf-gddfs8vbb238b) (JAVA 0)';
static const String downloadUserAgent =
    'Dalvik/2.1.0 (Linux; U; Android 12; M2004J7AC Build/SP1A.210812.016)';
static const List<String> captchaSalts = <String>[
  '9uJNVj/wLmdwKrJaVj/omlQ',
  'Oz64Lp0GigmChHMf/6TNfxx7O9PyopcczMsnf',
  'Eb+L7Ce+Ej48u',
  'jKY0',
  'ASr0zCl6v8W4aidjPK5KHd1Lq3t+vBFf41dqv5+fnOd',
  'wQlozdg6r1qxh0eRmt3QgNXOvSZO6q/GXK',
  'gmirk+ciAvIgA/cxUUCema47jr/YToixTT+Q6O',
  '5IiCoM9B1/788ntB',
  'P07JH0h6qoM6TSUAK2aL9T5s2QBVeY9JWvalf',
  '+oK0AN',
];
```

```dart
Map<String, String> apiHeaders({required String deviceId}) => <String, String>{
  'accept': 'application/json;charset=UTF-8',
  'user-agent': userAgent,
  'x-device-id': deviceId,
  'x-client-id': clientId,
  'x-client-version': clientVersion,
};
```

- [ ] **Step 6：运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_response_parser_test.dart test\xunlei_request_policy_test.dart`

Expected: PASS。

- [ ] **Step 7：提交**

```powershell
git add lib/services/cloud/xunlei test/fixtures/xunlei test/xunlei_response_parser_test.dart test/xunlei_request_policy_test.dart
git commit -m "实现迅雷协议解析和请求策略"
```

## Task 3：登录 API 与浏览器验证状态机

**Files:**
- Create: `lib/services/cloud/xunlei/xunlei_api_client.dart`
- Create: `lib/services/cloud/xunlei/xunlei_authorization_controller.dart`
- Create: `test/xunlei_api_client_test.dart`
- Create: `test/xunlei_authorization_controller_test.dart`

- [ ] **Step 1：写失败测试，固定登录请求、刷新和错误映射**

使用 Dio 测试适配器记录请求，断言：

```dart
expect(request.uri.host, 'xluser-ssl.xunlei.com');
expect(request.headers, containsPair('x-device-id', deviceId));
expect(await api.refresh('refresh-fixture'), isA<XunleiSession>());
expect(api.toString(), isNot(contains('password-fixture')));
```

测试适配器允许断言登录请求体把密码发往精确的迅雷登录主机，但抛出的异常、`toString()` 和记录器输出不得包含密码。分别覆盖网络、超时、`401/403`、`429`、协议错误和 `review_panel` 验证挑战。

- [ ] **Step 2：写失败测试，固定密码生命周期与验证状态**

```dart
test('需要验证时只在会话内保留秘密且取消后不可重试', () async {
  final gateway = _ChallengeGateway();
  final controller = XunleiAuthorizationController(
    gatewayFactory: () => gateway,
    now: () => DateTime.utc(2026, 7, 28),
  );

  await expectLater(
    controller.login(identifier: '13800000000', password: 'password-fixture'),
    throwsA(isA<XunleiVerificationRequired>()),
  );
  expect(controller.verificationUri, isNotNull);
  controller.cancelVerification();
  expect(controller.verificationUri, isNull);
  await expectLater(controller.completeVerification(),
      throwsA(isA<CloudDriveException>()));
  expect(controller.toString(), isNot(contains('password-fixture')));
});
```

另测登录成功返回的 `CloudCredential` 不含密码和 Access Token、十分钟验证超时、验证成功清空临时状态、失败不产生凭据。

- [ ] **Step 3：运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_api_client_test.dart test\xunlei_authorization_controller_test.dart`

Expected: FAIL，API 和控制器不存在。

- [ ] **Step 4：实现 `XunleiAuthGateway` 和 API 客户端**

```dart
abstract interface class XunleiAuthGateway {
  Future<XunleiSession> login({
    required String identifier,
    required String password,
    required String deviceId,
    String? captchaToken,
    String? creditKey,
  });
  Future<XunleiSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? captchaToken,
  });
  Future<XunleiAccount> account(XunleiSession session);
  Future<void> close();
}
```

登录顺序固定为 Core Login → Captcha Init → Sign-in Token。`review_panel` 解析为 `XunleiVerificationRequired`；API 错误只保留错误码和阶段。Dio 超时分别设置为 10、15、30 秒，`validateStatus` 返回 true 后统一映射状态。

- [ ] **Step 5：实现控制器状态机**

```dart
enum XunleiAuthorizationState {
  idle,
  signingIn,
  verificationRequired,
  verifying,
  authorized,
  failed,
}
```

控制器内部仅在 `verificationRequired` 状态保存账号、密码和 Credit Key；成功、失败、取消、超时和 `dispose()` 均调用同一个 `_clearPendingSecrets()`。生成 32 位随机十六进制 Device ID。成功凭据只包含 Refresh Token、Device ID、Captcha Token、User ID 和脱敏 Account Label。

- [ ] **Step 6：运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_api_client_test.dart test\xunlei_authorization_controller_test.dart`

Expected: PASS。

- [ ] **Step 7：提交**

```powershell
git add lib/services/cloud/xunlei/xunlei_api_client.dart lib/services/cloud/xunlei/xunlei_authorization_controller.dart test/xunlei_api_client_test.dart test/xunlei_authorization_controller_test.dart
git commit -m "实现迅雷登录和设备验证"
```

## Task 4：只读 Drive 客户端与分页扫描

**Files:**
- Create: `lib/services/cloud/xunlei/xunlei_drive_client.dart`
- Create: `test/xunlei_drive_client_test.dart`
- Modify: `test/cloud_media_indexer_test.dart`

- [ ] **Step 1：写失败测试，固定 Refresh Token 鉴权与并发刷新**

```dart
test('并发目录请求只刷新一次并更新安全凭据', () async {
  final api = _RecordingXunleiApi();
  final store = MemoryCloudCredentialStore();
  await store.write('xunlei-a', const CloudCredential(
    refreshToken: 'refresh-old',
    deviceId: '0123456789abcdef0123456789abcdef',
  ));
  final client = XunleiDriveClient(
    source: _source,
    credentialStore: store,
    apiFactory: (_) => api,
  );

  await Future.wait(<Future<Object?>>[
    client.listDirectory(const CloudRemoteRef(id: '0', path: '/')),
    client.listDirectory(const CloudRemoteRef(id: '0', path: '/')),
  ]);
  expect(api.refreshCalls, 1);
  expect((await store.read('xunlei-a'))?.refreshToken, 'refresh-next');
});
```

- [ ] **Step 2：写失败测试，固定分页、去重、稳定路径与原画**

覆盖两个分页、重复文件 ID、重复页令牌、目录/文件、非法分页、`getFile` 和 `resolvePlayback`。原画断言：

```dart
final resource = await client.resolvePlayback(
  const CloudRemoteRef(id: 'video-a', path: '/影视/A.mkv'),
);
expect(resource.uri, Uri.parse('https://download.xunlei.com/original'));
expect(resource.transport, CloudPlaybackTransport.rangeRelay);
expect(resource.networkRoute, PlaybackNetworkRoute.direct);
expect(resource.headers['User-Agent'], isNotEmpty);
expect(resource.uri.toString(), isNot(contains('transcode')));
```

- [ ] **Step 3：运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_drive_client_test.dart test\cloud_media_indexer_test.dart`

Expected: FAIL，Drive 客户端不存在。

- [ ] **Step 4：实现只读客户端**

```dart
class XunleiDriveClient implements CloudDriveClient {
  static const int _pageSize = 100;
  static const int _maxPages = 200;

  Future<XunleiApi> _ensureApi() async {
    final current = _api;
    if (current != null && current.hasUsableSession) return current;
    await (_refreshing ??= _refreshSession()).whenComplete(() {
      _refreshing = null;
    });
    return _api!;
  }
}
```

`authenticate()` 只接受含 Refresh Token 和合法 Device ID 的凭据，刷新并验证账号后才写入凭据仓储。分页以 `next_page_token` 驱动，以文件 ID 去重，并维护已见页令牌集合；空令牌结束，重复令牌或超过 200 页抛出 `incompatible`。`resolvePlayback()` 必须使用 `web_content_link`，即使响应包含 `medias` 也不得选择转码链接。

- [ ] **Step 5：运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_drive_client_test.dart test\cloud_media_indexer_test.dart`

Expected: PASS。

- [ ] **Step 6：提交**

```powershell
git add lib/services/cloud/xunlei/xunlei_drive_client.dart test/xunlei_drive_client_test.dart test/cloud_media_indexer_test.dart
git commit -m "实现迅雷目录扫描和原画解析"
```

## Task 5：迅雷原画 Range 读取器

**Files:**
- Create: `lib/services/cloud/xunlei/xunlei_range_remote_reader.dart`
- Create: `test/xunlei_range_remote_reader_test.dart`
- Modify: `lib/features/player/application/cloud_playback_cache_policy.dart`
- Modify: `test/cloud_playback_cache_policy_test.dart`

- [ ] **Step 1：写失败测试，固定 Range 与重定向安全边界**

测试服务器分别返回：合法 `206`、缺失/错误 `Content-Range`、长度不符、合法探测 `200`、五次以内 HTTPS 重定向、私网重定向、`401/403`、连接失败与延迟响应。关键断言：

```dart
expect(await reader.probe(),
  isA<XunleiRemoteMetadata>().having((m) => m.totalLength, '长度', 1024));
expect(refreshCalls, 1);
expect(secondAuthenticationFailure, throwsA(
  isA<CloudRangeRemoteAuthenticationException>(),
));
await reader.close();
expect(pendingRead, throwsA(anyOf(isA<StateError>(), isA<SocketException>())));
```

- [ ] **Step 2：运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_range_remote_reader_test.dart test\cloud_playback_cache_policy_test.dart`

Expected: FAIL，读取器不存在。

- [ ] **Step 3：实现读取器**

`XunleiRangeRemoteReader` 实现 `CloudRangeRemoteReader`，结构保持独立：

```dart
class XunleiRangeRemoteReader implements CloudRangeRemoteReader {
  XunleiRangeRemoteReader({
    required CloudRangeRemoteResource resource,
    required Future<CloudRangeRemoteResource> Function() refreshResource,
    XunleiRemoteUriValidator? uriValidator,
    XunleiHttpClientFactory? httpClientFactory,
    this.requestTimeout = const Duration(seconds: 15),
  });
}
```

每次请求设置 `Range` 和 `Accept-Encoding: identity`，只传资源允许的 `User-Agent`。最多 5 次受信任 HTTPS 重定向；`401/403` 共用一个刷新 Future 且整个读取器生命周期只用一次；传输错误按 500ms、1s、2s 重试；关闭时强制关闭全部活动 `HttpClient` 并关闭事件流。

将 `CloudPlaybackCachePolicy.quarkRelay` 重命名为 `cloudRangeRelay`，数值保持不变，并更新所有调用与测试。

- [ ] **Step 4：运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_range_remote_reader_test.dart test\cloud_playback_cache_policy_test.dart`

Expected: PASS。

- [ ] **Step 5：提交**

```powershell
git add lib/services/cloud/xunlei/xunlei_range_remote_reader.dart lib/features/player/application/cloud_playback_cache_policy.dart test/xunlei_range_remote_reader_test.dart test/cloud_playback_cache_policy_test.dart
git commit -m "实现迅雷原画分段读取"
```

## Task 6：Provider 注册、播放分发和通用错误文案

**Files:**
- Modify: `lib/services/cloud/cloud_provider_registry.dart`
- Modify: `lib/services/cloud/cloud_playback_resolver.dart`
- Modify: `test/cloud_provider_registry_test.dart`
- Modify: `test/cloud_playback_resolver_test.dart`
- Modify: `test/cloud_library_integration_test.dart`

- [ ] **Step 1：写失败测试，固定注册表所有迅雷分支**

```dart
test('迅雷注册客户端读取器名称地址和错误文案', () {
  final registry = CloudProviderRegistry(
    clientFactories: <CloudSourceType, CloudProviderClientFactory>{
      CloudSourceType.xunlei: (_, __, ___) => _FakeClient(),
    },
    rangeReaderFactories: <CloudSourceType, CloudProviderRangeReaderFactory>{
      CloudSourceType.xunlei: ({required source, required resource,
        required refreshResource, required credentialStore}) => _FakeReader(),
    },
  );
  expect(registry.providerName(CloudSourceType.xunlei), '迅雷网盘');
  expect(registry.normalizeSource(_xunlei).baseUrl, 'https://pan.xunlei.com');
  expect(registry.supportsSelfSignedCertificate(CloudSourceType.xunlei), isFalse);
  expect(registry.supportsShareTransfer(CloudSourceType.xunlei), isFalse);
});
```

- [ ] **Step 2：运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_provider_registry_test.dart test\cloud_playback_resolver_test.dart test\cloud_library_integration_test.dart`

Expected: FAIL，switch 未覆盖 `xunlei`。

- [ ] **Step 3：注册迅雷实现**

在默认工厂映射中增加 `XunleiDriveClient` 和 `XunleiRangeRemoteReader`。规范化来源：

```dart
CloudSourceType.xunlei => source.copyWith(
  baseUrl: 'https://pan.xunlei.com',
  allowSelfSignedCertificate: false,
),
```

凭据合并只保留新授权控制器产生的 Refresh Token、Device ID、Captcha Token、User ID 和 Account Label；表单空值不得清空现有有效凭据。新增文案：“迅雷登录已失效，请重新登录”“迅雷需要完成设备验证”“当前版本暂不兼容迅雷接口”“迅雷原画地址已失效”。

- [ ] **Step 4：验证播放通过 Range Relay 建立租约**

更新播放测试，断言迅雷 `CloudPlaybackResource` 进入 `CloudRangeRelayService`，关闭播放会释放读取器，刷新回调重新调用 `resolvePlayback()`，诊断文本只包含 provider、sourceId 和错误类型，不包含 URI。

- [ ] **Step 5：运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\cloud_provider_registry_test.dart test\cloud_playback_resolver_test.dart test\cloud_library_integration_test.dart`

Expected: PASS。

- [ ] **Step 6：提交**

```powershell
git add lib/services/cloud/cloud_provider_registry.dart lib/services/cloud/cloud_playback_resolver.dart test/cloud_provider_registry_test.dart test/cloud_playback_resolver_test.dart test/cloud_library_integration_test.dart
git commit -m "接入迅雷网盘公共播放链路"
```

## Task 7：迅雷来源编辑、目录选择和设置路由

**Files:**
- Create: `lib/pages/cloud/xunlei/xunlei_directory_picker.dart`
- Create: `lib/pages/cloud/xunlei/xunlei_source_editor.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `lib/pages/settings/cloud_sources_settings.dart`
- Create: `test/xunlei_source_editor_test.dart`
- Modify: `test/cloud_sources_ui_test.dart`
- Modify: `test/architecture_dependency_test.dart`

- [ ] **Step 1：写失败 Widget 测试，固定登录和验证交互**

```dart
testWidgets('迅雷账号登录后清空密码并允许选择目录', (tester) async {
  final authorization = _FakeAuthorizedController();
  await tester.pumpWidget(MaterialApp(home: XunleiSourceEditorPage(
    controller: _controller,
    credentialStore: MemoryCloudCredentialStore(),
    authorizationController: authorization,
  )));
  await tester.enterText(find.byKey(const ValueKey('xunlei-identifier')), '13800000000');
  await tester.enterText(find.byKey(const ValueKey('xunlei-password')), 'password-fixture');
  await tester.tap(find.text('登录迅雷'));
  await tester.pumpAndSettle();
  expect(find.text('登录成功'), findsOneWidget);
  expect(tester.widget<TextField>(find.byKey(
    const ValueKey('xunlei-password'))).controller?.text, isEmpty);
  expect(find.text('选择媒体目录'), findsOneWidget);
});
```

另测验证页打开失败、验证完成、取消、超时、编辑现有来源不回填密码、清除多选目录、保存回传来源 ID、失败不覆盖旧凭据和 dispose 清理控制器。

- [ ] **Step 2：运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_source_editor_test.dart test\cloud_sources_ui_test.dart test\architecture_dependency_test.dart`

Expected: FAIL，页面与路由不存在。

- [ ] **Step 3：实现目录选择包装**

```dart
class XunleiDirectoryPickerPage extends StatelessWidget {
  const XunleiDirectoryPickerPage({
    super.key,
    required this.source,
    required this.controller,
    required this.credential,
    this.initialSelection = const <CloudRemoteRef>[],
  });

  @override
  Widget build(BuildContext context) => CloudDirectoryPickerPage<List<CloudRemoteRef>>(
    title: '选择迅雷媒体目录',
    root: const CloudRemoteRef(id: '0', path: '/'),
    initialSelection: initialSelection,
    loader: (directory) => controller.browseRemoteDirectories(
      source, directory, credential: credential,
    ),
    resultBuilder: (selected) => selected,
  );
}
```

- [ ] **Step 4：实现来源编辑页**

页面持有名称、账号、密码控制器、授权控制器、根目录和已授权凭据。调用登录后必须在 `finally` 清空密码输入；验证网址用注入的 `Future<bool> Function(Uri)` 调用 `launchUrl(uri, mode: LaunchMode.externalApplication)`。只有授权凭据完整时允许选择目录和保存。保存来源固定：

```dart
CloudSource(
  id: sourceId,
  type: CloudSourceType.xunlei,
  name: name.trim(),
  baseUrl: 'https://pan.xunlei.com',
  rootPaths: rootRefs.map((ref) => ref.path).toList(growable: false),
  rootRefs: rootRefs,
  enabled: enabled,
)
```

- [ ] **Step 5：增加设置路由和来源管理入口**

注册 `/settings/cloud-sources/xunlei/edit`，从 Modular 注入 `CloudLibraryController`、`CloudCredentialStore` 与根目录刷新协调器。来源列表说明改为“管理个人夸克、百度、迅雷与 OpenList 网盘媒体来源”；新增菜单和选择页均显示“添加迅雷网盘”，`_editorRoute` 覆盖迅雷。

- [ ] **Step 6：运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\xunlei_source_editor_test.dart test\cloud_sources_ui_test.dart test\architecture_dependency_test.dart`

Expected: PASS。

- [ ] **Step 7：提交**

```powershell
git add lib/pages/cloud/xunlei lib/pages/settings/settings_module.dart lib/pages/settings/cloud_sources_settings.dart test/xunlei_source_editor_test.dart test/cloud_sources_ui_test.dart test/architecture_dependency_test.dart
git commit -m "添加迅雷来源编辑和目录选择"
```

## Task 8：网盘资源页的迅雷与 OpenList 快捷入口

**Files:**
- Modify: `lib/pages/cloud/resources/cloud_resources_page.dart`
- Modify: `test/cloud_resources_page_test.dart`

- [ ] **Step 1：写失败 Widget 测试，固定顶部菜单与空状态入口**

```dart
testWidgets('网盘资源页可直接添加迅雷和 OpenList', (tester) async {
  await tester.pumpWidget(_pageWithEmptySources());
  expect(find.text('添加迅雷网盘'), findsOneWidget);
  expect(find.text('添加 OpenList'), findsOneWidget);

  await tester.tap(find.byTooltip('添加网盘'));
  await tester.pumpAndSettle();
  expect(find.text('添加迅雷网盘'), findsOneWidget);
  expect(find.text('添加 OpenList'), findsOneWidget);
});
```

注入 `onAddXunlei` 和 `onAddOpenList`，分别断言保存后调用 `reloadSourcesAndSnapshot(preferredSourceId: sourceId)`。

- [ ] **Step 2：运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart`

Expected: FAIL，页面没有两个入口。

- [ ] **Step 3：实现统一四来源新增动作**

```dart
enum _CloudAddAction { quark, baidu, xunlei, openList }

String _routeFor(_CloudAddAction action) => switch (action) {
  _CloudAddAction.quark => '/settings/cloud-sources/quark/edit',
  _CloudAddAction.baidu => '/settings/cloud-sources/baidu/edit',
  _CloudAddAction.xunlei => '/settings/cloud-sources/xunlei/edit',
  _CloudAddAction.openList => '/settings/cloud-sources/openlist/edit',
};
```

为 Widget 增加两个可选回调。顶部菜单加入迅雷和 OpenList；空状态用 `Wrap(spacing: 12, runSpacing: 12)` 放置四个按钮，避免窄窗口溢出。OpenList 文案在入口中保持“调试中”提示，但按钮标签使用“添加 OpenList”。

- [ ] **Step 4：运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\cloud_resources_page_test.dart`

Expected: PASS。

- [ ] **Step 5：提交**

```powershell
git add lib/pages/cloud/resources/cloud_resources_page.dart test/cloud_resources_page_test.dart
git commit -m "补齐迅雷和 OpenList 资源页入口"
```

## Task 9：安全、架构和跨来源回归

**Files:**
- Modify: `test/diagnostic_log_exporter_test.dart`
- Modify: `test/runtime_identity_residue_test.dart`
- Modify: `test/cloud_library_controller_test.dart`
- Modify: `test/cloud_media_indexer_test.dart`
- Modify: `test/cloud_playback_resolver_test.dart`
- Modify: `test/windows_only_residue_test.dart`

- [ ] **Step 1：写失败安全测试，拒绝迅雷秘密进入日志和诊断包**

```dart
for (final forbidden in <String>[
  'password-fixture',
  'refresh-token-fixture',
  'access-token-fixture',
  'credit-key-fixture',
  'captcha-token-fixture',
  'https://download.xunlei.com/private-fixture',
]) {
  expect(exportedDiagnosticText, isNot(contains(forbidden)), reason: forbidden);
}
```

同时扫描活动源码，禁止 UI、异常和日志模板拼接 `password`、令牌值、验证网址查询串或原画地址。

- [ ] **Step 2：写失败跨来源测试**

覆盖迅雷与夸克/百度/OpenList 同名同路径不合并、删除迅雷来源等待扫描退出并清理凭据和索引、迅雷单目录失败保留旧缓存、TMDB 不可用时仍能扫描和播放已有索引。

- [ ] **Step 3：运行测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test test\diagnostic_log_exporter_test.dart test\runtime_identity_residue_test.dart test\cloud_library_controller_test.dart test\cloud_media_indexer_test.dart test\cloud_playback_resolver_test.dart test\windows_only_residue_test.dart`

Expected: FAIL，安全清单和迅雷集成断言尚未满足。

- [ ] **Step 4：修正暴露点和遗漏分支**

所有日志只允许：

```dart
'provider=xunlei sourceId=${source.id} stage=$stage errorType=${error.runtimeType}'
```

不得记录 `error.message`、Dio 请求/响应体或 URI。补齐遗漏的 switch、清理与来源隔离代码；不修改通用索引的数据保护语义。

- [ ] **Step 5：运行测试确认通过**

Run: `D:\flutter\bin\flutter.bat test test\diagnostic_log_exporter_test.dart test\runtime_identity_residue_test.dart test\cloud_library_controller_test.dart test\cloud_media_indexer_test.dart test\cloud_playback_resolver_test.dart test\windows_only_residue_test.dart`

Expected: PASS。

- [ ] **Step 6：提交**

```powershell
git add test/diagnostic_log_exporter_test.dart test/runtime_identity_residue_test.dart test/cloud_library_controller_test.dart test/cloud_media_indexer_test.dart test/cloud_playback_resolver_test.dart test/windows_only_residue_test.dart
git status --short
git commit -m "完善迅雷网盘安全与集成回归"
```

## Task 10：测试版版本、完整验证和签名交付

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`

- [ ] **Step 1：记录版本迭代前已安装版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, PackageFullName
```

Expected: 明确记录版本；若无输出则记录“未安装”。不能从 `pubspec.yaml` 推断。

- [ ] **Step 2：先更新版本测试并确认失败**

把预期测试版改为 `2.1.69`、构建号 `20169`，新增版本历史断言包含“迅雷网盘”“账号密码不保存”“原画播放”“OpenList 入口”“不会修改或删除”。

Run: `D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart`

Expected: FAIL，当前版本仍是 `2.1.68`。

- [ ] **Step 3：同步版本和普通用户文案**

```yaml
version: 2.1.69+20169
msix_config:
  msix_version: 2.1.69.0
```

`AppVersion.current`、README、更新弹窗、Release Notes 与版本历史全部同步。正式版 `1.0.2` 记录保持原样。文案明确迅雷为测试能力、密码不保存、只读扫描与原画播放、OpenList 快捷入口，以及不修改或删除原始文件。

- [ ] **Step 4：运行版本和针对性测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\identity_v2_zero_residue_test.dart
D:\flutter\bin\flutter.bat test test\xunlei_response_parser_test.dart test\xunlei_request_policy_test.dart test\xunlei_api_client_test.dart test\xunlei_authorization_controller_test.dart test\xunlei_drive_client_test.dart test\xunlei_range_remote_reader_test.dart test\xunlei_source_editor_test.dart test\cloud_resources_page_test.dart
```

Expected: 全部 PASS。

- [ ] **Step 5：执行完整质量门禁**

Run:

```powershell
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

Expected: 所有测试通过；`No issues found!`。

- [ ] **Step 6：执行真实账号手工验收**

在 Windows 实机依次验证：

1. 输入测试账号和密码并登录，检查密码框立即清空。
2. 若出现验证，确认系统浏览器打开迅雷 HTTPS 页面，完成后点击“验证完成”。
3. 重启应用，确认无需再次输入密码即可浏览目录。
4. 多选两个目录扫描，确认视频、字幕、TMDB、手动刮削和海报墙正常。
5. 播放一个支持 Range 的原始视频，确认字幕、选集、硬件解码和 Anime4K。
6. 断网后确认本地媒体库及已有索引仍可打开。
7. 移除迅雷来源，确认只清除来源配置、凭据、索引和缓存，不删除迅雷文件。

Expected: 七项均通过；若账号触发无法完成的协议验证，停止交付并记录脱敏错误阶段。

- [ ] **Step 7：构建、签名和验证 MSIX**

确认看影音进程已退出后执行：

```powershell
D:\flutter\bin\flutter.bat build windows --release --no-pub
& .\tool\windows\build_signed_release.ps1
```

Expected: Release 成功，SignTool 0 warning / 0 error，桌面生成：

- `C:\Users\asus\Desktop\看影音-2.1.69.msix`
- `C:\Users\asus\Desktop\看影音-2.1.69-异机安装包.zip`

独立读取 `AppxManifest.xml`，确认 Name=`com.kanyingyin.player`、Version=`2.1.69.0`、Architecture=`x64`；`Get-AuthenticodeSignature` 为 `Valid`；桌面 MSIX 与构建产物 SHA-256 相同；`kanyingyin.exe` 和 `data/app.so` 时间晚于本轮构建开始。

- [ ] **Step 8：如执行安装则再次核对已安装版本**

Run:

```powershell
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name, Version, PackageFullName
```

Expected: 若已安装本轮包则为 `2.1.69.0`；若未执行安装，明确报告仍是步骤 1 的版本。

- [ ] **Step 9：检查差异并提交交付版本**

```powershell
git diff --check
git status --short
git diff --stat
git add pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md test/version_consistency_test.dart test/version_history_current_test.dart test/identity_v2_zero_residue_test.dart
git diff --cached --check
git commit -m "接入迅雷网盘原画播放"
```

Expected: 提交成功，构建产物、证书、密码和临时夹具不进入 Git，提交后工作区干净。

## 最终核对清单

- [ ] 迅雷来源只有读取、扫描和播放能力，没有远程写接口。
- [ ] 密码、Access Token、Credit Key、验证网址和原画地址不持久化、不记录日志、不进入诊断包。
- [ ] Refresh Token、Device ID、Captcha Token 只保存在 Windows 安全存储。
- [ ] 设备验证使用系统浏览器，验证状态在完成、取消、超时和销毁时清理。
- [ ] 原画播放不回退迅雷转码，并对地址过期只刷新一次。
- [ ] OpenList 在网盘资源页顶部菜单和空状态均有入口。
- [ ] OpenList、夸克、百度和迅雷来源相互隔离。
- [ ] TMDB 不可用或断网时，本地扫描和播放继续可用。
- [ ] 全量测试、静态分析、Windows Release、签名 MSIX 和版本验证完成。
