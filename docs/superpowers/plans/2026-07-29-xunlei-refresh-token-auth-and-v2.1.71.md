# 迅雷 Refresh Token 授权与 2.1.71 交付 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 将迅雷数据源的默认登录方式改为 Refresh Token，准确识别旧验证码签名协议失效，安全记录授权阶段日志，并把全部 TMDB 与迅雷修复交付为 2.1.71 MSIX。

**Architecture:** `XunleiApiClient` 负责把服务端错误归一化并输出不含请求/响应正文的阶段日志；`XunleiAuthorizationController` 新增 Refresh Token 授权入口，刷新会话并确认账号后才生成可保存凭据；数据源编辑页默认显示 Token 表单，账号密码表单折叠为兼容入口。现有 `SecureCloudCredentialStore` 继续作为唯一持久化位置，旧凭据只在新授权验证并保存后替换。

**Tech Stack:** Flutter 3.41.9、Dart、Dio、flutter_secure_storage、flutter_test、Windows MSIX

---

### Task 1: 区分迅雷协议更新并加入脱敏阶段日志

**Files:**
- Modify: `lib/services/cloud/cloud_drive_client.dart`
- Modify: `lib/services/cloud/cloud_provider_registry.dart`
- Modify: `lib/services/cloud/xunlei/xunlei_api_client.dart`
- Modify: `test/xunlei_api_client_test.dart`
- Modify: `test/cloud_provider_registry_test.dart`

- [ ] **Step 1: 写入 `invalid captcha_sign` 和日志脱敏失败测试**

```dart
test('验证码签名失效映射为协议更新且日志不含秘密', () async {
  final logs = <String>[];
  final adapter = _QueueAdapter(<_FakeResponse>[
    const _FakeResponse(200, '{"sessionID":"session-fixture"}'),
    const _FakeResponse(
      400,
      '{"error":"invalid_argument","error_code":3,"error_description":"invalid captcha_sign secret-body"}',
    ),
  ]);
  final client = XunleiApiClient(
    deviceId: deviceId,
    dio: Dio()..httpClientAdapter = adapter,
    requestLog: logs.add,
  );

  await expectLater(
    client.login(
      identifier: 'account-secret',
      password: 'password-secret',
      deviceId: deviceId,
    ),
    throwsA(
      isA<CloudDriveException>().having(
        (error) => error.type,
        '错误类型',
        CloudDriveErrorType.protocolUpdated,
      ),
    ),
  );

  final text = logs.join('\n');
  expect(text, contains('captchaInit'));
  expect(text, contains('protocolUpdated'));
  for (final secret in <String>[
    'account-secret',
    'password-secret',
    'session-fixture',
    'secret-body',
    deviceId,
  ]) {
    expect(text, isNot(contains(secret)));
  }
});
```

在 `cloud_provider_registry_test.dart` 增加：

```dart
expect(
  message(CloudDriveErrorType.protocolUpdated),
  '迅雷登录协议已更新，请改用 Refresh Token',
);
```

- [ ] **Step 2: 运行两个测试并确认类型不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/xunlei_api_client_test.dart test/cloud_provider_registry_test.dart`

Expected: FAIL，提示 `protocolUpdated` 和 `requestLog` 不存在。

- [ ] **Step 3: 增加协议更新错误类型和全局迅雷提示**

在 `CloudDriveErrorType` 的 `incompatible` 前增加：

```dart
protocolUpdated,
```

在 `CloudProviderRegistry.errorMessage` 的迅雷分支增加：

```dart
(CloudSourceType.xunlei, CloudDriveErrorType.protocolUpdated) =>
  '迅雷登录协议已更新，请改用 Refresh Token',
```

- [ ] **Step 4: 为 API 客户端增加只包含阶段、状态和类型的日志**

在 `xunlei_api_client.dart` 增加：

```dart
import 'package:kanyingyin/utils/logger.dart';

typedef XunleiRequestLog = void Function(String message);

enum _XunleiRequestStage {
  coreLogin,
  captchaInit,
  signIn,
  refresh,
  account,
  listDirectory,
  fileDetail,
}
```

构造函数增加可注入日志出口：

```dart
XunleiRequestLog? requestLog,
```

字段和默认值为：

```dart
final XunleiRequestLog _requestLog;

