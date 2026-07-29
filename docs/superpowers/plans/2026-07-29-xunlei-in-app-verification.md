# Xunlei In-App Verification Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 Windows 看影音内用受限 WebView2 完成迅雷设备验证，验证成功后自动续登，并在明确输错密码时提供可立即重试的内联提示。

**Architecture:** API 层只负责识别登录阶段与设备验证挑战，授权控制器持有一次性账号密码和强类型挑战；独立桥接层生成文档开始脚本、解析验证结果并实施严格 URL 白名单。Windows 验证弹窗使用每次会话独立的 WebView2 用户数据目录，关闭后销毁环境并安全删除；来源编辑页只消费强类型弹窗结果，不再打开系统浏览器。

**Tech Stack:** Flutter 3.41.9、Dart 3.11、Material、ChangeNotifier、Dio、flutter_inappwebview 6.1.5、Windows WebView2、flutter_test、PowerShell、MSIX。

---

## 文件结构与职责

- `lib/services/cloud/xunlei/xunlei_models.dart`：新增不可持久化的 `XunleiVerificationChallenge`，继续保留 API 层抛出的脱敏异常。
- `lib/services/cloud/xunlei/xunlei_verification_bridge.dart`：唯一负责桥接脚本、验证结果解析和验证页导航白名单的纯 Dart 单元。
- `lib/services/cloud/xunlei/xunlei_verification_profile.dart`：唯一负责 WebView2 Runtime 检查、专用环境创建、Cookie/缓存清理、环境销毁和安全目录删除。
- `lib/pages/cloud/xunlei/xunlei_verification_dialog.dart`：Windows 验证弹窗、WebView 事件、权限拒绝、加载/重试/取消/成功交互。
- `lib/services/cloud/xunlei/xunlei_api_client.dart`：按请求阶段分类明确密码错误，不把通用 401、验证挑战或协议变化误判为密码错误。
- `lib/services/cloud/xunlei/xunlei_authorization_controller.dart`：拥有挑战和临时秘密生命周期，接收新 CreditKey 后只续登一次。
- `lib/pages/cloud/xunlei/xunlei_source_editor.dart`：启动应用内验证弹窗，并管理密码框错误、清空与焦点。
- `test/xunlei_verification_bridge_test.dart`：桥接编码、消息解析、URL 白名单测试。
- `test/xunlei_verification_profile_test.dart`：Runtime 缺失、会话路径和越界删除保护测试。
- `test/xunlei_verification_dialog_test.dart`：不创建真实平台视图的弹窗状态与交互测试。
- `test/xunlei_api_client_test.dart`、`test/xunlei_authorization_controller_test.dart`、`test/xunlei_source_editor_test.dart`：端到端覆盖错误分类、自动续登和设置页行为。
- `test/windows_only_residue_test.dart`：把“系统浏览器验证”门禁替换为“仅受限 WebView2 验证”门禁。

## 固定安全常量与结果约定

实施中统一使用以下名称，后续任务不得另起同义类型或方法：

```dart
const xunleiVerificationEntryUri =
    'https://i.xunlei.com/xlcaptcha/android.html';
const xunleiVerificationHandlerName = 'xunleiVerificationResult';

enum XunleiVerificationOutcome { success, cancelled, failed, incompatible }

enum XunleiVerificationDialogOutcome { verified, cancelled, failed }
```

页面桥接只接受官方容器当前使用的三参数入口：

```javascript
XLJSWebViewBridge.sendMessage(name, data, callbackName)
```

- `name === 'nativeGetUserDeviceInfo'` 时，`callbackName` 必须严格等于 `reviewCb`，并同步调用 `window.reviewCb(challengeData)`。
- `name === 'nativeRecvOperationResult'` 时，只把 `data` 传给 `window.flutter_inappwebview.callHandler('xunleiVerificationResult', data)`。
- 其他消息、回调名或非 `https://i.xunlei.com` 页面一律返回 `false`。

---

### Task 1: 引入固定版本 WebView2 依赖并更新 Windows 依赖门禁

**Files:**
- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Modify: `windows/flutter/generated_plugin_registrant.cc`
- Modify: `windows/flutter/generated_plugins.cmake`
- Modify: `test/windows_only_residue_test.dart`

- [ ] **Step 1: 写入会失败的明确依赖测试**

在 `test/windows_only_residue_test.dart` 的“pubspec 只声明 Windows 所需插件和覆盖”测试末尾加入：

```dart
expect(pubspec, contains('flutter_inappwebview: 6.1.5'));
expect(pubspec, isNot(contains('webview_flutter:')));
```

- [ ] **Step 2: 运行门禁测试并确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\windows_only_residue_test.dart
```

Expected: FAIL，原因包含缺少 `flutter_inappwebview: 6.1.5`。

- [ ] **Step 3: 添加固定依赖并生成 Windows 插件注册文件**

在 `pubspec.yaml` 的 `dependencies` 中加入明确版本，不直接依赖平台实现包：

```yaml
  flutter_inappwebview: 6.1.5
```

执行：

```powershell
D:\flutter\bin\flutter.bat pub get
```

Expected: `pubspec.lock` 锁定 `flutter_inappwebview 6.1.5`，Windows endorsed implementation 锁定兼容版本；生成的注册文件包含 `flutter_inappwebview_windows`，不新增 Android、iOS、Linux 或 macOS 工程。

- [ ] **Step 4: 重新运行门禁测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\windows_only_residue_test.dart
```

Expected: PASS。

- [ ] **Step 5: 提交依赖变更**

```powershell
git add pubspec.yaml pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake test/windows_only_residue_test.dart
git commit -m "build(迅雷): 引入应用内验证组件"
```

---

### Task 2: 建立强类型挑战、桥接结果和 URL 白名单

**Files:**
- Modify: `lib/services/cloud/xunlei/xunlei_models.dart`
- Create: `lib/services/cloud/xunlei/xunlei_verification_bridge.dart`
- Create: `test/xunlei_verification_bridge_test.dart`

- [ ] **Step 1: 编写挑战脱敏、脚本编码和消息解析失败测试**

创建 `test/xunlei_verification_bridge_test.dart`，完整覆盖以下断言：

```dart
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_verification_bridge.dart';

void main() {
  const deviceId = '0123456789abcdef0123456789abcdef';
  final challenge = XunleiVerificationChallenge(
    reviewUri: Uri.parse(
      'https://i.xunlei.com/xlcaptcha/vertifyPhone.html?ticket=fixture',
    ),
    creditKey: 'credit-\"\\雪-fixture',
    deviceId: deviceId,
    deviceSign: 'div101.$deviceId-signature',
    startedAt: DateTime.utc(2026, 7, 29, 10),
  );

  test('挑战对象和桥接对象字符串不暴露秘密', () {
    final bridge = XunleiVerificationBridge(challenge);

    expect(challenge.toString(), 'XunleiVerificationChallenge(<redacted>)');
    expect(bridge.toString(), 'XunleiVerificationBridge(<redacted>)');
    expect(challenge.toString(), isNot(contains('credit-')));
  });

  test('文档开始脚本用 JSON 编码并限制来源消息和回调名', () {
    final script = XunleiVerificationBridge(challenge).documentStartScript;
    final encodedPayload = jsonEncode(<String, String>{
      'creditkey': challenge.creditKey,
      'reviewurl': challenge.reviewUri.toString(),
      'deviceid': challenge.deviceId,
      'devicesign': challenge.deviceSign,
    });

    expect(script, contains(encodedPayload));
    expect(script, contains("location.protocol !== 'https:'"));
    expect(script, contains("location.hostname !== 'i.xunlei.com'"));
    expect(script, contains("callbackName !== 'reviewCb'"));
    expect(script, contains("name === 'nativeGetUserDeviceInfo'"));
    expect(script, contains("name === 'nativeRecvOperationResult'"));
    expect(script, contains("callHandler('xunleiVerificationResult', data)"));
    expect(script, isNot(contains('console.log')));
  });

  test('同时解析字符串和 Map 成功结果', () {
    final bridge = XunleiVerificationBridge(challenge);
    for (final raw in <Object>[
      '{"roErrorCode":"0","roData":{"creditkey":"credit-new"}}',
      <String, Object?>{
        'roErrorCode': '0',
        'roData': <String, Object?>{'creditkey': 'credit-new'},
      },
    ]) {
      final result = bridge.parseOperationResult(raw);
      expect(result.outcome, XunleiVerificationOutcome.success);
      expect(result.creditKey, 'credit-new');
    }
  });

  test('取消失败缺少新密钥超长和畸形消息映射明确', () {
    final bridge = XunleiVerificationBridge(challenge);
    expect(
      bridge.parseOperationResult('{"roErrorCode":"30001"}').outcome,
      XunleiVerificationOutcome.cancelled,
    );
    expect(
      bridge.parseOperationResult('{"roErrorCode":"9"}').outcome,
      XunleiVerificationOutcome.failed,
    );
    expect(
      bridge
          .parseOperationResult('{"roErrorCode":"0","roData":{}}')
          .outcome,
      XunleiVerificationOutcome.incompatible,
    );
    expect(
      bridge.parseOperationResult(List<String>.filled(16385, 'x').join()).outcome,
      XunleiVerificationOutcome.incompatible,
    );
    expect(
      bridge.parseOperationResult(<String, Object?>{
        'roErrorCode': '0',
        'padding': List<String>.filled(16385, 'x').join(),
      }).outcome,
      XunleiVerificationOutcome.incompatible,
    );
    expect(
      bridge.parseOperationResult('{broken').outcome,
      XunleiVerificationOutcome.incompatible,
    );
  });

  test('导航策略只允许迅雷精确 HTTPS 主机和默认 443 端口', () {
    for (final value in <String>[
      'https://i.xunlei.com/xlcaptcha/android.html',
      'https://i.xunlei.com:443/xlcaptcha/vertifyPhone.html',
    ]) {
      expect(XunleiVerificationNavigationPolicy.allows(Uri.parse(value)), isTrue);
    }
    for (final value in <String>[
      'http://i.xunlei.com/xlcaptcha/android.html',
      'https://i.xunlei.com:444/xlcaptcha/android.html',
      'https://user@i.xunlei.com/xlcaptcha/android.html',
      'https://i.xunlei.com.evil.example/xlcaptcha/android.html',
      'https://evil.example/xlcaptcha/android.html',
      'file:///C:/fixture.html',
      'data:text/html,fixture',
      'javascript:alert(1)',
    ]) {
      expect(
        XunleiVerificationNavigationPolicy.allows(Uri.parse(value)),
        isFalse,
        reason: value,
      );
    }
  });
}
```