_requestLog = requestLog ?? ((message) => AppLogger().i(message));
```

每个 `_request` 调用传入对应 `stage`。把 `_request` 签名改为：

```dart
Future<Map<String, Object?>> _request(
  String method,
  Uri uri, {
  required _XunleiRequestStage stage,
  Object? data,
  Map<String, String> headers = const <String, String>{},
}) async
```

请求开始、成功和失败仅记录以下固定格式，不记录 URI、头、data、json、异常文本或响应正文：

```dart
_requestLog('迅雷请求 stage=${stage.name} started');
// 成功响应：
_requestLog(
  '迅雷请求 stage=${stage.name} status=${response.statusCode ?? 0} success',
);
// 已归一化失败：
_requestLog(
  '迅雷请求 stage=${stage.name} status=${response.statusCode ?? 0} '
  'error=${errorType.name}',
);
// Dio 网络失败：
_requestLog(
  '迅雷请求 stage=${stage.name} status=0 error=${errorType.name}',
);
```

在 `_errorType` 的 HTTP 通用判断前增加精确协议识别：

```dart
final error = _optionalString(json['error'])?.toLowerCase();
final description =
    _optionalString(json['error_description'])?.toLowerCase();
if (error == 'invalid_argument' &&
    description?.contains('invalid captcha_sign') == true) {
  return CloudDriveErrorType.protocolUpdated;
}
```

- [ ] **Step 5: 运行 API 和注册表测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/xunlei_api_client_test.dart test/cloud_provider_registry_test.dart`

Expected: PASS；捕获日志不含账号、密码、设备 ID、会话或响应正文。

- [ ] **Step 6: 提交错误与日志修改**

```powershell
git add -- lib/services/cloud/cloud_drive_client.dart lib/services/cloud/cloud_provider_registry.dart lib/services/cloud/xunlei/xunlei_api_client.dart test/xunlei_api_client_test.dart test/cloud_provider_registry_test.dart
git commit -m "修复 迅雷登录协议错误提示"
```

### Task 2: 在授权控制器中实现 Refresh Token 登录

**Files:**
- Modify: `lib/services/cloud/xunlei/xunlei_authorization_controller.dart`
- Modify: `test/xunlei_authorization_controller_test.dart`

- [ ] **Step 1: 写入 Token 成功、轮换和失败提示测试**

```dart
test('Refresh Token 授权保存服务端轮换值和固定设备 ID', () async {
  final gateway = _RefreshGateway();
  final controller = XunleiAuthorizationController(
    gateway: gateway,
    deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
  );

  await controller.authorizeWithRefreshToken(
    refreshToken: 'refresh-old',
  );

  final credential = controller.authorizedCredential;
  expect(controller.state, XunleiAuthorizationState.authorized);
  expect(gateway.lastRefreshToken, 'refresh-old');
  expect(credential?.refreshToken, 'refresh-rotated');
  expect(credential?.deviceId, '0123456789abcdef0123456789abcdef');
  expect(credential?.accountLabel, '138****0000');
  expect(credential?.accessToken, isNull);
});

test('Refresh Token 失效显示明确提示且不生成凭据', () async {
  final controller = XunleiAuthorizationController(
    gateway: _RefreshGateway(
      error: const CloudDriveException(CloudDriveErrorType.authentication),
    ),
    deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
  );

  await expectLater(
    controller.authorizeWithRefreshToken(refreshToken: 'refresh-expired'),
    throwsA(isA<CloudDriveException>()),
  );
  expect(controller.authorizedCredential, isNull);
  expect(controller.errorMessage, 'Refresh Token 无效或已过期，请重新填写');
});
```

测试网关完整实现：

```dart
class _RefreshGateway implements XunleiAuthGateway {
  _RefreshGateway({this.error, this.accountError});

  final CloudDriveException? error;
  final CloudDriveException? accountError;
  String? lastRefreshToken;

  @override
  String? get captchaToken => 'captcha-fixture';

  @override
  Future<XunleiSession> refresh({
    required String refreshToken,
    required String deviceId,
    String? captchaToken,
  }) async {
    lastRefreshToken = refreshToken;
    if (error case final failure?) throw failure;
    return XunleiSession(
      tokenType: 'Bearer',
      accessToken: 'access-fixture',
      refreshToken: 'refresh-rotated',
      expiresAt: DateTime.utc(2026, 7, 29, 12),
      userId: 'user-fixture',
    );
  }

  @override
  Future<XunleiAccount> account(XunleiSession session) async {
    if (accountError case final failure?) throw failure;
    return const XunleiAccount(
      userId: 'user-fixture',
      accountLabel: '138****0000',
    );
  }

  @override
  Future<XunleiSession> login({
    required String identifier,
    required String password,
    required String deviceId,
    String? captchaToken,
    String? creditKey,
  }) async {
    if (error case final failure?) throw failure;
    return XunleiSession(
      tokenType: 'Bearer',
      accessToken: 'access-login-fixture',
      refreshToken: 'refresh-login-fixture',
      expiresAt: DateTime.utc(2026, 7, 29, 12),
      userId: 'user-fixture',
    );
  }

  @override
  Future<void> close() async {}
}
```

- [ ] **Step 2: 运行控制器测试并确认新入口不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/xunlei_authorization_controller_test.dart`

Expected: FAIL，提示 `authorizeWithRefreshToken` 不存在。

- [ ] **Step 3: 实现 Refresh Token 授权入口**

在控制器中增加：

```dart
Future<void> authorizeWithRefreshToken({
  required String refreshToken,
  String? deviceId,
}) async {
  final normalizedToken = refreshToken.trim();
  if (normalizedToken.isEmpty) {
    _fail('请填写 Refresh Token');
  }
  final normalizedDeviceId = deviceId?.trim();
  final resolvedDeviceId = normalizedDeviceId?.isNotEmpty == true
      ? normalizedDeviceId!
      : _deviceIdGenerator();
  if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(resolvedDeviceId)) {
    _fail('设备标识无效，请重新授权');
  }

  _clearPendingSecrets();
  _state = XunleiAuthorizationState.signingIn;
  _errorMessage = null;
  _notify();
  final gateway = await _gatewayForDevice(resolvedDeviceId);
  try {
    final session = await gateway.refresh(
      refreshToken: normalizedToken,
      deviceId: resolvedDeviceId,
      captchaToken: gateway.captchaToken,
    );
    final account = await gateway.account(session);
    _authorizedCredential = CloudCredential(
      refreshToken: session.refreshToken,
      deviceId: resolvedDeviceId,
      captchaToken: gateway.captchaToken,
      userId: account.userId,
      accountLabel: account.accountLabel,
    );
    _state = XunleiAuthorizationState.authorized;
    _errorMessage = null;
    _notify();
  } on CloudDriveException catch (error) {
    _state = XunleiAuthorizationState.failed;
    _errorMessage = _messageForRefresh(error.type);
    _notify();
    rethrow;
  } on Object {
    _state = XunleiAuthorizationState.failed;
    _errorMessage = '迅雷授权失败，请稍后重试';
    _notify();
    throw const CloudDriveException(CloudDriveErrorType.incompatible);
  }
}
```

为避免用户先尝试兼容登录失败、再改用 Token 时复用错误设备客户端，增加设备绑定字段与统一网关获取方法，并让现有账号密码 `_authorize` 同样调用它：

```dart
String? _gatewayDeviceId;

Future<XunleiAuthGateway> _gatewayForDevice(String deviceId) async {
  final current = _gateway;
  if (current != null &&
      (_gatewayDeviceId == null || _gatewayDeviceId == deviceId)) {
    _gatewayDeviceId ??= deviceId;
    return current;
  }
  if (current != null) await current.close();
  final replacement = _gatewayFactory(deviceId);
  _gateway = replacement;
  _gatewayDeviceId = deviceId;
  return replacement;
}
```

在 `dispose` 取出并清空 `_gateway` 时同步把 `_gatewayDeviceId` 设为 null。

增加 Refresh Token 专用提示，并在账号密码提示中加入协议更新：

```dart
static String _messageForRefresh(CloudDriveErrorType type) => switch (type) {
  CloudDriveErrorType.authentication => 'Refresh Token 无效或已过期，请重新填写',
  CloudDriveErrorType.network => '网络连接失败，请检查网络后重试',
  CloudDriveErrorType.timeout => '迅雷授权请求超时，请稍后重试',
  CloudDriveErrorType.rateLimited => '迅雷请求过于频繁，请稍后再试',
  CloudDriveErrorType.protocolUpdated => '迅雷登录协议已更新，请重新获取 Refresh Token',
  _ => '迅雷授权失败，请稍后重试',
};
```

账号密码 `_messageFor` 增加：

```dart
CloudDriveErrorType.protocolUpdated =>
  '迅雷登录协议已更新，请改用 Refresh Token',