- [ ] **Step 2: 运行桥接测试并确认缺少类型**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\xunlei_verification_bridge_test.dart
```

Expected: FAIL，编译器报告 `XunleiVerificationChallenge`、`XunleiVerificationBridge` 和结果类型未定义。

- [ ] **Step 3: 添加不可持久化的挑战模型**

在 `lib/services/cloud/xunlei/xunlei_models.dart` 中加入以下完整类型；不得添加 `toJson`、Hive Adapter 或日志正文：

```dart
class XunleiVerificationChallenge {
  const XunleiVerificationChallenge({
    required this.reviewUri,
    required this.creditKey,
    required this.deviceId,
    required this.deviceSign,
    required this.startedAt,
  });

  final Uri reviewUri;
  final String creditKey;
  final String deviceId;
  final String deviceSign;
  final DateTime startedAt;

  @override
  String toString() => 'XunleiVerificationChallenge(<redacted>)';
}
```

- [ ] **Step 4: 实现纯 Dart 桥接、结果解析和 URL 策略**

创建 `lib/services/cloud/xunlei/xunlei_verification_bridge.dart`。实现必须保持下列公开接口和分支：

```dart
import 'dart:convert';

import 'package:kanyingyin/services/cloud/xunlei/xunlei_models.dart';

const String xunleiVerificationEntryUri =
    'https://i.xunlei.com/xlcaptcha/android.html';
const String xunleiVerificationHandlerName = 'xunleiVerificationResult';

enum XunleiVerificationOutcome { success, cancelled, failed, incompatible }

class XunleiVerificationResult {
  const XunleiVerificationResult._(this.outcome, {this.creditKey});

  const XunleiVerificationResult.success(String creditKey)
      : this._(XunleiVerificationOutcome.success, creditKey: creditKey);
  const XunleiVerificationResult.cancelled()
      : this._(XunleiVerificationOutcome.cancelled);
  const XunleiVerificationResult.failed()
      : this._(XunleiVerificationOutcome.failed);
  const XunleiVerificationResult.incompatible()
      : this._(XunleiVerificationOutcome.incompatible);

  final XunleiVerificationOutcome outcome;
  final String? creditKey;

  @override
  String toString() => 'XunleiVerificationResult(${outcome.name}, <redacted>)';
}

abstract final class XunleiVerificationNavigationPolicy {
  static bool allows(Uri uri) =>
      uri.scheme.toLowerCase() == 'https' &&
      uri.host.toLowerCase() == 'i.xunlei.com' &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443);
}

class XunleiVerificationBridge {
  XunleiVerificationBridge(this._challenge);

  static const int _maxMessageLength = 16 * 1024;
  final XunleiVerificationChallenge _challenge;

  String get documentStartScript {
    final payload = jsonEncode(<String, String>{
      'creditkey': _challenge.creditKey,
      'reviewurl': _challenge.reviewUri.toString(),
      'deviceid': _challenge.deviceId,
      'devicesign': _challenge.deviceSign,
    });
    return '''
(() => {
  if (location.protocol !== 'https:' ||
      location.hostname !== 'i.xunlei.com' ||
      (location.port !== '' && location.port !== '443')) {
    return;
  }
  const challengeData = $payload;
  const bridge = Object.freeze({
    sendMessage: function(name, data, callbackName) {
      if (name === 'nativeGetUserDeviceInfo') {
        if (callbackName !== 'reviewCb' || typeof window.reviewCb !== 'function') {
          return false;
        }
        window.reviewCb(challengeData);
        return true;
      }
      if (name === 'nativeRecvOperationResult') {
        window.flutter_inappwebview
            .callHandler('xunleiVerificationResult', data);
        return true;
      }
      return false;
    }
  });
  Object.defineProperty(window, 'XLJSWebViewBridge', {
    value: bridge,
    configurable: false,
    enumerable: false,
    writable: false
  });
})();
''';
  }

  XunleiVerificationResult parseOperationResult(Object? raw) {
    Object? decoded = raw;
    if (raw is String) {
      if (raw.length > _maxMessageLength) {
        return const XunleiVerificationResult.incompatible();
      }
      try {
        decoded = jsonDecode(raw);
      } on FormatException {
        return const XunleiVerificationResult.incompatible();
      }
    } else if (raw is Map) {
      try {
        if (jsonEncode(raw).length > _maxMessageLength) {
          return const XunleiVerificationResult.incompatible();
        }
      } on JsonUnsupportedObjectError {
        return const XunleiVerificationResult.incompatible();
      }
    }
    if (decoded is! Map) {
      return const XunleiVerificationResult.incompatible();
    }
    final message = Map<String, Object?>.from(decoded);
    final errorCode = _string(message['roErrorCode']);
    if (errorCode == '30001') {
      return const XunleiVerificationResult.cancelled();
    }
    if (errorCode != '0') {
      return const XunleiVerificationResult.failed();
    }
    final data = message['roData'];
    if (data is! Map) {
      return const XunleiVerificationResult.incompatible();
    }
    final creditKey = _string(data['creditkey']);
    return creditKey == null
        ? const XunleiVerificationResult.incompatible()
        : XunleiVerificationResult.success(creditKey);
  }

  String? _string(Object? value) {
    if (value is! String) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  @override
  String toString() => 'XunleiVerificationBridge(<redacted>)';
}
```

- [ ] **Step 5: 格式化并运行桥接测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\services\cloud\xunlei\xunlei_models.dart lib\services\cloud\xunlei\xunlei_verification_bridge.dart test\xunlei_verification_bridge_test.dart
D:\flutter\bin\flutter.bat test test\xunlei_verification_bridge_test.dart
```

Expected: PASS；测试输出和对象 `toString()` 均不包含 CreditKey、Review URL、设备 ID 或设备签名。

- [ ] **Step 6: 提交桥接模型**

```powershell
git add lib/services/cloud/xunlei/xunlei_models.dart lib/services/cloud/xunlei/xunlei_verification_bridge.dart test/xunlei_verification_bridge_test.dart
git commit -m "feat(迅雷): 建立安全设备验证桥接"
```

---

### Task 3: 只在核心登录明确失败时分类密码错误

**Files:**
- Modify: `lib/services/cloud/cloud_drive_client.dart`
- Modify: `lib/services/cloud/xunlei/xunlei_api_client.dart`
- Modify: `lib/services/cloud/xunlei/xunlei_authorization_controller.dart`
- Modify: `lib/services/cloud/cloud_provider_registry.dart`
- Modify: `test/xunlei_api_client_test.dart`
- Modify: `test/xunlei_authorization_controller_test.dart`
- Modify: `test/cloud_provider_registry_test.dart`

- [ ] **Step 1: 编写明确密码错误与非密码错误分类测试**

在 `test/xunlei_api_client_test.dart` 增加表驱动测试；每个 case 只返回一次核心登录响应：

```dart
test('只有核心登录明确密码错误才映射 invalidPassword', () async {
  final cases = <(int, String, CloudDriveErrorType)>[
    (401, '{"error":"invalid_password"}', CloudDriveErrorType.invalidPassword),
    (400, '{"error":"password_error"}', CloudDriveErrorType.invalidPassword),
    (
      400,
      '{"error":"invalid_argument","error_description":"密码错误"}',
      CloudDriveErrorType.invalidPassword,
    ),
    (
      401,
      '{"error":"authentication_failed","error_description":"bad credentials"}',
      CloudDriveErrorType.authentication,
    ),
    (
      400,
      '{"error":"invalid_argument","error_description":"invalid captcha_sign"}',
      CloudDriveErrorType.protocolUpdated,
    ),
  ];

  for (final item in cases) {
    final client = XunleiApiClient(
      deviceId: deviceId,
      dio: Dio()..httpClientAdapter = _QueueAdapter(<_FakeResponse>[
        _FakeResponse(item.$1, item.$2),
      ]),
    );
    await expectLater(
      client.login(
        identifier: 'account-fixture',
        password: 'password-fixture',
        deviceId: deviceId,
      ),
      throwsA(
        isA<CloudDriveException>().having(
          (error) => error.type,
          '错误类型',
          item.$3,
        ),
      ),
    );
    await client.close();
  }
});
```

保留现有 `review_panel` 测试，它必须继续抛 `XunleiVerificationRequired`，不能进入 `invalidPassword`。

- [ ] **Step 2: 编写控制器和 Provider 文案失败测试**

在 `test/xunlei_authorization_controller_test.dart` 增加：

```dart
test('明确密码错误使用独立类型和用户提示', () async {
  final controller = XunleiAuthorizationController(
    gateway: _RefreshGateway(
      error: const CloudDriveException(CloudDriveErrorType.invalidPassword),
    ),
    deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
  );

  await expectLater(
    controller.login(identifier: 'account', password: 'wrong-password'),
    throwsA(isA<CloudDriveException>().having(
      (error) => error.type,
      '类型',
      CloudDriveErrorType.invalidPassword,
    )),
  );
  expect(controller.errorMessage, '迅雷密码错误，请重新输入');
  expect(controller.authorizedCredential, isNull);
  controller.dispose();
});
```

在 `test/cloud_provider_registry_test.dart` 对迅雷新增：

```dart
expect(
  registry.errorMessage(
    CloudSourceType.xunlei,
    const CloudDriveException(CloudDriveErrorType.invalidPassword),
  ),
  '迅雷密码错误，请重新输入',
);
```

- [ ] **Step 3: 运行三组测试并确认失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\xunlei_api_client_test.dart test\xunlei_authorization_controller_test.dart test\cloud_provider_registry_test.dart
```

Expected: FAIL，原因是 `CloudDriveErrorType.invalidPassword` 未定义。

- [ ] **Step 4: 新增错误类型并把请求阶段传入分类器**

在 `CloudDriveErrorType` 的 `authentication` 后加入：

```dart
invalidPassword,
```

将 API 失败分支改为：

```dart
throw CloudDriveException(_errorType(stage, statusCode, json));
```

将 `_errorType` 替换为下列逻辑；通用 401/403 仍是 `authentication`：

```dart
CloudDriveErrorType _errorType(
  _XunleiRequestStage stage,
  int? statusCode,
  Map<String, Object?> json,
) {
  final error = _optionalString(json['error'])?.toLowerCase();
  final description =
      _optionalString(json['error_description'])?.toLowerCase();
  if (error == 'invalid_argument' &&
      description?.contains('invalid captcha_sign') == true) {
    return CloudDriveErrorType.protocolUpdated;
  }
  if (stage == _XunleiRequestStage.coreLogin &&
      _isExplicitPasswordError(error, description)) {
    return CloudDriveErrorType.invalidPassword;
  }
  if (statusCode == 401 || statusCode == 403) {
    return CloudDriveErrorType.authentication;
  }
  if (statusCode == 404) return CloudDriveErrorType.notFound;
  if (statusCode == 429) return CloudDriveErrorType.rateLimited;
  if (statusCode != null && statusCode >= 500) {
    return CloudDriveErrorType.network;
  }
  final code = json['error_code'];
  final numericCode = code is num ? code.toInt() : int.tryParse('$code');
  return switch (numericCode) {
    9 => CloudDriveErrorType.verificationRequired,
    10 || 16 || 4121 || 4122 => CloudDriveErrorType.authentication,
    _ => CloudDriveErrorType.incompatible,
  };
}

bool _isExplicitPasswordError(String? error, String? description) {
  if (const <String>{
    'invalid_password',
    'password_error',
    'wrong_password',
  }.contains(error)) {
    return true;
  }
  final text = description ?? '';
  return text.contains('密码错误') ||
      text.contains('密码不正确') ||
      text.contains('密码有误') ||
      (text.contains('password') &&
          (text.contains('incorrect') ||
              text.contains('invalid') ||
              text.contains('wrong')));
}
```

- [ ] **Step 5: 加入控制器和 Provider 的精准文案**

在 `XunleiAuthorizationController._messageFor` 增加：

```dart
CloudDriveErrorType.invalidPassword => '迅雷密码错误，请重新输入',
```

在 `CloudProviderRegistry.errorMessage` 的迅雷分支增加：

```dart
(CloudSourceType.xunlei, CloudDriveErrorType.invalidPassword) =>
  '迅雷密码错误，请重新输入',
```

Refresh Token 文案不得加入 `invalidPassword` 分支，避免 Token 失败被称为密码错误。

- [ ] **Step 6: 格式化并运行分类测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\services\cloud\cloud_drive_client.dart lib\services\cloud\xunlei\xunlei_api_client.dart lib\services\cloud\xunlei\xunlei_authorization_controller.dart lib\services\cloud\cloud_provider_registry.dart test\xunlei_api_client_test.dart test\xunlei_authorization_controller_test.dart test\cloud_provider_registry_test.dart
D:\flutter\bin\flutter.bat test test\xunlei_api_client_test.dart test\xunlei_authorization_controller_test.dart test\cloud_provider_registry_test.dart
```

Expected: PASS；`invalid captcha_sign`、通用 401、设备验证挑战和 Refresh Token 失败都不映射为密码错误。

- [ ] **Step 7: 提交错误分类**

```powershell
git add lib/services/cloud/cloud_drive_client.dart lib/services/cloud/xunlei/xunlei_api_client.dart lib/services/cloud/xunlei/xunlei_authorization_controller.dart lib/services/cloud/cloud_provider_registry.dart test/xunlei_api_client_test.dart test/xunlei_authorization_controller_test.dart test/cloud_provider_registry_test.dart
git commit -m "fix(迅雷): 区分明确密码错误"
```

---

### Task 4: 让授权控制器用新 CreditKey 自动续登且阻止验证循环

**Files:**
- Modify: `lib/services/cloud/xunlei/xunlei_authorization_controller.dart`
- Modify: `test/xunlei_authorization_controller_test.dart`

- [ ] **Step 1: 把现有验证测试改为完整挑战与新 CreditKey**

将控制器测试中的 `verificationUri` 断言改为：

```dart
final challenge = controller.verificationChallenge;
expect(challenge?.reviewUri.host, 'i.xunlei.com');
expect(challenge?.creditKey, 'credit-initial');
expect(challenge?.deviceId, '0123456789abcdef0123456789abcdef');
expect(challenge?.deviceSign, startsWith('div101.'));
expect(challenge?.startedAt, DateTime.utc(2026, 7, 28, 10));
```

将成功续登调用和断言改为：

```dart
await controller.completeVerification(creditKey: 'credit-new');
expect(gateway.lastCreditKey, 'credit-new');
expect(gateway.loginCalls, 2);
expect(controller.verificationChallenge, isNull);
expect(controller.state, XunleiAuthorizationState.authorized);
```

把 `_FakeGateway._loginCalls` 改为可断言字段：

```dart
var loginCalls = 0;
```

- [ ] **Step 2: 新增空新密钥、重复挑战和失败清理测试**

新增以下测试：

```dart
test('验证成功必须提供新 CreditKey', () async {
  final controller = XunleiAuthorizationController(
    gateway: _FakeGateway(challengeFirst: true),
    deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
  );
  await expectLater(
    controller.login(identifier: 'user', password: 'password'),
    throwsA(isA<XunleiVerificationRequired>()),
  );
  await expectLater(
    controller.completeVerification(creditKey: '   '),
    throwsA(isA<CloudDriveException>().having(
      (error) => error.type,
      '类型',
      CloudDriveErrorType.incompatible,
    )),
  );
  expect(controller.verificationChallenge, isNull);
  expect(controller.authorizedCredential, isNull);
  controller.dispose();
});

test('续登再次收到挑战时停止循环并清除秘密', () async {
  final gateway = _FakeGateway(challengeEveryTime: true);
  final controller = XunleiAuthorizationController(
    gateway: gateway,
    deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
  );
  await expectLater(
    controller.login(identifier: 'user', password: 'password-secret'),
    throwsA(isA<XunleiVerificationRequired>()),
  );
  await expectLater(
    controller.completeVerification(creditKey: 'credit-new'),
    throwsA(isA<CloudDriveException>().having(
      (error) => error.type,
      '类型',
      CloudDriveErrorType.verificationRequired,
    )),
  );
  expect(gateway.loginCalls, 2);
  expect(controller.verificationChallenge, isNull);
  expect(controller.errorMessage, '迅雷再次要求设备验证，请重新登录');
  expect(controller.toString(), isNot(contains('password-secret')));
  controller.dispose();
});

test('页面失败会结束验证并清除挑战', () async {
  final controller = XunleiAuthorizationController(
    gateway: _FakeGateway(challengeFirst: true),
    deviceIdGenerator: () => '0123456789abcdef0123456789abcdef',
  );
  await expectLater(
    controller.login(identifier: 'user', password: 'password'),
    throwsA(isA<XunleiVerificationRequired>()),
  );
  controller.failVerification('迅雷验证页面加载失败');
  expect(controller.state, XunleiAuthorizationState.failed);
  expect(controller.verificationChallenge, isNull);
  expect(controller.errorMessage, '迅雷验证页面加载失败');
  controller.dispose();
});
```

- [ ] **Step 3: 运行控制器测试并确认签名与 getter 失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\xunlei_authorization_controller_test.dart
```

Expected: FAIL，原因包括缺少 `verificationChallenge`、`failVerification` 以及 `completeVerification({required creditKey})`。

- [ ] **Step 4: 用一个强类型挑战替代分散字段**

在控制器中删除 `_verificationUri`、`_pendingCreditKey`、`_verificationStartedAt`，新增：

```dart
XunleiVerificationChallenge? _verificationChallenge;

XunleiVerificationChallenge? get verificationChallenge =>
    _verificationChallenge;
```

首次捕获挑战时构造：

```dart
_verificationChallenge = XunleiVerificationChallenge(
  reviewUri: challenge.uri,
  creditKey: challenge.creditKey,
  deviceId: deviceId,
  deviceSign: _policy.deviceSign(deviceId),
  startedAt: _now().toUtc(),
);
```

`_clearPendingSecrets()` 必须把 `_verificationChallenge` 设为 `null`。

- [ ] **Step 5: 修改完成验证与授权重试状态机**

使用下列公开签名：

```dart
Future<void> completeVerification({required String creditKey}) async
```

方法必须按顺序执行：

```dart
final challenge = _verificationChallenge;
if (_state != XunleiAuthorizationState.verificationRequired ||
    challenge == null ||
    _pendingIdentifier == null ||
    _pendingPassword == null ||
    _pendingDeviceId == null) {
  _fail('没有可继续的迅雷验证');
}
if (_now().toUtc().difference(challenge.startedAt) > _verificationLifetime) {
  _clearPendingSecrets();
  _state = XunleiAuthorizationState.failed;
  _errorMessage = '迅雷验证已过期，请重新登录';
  _notify();
  throw const CloudDriveException(CloudDriveErrorType.verificationRequired);
}
final normalizedCreditKey = creditKey.trim();
if (normalizedCreditKey.isEmpty) {
  _clearPendingSecrets();
  _state = XunleiAuthorizationState.failed;
  _errorMessage = '迅雷设备验证结果不兼容，请重新登录';
  _notify();
  throw const CloudDriveException(CloudDriveErrorType.incompatible);
}
_state = XunleiAuthorizationState.verifying;
_errorMessage = null;
_notify();
await _authorize(
  creditKey: normalizedCreditKey,
  isVerificationRetry: true,
);
```

把初次登录调用改为：

```dart
await _authorize(creditKey: null, isVerificationRetry: false);
```

把 `_authorize` 签名改为：

```dart
Future<void> _authorize({
  required String? creditKey,
  required bool isVerificationRetry,
}) async
```

在 `on XunleiVerificationRequired` 的最前面加入重复挑战保护：

```dart
if (isVerificationRetry) {
  _clearPendingSecrets();
  _state = XunleiAuthorizationState.failed;
  _errorMessage = '迅雷再次要求设备验证，请重新登录';
  _notify();
  throw const CloudDriveException(CloudDriveErrorType.verificationRequired);
}
```

- [ ] **Step 6: 提供失败结束入口并保持取消语义**

加入：

```dart
void failVerification(String message) {
  _clearPendingSecrets();
  _state = XunleiAuthorizationState.failed;
  _errorMessage = message;
  _notify();
}
```

`cancelVerification()` 继续回到 `idle` 且不显示失败；`dispose()`、超时、成功、失败和重复挑战都必须清除挑战引用。

- [ ] **Step 7: 格式化并运行控制器测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\services\cloud\xunlei\xunlei_authorization_controller.dart test\xunlei_authorization_controller_test.dart
D:\flutter\bin\flutter.bat test test\xunlei_authorization_controller_test.dart
```

Expected: PASS；续登调用总数严格为 2，第二次挑战不产生第三次请求。

- [ ] **Step 8: 提交授权状态机**

```powershell
git add lib/services/cloud/xunlei/xunlei_authorization_controller.dart test/xunlei_authorization_controller_test.dart
git commit -m "feat(迅雷): 验证成功后自动续登"
```

---

### Task 5: 创建独立 WebView2 Profile 并安全清理临时数据

**Files:**
- Create: `lib/services/cloud/xunlei/xunlei_verification_profile.dart`
- Create: `test/xunlei_verification_profile_test.dart`

- [ ] **Step 1: 编写 Runtime 缺失与目录边界失败测试**

创建 `test/xunlei_verification_profile_test.dart`，用系统临时目录测试，不创建真实 WebView2：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/xunlei/xunlei_verification_profile.dart';
import 'package:path/path.dart' as p;

void main() {
  test('WebView2 Runtime 缺失返回可识别错误', () async {
    final factory = XunleiVerificationProfileFactory(
      availableVersionLoader: () async => null,
      supportDirectoryLoader: () async => Directory.systemTemp,
    );
    await expectLater(
      factory.create(),
      throwsA(isA<XunleiVerificationProfileException>().having(
        (error) => error.type,
        '类型',
        XunleiVerificationProfileError.runtimeUnavailable,
      )),
    );
  });

  test('只删除专用根目录中的直接会话子目录', () async {
    final root = await Directory.systemTemp.createTemp('xunlei-profile-root-');
    final outside = await Directory.systemTemp.createTemp('xunlei-profile-outside-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
      if (await outside.exists()) await outside.delete(recursive: true);
    });
    final session = Directory(
      p.join(root.path, 'session-0123456789abcdef0123456789abcdef'),
    );
    await session.create();

    expect(
      XunleiVerificationProfileFactory.isSafeSessionDirectory(root, session),
      isTrue,
    );
    expect(
      XunleiVerificationProfileFactory.isSafeSessionDirectory(root, outside),
      isFalse,
    );
    await XunleiVerificationProfileFactory.deleteSessionDirectory(
      root: root,
      session: session,
    );
    expect(await session.exists(), isFalse);
    await expectLater(
      XunleiVerificationProfileFactory.deleteSessionDirectory(
        root: root,
        session: outside,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await outside.exists(), isTrue);
  });
}
```

- [ ] **Step 2: 运行 Profile 测试并确认文件缺失**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\xunlei_verification_profile_test.dart
```

Expected: FAIL，原因是 Profile 类型未定义。

- [ ] **Step 3: 实现 Runtime 检查、专用路径和环境创建**

创建 `lib/services/cloud/xunlei/xunlei_verification_profile.dart`，公开接口固定为：

```dart
enum XunleiVerificationProfileError { runtimeUnavailable, initializationFailed }

class XunleiVerificationProfileException implements Exception {
  const XunleiVerificationProfileException(this.type);
  final XunleiVerificationProfileError type;

  @override
  String toString() => 'XunleiVerificationProfileException(${type.name})';
}

typedef XunleiAvailableVersionLoader = Future<String?> Function();
typedef XunleiSupportDirectoryLoader = Future<Directory> Function();
typedef XunleiEnvironmentLoader = Future<WebViewEnvironment> Function(
  String userDataFolder,
);

class XunleiVerificationProfileFactory {
  XunleiVerificationProfileFactory({
    XunleiAvailableVersionLoader? availableVersionLoader,
    XunleiSupportDirectoryLoader? supportDirectoryLoader,
    XunleiEnvironmentLoader? environmentLoader,
    String Function()? sessionIdGenerator,
  })  : _availableVersionLoader = availableVersionLoader ??
            (() => WebViewEnvironment.getAvailableVersion()),
        _supportDirectoryLoader =
            supportDirectoryLoader ?? getApplicationSupportDirectory,
        _environmentLoader = environmentLoader ?? _createEnvironment,
        _sessionIdGenerator = sessionIdGenerator ?? _generateSessionId;

  final XunleiAvailableVersionLoader _availableVersionLoader;
  final XunleiSupportDirectoryLoader _supportDirectoryLoader;
  final XunleiEnvironmentLoader _environmentLoader;
  final String Function() _sessionIdGenerator;

  Future<XunleiVerificationProfile> create() async {
    String? version;
    try {
      version = await _availableVersionLoader();
    } on Object {
      throw const XunleiVerificationProfileException(
        XunleiVerificationProfileError.initializationFailed,
      );
    }
    if (version == null || version.trim().isEmpty) {
      throw const XunleiVerificationProfileException(
        XunleiVerificationProfileError.runtimeUnavailable,
      );
    }
    try {
      final support = await _supportDirectoryLoader();
      final root = Directory(p.join(
        support.path,
        AppIdentity.storageNamespace,
        'webview',
        'xunlei',
      ));
      final sessionId = _sessionIdGenerator();
      if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(sessionId)) {
        throw const FormatException('invalid session id');
      }
      final session = Directory(p.join(root.path, 'session-$sessionId'));
      await session.create(recursive: true);
      try {
        final environment = await _environmentLoader(session.path);
        return XunleiVerificationProfile._(
          rootDirectory: root,
          sessionDirectory: session,
          environment: environment,
        );
      } on Object {
        try {
          await deleteSessionDirectory(root: root, session: session);
        } on Object {
          AppLogger().w(
            'XunleiVerificationProfile: initialization cleanup failed',
          );
        }
        rethrow;
      }
    } on XunleiVerificationProfileException {
      rethrow;
    } on Object {
      throw const XunleiVerificationProfileException(
        XunleiVerificationProfileError.initializationFailed,
      );
    }
  }

  static Future<WebViewEnvironment> _createEnvironment(String path) =>
      WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(userDataFolder: path),
      );

  static String _generateSessionId() {
    final random = Random.secure();
    return List<String>.generate(
      32,
      (_) => random.nextInt(16).toRadixString(16),
      growable: false,
    ).join();
  }

  static bool isSafeSessionDirectory(Directory root, Directory session) {
    final normalizedRoot = p.normalize(p.absolute(root.path));
    final normalizedSession = p.normalize(p.absolute(session.path));
    return p.equals(p.dirname(normalizedSession), normalizedRoot) &&
        RegExp(r'^session-[0-9a-f]{32}$')
            .hasMatch(p.basename(normalizedSession));
  }

  static Future<void> deleteSessionDirectory({
    required Directory root,
    required Directory session,
  }) async {
    if (!isSafeSessionDirectory(root, session)) {
      throw const FileSystemException('拒绝删除非迅雷验证会话目录');
    }
    final type = await FileSystemEntity.type(
      session.path,
      followLinks: false,
    );
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory) {
      throw const FileSystemException('拒绝删除非目录验证会话');
    }
    await session.delete(recursive: true);
  }
}

class XunleiVerificationProfile {
  XunleiVerificationProfile._({
    required this.rootDirectory,
    required this.sessionDirectory,
    required this.environment,
  });

  final Directory rootDirectory;
  final Directory sessionDirectory;
  final WebViewEnvironment environment;
  bool _disposed = false;

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _cleanup('cookie', () async {
      await CookieManager.instance(
        webViewEnvironment: environment,
      ).deleteAllCookies();
    });
    await _cleanup('cache', () async {
      await InAppWebViewController.clearAllCache(includeDiskFiles: true);
    });
    await _cleanup('environment', environment.dispose);
    await _cleanup('directory', () async {
      await XunleiVerificationProfileFactory.deleteSessionDirectory(
        root: rootDirectory,
        session: sessionDirectory,
      );
    });
  }

  Future<void> _cleanup(
    String step,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } on Object {
      AppLogger().w('XunleiVerificationProfile: $step cleanup failed');
    }
  }
}
```

`XunleiVerificationProfileFactory` 默认实现必须使用上面的专用路径：

```dart
final support = await _supportDirectoryLoader();
final root = Directory(p.join(
  support.path,
  AppIdentity.storageNamespace,
  'webview',
  'xunlei',
));
final session = Directory(p.join(root.path, 'session-${_sessionId()}'));
```

其中 `_sessionId()` 使用 `Random.secure()` 生成 32 位小写十六进制；创建环境前先执行：

```dart
final version = await _availableVersionLoader();
if (version == null || version.trim().isEmpty) {
  throw const XunleiVerificationProfileException(
    XunleiVerificationProfileError.runtimeUnavailable,
  );
}
```

默认环境加载器使用：

```dart
WebViewEnvironment.create(
  settings: WebViewEnvironmentSettings(userDataFolder: userDataFolder),
)
```

环境初始化失败时先安全删除刚创建的会话目录，再只抛 `initializationFailed`，不得把插件异常正文、目录路径或挑战数据传给 UI/日志。

- [ ] **Step 4: 实现严格清理顺序和删除边界**

`XunleiVerificationProfile.dispose()` 按以下顺序分别捕获异常继续执行：

```dart
await CookieManager.instance(
  webViewEnvironment: environment,
).deleteAllCookies();
await InAppWebViewController.clearAllCache(includeDiskFiles: true);
await environment.dispose();
await XunleiVerificationProfileFactory.deleteSessionDirectory(
  root: rootDirectory,
  session: sessionDirectory,
);
```

清理诊断只能使用固定文本，例如：

```dart
AppLogger().w('XunleiVerificationProfile: cookie cleanup failed');
```

不得传递捕获到的异常、堆栈、路径或响应正文。目录删除前必须同时满足：

```dart
final normalizedRoot = p.normalize(p.absolute(root.path));
final normalizedSession = p.normalize(p.absolute(session.path));
final safe = p.equals(p.dirname(normalizedSession), normalizedRoot) &&
    RegExp(r'^session-[0-9a-f]{32}$').hasMatch(p.basename(normalizedSession));
```

若不满足，抛 `FileSystemException('拒绝删除非迅雷验证会话目录')`；不得执行递归删除。

- [ ] **Step 5: 格式化并运行 Profile 测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\services\cloud\xunlei\xunlei_verification_profile.dart test\xunlei_verification_profile_test.dart
D:\flutter\bin\flutter.bat test test\xunlei_verification_profile_test.dart
```

Expected: PASS；外部目录仍存在，Runtime 缺失没有触发平台环境创建。

- [ ] **Step 6: 提交 Profile 生命周期**

```powershell
git add lib/services/cloud/xunlei/xunlei_verification_profile.dart test/xunlei_verification_profile_test.dart
git commit -m "feat(迅雷): 隔离验证浏览数据"
```

---

### Task 6: 实现受限应用内验证弹窗

**Files:**
- Create: `lib/pages/cloud/xunlei/xunlei_verification_dialog.dart`
- Create: `test/xunlei_verification_dialog_test.dart`

- [ ] **Step 1: 编写不依赖真实平台视图的弹窗状态测试**

弹窗构造函数提供 `surfaceBuilder` 测试缝；创建 `test/xunlei_verification_dialog_test.dart`，覆盖以下场景：

```dart
testWidgets('验证弹窗显示加载状态并允许重试和取消', (tester) async {
  final fixtureChallenge = XunleiVerificationChallenge(
    reviewUri: Uri.parse(
      'https://i.xunlei.com/xlcaptcha/vertifyPhone.html?ticket=fixture',
    ),
    creditKey: 'credit-initial',
    deviceId: '0123456789abcdef0123456789abcdef',
    deviceSign: 'div101.0123456789abcdef0123456789abcdef-signature',
    startedAt: DateTime.now().toUtc(),
  );
  var attempts = 0;
  XunleiVerificationDialogResult? result;
  await tester.pumpWidget(MaterialApp(
    home: Builder(builder: (context) {
      return FilledButton(
        onPressed: () async {
          result = await showDialog<XunleiVerificationDialogResult>(
            context: context,
            barrierDismissible: false,
            builder: (_) => XunleiVerificationDialog.test(
              challenge: fixtureChallenge,
              surfaceBuilder: (callbacks, attempt) {
                attempts = attempt;
                return Column(children: <Widget>[
                  FilledButton(
                    onPressed: callbacks.onReady,
                    child: const Text('模拟加载成功'),
                  ),
                  FilledButton(
                    onPressed: callbacks.onLoadFailed,
                    child: const Text('模拟加载失败'),
                  ),
                ]);
              },
            ),
          );
        },
        child: const Text('打开验证'),
      );
    }),
  ));
  await tester.tap(find.text('打开验证'));
  await tester.pumpAndSettle();
  expect(find.text('正在加载迅雷验证页面'), findsOneWidget);
  await tester.tap(find.text('模拟加载失败'));
  await tester.pump();
  expect(find.text('迅雷验证页面加载失败'), findsOneWidget);
  await tester.tap(find.text('重试'));
  await tester.pump();
  expect(attempts, 2);
  await tester.tap(find.text('取消'));
  await tester.pumpAndSettle();
  expect(result?.outcome, XunleiVerificationDialogOutcome.cancelled);
});
```

再增加三个独立 Widget 测试：

- `callbacks.onResult(XunleiVerificationResult.success('credit-new'))` 自动关闭并返回 `verified` 和新 CreditKey。
- `cancelled` 返回 `cancelled`，不显示失败。
- `failed`、`incompatible`、安全导航阻止和十分钟超时分别返回/显示“迅雷设备验证失败，请重新登录”“迅雷设备验证结果不兼容，请重新登录”“已阻止不安全的迅雷验证页面”“迅雷验证已过期，请重新登录”。

- [ ] **Step 2: 运行弹窗测试并确认类型缺失**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\xunlei_verification_dialog_test.dart
```

Expected: FAIL，原因是弹窗、结果和测试回调类型未定义。

- [ ] **Step 3: 定义弹窗结果、启动器和测试回调**

在新文件中定义：

```dart
enum XunleiVerificationDialogOutcome { verified, cancelled, failed }

class XunleiVerificationDialogResult {
  const XunleiVerificationDialogResult._(
    this.outcome, {
    this.creditKey,
    this.errorMessage,
  });

  const XunleiVerificationDialogResult.verified(String creditKey)
      : this._(XunleiVerificationDialogOutcome.verified, creditKey: creditKey);
  const XunleiVerificationDialogResult.cancelled()
      : this._(XunleiVerificationDialogOutcome.cancelled);
  const XunleiVerificationDialogResult.failed(String message)
      : this._(XunleiVerificationDialogOutcome.failed, errorMessage: message);

  final XunleiVerificationDialogOutcome outcome;
  final String? creditKey;
  final String? errorMessage;
}

typedef XunleiVerificationDialogLauncher =
    Future<XunleiVerificationDialogResult> Function(
  BuildContext context,
  XunleiVerificationChallenge challenge,
);

class XunleiVerificationSurfaceCallbacks {
  const XunleiVerificationSurfaceCallbacks({
    required this.onReady,
    required this.onLoadFailed,
    required this.onSecurityViolation,
    required this.onResult,
  });

  final VoidCallback onReady;
  final VoidCallback onLoadFailed;
  final VoidCallback onSecurityViolation;
  final ValueChanged<XunleiVerificationResult> onResult;
}

typedef XunleiVerificationSurfaceBuilder = Widget Function(
  XunleiVerificationSurfaceCallbacks callbacks,
  int attempt,
);
```

默认启动函数使用与 typedef 完全一致的位置参数：

```dart
Future<XunleiVerificationDialogResult> showXunleiVerificationDialog(
  BuildContext context,
  XunleiVerificationChallenge challenge,
) async
```

`XunleiVerificationDialog.test` 是只供 Widget 测试注入 Surface 的命名构造函数，签名固定为：

```dart
XunleiVerificationDialog.test({
  super.key,
  required this.challenge,
  required XunleiVerificationSurfaceBuilder surfaceBuilder,
  DateTime Function()? now,
})  : profile = null,
      _surfaceBuilder = surfaceBuilder,
      _now = now ?? DateTime.now;
```

`showXunleiVerificationDialog` 必须先通过 `XunleiVerificationProfileFactory.create()` 创建环境；Runtime 缺失时显示不可关闭到外部页面的应用内错误对话框并返回：

```dart
const XunleiVerificationDialogResult.failed(
  '迅雷验证组件不可用，请安装或修复 Microsoft Edge WebView2 Runtime',
)
```

主对话框 Future 结束后，在 `finally` 中 `await profile.dispose()`，保证环境销毁和目录清理完成后才把结果交回来源编辑页。

- [ ] **Step 4: 构建固定入口和文档开始桥接脚本**

实际 Surface 必须按下列结构创建：

```dart
InAppWebView(
  key: ValueKey<int>(attempt),
  webViewEnvironment: profile.environment,
  initialUrlRequest: URLRequest(
    url: WebUri(xunleiVerificationEntryUri),
  ),
  initialUserScripts: UnmodifiableListView<UserScript>(<UserScript>[
    UserScript(
      groupName: 'xunlei-verification-bridge',
      source: bridge.documentStartScript,
      injectionTime: UserScriptInjectionTime.AT_DOCUMENT_START,
      forMainFrameOnly: false,
    ),
  ]),
  initialSettings: InAppWebViewSettings(
    javaScriptEnabled: true,
    javaScriptCanOpenWindowsAutomatically: false,
    useShouldOverrideUrlLoading: true,
    useOnDownloadStart: true,
    incognito: true,
    cacheEnabled: false,
    clearCache: true,
    disableContextMenu: true,
    supportZoom: false,
    allowFileAccessFromFileURLs: false,
    allowUniversalAccessFromFileURLs: false,
  ),
  onWebViewCreated: (controller) {
    webViewController = controller;
    controller.addJavaScriptHandler(
      handlerName: xunleiVerificationHandlerName,
      callback: (arguments) {
        final raw = arguments.length == 1 ? arguments.first : null;
        callbacks.onResult(bridge.parseOperationResult(raw));
        return null;
      },
    );
  },
  shouldOverrideUrlLoading: (controller, action) async {
    final value = action.request.url?.toString();
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || !XunleiVerificationNavigationPolicy.allows(uri)) {
      callbacks.onSecurityViolation();
      return NavigationActionPolicy.CANCEL;
    }
    return NavigationActionPolicy.ALLOW;
  },
  onCreateWindow: (controller, action) async => false,
  onDownloadStartRequest: (controller, request) {
    callbacks.onSecurityViolation();
  },
  onPermissionRequest: (controller, request) async => PermissionResponse(
    resources: request.resources,
    action: PermissionResponseAction.DENY,
  ),
  onGeolocationPermissionsShowPrompt: (controller, origin) async =>
      GeolocationPermissionShowPromptResponse(
    origin: origin,
    allow: false,
    retain: false,
  ),
  onLoadStop: (controller, url) => callbacks.onReady(),
  onReceivedError: (controller, request, error) {
    if (request.isForMainFrame == true) callbacks.onLoadFailed();
  },
  onReceivedHttpError: (controller, request, response) {
    if (request.isForMainFrame == true) callbacks.onLoadFailed();
  },
)
```

不得注册 `onConsoleMessage`、不得调用 `openDevTools`、不得使用 `initialData`/`loadData`、不得把 URL 或错误正文写入日志。

- [ ] **Step 5: 完成对话框视觉和退出清理**

对话框使用 `AlertDialog`/`Dialog` 的现有 Material 样式，标题固定为“迅雷设备验证”，主体最小尺寸 `720 x 560`、最大尺寸受窗口约束。状态文案和按钮严格为：

- 加载：“正在加载迅雷验证页面”。
- 页面失败：“迅雷验证页面加载失败”，按钮“重试”“取消”。
- 安全阻止：“已阻止不安全的迅雷验证页面”，只允许“取消”。
- 验证失败：“迅雷设备验证失败，请重新登录”。
- Runtime 缺失：“迅雷验证组件不可用，请安装或修复 Microsoft Edge WebView2 Runtime”。

关闭前执行：

```dart
await webViewController?.stopLoading();
webViewController?.removeJavaScriptHandler(
  handlerName: xunleiVerificationHandlerName,
);
```

然后 `Navigator.pop(result)`；`showXunleiVerificationDialog` 的 `finally` 再清 Cookie、缓存、环境和目录。十分钟 Timer 按 `challenge.startedAt` 计算剩余时间，`dispose()` 时必须取消。

- [ ] **Step 6: 格式化并运行弹窗与桥接/Profile 测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\pages\cloud\xunlei\xunlei_verification_dialog.dart test\xunlei_verification_dialog_test.dart
D:\flutter\bin\flutter.bat test test\xunlei_verification_bridge_test.dart test\xunlei_verification_profile_test.dart test\xunlei_verification_dialog_test.dart
```

Expected: PASS；Widget 测试不初始化真实 WebView2 平台视图。

- [ ] **Step 7: 提交应用内验证弹窗**

```powershell
git add lib/pages/cloud/xunlei/xunlei_verification_dialog.dart test/xunlei_verification_dialog_test.dart
git commit -m "feat(迅雷): 添加应用内设备验证窗口"
```

---

### Task 7: 集成来源编辑页并增加密码框内联提示

**Files:**
- Modify: `lib/pages/cloud/xunlei/xunlei_source_editor.dart`
- Modify: `test/xunlei_source_editor_test.dart`

- [ ] **Step 1: 把系统浏览器测试改为应用内验证自动续登测试**

将原“需要设备验证时用外部浏览器打开并可完成”测试替换为：

```dart
testWidgets('需要设备验证时打开应用内窗口并用新密钥自动续登', (tester) async {
  final authorization = _FakeXunleiAuthorizationController(
    challengeOnLogin: true,
  );
  XunleiVerificationChallenge? openedChallenge;
  await tester.pumpWidget(MaterialApp(
    home: XunleiSourceEditorPage(
      authorizationController: authorization,
      credentialStore: MemoryCloudCredentialStore(),
      verificationDialogLauncher: (context, challenge) async {
        openedChallenge = challenge;
        return const XunleiVerificationDialogResult.verified('credit-new');
      },
    ),
  ));
  await tester.tap(find.text('账号密码兼容登录'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const ValueKey<String>('xunlei-identifier')),
    'account-fixture',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('xunlei-password')),
    'password-fixture',
  );
  await tester.tap(find.text('兼容登录'));
  await tester.pumpAndSettle();

  expect(openedChallenge?.reviewUri.host, 'i.xunlei.com');
  expect(authorization.completeCreditKey, 'credit-new');
  expect(authorization.completeCalls, 1);
  expect(find.text('登录成功'), findsOneWidget);
  expect(find.textContaining('系统浏览器'), findsNothing);
  expect(find.text('完成验证'), findsNothing);
});
```

- [ ] **Step 2: 新增密码错误焦点、账号保留和误报防护测试**

```dart
testWidgets('明确密码错误清空密码保留账号并恢复焦点', (tester) async {
  final authorization = _FakeXunleiAuthorizationController(
    loginErrorType: CloudDriveErrorType.invalidPassword,
  );
  await tester.pumpWidget(MaterialApp(
    home: XunleiSourceEditorPage(
      authorizationController: authorization,
      credentialStore: MemoryCloudCredentialStore(),
    ),
  ));
  await tester.tap(find.text('账号密码兼容登录'));
  await tester.pumpAndSettle();
  final account = find.byKey(const ValueKey<String>('xunlei-identifier'));
  final password = find.byKey(const ValueKey<String>('xunlei-password'));
  await tester.enterText(account, 'account-fixture');
  await tester.enterText(password, 'wrong-password');
  await tester.tap(find.text('兼容登录'));
  await tester.pumpAndSettle();

  expect(find.text('迅雷密码错误，请重新输入'), findsOneWidget);
  expect(tester.widget<TextFormField>(account).controller?.text, 'account-fixture');
  expect(tester.widget<TextFormField>(password).controller?.text, isEmpty);
  expect(
    tester.widget<EditableText>(
      find.descendant(of: password, matching: find.byType(EditableText)),
    ).focusNode.hasFocus,
    isTrue,
  );
});
```

再写表驱动 Widget 测试，分别让控制器抛 `network`、`verificationRequired`、`protocolUpdated` 和 `authentication`，断言密码框不显示“迅雷密码错误，请重新输入”，而是沿用控制器对应 SnackBar 文案。

- [ ] **Step 3: 新增取消、组件缺失和页面失败测试**

分别注入以下结果并断言：

```dart
const XunleiVerificationDialogResult.cancelled()
```

- 调用 `cancelVerification()`，不调用 `completeVerification()`，不显示“登录失败”。

```dart
const XunleiVerificationDialogResult.failed(
  '迅雷验证组件不可用，请安装或修复 Microsoft Edge WebView2 Runtime',
)
```

- 调用 `failVerification()`、清除挑战，并显示精确 SnackBar。

- [ ] **Step 4: 运行来源编辑页测试并确认构造参数失败**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\xunlei_source_editor_test.dart
```