```

- [ ] **Step 4: 增加账号查询失败不接受半成品凭据测试**

使用测试网关已经定义的 `accountError`，写入完整断言：

```dart
test('账号确认失败不接受半完成 Token 凭据', () async {
  final controller = XunleiAuthorizationController(
    gateway: _RefreshGateway(
      accountError: const CloudDriveException(CloudDriveErrorType.network),
    ),
    deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
  );

  await expectLater(
    controller.authorizeWithRefreshToken(refreshToken: 'refresh-fixture'),
    throwsA(isA<CloudDriveException>()),
  );
  expect(controller.state, XunleiAuthorizationState.failed);
  expect(controller.authorizedCredential, isNull);
});
```

同时增加错误文案参数化测试：

```dart
test('Refresh Token 授权区分网络超时限流和协议更新', () async {
  final cases = <(CloudDriveErrorType, String)>[
    (CloudDriveErrorType.network, '网络连接失败，请检查网络后重试'),
    (CloudDriveErrorType.timeout, '迅雷授权请求超时，请稍后重试'),
    (CloudDriveErrorType.rateLimited, '迅雷请求过于频繁，请稍后再试'),
    (CloudDriveErrorType.protocolUpdated, '迅雷登录协议已更新，请重新获取 Refresh Token'),
  ];
  for (final item in cases) {
    final controller = XunleiAuthorizationController(
      gateway: _RefreshGateway(error: CloudDriveException(item.$1)),
      deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
    );
    await expectLater(
      controller.authorizeWithRefreshToken(refreshToken: 'refresh-fixture'),
      throwsA(isA<CloudDriveException>()),
    );
    expect(controller.errorMessage, item.$2, reason: item.$1.name);
    controller.dispose();
  }
});

test('兼容登录遇到旧签名失效时建议改用 Refresh Token', () async {
  final controller = XunleiAuthorizationController(
    gateway: _RefreshGateway(
      error: const CloudDriveException(CloudDriveErrorType.protocolUpdated),
    ),
    deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
  );
  await expectLater(
    controller.login(identifier: 'account', password: 'password'),
    throwsA(isA<CloudDriveException>()),
  );
  expect(controller.errorMessage, '迅雷登录协议已更新，请改用 Refresh Token');
});
```

- [ ] **Step 5: 运行授权控制器测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/xunlei_authorization_controller_test.dart`

Expected: PASS；Refresh Token 成功、轮换、过期、账号确认失败和协议更新提示均有覆盖。

- [ ] **Step 6: 提交授权控制器修改**

```powershell
git add -- lib/services/cloud/xunlei/xunlei_authorization_controller.dart test/xunlei_authorization_controller_test.dart
git commit -m "新增 迅雷 Refresh Token 授权"
```

### Task 3: 将 Refresh Token 设为数据源编辑页默认入口

**Files:**
- Modify: `lib/pages/cloud/xunlei/xunlei_source_editor.dart`
- Modify: `test/xunlei_source_editor_test.dart`

- [ ] **Step 1: 写入默认界面与授权门禁测试**

```dart
testWidgets('默认显示 Refresh Token 且兼容账号密码登录折叠', (tester) async {
  final authorization = _FakeXunleiAuthorizationController();
  await tester.pumpWidget(MaterialApp(
    home: XunleiSourceEditorPage(
      authorizationController: authorization,
      credentialStore: MemoryCloudCredentialStore(),
    ),
  ));

  expect(find.byKey(const ValueKey<String>('xunlei-refresh-token')), findsOneWidget);
  expect(
    tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('xunlei-refresh-token')),
    ).obscureText,
    isTrue,
  );
  expect(find.text('验证并登录'), findsOneWidget);
  expect(find.byKey(const ValueKey<String>('xunlei-identifier')), findsNothing);
  expect(find.text('账号密码兼容登录'), findsOneWidget);
  expect(
    tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, '选择媒体目录'),
    ).onPressed,
    isNull,
  );

  await tester.enterText(
    find.byKey(const ValueKey<String>('xunlei-refresh-token')),
    'refresh-user-fixture',
  );
  await tester.tap(find.text('验证并登录'));
  await tester.pumpAndSettle();

  expect(authorization.lastRefreshToken, 'refresh-user-fixture');
  expect(find.textContaining('登录成功'), findsOneWidget);
  expect(
    tester.widget<TextFormField>(
      find.byKey(const ValueKey<String>('xunlei-refresh-token')),
    ).controller?.text,
    isEmpty,
  );
});
```