Expected: FAIL，原因包括 `verificationDialogLauncher` 未定义，以及旧 `completeVerification()` 签名不匹配。

- [ ] **Step 5: 删除系统浏览器入口并注入弹窗启动器**

从来源编辑页删除：

```dart
import 'package:url_launcher/url_launcher.dart';
typedef XunleiVerificationUrlLauncher = Future<bool> Function(Uri uri);
final XunleiVerificationUrlLauncher? launchVerificationUrl;
Future<void> _openVerification()
Future<void> _completeVerification()
static Future<bool> _launchInExternalBrowser(Uri uri)
```

新增导入和字段：

```dart
import 'package:kanyingyin/pages/cloud/xunlei/xunlei_verification_dialog.dart';

final XunleiVerificationDialogLauncher? verificationDialogLauncher;
late final XunleiVerificationDialogLauncher _verificationDialogLauncher;
```

`initState()` 中设置：

```dart
_verificationDialogLauncher =
    widget.verificationDialogLauncher ?? showXunleiVerificationDialog;
```

- [ ] **Step 6: 登录遇到挑战时自动运行弹窗并处理强类型结果**

新增：

```dart
Future<void> _runVerification() async {
  final challenge = _authorizationController.verificationChallenge;
  if (challenge == null || !mounted) {
    _showMessage('迅雷设备验证失败，请重新登录');
    return;
  }
  final result = await _verificationDialogLauncher(context, challenge);
  if (!mounted) return;
  switch (result.outcome) {
    case XunleiVerificationDialogOutcome.verified:
      try {
        await _authorizationController.completeVerification(
          creditKey: result.creditKey ?? '',
        );
        _acceptAuthorizedCredential();
      } on Object {
        if (mounted) {
          _showMessage(
            _authorizationController.errorMessage ?? '迅雷设备验证失败，请重新登录',
          );
        }
      }
      return;
    case XunleiVerificationDialogOutcome.cancelled:
      _authorizationController.cancelVerification();
      return;
    case XunleiVerificationDialogOutcome.failed:
      final message =
          result.errorMessage ?? '迅雷设备验证失败，请重新登录';
      _authorizationController.failVerification(message);
      _showMessage(message);
      return;
  }
}
```

`_login()` 捕获 `XunleiVerificationRequired` 时只执行 `await _runVerification()`，不再读取或打开 Review URL。

- [ ] **Step 7: 增加密码错误状态和焦点生命周期**

状态字段：

```dart
late final FocusNode _passwordFocusNode;
String? _passwordErrorText;
```

`initState()` 创建 `FocusNode()`；`dispose()` 在密码控制器前调用 `_passwordFocusNode.dispose()`。

每次登录前：

```dart
setState(() => _passwordErrorText = null);
```

单独捕获：

```dart
} on CloudDriveException catch (error) {
  if (!mounted) return;
  if (error.type == CloudDriveErrorType.invalidPassword) {
    setState(() => _passwordErrorText = '迅雷密码错误，请重新输入');
    _passwordController.clear();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _passwordFocusNode.requestFocus();
    });
  } else {
    _showMessage(_authorizationController.errorMessage ?? '迅雷登录失败');
  }
}
```

密码框改为：

```dart
TextFormField(
  key: const ValueKey<String>('xunlei-password'),
  controller: _passwordController,
  focusNode: _passwordFocusNode,
  obscureText: true,
  autocorrect: false,
  enableSuggestions: false,
  decoration: InputDecoration(
    labelText: '迅雷密码',
    helperText: '密码仅用于本次兼容登录，不会保存',
    errorText: _passwordErrorText,
  ),
  onChanged: (_) {
    if (_passwordErrorText != null) {
      setState(() => _passwordErrorText = null);
    }
  },
  onFieldSubmitted: (_) => _busy ? null : _login(),
)
```