- [ ] **Step 2: 运行界面测试并确认默认入口失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/xunlei_source_editor_test.dart`

Expected: FAIL；当前页面只有账号密码表单。

- [ ] **Step 3: 实现 Token 输入、遮挡和重新授权**

状态增加：

```dart
late final TextEditingController _refreshTokenController;
bool _showRefreshToken = false;
```

初始化和释放控制器；增加授权方法：

```dart
// initState
_refreshTokenController = TextEditingController();

// dispose
_refreshTokenController.dispose();
```

授权方法为：

```dart
Future<void> _authorizeWithRefreshToken() async {
  final refreshToken = _refreshTokenController.text.trim();
  if (refreshToken.isEmpty) {
    _showMessage('请填写 Refresh Token');
    return;
  }
  try {
    await _authorizationController.authorizeWithRefreshToken(
      refreshToken: refreshToken,
      deviceId: _authorizedCredential?.deviceId,
    );
    _acceptAuthorizedCredential();
  } on Object {
    if (mounted) {
      _showMessage(_authorizationController.errorMessage ?? '迅雷授权失败');
    }
  } finally {
    if (mounted) _refreshTokenController.clear();
  }
}
```

来源名称下方默认放置：

```dart
TextFormField(
  key: const ValueKey<String>('xunlei-refresh-token'),
  controller: _refreshTokenController,
  obscureText: !_showRefreshToken,
  autocorrect: false,
  enableSuggestions: false,
  decoration: InputDecoration(
    labelText: 'Refresh Token',
    helperText: _isAuthorized
        ? '已授权；如需更换账号，请粘贴新的 Token'
        : '仅保存到 Windows 安全凭据，不会写入日志',
    suffixIcon: IconButton(
      onPressed: () => setState(() => _showRefreshToken = !_showRefreshToken),
      icon: Icon(
        _showRefreshToken ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
    ),
  ),
  onFieldSubmitted: (_) => _busy ? null : _authorizeWithRefreshToken(),
),
const SizedBox(height: 16),
Wrap(
  spacing: 12,
  runSpacing: 12,
  crossAxisAlignment: WrapCrossAlignment.center,
  children: <Widget>[
    FilledButton.icon(
      onPressed: _busy ? null : _authorizeWithRefreshToken,
      icon: const Icon(Icons.key_outlined),
      label: Text(
        _authorizationBusy
            ? '正在验证'
            : _isAuthorized
                ? '重新授权'
                : '验证并登录',
      ),
    ),
    if (_isAuthorized)
      Text(
        accountLabel == null || accountLabel.isEmpty
            ? '登录成功'
            : '登录成功：$accountLabel',
      ),
  ],
),
```

把原账号和密码输入、登录按钮及浏览器设备验证卡放进默认折叠的 `ExpansionTile`：

```dart
ExpansionTile(
  key: const ValueKey<String>('xunlei-compatible-login'),
  title: const Text('账号密码兼容登录'),
  subtitle: const Text('旧协议可能失效，建议优先使用 Refresh Token'),
  children: _buildCompatibleLogin(verifying),
),
```

兼容区域辅助方法完整定义为：

```dart
List<Widget> _buildCompatibleLogin(bool verifying) => <Widget>[
  TextFormField(
    key: const ValueKey<String>('xunlei-identifier'),
    controller: _identifierController,
    autocorrect: false,
    enableSuggestions: false,
    decoration: const InputDecoration(
      labelText: '迅雷账号',
      helperText: '支持手机号或迅雷账号',
    ),
  ),
  const SizedBox(height: 16),
  TextFormField(
    key: const ValueKey<String>('xunlei-password'),
    controller: _passwordController,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    decoration: const InputDecoration(
      labelText: '迅雷密码',
      helperText: '密码仅用于本次兼容登录，不会保存',
    ),
    onFieldSubmitted: (_) => _busy ? null : _login(),
  ),
  const SizedBox(height: 16),
  Align(
    alignment: Alignment.centerLeft,
    child: FilledButton.icon(
      onPressed: _busy ? null : _login,
      icon: const Icon(Icons.login_outlined),
      label: Text(_authorizationBusy ? '正在登录' : '兼容登录'),
    ),
  ),
  if (verifying) ...<Widget>[
    const SizedBox(height: 16),
    Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text('请在系统浏览器中完成迅雷设备验证'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: <Widget>[
                OutlinedButton.icon(
                  onPressed: _busy ? null : _openVerification,
                  icon: const Icon(Icons.open_in_browser_outlined),
                  label: const Text('打开验证页面'),
                ),
                FilledButton.icon(
                  onPressed: _busy ? null : _completeVerification,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: const Text('完成验证'),
                ),
                TextButton(
                  onPressed: _busy ? null : _cancelVerification,
                  child: const Text('取消验证'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  ],
];
```

- [ ] **Step 4: 更新既有账号密码界面测试**

所有需要查找 `xunlei-identifier` 或 `xunlei-password` 的测试，先执行：

```dart
await tester.tap(find.text('账号密码兼容登录'));
await tester.pumpAndSettle();
```

并把原测试中点击 `登录迅雷` 的查找改为：

```dart
await tester.tap(find.text('兼容登录'));
```

测试假控制器增加：

```dart
String? lastRefreshToken;

@override
Future<void> authorizeWithRefreshToken({
  required String refreshToken,
  String? deviceId,
}) async {
  lastRefreshToken = refreshToken;
  if (failLogin) {
    _fakeState = XunleiAuthorizationState.failed;
    _error = 'Refresh Token 无效或已过期，请重新填写';
    notifyListeners();
    throw const CloudDriveException(CloudDriveErrorType.authentication);
  }
  _authorize();
}
```

- [ ] **Step 5: 验证旧凭据不回显且失败不覆盖**

扩展现有“登录失败不覆盖已保存凭据”测试，加入以下断言；随后输入失败的新 Token，确认安全存储仍返回 `oldCredential`，账号状态仍显示原账号：

```dart
expect(
  tester.widget<TextFormField>(
    find.byKey(const ValueKey<String>('xunlei-refresh-token')),
  ).controller?.text,
  isEmpty,
);
await tester.enterText(
  find.byKey(const ValueKey<String>('xunlei-refresh-token')),
  'refresh-invalid',
);
await tester.tap(find.text('重新授权'));
await tester.pumpAndSettle();
expect(await store.read(source.id), same(oldCredential));
expect(find.textContaining('138****0000'), findsOneWidget);
```

- [ ] **Step 6: 运行迅雷界面与授权测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/xunlei_source_editor_test.dart test/xunlei_authorization_controller_test.dart test/xunlei_api_client_test.dart`

Expected: PASS，默认 Token、兼容折叠、重新授权、失败保留和设备验证均通过。

- [ ] **Step 7: 提交界面修改**

```powershell
git add -- lib/pages/cloud/xunlei/xunlei_source_editor.dart test/xunlei_source_editor_test.dart
git commit -m "调整 迅雷网盘授权入口"
```

### Task 4: 更新 2.1.71 版本契约和用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `README.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `RELEASE_NOTES.md`
- Modify: `lib/utils/version_history.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 查询并记录当前已安装版本**

Run: `Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,PackageFullName`

Expected: 当前基线为 `2.1.70.0`；如果实际结果变化，以命令结果为准并在交付记录中说明。

- [ ] **Step 2: 把应用和 MSIX 版本同步到 2.1.71**

```yaml
version: 2.1.71+20171
```

```yaml
  msix_version: 2.1.71.0
```

同步 `AppVersion.current`、README 当前版本以及三个版本契约测试中的版本和构建号。

- [ ] **Step 3: 写入面向用户的统一更新文案**

`RELEASE_NOTES.md`、`UPDATE_DIALOG_COPY.md` 和 `version_history.dart` 的当前版本必须共同包含：

```text
TMDB 主站在当前网络不可用时会自动切换到官方备用端点，不开 VPN 也能继续刮削
扩充发布站、语言、片源、音轨、季度和合集名称清理，年份与季号继续用于准确匹配
迅雷网盘默认改用 Refresh Token 授权，账号密码保留为兼容入口
迅雷旧登录协议失效时会给出明确提示，账号、密码和 Token 不会写入日志
TMDB 或迅雷暂时不可用时，本地扫描与播放继续使用；不会修改或删除原始媒体文件
```

`version_history_current_test.dart` 新增 2.1.71 测试；`version_consistency_test.dart` 当前文案关键词改为 `官方备用端点`、`Refresh Token`、`名称清理`、`日志`、`本地扫描与播放`、`不会修改或删除`。

- [ ] **Step 4: 运行版本契约测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart test/release_config_contract_test.dart`

Expected: PASS，应用版本、构建号、MSIX 版本和三处文案一致。

- [ ] **Step 5: 提交版本与文案**

```powershell
git add -- pubspec.yaml lib/core/app_version.dart README.md UPDATE_DIALOG_COPY.md RELEASE_NOTES.md lib/utils/version_history.dart test/identity_v2_zero_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "更新 2.1.71 版本说明"
```

### Task 5: 全量验证、Windows Release 和 MSIX 交付

**Files:**
- Verify: all tracked source and tests
- Generate: `build/windows/x64/runner/Release/kanyingyin.exe`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.71.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.71-异机安装包.zip`

- [ ] **Step 1: 读取并遵循 Windows MSIX 打包技能**

读取 `C:\Users\asus\.codex\skills\flutter-windows-msix-packaging\SKILL.md`，确认签名材料读取、进程检查、MSIX 清单验证和桌面交付要求。技能只影响打包动作，不改变已批准功能范围。

- [ ] **Step 2: 运行全量测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub`

Expected: 全部通过，0 failures。

- [ ] **Step 3: 运行静态分析**

Run: `D:\flutter\bin\flutter.bat analyze --no-pub`

Expected: `No issues found!`。

- [ ] **Step 4: 构建 Windows Release**

Run: `D:\flutter\bin\flutter.bat build windows --release --no-pub`

Expected: Exit code 0，`build/windows/x64/runner/Release/kanyingyin.exe` 和 `data/app.so` 为本轮非空产物。

- [ ] **Step 5: 生成签名 MSIX 和异机安装包**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File tool/windows/build_signed_release.ps1`

Expected: SignTool 验证通过；脚本核对 Identity=`com.kanyingyin.player`、Publisher=`CN=KanYingYin`、Version=`2.1.71.0`、架构=`x64`，并在桌面生成 MSIX 与 ZIP。签名密码只在脚本当前进程内解密且最终清零。

- [ ] **Step 6: 再次独立核对桌面产物和清单版本**

```powershell
Get-Item -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.71.msix", "$env:USERPROFILE\Desktop\看影音-2.1.71-异机安装包.zip" |
  Select-Object FullName,Length,LastWriteTime
Get-FileHash -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.71.msix" -Algorithm SHA256
```

使用只读 ZIP API 读取 MSIX 内的 `AppxManifest.xml`，再次确认 Identity、Publisher、Version 和 ProcessorArchitecture 与预期一致。

```powershell
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$msix = "$env:USERPROFILE\Desktop\看影音-2.1.71.msix"
$archive = [System.IO.Compression.ZipFile]::OpenRead($msix)
try {
  $entry = $archive.Entries | Where-Object FullName -eq 'AppxManifest.xml' |
    Select-Object -First 1
  if ($null -eq $entry) { throw 'MSIX 缺少 AppxManifest.xml' }
  $reader = [System.IO.StreamReader]::new($entry.Open(), [Text.Encoding]::UTF8)
  try { [xml]$manifest = $reader.ReadToEnd() } finally { $reader.Dispose() }
} finally {
  $archive.Dispose()
}
$identity = $manifest.Package.Identity
if ($identity.Name -ne 'com.kanyingyin.player' -or
    $identity.Publisher -ne 'CN=KanYingYin' -or
    $identity.Version -ne '2.1.71.0' -or
    $identity.ProcessorArchitecture -ne 'x64') {
  throw '桌面 MSIX 清单验证失败'
}
```

- [ ] **Step 7: 检查关键差异并提交遗漏的本轮文件**

```powershell
git status --short
git diff --check
git diff -- lib/services/tmdb lib/services/cloud/xunlei lib/pages/cloud/xunlei test pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart
```

只暂存本轮计划列出的相关文件；若前面均已按任务提交，此处不制造空提交。

- [ ] **Step 8: 最终状态和版本核对**

```powershell
git status --short --branch
git log -10 --oneline
Get-AppxPackage -Name com.kanyingyin.player | Select-Object Name,Version,PackageFullName
```

Expected: 工作区干净；桌面包为 2.1.71。若本轮未安装新 MSIX，已安装版本仍为 2.1.70.0，并在交付说明中明确区分“已安装版本”和“已生成安装包版本”。