删除原验证 Card、“打开验证页面”“完成验证”“取消验证”按钮；密码仍不得持久化或写日志。

- [ ] **Step 8: 更新测试 Fake 控制器并运行 Widget 测试**

Fake 控制器公开：

```dart
XunleiVerificationChallenge? _verificationChallenge;
String? completeCreditKey;
CloudDriveErrorType? loginErrorType;

@override
XunleiVerificationChallenge? get verificationChallenge =>
    _verificationChallenge;

@override
Future<void> completeVerification({required String creditKey}) async {
  completeCalls++;
  completeCreditKey = creditKey;
  _authorize();
}
```

挑战 fixture 必须包含 Review URL、初始 CreditKey、设备 ID、设备签名和开始时间；`cancelVerification`、`failVerification` 均清除它。

Run:

```powershell
D:\flutter\bin\dart.bat format lib\pages\cloud\xunlei\xunlei_source_editor.dart test\xunlei_source_editor_test.dart
D:\flutter\bin\flutter.bat test test\xunlei_source_editor_test.dart
```

Expected: PASS；应用内验证成功后自动登录，密码错误时账号保留、密码清空且焦点回到密码框。

- [ ] **Step 9: 提交来源编辑页集成**

```powershell
git add lib/pages/cloud/xunlei/xunlei_source_editor.dart test/xunlei_source_editor_test.dart
git commit -m "feat(迅雷): 集成验证窗口和密码提示"
```

---

### Task 8: 加固 Windows-only、安全与隐私回归门禁

**Files:**
- Modify: `test/windows_only_residue_test.dart`
- Create: `test/xunlei_verification_security_test.dart`

- [ ] **Step 1: 替换旧“系统浏览器”断言**

把 `test/windows_only_residue_test.dart` 最后的旧测试完整替换为：

```dart
test('迅雷设备验证只使用受限应用内 WebView2', () {
  final editor = File(
    'lib/pages/cloud/xunlei/xunlei_source_editor.dart',
  ).readAsStringSync();
  final dialog = File(
    'lib/pages/cloud/xunlei/xunlei_verification_dialog.dart',
  ).readAsStringSync();
  final pubspec = File('pubspec.yaml').readAsStringSync();

  expect(pubspec, contains('flutter_inappwebview: 6.1.5'));
  expect(pubspec, isNot(contains('webview_flutter:')));
  expect(editor, isNot(contains('LaunchMode.externalApplication')));
  expect(editor, isNot(contains('launchUrl(')));
  expect(editor, isNot(contains('url_launcher')));
  expect(dialog, contains('xunleiVerificationEntryUri'));
  expect(dialog, contains('PermissionResponseAction.DENY'));
  expect(dialog, contains('NavigationActionPolicy.CANCEL'));
  expect(dialog, isNot(contains('openDevTools')));
  expect(dialog, isNot(contains('onConsoleMessage')));
  expect(dialog, isNot(contains('initialData:')));
  expect(dialog, isNot(contains('loadData(')));
});
```

- [ ] **Step 2: 新增秘密与能力边界源码门禁**

创建 `test/xunlei_verification_security_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('迅雷验证不提供网页浏览媒体解析和调试能力', () {
    final sources = <String>[
      'lib/services/cloud/xunlei/xunlei_verification_bridge.dart',
      'lib/services/cloud/xunlei/xunlei_verification_profile.dart',
      'lib/pages/cloud/xunlei/xunlei_verification_dialog.dart',
      'lib/pages/cloud/xunlei/xunlei_source_editor.dart',
    ].map((path) => File(path).readAsStringSync()).join('\n');

    for (final forbidden in <String>[
      'WebView 视频解析',
      'openDevTools(',
      'onConsoleMessage:',
      'Clipboard.',
      'LaunchMode.externalApplication',
      'loadData(',
      'initialData:',
      'file://',
    ]) {
      expect(sources, isNot(contains(forbidden)), reason: forbidden);
    }
    expect(sources, contains('https://i.xunlei.com/xlcaptcha/android.html'));
    expect(sources, contains("host.toLowerCase() == 'i.xunlei.com'"));
    expect(sources, contains('PermissionResponseAction.DENY'));
    expect(sources, contains('AppIdentity.storageNamespace'));
  });

  test('挑战模型未提供序列化持久化入口', () {
    final models = File(
      'lib/services/cloud/xunlei/xunlei_models.dart',
    ).readAsStringSync();
    final start = models.indexOf('class XunleiVerificationChallenge');
    final end = models.indexOf('\nclass ', start + 1);
    final challenge = models.substring(
      start,
      end == -1 ? models.length : end,
    );
    expect(challenge, isNot(contains('toJson')));
    expect(challenge, isNot(contains('fromJson')));
    expect(challenge, contains('<redacted>'));
  });
}
```

- [ ] **Step 3: 运行全部迅雷与 Windows 门禁测试**

Run:

```powershell
D:\flutter\bin\flutter.bat test test\xunlei_verification_bridge_test.dart test\xunlei_verification_profile_test.dart test\xunlei_verification_dialog_test.dart test\xunlei_api_client_test.dart test\xunlei_authorization_controller_test.dart test\xunlei_source_editor_test.dart test\xunlei_response_parser_test.dart test\xunlei_request_policy_test.dart test\cloud_provider_registry_test.dart test\windows_only_residue_test.dart test\xunlei_verification_security_test.dart
```

Expected: 全部 PASS；测试日志不含账号、密码、Token、CreditKey、完整 Review URL、设备 ID、设备签名或响应正文。

- [ ] **Step 4: 提交安全门禁**

```powershell
git add test/windows_only_residue_test.dart test/xunlei_verification_security_test.dart
git commit -m "test(迅雷): 加固验证安全边界"
```

---

### Task 9: 更新到 2.1.73 并同步用户文案

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `README.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/version_history_current_test.dart`

- [ ] **Step 1: 在修改版本前查询并记录 Windows 已安装版本**

Run:

```powershell
$installed = Get-AppxPackage -Name com.kanyingyin.player
if ($null -eq $installed) {
  Write-Output '当前未安装 com.kanyingyin.player'
} else {
  $installed | Select-Object Name,Version,PackageFullName,InstallLocation
}
```

Expected: 工具输出中明确记录实际安装版本或“当前未安装”；不得从 `pubspec.yaml` 推断。开始此步骤前确认运行中的 `kanyingyin.exe` 已退出。

- [ ] **Step 2: 先把版本一致性测试改为 2.1.73 并确认失败**

在 `test/version_consistency_test.dart` 修改：

```dart
const expectedVersion = '2.1.73';
const expectedBuildNumber = '20173';
```

把当前文案关键词改为：

```dart
for (final text in <String>[
  '应用内',
  '设备验证',
  '自动继续登录',
  '密码错误',
  'WebView2',
  '临时数据',
  '不会修改或删除',
]) {
  expect(currentCopy, contains(text));
}
```

在 `test/version_history_current_test.dart` 顶部新增 `2.1.73` 测试，使用相同关键词并断言 `isPrerelease` 为 `true`。

Run:

```powershell
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart
```

Expected: FAIL，当前项目仍是 `2.1.72` 且没有 `2.1.73` 文案。

- [ ] **Step 3: 同步所有版本字段**

修改为：

```yaml
version: 2.1.73+20173
```

```yaml
msix_config:
  msix_version: 2.1.73.0
```

`lib/core/app_version.dart`：

```dart
static const String current = '2.1.73';
```

`README.md` 当前版本表格更新为 `2.1.73`。

- [ ] **Step 4: 写入面向普通用户的统一发行文案**

在 `versionHistoryList` 的 `1.0.2` 后加入：

```dart
VersionHistory(
  version: '2.1.73',
  date: '2026-07-29',
  isPrerelease: true,
  changes: [
    '迅雷设备验证改为应用内安全窗口，不再打开系统浏览器空白页；短信或图形验证完成后会自动关闭并继续登录',
    '明确输错迅雷密码时，密码框会提示“迅雷密码错误，请重新输入”，清空错误密码并保留账号',
    '验证窗口只允许迅雷官方 HTTPS 页面，拒绝新窗口、下载、摄像头、麦克风、位置和其他权限请求',
    '每次验证使用独立 WebView2 临时数据目录，关闭后清除 Cookie、缓存和临时数据；账号、密码、Token 和验证参数不会写入日志',
    'WebView2 缺失、页面加载失败、取消、超时或协议变化会显示明确提示；本次更新不会修改或删除本地及网盘原始文件',
  ],
),
```

`RELEASE_NOTES.md` 顶部和 `UPDATE_DIALOG_COPY.md` 当前版本使用同一组五条文案；标题为“看影音 2.1.73 测试版”，MSIX 版本为 `2.1.73.0`。

- [ ] **Step 5: 运行版本与发布配置测试**

Run:

```powershell
D:\flutter\bin\dart.bat format lib\core\app_version.dart lib\utils\version_history.dart test\version_consistency_test.dart test\version_history_current_test.dart
D:\flutter\bin\flutter.bat test test\version_consistency_test.dart test\version_history_current_test.dart test\release_config_contract_test.dart test\signed_release_packaging_test.dart
```

Expected: PASS；应用版本、构建号、MSIX 版本、README、更新弹窗、发行说明和版本历史一致。

- [ ] **Step 6: 提交版本文案**

```powershell
git add pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md README.md UPDATE_DIALOG_COPY.md test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "chore: 发布看影音 2.1.73"
```

---

### Task 10: 全量验证、Windows 实机检查、签名 MSIX 和最终提交

**Files:**
- Verify: all modified Dart, YAML, Markdown, Windows generated plugin files
- Generate: `build/windows/x64/runner/Release/kanyingyin.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.73.msix`
- Deliver: `C:\Users\asus\Desktop\看影音-2.1.73-异机安装包.zip`

- [ ] **Step 1: 检查工作区和关键 diff，禁止秘密进入提交**

Run:

```powershell
git status --short
git diff --check
git diff --stat
git diff -- lib/services/cloud/xunlei lib/pages/cloud/xunlei test/xunlei_api_client_test.dart test/xunlei_authorization_controller_test.dart test/xunlei_source_editor_test.dart test/xunlei_verification_bridge_test.dart test/xunlei_verification_profile_test.dart test/xunlei_verification_dialog_test.dart test/xunlei_verification_security_test.dart test/windows_only_residue_test.dart pubspec.yaml RELEASE_NOTES.md lib/utils/version_history.dart
```

Expected: 只包含本计划相关变更；无账号、密码、Token、CreditKey、完整验证 URL、设备 ID、设备签名、真实响应正文、证书或签名密码。

- [ ] **Step 2: 执行格式化、全量测试与静态分析**

Run:

```powershell
D:\flutter\bin\dart.bat format lib test
D:\flutter\bin\flutter.bat test
D:\flutter\bin\flutter.bat analyze
```

Expected: `flutter test` 全部通过；`flutter analyze` 输出 `No issues found!`。

- [ ] **Step 3: 构建 Windows Release**

Run:

```powershell
D:\flutter\bin\flutter.bat build windows --release
```

Expected: exit code 0；`build\windows\x64\runner\Release\kanyingyin.exe` 和 `data\app.so` 为本轮非空产物，WebView2 插件 DLL/注册项存在。

- [ ] **Step 4: 在 Windows 实机执行无秘密功能检查**

启动 Release 应用，使用虚构数据和网络切换完成以下检查，不调用真实短信接口：

1. 打开迅雷来源编辑页，Refresh Token 登录入口、目录选择和已授权来源编辑仍正常。
2. 密码框错误提示的 Widget 行为与测试一致，账号保留、错误密码清空、焦点返回。
3. 断网后触发验证弹窗加载失败状态，确认“重试”“取消”可操作且不会影响本地媒体库、其他网盘来源和播放器。
4. 关闭弹窗后确认 `%APPDATA%`/应用支持目录的 `kanyingyin\webview\xunlei` 下没有遗留 `session-<32hex>` 会话目录。
5. 不打开开发者工具，不复制或记录用户账号、密码、Token、CreditKey、完整 Review URL、设备 ID、设备签名或响应正文。

Expected: UI 无异常，取消/失败能返回设置页，本地播放与 TMDB 设置不受影响。

- [ ] **Step 5: 由用户本人完成一次真实设备验证冒烟测试**

用户在 Release 应用中自行输入本人迅雷账号和密码；执行者不得观察、复制、输出或记录输入内容和验证参数。确认：

1. 触发风控时出现应用内“迅雷设备验证”窗口，而不是系统浏览器。
2. 短信或图形验证内容可见可操作。
3. 验证成功后窗口自动关闭，只自动续登一次，并显示登录成功后允许选择媒体目录。
4. 若再次返回设备挑战，应用停止循环并提示“迅雷再次要求设备验证，请重新登录”。

Expected: 以上四项均符合；若账号当次未触发风控，仅记录“服务端本次未下发设备验证”，不得伪造成功结论，自动化测试结果仍作为桥接与状态机验收依据。

- [ ] **Step 6: 生成并验证签名 MSIX**

确认 `kanyingyin.exe` 已退出后运行项目固定发布脚本：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tool\windows\build_signed_release.ps1
```

Expected: 脚本重新构建 Windows Release，生成签名 `build\windows\x64\runner\Release\kanyingyin.msix`，校验清单身份 `com.kanyingyin.player`、发布者 `CN=KanYingYin`、架构 `x64`、版本 `2.1.73.0`，并复制到桌面 `看影音-2.1.73.msix`；签名密码只存在于脚本当前进程内存并被清零。

- [ ] **Step 7: 独立核对桌面包签名、清单版本和哈希**

Run:

```powershell
$msix = 'C:\Users\asus\Desktop\看影音-2.1.73.msix'
$signature = Get-AuthenticodeSignature -LiteralPath $msix
$signature | Select-Object Status,StatusMessage
Get-FileHash -LiteralPath $msix -Algorithm SHA256
Get-FileHash -LiteralPath 'build\windows\x64\runner\Release\kanyingyin.msix' -Algorithm SHA256
```

再以只读方式打开 MSIX ZIP 容器并读取 `AppxManifest.xml`，断言 `Identity Version="2.1.73.0"`；不得解包到工作区或输出证书私钥信息。

Expected: 签名状态 `Valid`，桌面包与构建产物 SHA-256 完全一致，清单版本为 `2.1.73.0`。

- [ ] **Step 8: 安装交付包并再次核对已安装版本**

Run:

```powershell
Add-AppxPackage -Path 'C:\Users\asus\Desktop\看影音-2.1.73.msix'
Get-AppxPackage -Name com.kanyingyin.player |
  Select-Object Name,Version,PackageFullName,InstallLocation
```

Expected: 安装成功，实际已安装版本为 `2.1.73.0`。首次启动若桌面或开始菜单快捷方式不存在，应用按现有逻辑弹窗询问是否创建，不静默跳过。

- [ ] **Step 9: 最终检查并提交未提交的本轮相关文件**

Run:

```powershell
git status --short
git diff --check
git diff --stat
```

若格式化或生成文件在前述提交后产生本轮相关差异，逐项核对后执行：

```powershell
git add pubspec.yaml pubspec.lock windows/flutter/generated_plugin_registrant.cc windows/flutter/generated_plugins.cmake lib/services/cloud/cloud_drive_client.dart lib/services/cloud/cloud_provider_registry.dart lib/services/cloud/xunlei lib/pages/cloud/xunlei lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md README.md UPDATE_DIALOG_COPY.md test/xunlei_api_client_test.dart test/xunlei_authorization_controller_test.dart test/xunlei_source_editor_test.dart test/xunlei_verification_bridge_test.dart test/xunlei_verification_profile_test.dart test/xunlei_verification_dialog_test.dart test/xunlei_verification_security_test.dart test/cloud_provider_registry_test.dart test/windows_only_residue_test.dart test/version_consistency_test.dart test/version_history_current_test.dart
git commit -m "fix(迅雷): 完成应用内设备验证交付"
```

Expected: 最终 `git status --short` 为空；不提交 `build/`、桌面 MSIX/ZIP、日志、临时 Profile、账号凭据或签名材料。

## 最终验收清单

- [ ] 设备挑战只打开固定 `https://i.xunlei.com/xlcaptcha/android.html`，不直接打开 Review 子页面或系统浏览器。
- [ ] 文档开始脚本只在 `https://i.xunlei.com:443` 暴露两类桥接消息，所有字段经 `jsonEncode`。
- [ ] 验证成功必须得到非空新 CreditKey，使用原设备 ID、原账号和内存密码只续登一次。
- [ ] 取消、超时、页面失败、协议异常、重复挑战和控制器销毁都清除临时秘密与挑战。
- [ ] 只有核心登录明确密码失败才显示“迅雷密码错误，请重新输入”；网络、验证、Token 和协议更新不误报。
- [ ] 密码错误后账号保留、密码清空、焦点返回密码框。
- [ ] 新窗口、下载、摄像头、麦克风、位置和其他 WebView 权限全部拒绝。
- [ ] 每次会话使用专用 WebView2 目录，先销毁环境再做经过父目录与命名双重校验的递归删除。
- [ ] 日志、普通配置、剪贴板、临时 HTML 和 Git 历史不包含账号、密码、Token、CreditKey、完整验证 URL、设备标识或响应正文。
- [ ] 本地扫描、播放、TMDB 与其他网盘来源在迅雷验证失败时继续可用，任何清理都不删除用户原始媒体文件。
- [ ] 全量测试、静态分析、Windows Release、签名 MSIX、清单版本、签名和哈希验证全部通过。
- [ ] 桌面存在 `C:\Users\asus\Desktop\看影音-2.1.73.msix`，安装后 `Get-AppxPackage` 返回 `2.1.73.0`。
