# TV 配置配对与加密迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 为看影音增加可验证的 TV 高对比焦点、完整的局域网手机配置闭环，以及包含 TMDB Key 和个人网盘凭据的密码加密配置导入导出。

**Architecture:** 新建 `configuration_transfer` 功能域，用强类型 `PortableAppConfiguration` 统一扫码和文件迁移的数据结构，以 AES-256-GCM 加密文件，并由单一原子导入器负责 TMDB 与网盘来源的合并和回滚。TV 配对服务器只负责一次性局域网会话和手机页面，控制器负责连接/确认状态，设置表现层通过独立 TV 焦点表面增强遥控器反馈，Windows 和普通 Android 保持现有交互。

**Tech Stack:** Flutter 3.41.9、Dart、Flutter Modular、MobX、`cryptography` 2.9.0、`cryptography_flutter` 2.3.4、`file_picker`、`share_plus`、`path_provider`、`HttpServer`、Flutter test、Inno Setup、Android `tvTest` flavor。

---

## 文件结构

- Create: `lib/features/configuration_transfer/domain/portable_app_configuration.dart`，定义便携配置、来源记录、校验异常和脱敏输出。
- Create: `lib/features/configuration_transfer/application/configuration_archive_codec.dart`，实现 `.kyyconfig` 的 PBKDF2/AES-GCM 加解密信封。
- Create: `lib/features/configuration_transfer/application/configuration_importer.dart`，计算合并预览并原子写入 TMDB 与网盘配置。
- Create: `lib/features/configuration_transfer/application/configuration_transfer_service.dart`，组合导出快照、加密、解密检查和导入会话。
- Create: `lib/features/configuration_transfer/presentation/configuration_transfer_page.dart`，实现跨 Windows/Android/TV 的文件选择、密码、预览、确认和反馈。
- Create: `lib/features/settings/presentation/tv_settings_focus_surface.dart`，提供 3 px 边框、浅色背景、勾选图标和焦点提示。
- Create: `lib/features/tv_pairing/data/tv_pairing_phone_page.dart`，集中生成无外部依赖的手机 HTML/CSS/JavaScript。
- Modify: `lib/features/tv_pairing/domain/tv_pairing_models.dart`，让协议载荷直接承载 `PortableAppConfiguration`。
- Modify: `lib/features/tv_pairing/application/tv_pairing_controller.dart`，加入手机已连接状态并复用原子导入器。
- Modify: `lib/features/tv_pairing/data/tv_pairing_http_server.dart`，加入幂等连接通知和明确的拒绝/写入失败响应。
- Modify: `lib/features/tv_pairing/presentation/tv_pairing_page.dart`，显示连接、等待确认、写入、成功和失败页面。
- Modify: `lib/features/settings/presentation/k_settings_tile.dart`、`settings_presentation.dart`，让统一设置项使用 TV 焦点表面。
- Modify: `lib/pages/settings/cloud_sources_settings.dart`、`tmdb_settings.dart`、`settings_module.dart`，接入迁移入口、TV 操作项和路由。
- Modify: `lib/app/bindings/cloud_bindings.dart`、`lib/main.dart`、`pubspec.yaml`，注册服务并启用原生加密实现。
- Test: `test/portable_app_configuration_test.dart`、`test/configuration_archive_codec_test.dart`、`test/configuration_importer_test.dart`、`test/configuration_transfer_service_test.dart`、`test/configuration_transfer_page_test.dart`、`test/tv_pairing_*_test.dart`、`test/settings_presentation_components_test.dart`、`test/cloud_sources_ui_test.dart`、`test/tmdb_settings_language_test.dart`。
- Release: `pubspec.yaml`、`lib/core/app_version.dart`、`lib/utils/version_history.dart`、`RELEASE_NOTES.md`、`README.md`、`UPDATE_DIALOG_COPY.md`、版本契约测试和 `docs/android-tv-test-report.md`。

## 不变量

- `.kyyconfig` 明文只能存在于内存，不写临时文件；分享回退只写已经加密的字节。
- 日志、异常、`toString()`、测试失败文本和 UI 都不得出现 TMDB Key、密码、Cookie、Token、客户端 Secret。
- 文件最大 512 KiB，密码至少 8 个字符，格式版本和加密算法必须白名单校验后再解密或写入。
- 空 TMDB Key 表示保留目标设备当前 Key；来源按 ID 合并，同 ID 更新，未包含来源保留。
- 导入不得删除原始视频、字幕、媒体索引或缓存；导入来源的扫描状态统一重置为 `never`。
- 手机手动新增夸克、百度、迅雷来源时 `rootPaths/rootRefs` 为空，电视成功页必须提示继续选择媒体目录。
- 手机页面不请求外部脚本、样式、字体或接口；配对仍限制在一次性五分钟局域网会话。
- 实施开始前必须实查 Windows Inno 安装状态、`kanyingyin.exe` 产品版本和旧 MSIX 状态；不得从 `pubspec.yaml` 推断。

### Task 1: 便携配置领域模型与校验

**Files:**
- Create: `lib/features/configuration_transfer/domain/portable_app_configuration.dart`
- Test: `test/portable_app_configuration_test.dart`

- [ ] **Step 1: 写出 JSON 往返、扫描状态清理、重复 ID、固定地址和脱敏测试**

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

void main() {
  test('便携配置往返时保留秘密但清除设备扫描状态', () {
    final exported = PortableAppConfiguration.create(
      exportedAt: DateTime.utc(2026, 8, 7, 1, 2, 3),
      appVersion: '2.1.142',
      tmdbApiKey: 'tmdb-secret',
      cloudSources: <PortableCloudSourceConfiguration>[
        PortableCloudSourceConfiguration.fromSource(
          source: CloudSource(
            id: 'quark-1',
            type: CloudSourceType.quark,
            name: '夸克影视',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: const <String>['/影视'],
            lastScannedAt: DateTime.utc(2026, 8, 6),
            scanStatus: CloudScanStatus.completed,
            indexedVideoCount: 19,
            matchedSubtitleCount: 8,
            lastScanFailureCount: 2,
          ),
          credential: const CloudCredential(cookie: 'cookie-secret'),
        ),
      ],
    );

    final restored = PortableAppConfiguration.fromJson(exported.toJson());

    expect(restored.tmdbApiKey, 'tmdb-secret');
    expect(restored.cloudSources.single.credential?.cookie, 'cookie-secret');
    expect(restored.cloudSources.single.source.scanStatus, CloudScanStatus.never);
    expect(restored.cloudSources.single.source.lastScannedAt, isNull);
    expect(restored.cloudSources.single.source.indexedVideoCount, 0);
    expect(restored.toString(), isNot(contains('tmdb-secret')));
    expect(restored.toString(), isNot(contains('cookie-secret')));
  });

  test('便携配置拒绝重复来源 ID 和伪造固定网盘地址', () {
    PortableCloudSourceConfiguration quark(String id, String baseUrl) =>
        PortableCloudSourceConfiguration.fromSource(
          source: CloudSource(
            id: id,
            type: CloudSourceType.quark,
            name: '夸克',
            baseUrl: baseUrl,
            rootPaths: const <String>[],
          ),
          credential: const CloudCredential(cookie: 'cookie'),
        );

    expect(
      () => PortableAppConfiguration.create(
        exportedAt: DateTime.utc(2026, 8, 7),
        appVersion: '2.1.142',
        tmdbApiKey: '',
        cloudSources: <PortableCloudSourceConfiguration>[
          quark('same', 'https://pan.quark.cn'),
          quark('same', 'https://pan.quark.cn'),
        ],
      ),
      throwsA(isA<PortableConfigurationValidationException>()),
    );
    expect(
      () => quark('quark-1', 'https://attacker.example'),
      throwsA(isA<PortableConfigurationValidationException>()),
    );
  });

  test('OpenList 地址只接受不含用户信息的 HTTP 或 HTTPS URL', () {
    expect(
      () => PortableCloudSourceConfiguration.fromSource(
        source: const CloudSource(
          id: 'openlist-1',
          type: CloudSourceType.openList,
          name: '家庭盘',
          baseUrl: 'https://user:pass@drive.example.com',
          rootPaths: <String>['/影视'],
        ),
      ),
      throwsA(isA<PortableConfigurationValidationException>()),
    );
  });
}
```

- [ ] **Step 2: 运行测试并确认因模型不存在而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\portable_app_configuration_test.dart`

Expected: FAIL，提示 `portable_app_configuration.dart` 或 `PortableAppConfiguration` 不存在。

- [ ] **Step 3: 实现强类型模型、来源清理和稳定校验错误**

`portable_app_configuration.dart` 暴露以下完整接口；JSON 入口把 `Map<Object?, Object?>` 转成 `Map<String, dynamic>` 后再调用现有 `CloudSource.fromJson`/`CloudCredential.fromJson`，并在构造阶段统一执行 `_validateSource`：

```dart
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

@immutable
final class PortableCloudSourceConfiguration {
  PortableCloudSourceConfiguration._({
    required this.source,
    required this.credential,
  });

  factory PortableCloudSourceConfiguration.fromSource({
    required CloudSource source,
    CloudCredential? credential,
  }) {
    final sanitized = CloudSource(
      id: source.id.trim(),
      type: source.type,
      name: source.name.trim(),
      baseUrl: source.baseUrl.trim(),
      rootPaths: List<String>.unmodifiable(
        source.rootPaths.map((value) => value.trim()).where((value) => value.isNotEmpty),
      ),
      rootRefs: List.unmodifiable(source.rootRefs),
      defaultTransferDirectory: source.defaultTransferDirectory,
      enabled: source.enabled,
      allowSelfSignedCertificate: source.allowSelfSignedCertificate,
    );
    _validateSource(sanitized);
    return PortableCloudSourceConfiguration._(
      source: sanitized,
      credential: credential == null || credential.isEmpty ? null : credential,
    );
  }

  factory PortableCloudSourceConfiguration.fromJson(Map<String, Object?> json) {
    final rawSource = json['source'];
    if (rawSource is! Map<Object?, Object?>) {
      throw const PortableConfigurationValidationException('invalid_source');
    }
    final rawCredential = json['credential'];
    return PortableCloudSourceConfiguration.fromSource(
      source: CloudSource.fromJson(Map<String, dynamic>.from(rawSource)),
      credential: rawCredential is Map<Object?, Object?>
          ? CloudCredential.fromJson(Map<String, dynamic>.from(rawCredential))
          : null,
    );
  }

  final CloudSource source;
  final CloudCredential? credential;

  bool get requiresRootSelection =>
      source.type != CloudSourceType.openList &&
      source.rootPaths.isEmpty &&
      source.rootRefs.isEmpty;

  Map<String, Object?> toJson() => <String, Object?>{
        'source': source.toJson(),
        if (credential != null) 'credential': credential!.toJson(),
      };

  @override
  String toString() =>
      'PortableCloudSourceConfiguration(sourceId: ${source.id}, type: ${source.type.name}, hasCredential: ${credential != null})';

  static void _validateSource(CloudSource source) {
    if (source.id.isEmpty || source.id.length > 128) {
      throw const PortableConfigurationValidationException('invalid_source_id');
    }
    if (source.name.isEmpty || source.name.length > 120) {
      throw const PortableConfigurationValidationException('invalid_source_name');
    }
    final uri = Uri.tryParse(source.baseUrl);
    if (uri == null ||
        !uri.hasAuthority ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.userInfo.isNotEmpty) {
      throw const PortableConfigurationValidationException('invalid_source_url');
    }
    final expected = switch (source.type) {
      CloudSourceType.openList => null,
      CloudSourceType.quark => 'https://pan.quark.cn',
      CloudSourceType.baidu => 'https://pan.baidu.com',
      CloudSourceType.xunlei => 'https://pan.xunlei.com',
    };
    if (expected != null && source.baseUrl != expected) {
      throw const PortableConfigurationValidationException('invalid_provider_url');
    }
    if (source.rootPaths.length > 64 ||
        source.rootPaths.any((value) => value.length > 1024)) {
      throw const PortableConfigurationValidationException('invalid_root_paths');
    }
  }
}

@immutable
final class PortableAppConfiguration {
  PortableAppConfiguration._({
    required this.formatVersion,
    required this.exportedAt,
    required this.appVersion,
    required this.tmdbApiKey,
    required this.cloudSources,
  });

  static const int currentFormatVersion = 1;
  static const int maxCloudSourceCount = 100;

  factory PortableAppConfiguration.create({
    required DateTime exportedAt,
    required String appVersion,
    required String tmdbApiKey,
    required List<PortableCloudSourceConfiguration> cloudSources,
  }) => PortableAppConfiguration._validated(
        formatVersion: currentFormatVersion,
        exportedAt: exportedAt,
        appVersion: appVersion,
        tmdbApiKey: tmdbApiKey,
        cloudSources: cloudSources,
      );

  factory PortableAppConfiguration.fromJson(Map<String, Object?> json) {
    final rawSources = json['cloudSources'];
    if (rawSources is! List<Object?>) {
      throw const PortableConfigurationValidationException('invalid_sources');
    }
    final exportedAt = DateTime.tryParse(json['exportedAt']?.toString() ?? '');
    return PortableAppConfiguration._validated(
      formatVersion: json['formatVersion'],
      exportedAt: exportedAt,
      appVersion: json['appVersion'],
      tmdbApiKey: json['tmdbApiKey'],
      cloudSources: rawSources.map((value) {
        if (value is! Map<Object?, Object?>) {
          throw const PortableConfigurationValidationException('invalid_source');
        }
        return PortableCloudSourceConfiguration.fromJson(
          Map<String, Object?>.from(value),
        );
      }).toList(growable: false),
    );
  }

  factory PortableAppConfiguration._validated({
    required Object? formatVersion,
    required DateTime? exportedAt,
    required Object? appVersion,
    required Object? tmdbApiKey,
    required List<PortableCloudSourceConfiguration> cloudSources,
  }) {
    if (formatVersion != currentFormatVersion) {
      throw const PortableConfigurationValidationException('unsupported_format_version');
    }
    if (exportedAt == null || appVersion is! String || appVersion.trim().isEmpty) {
      throw const PortableConfigurationValidationException('invalid_metadata');
    }
    if (tmdbApiKey is! String || tmdbApiKey.length > 16384) {
      throw const PortableConfigurationValidationException('invalid_tmdb_key');
    }
    if (cloudSources.length > maxCloudSourceCount) {
      throw const PortableConfigurationValidationException('too_many_sources');
    }
    final ids = <String>{};
    for (final record in cloudSources) {
      if (!ids.add(record.source.id)) {
        throw const PortableConfigurationValidationException('duplicate_source_id');
      }
    }
    return PortableAppConfiguration._(
      formatVersion: currentFormatVersion,
      exportedAt: exportedAt.toUtc(),
      appVersion: appVersion.trim(),
      tmdbApiKey: tmdbApiKey.trim(),
      cloudSources: List<PortableCloudSourceConfiguration>.unmodifiable(cloudSources),
    );
  }

  final int formatVersion;
  final DateTime exportedAt;
  final String appVersion;
  final String tmdbApiKey;
  final List<PortableCloudSourceConfiguration> cloudSources;

  Map<String, Object?> toJson() => <String, Object?>{
        'formatVersion': formatVersion,
        'exportedAt': exportedAt.toIso8601String(),
        'appVersion': appVersion,
        'tmdbApiKey': tmdbApiKey,
        'cloudSources': cloudSources.map((value) => value.toJson()).toList(growable: false),
      };

  @override
  String toString() =>
      'PortableAppConfiguration(formatVersion: $formatVersion, appVersion: $appVersion, cloudSourceCount: ${cloudSources.length}, hasTmdbKey: ${tmdbApiKey.isNotEmpty})';
}

final class PortableConfigurationValidationException implements Exception {
  const PortableConfigurationValidationException(this.code);
  final String code;
  @override
  String toString() => 'PortableConfigurationValidationException($code)';
}
```

- [ ] **Step 4: 运行模型测试并确认通过**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\portable_app_configuration_test.dart`

Expected: PASS，扫描字段归零，秘密不出现在字符串中，非法来源在进入存储前失败。

- [ ] **Step 5: 提交领域模型**

```powershell
git add lib/features/configuration_transfer/domain/portable_app_configuration.dart test/portable_app_configuration_test.dart
git commit -m "feat: 增加便携配置模型"
```

### Task 2: 加密信封编解码

**Files:**
- Create: `lib/features/configuration_transfer/application/configuration_archive_codec.dart`
- Modify: `pubspec.yaml`
- Modify: `lib/main.dart`
- Test: `test/configuration_archive_codec_test.dart`

- [ ] **Step 1: 写出正确密码、随机值、错误密码、篡改、超大文件和版本测试**

```dart
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';

void main() {
  final config = PortableAppConfiguration.create(
    exportedAt: DateTime.utc(2026, 8, 7),
    appVersion: '2.1.142',
    tmdbApiKey: 'tmdb-secret',
    cloudSources: const <PortableCloudSourceConfiguration>[],
  );
  final codec = ConfigurationArchiveCodec();

  test('AES-GCM 配置包使用正确密码往返且每次 Salt 和 Nonce 不同', () async {
    final first = await codec.encrypt(config, password: 'correct-pass');
    final second = await codec.encrypt(config, password: 'correct-pass');
    final firstJson = jsonDecode(utf8.decode(first)) as Map<String, dynamic>;
    final secondJson = jsonDecode(utf8.decode(second)) as Map<String, dynamic>;

    expect(firstJson['format'], 'kyy-config');
    expect(firstJson['envelopeVersion'], 1);
    expect(firstJson['kdf']['iterations'], 600000);
    expect(firstJson['kdf']['salt'], isNot(secondJson['kdf']['salt']));
    expect(firstJson['cipher']['nonce'], isNot(secondJson['cipher']['nonce']));
    expect((await codec.decrypt(first, password: 'correct-pass')).tmdbApiKey, 'tmdb-secret');
  });

  test('错误密码和密文篡改统一返回认证失败', () async {
    final bytes = await codec.encrypt(config, password: 'correct-pass');
    expect(
      codec.decrypt(bytes, password: 'wrong-pass'),
      throwsA(isA<ConfigurationArchiveAuthenticationException>()),
    );
    final envelope = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    envelope['cipher']['ciphertext'] = base64Encode(Uint8List.fromList(<int>[1, 2, 3]));
    expect(
      codec.decrypt(Uint8List.fromList(utf8.encode(jsonEncode(envelope))), password: 'correct-pass'),
      throwsA(isA<ConfigurationArchiveAuthenticationException>()),
    );
  });

  test('超大文件和不支持的信封版本在解密前失败', () async {
    expect(
      codec.decrypt(
        Uint8List(ConfigurationArchiveCodec.maxEnvelopeBytes + 1),
        password: 'correct-pass',
      ),
      throwsA(isA<ConfigurationArchiveTooLargeException>()),
    );
    final bytes = utf8.encode(jsonEncode(<String, Object>{
      'format': 'kyy-config',
      'envelopeVersion': 99,
    }));
    expect(
      codec.decrypt(Uint8List.fromList(bytes), password: 'correct-pass'),
      throwsA(isA<ConfigurationArchiveUnsupportedVersionException>()),
    );
  });
}
```

- [ ] **Step 2: 运行测试并确认因编解码器和依赖不存在而失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\configuration_archive_codec_test.dart`

Expected: FAIL，提示 `configuration_archive_codec.dart` 不存在。

- [ ] **Step 3: 添加固定版本加密依赖并更新锁文件**

在 `pubspec.yaml` 的依赖区加入：

```yaml
  cryptography: ^2.9.0
  cryptography_flutter: ^2.3.4
```

Run: `D:\flutter\bin\flutter.bat pub get`

Expected: exit code 0，`pubspec.lock` 锁定兼容版本；不得移除已有媒体依赖或覆盖项。

- [ ] **Step 4: 实现固定格式的 PBKDF2/AES-GCM codec**

核心实现必须使用 16 字节 Salt、12 字节 Nonce、600000 次 PBKDF2-HMAC-SHA256、256 位密钥，并严格校验信封字段：

```dart
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';

final class ConfigurationArchiveCodec {
  ConfigurationArchiveCodec({Random? random}) : _random = random ?? Random.secure();

  static const int maxEnvelopeBytes = 512 * 1024;
  static const int minimumPasswordLength = 8;
  static const int kdfIterations = 600000;
  static const int envelopeVersion = 1;

  final Random _random;
  final AesGcm _cipher = AesGcm.with256bits();

  Future<Uint8List> encrypt(
    PortableAppConfiguration configuration, {
    required String password,
  }) async {
    _validatePassword(password);
    final salt = _randomBytes(16);
    final nonce = _randomBytes(12);
    final secretKey = await _deriveKey(password, salt, kdfIterations);
    final cleartext = utf8.encode(jsonEncode(configuration.toJson()));
    final box = await _cipher.encrypt(cleartext, secretKey: secretKey, nonce: nonce);
    final envelope = <String, Object>{
      'format': 'kyy-config',
      'envelopeVersion': envelopeVersion,
      'kdf': <String, Object>{
        'name': 'pbkdf2-hmac-sha256',
        'iterations': kdfIterations,
        'salt': base64Encode(salt),
      },
      'cipher': <String, Object>{
        'name': 'aes-256-gcm',
        'nonce': base64Encode(nonce),
        'ciphertext': base64Encode(box.cipherText),
        'mac': base64Encode(box.mac.bytes),
      },
    };
    final encoded = Uint8List.fromList(utf8.encode(jsonEncode(envelope)));
    if (encoded.length > maxEnvelopeBytes) {
      throw ConfigurationArchiveTooLargeException(encoded.length);
    }
    return encoded;
  }

  Future<PortableAppConfiguration> decrypt(
    Uint8List bytes, {
    required String password,
  }) async {
    _validatePassword(password);
    if (bytes.length > maxEnvelopeBytes) {
      throw ConfigurationArchiveTooLargeException(bytes.length);
    }
    final Map<String, dynamic> envelope;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is! Map<Object?, Object?>) throw const FormatException();
      envelope = Map<String, dynamic>.from(decoded);
    } on Object {
      throw const ConfigurationArchiveFormatException('invalid_json');
    }
    if (envelope['format'] != 'kyy-config') {
      throw const ConfigurationArchiveFormatException('invalid_format');
    }
    if (envelope['envelopeVersion'] != envelopeVersion) {
      throw const ConfigurationArchiveUnsupportedVersionException();
    }
    final kdf = _objectMap(envelope['kdf']);
    final cipher = _objectMap(envelope['cipher']);
    if (kdf['name'] != 'pbkdf2-hmac-sha256' ||
        kdf['iterations'] != kdfIterations ||
        cipher['name'] != 'aes-256-gcm') {
      throw const ConfigurationArchiveFormatException('unsupported_algorithm');
    }
    try {
      final salt = base64Decode(kdf['salt'] as String);
      final nonce = base64Decode(cipher['nonce'] as String);
      final ciphertext = base64Decode(cipher['ciphertext'] as String);
      final mac = base64Decode(cipher['mac'] as String);
      if (salt.length != 16 || nonce.length != 12 || mac.length != 16) {
        throw const FormatException();
      }
      final key = await _deriveKey(password, salt, kdfIterations);
      final cleartext = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(mac)),
        secretKey: key,
      );
      final decoded = jsonDecode(utf8.decode(cleartext));
      if (decoded is! Map<Object?, Object?>) throw const FormatException();
      return PortableAppConfiguration.fromJson(Map<String, Object?>.from(decoded));
    } on SecretBoxAuthenticationError {
      throw const ConfigurationArchiveAuthenticationException();
    } on PortableConfigurationValidationException catch (error) {
      if (error.code == 'unsupported_format_version') {
        throw const ConfigurationArchiveUnsupportedVersionException();
      }
      rethrow;
    } on ConfigurationArchiveAuthenticationException {
      rethrow;
    } on Object {
      throw const ConfigurationArchiveFormatException('invalid_envelope');
    }
  }

  Future<SecretKey> _deriveKey(String password, List<int> salt, int iterations) =>
      Pbkdf2.hmacSha256(iterations: iterations, bits: 256).deriveKeyFromPassword(
        password: password,
        nonce: salt,
      );

  Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List<int>.generate(length, (_) => _random.nextInt(256)));

  static Map<String, dynamic> _objectMap(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const ConfigurationArchiveFormatException('missing_section');
    }
    return Map<String, dynamic>.from(value);
  }

  static void _validatePassword(String password) {
    if (password.length < minimumPasswordLength) {
      throw const ConfigurationArchivePasswordException();
    }
  }
}

final class ConfigurationArchivePasswordException implements Exception {
  const ConfigurationArchivePasswordException();
}

final class ConfigurationArchiveAuthenticationException implements Exception {
  const ConfigurationArchiveAuthenticationException();
}

final class ConfigurationArchiveUnsupportedVersionException implements Exception {
  const ConfigurationArchiveUnsupportedVersionException();
}

final class ConfigurationArchiveFormatException implements Exception {
  const ConfigurationArchiveFormatException(this.code);
  final String code;
}

final class ConfigurationArchiveTooLargeException implements Exception {
  const ConfigurationArchiveTooLargeException(this.actualBytes);
  final int actualBytes;
}
```

- [ ] **Step 5: 在 Flutter 启动后立即启用平台加密实现**

在 `lib/main.dart` 添加 `cryptography_flutter` 导入，并紧跟 `WidgetsFlutterBinding.ensureInitialized()` 调用：

```dart
import 'package:cryptography_flutter/cryptography_flutter.dart';

WidgetsFlutterBinding.ensureInitialized();
FlutterCryptography.enable();
```

- [ ] **Step 6: 格式化并运行 codec 测试**

Run: `D:\flutter\bin\dart.bat format lib\features\configuration_transfer\application\configuration_archive_codec.dart lib\main.dart test\configuration_archive_codec_test.dart`

Run: `D:\flutter\bin\flutter.bat test --no-pub test\configuration_archive_codec_test.dart`

Expected: PASS；同一明文的两个信封不同，错误密码和篡改均不能产生配置对象。

- [ ] **Step 7: 提交加密编解码**

```powershell
git add pubspec.yaml pubspec.lock lib/main.dart lib/features/configuration_transfer/application/configuration_archive_codec.dart test/configuration_archive_codec_test.dart
git commit -m "feat: 增加配置文件加密格式"
```

### Task 3: 原子配置导入与回滚

**Files:**
- Create: `lib/features/configuration_transfer/application/configuration_importer.dart`
- Modify: `lib/repositories/cloud_source_repository.dart`
- Test: `test/configuration_importer_test.dart`
- Test: `test/cloud_source_repository_test.dart`

- [ ] **Step 1: 写出合并计数、空 TMDB 保留和跨存储回滚测试**

```dart
test('同 ID 更新、新 ID 新增、未出现来源保留且空 TMDB 不覆盖', () async {
  await repository.importForPairing(<CloudSourcePairingEntry>[
    const CloudSourcePairingEntry(source: CloudSource(
      id: 'existing',
      type: CloudSourceType.openList,
      name: '旧名称',
      baseUrl: 'https://old.example.com',
      rootPaths: <String>['/'],
    )),
    const CloudSourcePairingEntry(source: CloudSource(
      id: 'preserved',
      type: CloudSourceType.openList,
      name: '保留来源',
      baseUrl: 'https://keep.example.com',
      rootPaths: <String>['/'],
    )),
  ]);
  final configuration = PortableAppConfiguration.create(
    exportedAt: DateTime.utc(2026, 8, 7),
    appVersion: '2.1.142',
    tmdbApiKey: '',
    cloudSources: <PortableCloudSourceConfiguration>[
      PortableCloudSourceConfiguration.fromSource(source: const CloudSource(
        id: 'existing',
        type: CloudSourceType.openList,
        name: '新名称',
        baseUrl: 'https://new.example.com',
        rootPaths: <String>['/电影'],
      )),
      PortableCloudSourceConfiguration.fromSource(source: const CloudSource(
        id: 'added',
        type: CloudSourceType.quark,
        name: '新增夸克',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: <String>[],
      )),
    ],
  );

  final preview = await importer.preview(configuration);
  expect((preview.added, preview.updated, preview.preserved), (1, 1, 1));
  expect(preview.tmdbWillUpdate, isFalse);
  expect(preview.requiresRootSelection, 1);

  final result = await importer.apply(configuration);
  expect((result.added, result.updated, result.preserved), (1, 1, 1));
  expect(tmdbManager.read(), 'old-key');
  expect((await repository.getById('preserved'))?.name, '保留来源');
});

test('来源凭据写入失败时恢复 TMDB 来源和所有涉及凭据', () async {
  final failingStore = _FailOnSourceCredentialStore('added');
  final failingRepository = CloudSourceRepository(
    storage: sourceStorage,
    credentialStore: failingStore,
  );
  final failingImporter = ConfigurationImporter(
    sourceRepository: failingRepository,
    tmdbCredentialManager: tmdbManager,
  );
  final configuration = configurationWithTwoSourcesAndTmdb();

  expect(
    failingImporter.apply(configuration),
    throwsA(isA<ConfigurationImportException>()),
  );
  expect(tmdbManager.read(), 'old-key');
  expect(await sourceStorage.read(), previousSourceJson);
  expect((await failingStore.read('existing'))?.password, 'old-password');
});
```

测试夹具使用 `MemoryCloudSourceStorage`、`MemoryCloudCredentialStore`、`MemoryTmdbCredentialStore`；失败存储只在首次写入指定来源时抛错，随后允许回滚写入，从而验证真正恢复而不是测试替身永久失败。

- [ ] **Step 2: 运行测试并确认导入器不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\configuration_importer_test.dart`

Expected: FAIL，提示 `ConfigurationImporter` 不存在。

- [ ] **Step 3: 实现预览、结果和原子导入器**

```dart
import 'package:flutter/foundation.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

@immutable
final class ConfigurationMergeSummary {
  const ConfigurationMergeSummary({
    required this.added,
    required this.updated,
    required this.preserved,
    required this.tmdbWillUpdate,
    required this.requiresRootSelection,
  });
  final int added;
  final int updated;
  final int preserved;
  final bool tmdbWillUpdate;
  final int requiresRootSelection;
}

typedef ConfigurationImportResult = ConfigurationMergeSummary;

final class ConfigurationImporter {
  const ConfigurationImporter({
    required CloudSourceRepository sourceRepository,
    required TmdbCredentialManager tmdbCredentialManager,
  })  : _sourceRepository = sourceRepository,
        _tmdbCredentialManager = tmdbCredentialManager;

  final CloudSourceRepository _sourceRepository;
  final TmdbCredentialManager _tmdbCredentialManager;

  Future<ConfigurationMergeSummary> preview(
    PortableAppConfiguration configuration,
  ) async {
    final current = await _sourceRepository.getAll();
    final currentIds = current.map((source) => source.id).toSet();
    final importedIds = configuration.cloudSources
        .map((record) => record.source.id)
        .toSet();
    return ConfigurationMergeSummary(
      added: importedIds.difference(currentIds).length,
      updated: importedIds.intersection(currentIds).length,
      preserved: currentIds.difference(importedIds).length,
      tmdbWillUpdate: configuration.tmdbApiKey.isNotEmpty,
      requiresRootSelection: configuration.cloudSources
          .where((record) => record.requiresRootSelection)
          .length,
    );
  }

  Future<ConfigurationImportResult> apply(
    PortableAppConfiguration configuration,
  ) async {
    final summary = await preview(configuration);
    final previousTmdb = _tmdbCredentialManager.exportForPairing();
    final shouldUpdateTmdb = configuration.tmdbApiKey.isNotEmpty;
    try {
      if (shouldUpdateTmdb) {
        await _tmdbCredentialManager.importForPairing(configuration.tmdbApiKey);
      }
      await _sourceRepository.importForPairing(
        configuration.cloudSources
            .map((record) => CloudSourcePairingEntry(
                  source: record.source,
                  credential: record.credential,
                ))
            .toList(growable: false),
      );
      return summary;
    } on Object catch (error, stackTrace) {
      try {
        if (shouldUpdateTmdb) {
          await _tmdbCredentialManager.importForPairing(previousTmdb);
        }
      } on Object {
        throw const ConfigurationRollbackException();
      }
      if (error is CloudSourcePairingRollbackException) {
        throw const ConfigurationRollbackException();
      }
      Error.throwWithStackTrace(const ConfigurationImportException(), stackTrace);
    }
  }
}

final class ConfigurationImportException implements Exception {
  const ConfigurationImportException();
}

final class ConfigurationRollbackException implements Exception {
  const ConfigurationRollbackException();
}
```

在 `CloudSourceRepository` 保留当前存储级锁和 `_restorePairingSnapshot`；补充测试确认凭据删除失败、来源列表写入失败和回滚失败各自的稳定异常，不把凭据内容放进异常文本。

- [ ] **Step 4: 运行导入与仓库回滚测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\configuration_importer_test.dart test\cloud_source_repository_test.dart`

Expected: PASS；任何失败后旧 TMDB、来源列表和受影响凭据与导入前一致。

- [ ] **Step 5: 提交原子导入器**

```powershell
git add lib/features/configuration_transfer/application/configuration_importer.dart lib/repositories/cloud_source_repository.dart test/configuration_importer_test.dart test/cloud_source_repository_test.dart
git commit -m "feat: 原子合并设备配置"
```

### Task 4: 配置迁移服务与本机导入导出页面

**Files:**
- Create: `lib/features/configuration_transfer/application/configuration_transfer_service.dart`
- Create: `lib/features/configuration_transfer/presentation/configuration_transfer_page.dart`
- Modify: `lib/app/bindings/cloud_bindings.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Modify: `lib/pages/settings/cloud_sources_settings.dart`
- Test: `test/configuration_transfer_service_test.dart`
- Test: `test/configuration_transfer_page_test.dart`
- Test: `test/cloud_sources_ui_test.dart`

- [ ] **Step 1: 写服务测试，锁定导出内容、解密只预览和确认后写入**

```dart
test('导出捕获 TMDB 和全部来源凭据且 inspect 不写入目标配置', () async {
  await sourceRepository.save(quarkSource);
  await credentialStore.write(
    quarkSource.id,
    const CloudCredential(cookie: 'cookie-secret'),
  );
  await tmdbManager.save('tmdb-secret');

  final bytes = await service.exportEncrypted(password: 'export-pass');
  await sourceRepository.delete(quarkSource.id);
  await tmdbManager.save('target-key');

  final session = await service.inspect(bytes, password: 'export-pass');
  expect(session.summary.added, 1);
  expect(session.summary.tmdbWillUpdate, isTrue);
  expect(await sourceRepository.getAll(), isEmpty);
  expect(tmdbManager.read(), 'target-key');

  final result = await service.apply(session);
  expect(result.added, 1);
  expect(tmdbManager.read(), 'tmdb-secret');
  expect((await credentialStore.read(quarkSource.id))?.cookie, 'cookie-secret');
});
```

- [ ] **Step 2: 运行服务测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\configuration_transfer_service_test.dart`

Expected: FAIL，提示 `ConfigurationTransferService` 不存在。

- [ ] **Step 3: 实现服务门面和不可变导入会话**

```dart
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:kanyingyin/core/app_version.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_archive_codec.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

@immutable
final class ConfigurationImportSession {
  const ConfigurationImportSession({
    required this.configuration,
    required this.summary,
  });
  final PortableAppConfiguration configuration;
  final ConfigurationMergeSummary summary;
}

final class ConfigurationTransferService {
  const ConfigurationTransferService({
    required CloudSourceRepository sourceRepository,
    required TmdbCredentialManager tmdbCredentialManager,
    required ConfigurationImporter importer,
    required ConfigurationArchiveCodec codec,
    this.now = DateTime.now,
    this.appVersion = AppVersion.current,
  })  : _sourceRepository = sourceRepository,
        _tmdbCredentialManager = tmdbCredentialManager,
        _importer = importer,
        _codec = codec;

  final CloudSourceRepository _sourceRepository;
  final TmdbCredentialManager _tmdbCredentialManager;
  final ConfigurationImporter _importer;
  final ConfigurationArchiveCodec _codec;
  final DateTime Function() now;
  final String appVersion;

  Future<PortableAppConfiguration> capture() async {
    final entries = await _sourceRepository.exportForPairing();
    return PortableAppConfiguration.create(
      exportedAt: now().toUtc(),
      appVersion: appVersion,
      tmdbApiKey: _tmdbCredentialManager.exportForPairing(),
      cloudSources: entries
          .map((entry) => PortableCloudSourceConfiguration.fromSource(
                source: entry.source,
                credential: entry.credential,
              ))
          .toList(growable: false),
    );
  }

  Future<Uint8List> exportEncrypted({required String password}) async =>
      _codec.encrypt(await capture(), password: password);

  Future<ConfigurationImportSession> inspect(
    Uint8List bytes, {
    required String password,
  }) async {
    final configuration = await _codec.decrypt(bytes, password: password);
    return ConfigurationImportSession(
      configuration: configuration,
      summary: await _importer.preview(configuration),
    );
  }

  Future<ConfigurationImportResult> apply(ConfigurationImportSession session) =>
      _importer.apply(session.configuration);
}
```

在 `registerCloudBindings` 中按顺序注册 `ConfigurationArchiveCodec`、`ConfigurationImporter`、`ConfigurationTransferService`，全部从同一个 `CloudSourceRepository` 和 `TmdbCredentialManager` 单例取依赖。

- [ ] **Step 4: 写页面测试，锁定密码确认、预览、取消、成功和列表刷新**

```dart
testWidgets('配置导出要求两次密码一致且成功信息不显示秘密', (tester) async {
  Uint8List? saved;
  await tester.pumpWidget(MaterialApp(
    home: ConfigurationTransferPage(
      service: fixture.service,
      saveFile: (bytes, fileName) async {
        saved = bytes;
        return fileName;
      },
      openFile: () async => null,
      shareEncryptedFile: (_, __) async => ConfigurationShareOutcome.shared,
      onImported: () async {},
      capabilities: AppPlatformCapabilities.windows,
    ),
  ));
  await tester.tap(find.text('导出配置'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('export-password')), 'password-a');
  await tester.enterText(find.byKey(const ValueKey('export-password-confirm')), 'password-b');
  await tester.tap(find.text('开始导出'));
  await tester.pump();
  expect(find.text('两次输入的密码不一致'), findsOneWidget);

  await tester.enterText(find.byKey(const ValueKey('export-password-confirm')), 'password-a');
  await tester.tap(find.text('开始导出'));
  await tester.pumpAndSettle();
  expect(saved, isNotNull);
  expect(find.textContaining('导出完成'), findsOneWidget);
  expect(find.textContaining('tmdb-secret'), findsNothing);
});

testWidgets('配置导入先显示合并摘要，取消不写入，确认后刷新来源', (tester) async {
  var refreshCount = 0;
  await tester.pumpWidget(MaterialApp(
    home: ConfigurationTransferPage(
      service: fixture.service,
      saveFile: (_, __) async => null,
      openFile: () async => encryptedFixture,
      shareEncryptedFile: (_, __) async => ConfigurationShareOutcome.shared,
      onImported: () async => refreshCount++,
      capabilities: AppPlatformCapabilities.android,
    ),
  ));
  await tester.tap(find.text('导入配置'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('import-password')), 'password-a');
  await tester.tap(find.text('检查配置'));
  await tester.pumpAndSettle();
  expect(find.text('新增来源：1 个'), findsOneWidget);
  await tester.tap(find.text('取消'));
  expect(refreshCount, 0);

  await tester.tap(find.text('导入配置'));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const ValueKey('import-password')), 'password-a');
  await tester.tap(find.text('检查配置'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('确认导入'));
  await tester.pumpAndSettle();
  expect(refreshCount, 1);
  expect(find.textContaining('导入完成'), findsOneWidget);
});
```

- [ ] **Step 5: 运行页面测试并确认页面不存在**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\configuration_transfer_page_test.dart`

Expected: FAIL，提示 `ConfigurationTransferPage` 不存在。

- [ ] **Step 6: 实现迁移页面和可注入文件端口**

页面公开以下端口，使 Widget 测试不调用系统选择器；生产默认实现严格区分“用户取消”和“插件不支持”：

```dart
typedef ConfigurationSaveFile = Future<String?> Function(
  Uint8List bytes,
  String fileName,
);
typedef ConfigurationOpenFile = Future<Uint8List?> Function();
typedef ConfigurationShareEncryptedFile = Future<ConfigurationShareOutcome>
    Function(Uint8List bytes, String fileName);

enum ConfigurationShareOutcome { shared, dismissed }
```

`ConfigurationTransferPage` 的 `_export()` 必须：先 `service.capture()` 展示 TMDB 是否存在和四类来源计数；弹出两个 `obscureText` 密码框；验证长度和一致性；调用 `exportEncrypted`；Windows 使用 `FilePicker.saveFile` 取得路径后写入加密字节；Android/TV 使用 `FilePicker.saveFile(bytes: bytes)`，只有捕获 `PlatformException` 或 `UnimplementedError` 时才把加密字节写到 `getTemporaryDirectory()` 并通过现有 `SharePlus.instance.share(ShareParams(files: <XFile>[...]))` 分享。分享完成或取消后在 `finally` 中删除临时的加密文件。用户取消选择器不得自动弹出分享面板。

`_import()` 必须：使用 `FilePicker.pickFiles(type: FileType.custom, allowedExtensions: <String>['kyyconfig'], withData: true)`；在读取后立即检查 512 KiB；弹出单个密码框；调用 `inspect` 后显示 `added/updated/preserved/tmdbWillUpdate/requiresRootSelection`；只有“确认导入”调用 `apply` 和 `onImported`。稳定错误映射如下：

```dart
String configurationTransferErrorMessage(Object error) => switch (error) {
  ConfigurationArchivePasswordException() => '密码至少需要 8 个字符',
  ConfigurationArchiveAuthenticationException() => '密码错误或配置文件已损坏',
  ConfigurationArchiveUnsupportedVersionException() => '此配置文件版本暂不支持',
  ConfigurationArchiveTooLargeException() => '配置文件超过 512 KiB',
  PortableConfigurationValidationException() => '配置文件内容无效',
  ConfigurationRollbackException() => '配置写入失败，自动恢复未完整完成，请重新检查当前配置',
  ConfigurationImportException() => '配置写入失败，原配置已保留',
  _ => '配置迁移失败，请检查文件后重试',
};
```

- [ ] **Step 7: 添加路由、入口和导入后刷新**

在 `SettingsModule` 增加 `/cloud-sources/configuration-transfer`，注入 `Modular.get<ConfigurationTransferService>()`，并把 `onImported` 绑定到共享 `CloudLibraryController.load()`。在 `CloudSourcesSettingsPage` 的顶部加入所有平台可见的 `KSettingsTile.navigation`：

```dart
KSettingsTile<void>.navigation(
  key: const ValueKey<String>('configuration-transfer-entry'),
  leading: const Icon(Icons.import_export_rounded),
  title: const Text('配置迁移'),
  description: const Text('用密码加密导出或导入 TMDB 与网盘账号配置'),
  onPressed: (_) => Modular.to.pushNamed(
    '/settings/cloud-sources/configuration-transfer',
  ),
),
```

手机扫码入口仍只在 Android TV 显示；迁移入口在 Windows、普通 Android、Android TV 都显示。

- [ ] **Step 8: 运行迁移服务、页面和设置入口测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\configuration_transfer_service_test.dart test\configuration_transfer_page_test.dart test\cloud_sources_ui_test.dart`

Expected: PASS；取消导入零写入，成功导入刷新共享控制器，UI 不展示秘密。

- [ ] **Step 9: 提交本机配置迁移**

```powershell
git add lib/features/configuration_transfer lib/app/bindings/cloud_bindings.dart lib/pages/settings/settings_module.dart lib/pages/settings/cloud_sources_settings.dart test/configuration_transfer_service_test.dart test/configuration_transfer_page_test.dart test/cloud_sources_ui_test.dart
git commit -m "feat: 增加加密配置导入导出"
```

### Task 5: 配对协议复用便携配置并增加手机连接状态

**Files:**
- Modify: `lib/features/tv_pairing/domain/tv_pairing_models.dart`
- Modify: `lib/features/tv_pairing/application/tv_pairing_controller.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Test: `test/tv_pairing_models_test.dart`
- Test: `test/tv_pairing_controller_test.dart`

- [ ] **Step 1: 更新模型测试为嵌套的公共配置载荷**

```dart
test('配对载荷复用便携配置且字符串不泄漏秘密', () {
  final payload = TvPairingPayload(
    protocolVersion: TvPairingPayload.currentProtocolVersion,
    deviceName: '手机配置',
    configuration: PortableAppConfiguration.create(
      exportedAt: DateTime.utc(2026, 8, 7),
      appVersion: 'phone-web',
      tmdbApiKey: 'tmdb-secret',
      cloudSources: <PortableCloudSourceConfiguration>[
        PortableCloudSourceConfiguration.fromSource(
          source: const CloudSource(
            id: 'quark-1',
            type: CloudSourceType.quark,
            name: '夸克',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>[],
          ),
          credential: const CloudCredential(cookie: 'cookie-secret'),
        ),
      ],
    ),
  );
  final restored = TvPairingPayload.decode(payload.encode());
  expect(restored.configuration.cloudSources.single.source.id, 'quark-1');
  expect(restored.toString(), isNot(contains('tmdb-secret')));
  expect(restored.toString(), isNot(contains('cookie-secret')));
});
```

把 `currentProtocolVersion` 升为 `2`，旧版扁平载荷明确返回 `TvPairingInvalidPayloadException('配对协议版本不受支持')`；手机页和二维码都随同一提交切换到 v2，不维护两个协议写入路径。

- [ ] **Step 2: 写控制器的连接、确认、拒绝和写入失败状态测试**

```dart
test('手机打开页面后进入 phoneConnected 且重复通知幂等', () async {
  await controller.start();
  server.notifyPhoneConnected();
  server.notifyPhoneConnected();
  expect(controller.state, TvPairingState.phoneConnected);
});

test('手机提交后预览并在 TV 确认后调用公共导入器', () async {
  await controller.start();
  server.notifyPhoneConnected();
  final submission = server.submit(payload);
  await Future<void>.delayed(Duration.zero);
  expect(controller.state, TvPairingState.awaitingConfirmation);
  expect(controller.pendingSummary?.requiresRootSelection, 1);

  await controller.confirmPending();
  expect(await submission, TvPairingSubmissionResult.accepted);
  expect(controller.state, TvPairingState.success);
});

test('公共导入器失败时返回 applyFailed 而不是用户拒绝', () async {
  final controller = controllerWithFailingImporter();
  await controller.start();
  final submission = server.submit(payload);
  await Future<void>.delayed(Duration.zero);
  await controller.confirmPending();
  expect(await submission, TvPairingSubmissionResult.applyFailed);
  expect(controller.errorMessage, '配置写入失败，原配置已保留');
});
```

- [ ] **Step 3: 运行模型和控制器测试并确认旧接口失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\tv_pairing_models_test.dart test\tv_pairing_controller_test.dart`

Expected: FAIL，`configuration`、`phoneConnected`、`onPhoneConnected` 或 `applyFailed` 尚不存在。

- [ ] **Step 4: 改造载荷和控制器**

`TvPairingPayload` 改为：

```dart
@immutable
final class TvPairingPayload {
  const TvPairingPayload({
    required this.protocolVersion,
    required this.deviceName,
    required this.configuration,
  });

  static const int currentProtocolVersion = 2;
  static const int maxPayloadBytes = 256 * 1024;

  final int protocolVersion;
  final String deviceName;
  final PortableAppConfiguration configuration;

  Map<String, Object?> toJson() => <String, Object?>{
        'protocolVersion': protocolVersion,
        'deviceName': deviceName,
        'configuration': configuration.toJson(),
      };

  @override
  String toString() =>
      'TvPairingPayload(protocolVersion: $protocolVersion, deviceName: $deviceName, cloudSourceCount: ${configuration.cloudSources.length}, hasTmdbKey: ${configuration.tmdbApiKey.isNotEmpty})';
}
```

保留当前 256 KiB 限制和 UTF-8 JSON 错误封装。控制器状态改为：

```dart
enum TvPairingState {
  idle,
  starting,
  active,
  phoneConnected,
  awaitingConfirmation,
  applying,
  success,
  error,
}
```

控制器构造函数改为接收 `ConfigurationImporter importer`；`start()` 把 `_handlePhoneConnected` 传给服务器；该回调只在 `active` 时切到 `phoneConnected`。`_handlePayload` 接受 `active` 或 `phoneConnected`，先调用 `importer.preview(payload.configuration)` 构造不含秘密的摘要。控制器新增只读 `ConfigurationMergeSummary? completedSummary`：`confirmPending()` 成功时先保存 `importer.apply` 返回值，再清除待确认载荷并进入 `success`，使成功页仍能显示待选择目录数量；重新开始、取消和过期时清空完成摘要。用户拒绝完成 `rejected` 并返回 `phoneConnected`；写入异常完成 `applyFailed` 并显示“配置写入失败，原配置已保留”。

- [ ] **Step 5: 更新 SettingsModule 注入并运行测试**

`TvPairingPage` 的控制器创建改为：

```dart
controller: TvPairingController(
  importer: Modular.get<ConfigurationImporter>(),
),
```

Run: `D:\flutter\bin\flutter.bat test --no-pub test\tv_pairing_models_test.dart test\tv_pairing_controller_test.dart`

Expected: PASS；扫码打开和提交是两个独立状态，写入失败与用户拒绝可区分。

- [ ] **Step 6: 提交配对领域和控制器**

```powershell
git add lib/features/tv_pairing/domain/tv_pairing_models.dart lib/features/tv_pairing/application/tv_pairing_controller.dart lib/pages/settings/settings_module.dart test/tv_pairing_models_test.dart test/tv_pairing_controller_test.dart
git commit -m "feat(tv): 完善配对确认状态机"
```

### Task 6: 手机四类网盘表单和双端结果响应

**Files:**
- Create: `lib/features/tv_pairing/data/tv_pairing_phone_page.dart`
- Modify: `lib/features/tv_pairing/data/tv_pairing_http_server.dart`
- Test: `test/tv_pairing_http_server_test.dart`
- Test: `test/tv_pairing_phone_page_test.dart`

- [ ] **Step 1: 写服务器连接通知与稳定响应测试**

```dart
test('有效 GET 只幂等通知一次手机已连接', () async {
  var connected = 0;
  final endpoint = await server.start(
    session: session,
    onPhoneConnected: () => connected++,
    onPayload: (_) async => TvPairingSubmissionResult.rejected,
  );
  await _request(endpoint.pairUri);
  await _request(endpoint.pairUri);
  expect(connected, 1);
});

test('电视写入失败返回 apply_failed，用户拒绝返回 rejected_on_tv', () async {
  final applyFailedEndpoint = await server.start(
    session: session,
    onPhoneConnected: () {},
    onPayload: (_) async => TvPairingSubmissionResult.applyFailed,
  );
  final failed = await _request(
    applyFailedEndpoint.pairApiUri,
    method: 'POST',
    token: session.token,
    contentType: ContentType.json,
    body: _payloadBytes(),
  );
  expect(failed.statusCode, HttpStatus.internalServerError);
  expect(failed.body, contains('apply_failed'));
});
```

- [ ] **Step 2: 写手机页面结构和四类映射契约测试**

```dart
test('手机页面不依赖 template 且包含四类来源字段、倒计时和成功页面', () {
  final html = buildTvPairingPhonePage(
    token: 'pairing-token',
    expiresAt: DateTime.utc(2026, 8, 7, 12, 5),
  );
  expect(html, isNot(contains('<template')));
  expect(html, contains('id="add-source"'));
  expect(html, contains('scrollIntoView'));
  expect(html, contains('.focus()'));
  expect(html, contains('crypto.getRandomValues'));
  expect(html, contains('https://pan.quark.cn'));
  expect(html, contains('https://pan.baidu.com'));
  expect(html, contains('https://pan.xunlei.com'));
  expect(html, contains('clientSecret'));
  expect(html, contains('accessTokenExpiresAt'));
  expect(html, contains('refreshToken'));
  expect(html, contains('allowSelfSignedCertificate'));
  expect(html, contains('等待电视确认'));
  expect(html, contains('电视配置成功'));
  expect(html, contains('id="pairing-remaining"'));
  expect(html, contains('session_expired'));
  expect(html, isNot(contains('https://cdn.')));
});
```

另在 HTTP 测试中分别提交 OpenList、夸克、百度、迅雷的 v2 JSON，断言服务端解析后的 `CloudSource.type/baseUrl/rootPaths` 和对应 `CloudCredential` 字段准确；非 OpenList 新来源必须 `requiresRootSelection == true`。

- [ ] **Step 3: 运行 HTTP 和页面测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\tv_pairing_http_server_test.dart test\tv_pairing_phone_page_test.dart`

Expected: FAIL，连接回调、`applyFailed` 和独立手机页面生成器尚不存在。

- [ ] **Step 4: 从服务器拆出手机页面生成器并实现无 template 动态卡片**

`buildTvPairingPhonePage({required String token, required DateTime expiresAt})` 必须用 `jsonEncode(token)` 注入令牌、用 UTC 毫秒时间戳注入真实到期时间；页面顶部显示“已连接电视”、`pairing-remaining` 秒级倒计时和“不在公共 Wi-Fi 使用”的提醒。倒计时归零时禁用提交并显示 `session_expired` 对应的“配对已过期，请在电视重新生成二维码”。JavaScript 用以下稳定 ID 和提供方定义创建卡片：

```javascript
const providers={
  openList:{label:'OpenList',baseUrl:'',fields:['rootPaths','username','password','allowSelfSignedCertificate']},
  quark:{label:'夸克网盘',baseUrl:'https://pan.quark.cn',fields:['cookie']},
  baidu:{label:'百度网盘',baseUrl:'https://pan.baidu.com',fields:['clientId','clientSecret','accessToken','refreshToken','accessTokenExpiresAt']},
  xunlei:{label:'迅雷网盘',baseUrl:'https://pan.xunlei.com',fields:['refreshToken']}
};
function newSourceId(){
  const bytes=new Uint8Array(16);crypto.getRandomValues(bytes);
  return 'phone-'+Array.from(bytes,function(value){return value.toString(16).padStart(2,'0')}).join('');
}
function addSource(){
  const card=document.createElement('article');
  card.className='source';card.dataset.sourceId=newSourceId();
  card.append(buildTypeField(),buildNameField(),document.createElement('div'));
  card.querySelector('[data-field="type"]').addEventListener('change',function(){renderProviderFields(card)});
  card.append(buildRemoveButton(card));sources.append(card);renderProviderFields(card);
  card.scrollIntoView({behavior:'smooth',block:'center'});
  card.querySelector('[data-field="type"]').focus();
}
```

不要每次 `buildPayload()` 重新生成 ID。`buildPayload()` 生成 v2 嵌套配置：OpenList 可填写路径；夸克/百度/迅雷的 `rootPaths` 和 `rootRefs` 为空；固定提供方 URL 不使用用户输入。百度到期时间用 `new Date(value).toISOString()`，空值不写入凭据。

本地校验必须返回卡片级错误并聚焦：OpenList 需要名称、合法 HTTP(S) 地址和至少一个根目录；夸克需要 Cookie；百度需要 clientId/clientSecret/accessToken/refreshToken/有效到期时间；迅雷需要 refreshToken。页面顶部显示会话仅五分钟且不要在公共 Wi-Fi 使用。

提交期间按钮禁用并显示“等待电视确认”；`paired` 时隐藏表单、显示不可编辑的“电视配置成功”；`rejected_on_tv` 时保留输入并允许修改重发；`apply_failed` 显示“电视写入失败，原配置已保留”；网络错误提示同一局域网和 AP 隔离。

- [ ] **Step 5: 扩展服务器接口并实现幂等连接通知**

```dart
enum TvPairingSubmissionResult { accepted, rejected, applyFailed }
typedef TvPairingPhoneConnectedHandler = void Function();

abstract interface class TvPairingServer {
  bool get isRunning;
  Future<TvPairingServerEndpoint> start({
    required TvPairingSession session,
    required TvPairingPhoneConnectedHandler onPhoneConnected,
    required TvPairingPayloadHandler onPayload,
    TvPairingCancelledHandler? onCancelled,
  });
  Future<void> stop();
}
```

`TvPairingHttpServer` 增加 `_onPhoneConnected` 和 `_phoneConnectedNotified`；`start/stop/_stopAcceptingNewRequests` 完整清理。`_handlePairPage` 在令牌与协议版本都有效后同步设置 `_phoneConnectedNotified = true` 再调用回调，保证并发 GET 也只通知一次，并把 `session.expiresAt` 传给手机页面生成器。POST 结果映射：accepted=`200 paired`，rejected=`409 rejected_on_tv`，applyFailed=`500 apply_failed`；只有 accepted 消费令牌并关闭服务。

- [ ] **Step 6: 运行 HTTP、HTML 契约和格式检查**

Run: `D:\flutter\bin\dart.bat format lib\features\tv_pairing\data\tv_pairing_http_server.dart lib\features\tv_pairing\data\tv_pairing_phone_page.dart test\tv_pairing_http_server_test.dart test\tv_pairing_phone_page_test.dart`

Run: `D:\flutter\bin\flutter.bat test --no-pub test\tv_pairing_http_server_test.dart test\tv_pairing_phone_page_test.dart`

Expected: PASS；GET 幂等通知，四种来源提交映射正确，失败状态不会消费令牌。

- [ ] **Step 7: 提交手机配对闭环**

```powershell
git add lib/features/tv_pairing/data/tv_pairing_http_server.dart lib/features/tv_pairing/data/tv_pairing_phone_page.dart test/tv_pairing_http_server_test.dart test/tv_pairing_phone_page_test.dart
git commit -m "feat(tv): 完善手机网盘配置页面"
```

### Task 7: TV 配对状态页和成功反馈

**Files:**
- Modify: `lib/features/tv_pairing/presentation/tv_pairing_page.dart`
- Modify: `lib/pages/settings/settings_module.dart`
- Test: `test/tv_pairing_page_test.dart`

- [ ] **Step 1: 写连接、确认、拒绝、成功和待选目录 Widget 测试**

```dart
testWidgets('手机打开后隐藏主二维码并显示连接成功', (tester) async {
  final fixture = await _PairingPageFixture.create();
  await tester.pumpWidget(MaterialApp(home: TvPairingPage(controller: fixture.controller)));
  await tester.pumpAndSettle();
  fixture.server.notifyPhoneConnected();
  await tester.pump();
  expect(find.byKey(const ValueKey<String>('tv-pairing-qr')), findsNothing);
  expect(find.text('手机已连接'), findsOneWidget);
  expect(find.text('等待手机填写并发送配置'), findsOneWidget);
});

testWidgets('确认写入后两端成功且提示未选择目录的来源', (tester) async {
  final fixture = await _PairingPageFixture.create();
  var reloadCount = 0;
  await tester.pumpWidget(MaterialApp(home: TvPairingPage(
    controller: fixture.controller,
    onCompleted: () async => reloadCount++,
  )));
  await tester.pumpAndSettle();
  final submission = fixture.server.submit(payloadWithQuarkWithoutRoot());
  await tester.pumpAndSettle();
  expect(find.text('需要选择媒体目录：1 个'), findsOneWidget);
  await tester.tap(find.text('确认写入'));
  await tester.pumpAndSettle();
  expect(await submission, TvPairingSubmissionResult.accepted);
  expect(find.text('配置已写入'), findsOneWidget);
  expect(find.text('返回网盘数据源选择目录'), findsOneWidget);
  await tester.tap(find.text('返回网盘数据源选择目录'));
  await tester.pumpAndSettle();
  expect(reloadCount, 1);
});

testWidgets('TV 拒绝后恢复等待手机修改而不是退出页面', (tester) async {
  final fixture = await _PairingPageFixture.create();
  await tester.pumpWidget(MaterialApp(home: TvPairingPage(controller: fixture.controller)));
  await tester.pumpAndSettle();
  final submission = fixture.server.submit(payloadWithOpenList());
  await tester.pumpAndSettle();
  await tester.tap(find.text('拒绝'));
  await tester.pump();
  expect(await submission, TvPairingSubmissionResult.rejected);
  expect(find.text('手机已连接'), findsOneWidget);
});
```

- [ ] **Step 2: 运行页面测试并确认新状态没有 UI**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\tv_pairing_page_test.dart`

Expected: FAIL，找不到“手机已连接”或待选目录提示。

- [ ] **Step 3: 为每个状态提供独立页面内容**

`TvPairingPage` 的状态 switch 必须完整映射：

```dart
Widget _buildState(BuildContext context) => switch (_controller.state) {
  TvPairingState.idle || TvPairingState.starting => const Center(
      child: CircularProgressIndicator(),
    ),
  TvPairingState.active => _buildQrState(context),
  TvPairingState.phoneConnected => _buildMessageState(
      icon: Icons.phonelink_ring_rounded,
      title: '手机已连接',
      message: '等待手机填写并发送配置',
    ),
  TvPairingState.awaitingConfirmation => _buildConfirmation(context),
  TvPairingState.applying => _buildMessageState(
      icon: Icons.sync_rounded,
      title: '正在写入配置',
      message: '请保持电视和手机连接，不要关闭应用',
      progress: true,
    ),
  TvPairingState.success => _buildSuccess(context),
  TvPairingState.error => _buildError(context),
};
```

确认摘要只显示设备名称、TMDB 是否更新、新增/更新/保留数量和待选择目录数量。`TvPairingPage` 新增 `Future<void> Function()? onCompleted`；成功页按钮“返回网盘数据源选择目录”和普通完成按钮先等待该回调，再调用 `Navigator.of(context).pop()`。`SettingsModule` 传入 `Modular.get<CloudLibraryController>().load`，确保返回列表时从仓库重新读取来源；刷新失败只显示提示，不把已经成功写入的配置改判为失败。页面不显示任何凭据值，错误页提供“重新生成二维码”和“手动配置”。

- [ ] **Step 4: 运行所有配对测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\tv_pairing_models_test.dart test\tv_pairing_controller_test.dart test\tv_pairing_http_server_test.dart test\tv_pairing_phone_page_test.dart test\tv_pairing_page_test.dart`

Expected: PASS；扫码、提交、电视确认和手机响应形成完整状态闭环。

- [ ] **Step 5: 提交 TV 配对页面**

```powershell
git add lib/features/tv_pairing/presentation/tv_pairing_page.dart lib/pages/settings/settings_module.dart test/tv_pairing_page_test.dart
git commit -m "feat(tv): 显示配对连接与写入结果"
```

### Task 8: TV 设置高对比焦点表面

**Files:**
- Create: `lib/features/settings/presentation/tv_settings_focus_surface.dart`
- Modify: `lib/features/settings/presentation/settings_presentation.dart`
- Modify: `lib/features/settings/presentation/k_settings_tile.dart`
- Modify: `lib/pages/settings/tmdb_settings.dart`
- Modify: `lib/pages/settings/cloud_sources_settings.dart`
- Modify: `lib/features/tv_pairing/presentation/tv_pairing_page.dart`
- Test: `test/settings_presentation_components_test.dart`
- Test: `test/tmdb_settings_language_test.dart`
- Test: `test/cloud_sources_ui_test.dart`
- Test: `test/tv_pairing_page_test.dart`

- [ ] **Step 1: 写 TV 焦点视觉、语义和中心键激活测试**

```dart
testWidgets('TV 设置焦点显示 3px 边框、浅色背景、勾选和操作提示', (tester) async {
  var activated = 0;
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: TvSettingsFocusSurface(
        autofocus: true,
        capabilities: AppPlatformCapabilities.android.copyWith(television: true),
        onPressed: () => activated++,
        child: const Text('测试 TMDB 连接'),
      ),
    ),
  ));
  await tester.pump();
  final surface = tester.widget<AnimatedContainer>(
    find.byKey(const ValueKey<String>('tv-settings-focused-surface')),
  );
  final decoration = surface.decoration as BoxDecoration;
  expect((decoration.border! as Border).top.width, 3);
  expect(decoration.color, isNot(Colors.transparent));
  expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
  expect(find.text('当前选中 · 按确认执行'), findsOneWidget);
  await tester.sendKeyEvent(LogicalKeyboardKey.select);
  expect(activated, 1);
});

testWidgets('Windows 设置项不增加 TV 提示且点击行为不变', (tester) async {
  await tester.pumpWidget(MaterialApp(
    home: TvSettingsFocusSurface(
      capabilities: AppPlatformCapabilities.windows,
      onPressed: () {},
      child: const Text('普通设置项'),
    ),
  ));
  expect(find.text('当前选中 · 按确认执行'), findsNothing);
  expect(find.byKey(const ValueKey<String>('tv-settings-focused-surface')), findsNothing);
});
```

再安装 TV 全局能力后泵出 `KSettingsNavigationTile`、`KSettingsSwitchTile`、`KSettingsRadioTile`，用方向键移动焦点并断言每次只有一个 `tv-settings-focused-surface`；Enter/Select 只触发一次，内层 Switch/Radio 不建立第二焦点。

- [ ] **Step 2: 运行设置组件测试并确认失败**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\settings_presentation_components_test.dart`

Expected: FAIL，提示 `TvSettingsFocusSurface` 不存在。

- [ ] **Step 3: 实现 TV 专用焦点表面**

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:kanyingyin/platform/app_platform.dart';
import 'package:kanyingyin/platform/app_platform_io.dart';

class TvSettingsFocusSurface extends StatefulWidget {
  const TvSettingsFocusSurface({
    super.key,
    required this.child,
    required this.onPressed,
    this.enabled = true,
    this.autofocus = false,
    this.capabilities,
  });
  final Widget child;
  final VoidCallback onPressed;
  final bool enabled;
  final bool autofocus;
  final AppPlatformCapabilities? capabilities;

  @override
  State<TvSettingsFocusSurface> createState() => _TvSettingsFocusSurfaceState();
}

class _TvSettingsFocusSurfaceState extends State<TvSettingsFocusSurface> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final isTv = (widget.capabilities ?? detectAppPlatform()).isAndroidTv;
    if (!isTv) return widget.child;
    final scheme = Theme.of(context).colorScheme;
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      enabled: widget.enabled,
      onFocusChange: (value) {
        if (_focused != value) setState(() => _focused = value);
        if (value) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _focused) {
              Scrollable.ensureVisible(
                context,
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
              );
            }
          });
        }
      },
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.select): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
          if (widget.enabled) widget.onPressed();
          return null;
        }),
      },
      child: Semantics(
        button: true,
        enabled: widget.enabled,
        child: AnimatedContainer(
          key: ValueKey<String>(
            _focused ? 'tv-settings-focused-surface' : 'tv-settings-unfocused-surface',
          ),
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: _focused
                ? scheme.primaryContainer.withValues(alpha: 0.72)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _focused ? scheme.primary : Colors.transparent,
              width: 3,
            ),
          ),
          child: ExcludeFocus(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                widget.child,
                SizedBox(
                  height: 28,
                  child: AnimatedOpacity(
                    opacity: _focused ? 1 : 0,
                    duration: const Duration(milliseconds: 160),
                    curve: Curves.easeOut,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.check_circle_rounded, size: 18, color: scheme.primary),
                        const SizedBox(width: 6),
                        Text('当前选中 · 按确认执行', style: Theme.of(context).textTheme.labelMedium),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

保持 28 px 提示区始终占位，避免焦点移动引发布局跳动；非 TV 直接返回原 child，不改变 Windows 悬停、触摸或普通 Android 行为。

- [ ] **Step 4: 让 KSettings 三类交互项统一使用焦点表面**

`_InteractiveSettingsTile` 的现有 `MouseRegion -> AnimatedScale -> Material -> InkWell` 保留；把它作为 `TvSettingsFocusSurface.child`，并把同一个 `onPressed` 传给焦点表面。TV 下 `ExcludeFocus` 阻止内层 InkWell/Switch/Radio 建立第二焦点，但鼠标和触摸点击仍可工作。禁用项同时禁用两层。

- [ ] **Step 5: 把 TMDB 指定操作改为统一设置项并包裹保存按钮**

将“测试 TMDB 连接”“清理元数据缓存”“迁移刮削资料”改为 `KSettingsTile.navigation`；保存按钮用 `TvSettingsFocusSurface` 包裹。`TmdbSettingsPage` 新增可选 `AppPlatformCapabilities? capabilities` 只用于测试/焦点表面，默认使用全局能力。测试断言聚焦“测试 TMDB 连接”时能看到勾选和提示，中心键触发 `_testConnection`，不会被 TextField 困住。

- [ ] **Step 6: 为 TV 网盘列表拆开嵌套操作焦点**

Windows/普通 Android 保留当前来源 `ListTile`、尾部 IconButton 和 PopupMenu。Android TV 分支为每个来源渲染一个 `KSettingsSection`：来源主项负责进入编辑；可用夸克分享导入、扫描/停止、删除分别是独立 `KSettingsTile.navigation`；“添加网盘来源”直接进入 `/settings/cloud-sources/add`，避免遥控器操作 PopupMenu；配对和配置迁移也使用 `KSettingsTile.navigation`。`CloudSourceTypePickerPage` 的四个入口全部换成 `KSettingsTile.navigation`。

- [ ] **Step 7: 为配对页按钮使用同一焦点表面**

配对页的取消、手动配置、拒绝、确认、重试、返回来源列表按钮分别包裹 `TvSettingsFocusSurface`；每个表面只拥有一个 `onPressed`，按钮本体位于 `ExcludeFocus` 内。测试用左右键移动并断言焦点边框和中心键回调准确。

- [ ] **Step 8: 运行焦点、TMDB、网盘与配对页面测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\settings_presentation_components_test.dart test\tmdb_settings_language_test.dart test\cloud_sources_ui_test.dart test\tv_pairing_page_test.dart`

Expected: PASS；TV 可明显看到当前操作，Windows/普通 Android 不出现 TV 辅助提示，按键只触发一次。

- [ ] **Step 9: 提交 TV 焦点表现**

```powershell
git add lib/features/settings/presentation/tv_settings_focus_surface.dart lib/features/settings/presentation/settings_presentation.dart lib/features/settings/presentation/k_settings_tile.dart lib/pages/settings/tmdb_settings.dart lib/pages/settings/cloud_sources_settings.dart lib/features/tv_pairing/presentation/tv_pairing_page.dart test/settings_presentation_components_test.dart test/tmdb_settings_language_test.dart test/cloud_sources_ui_test.dart test/tv_pairing_page_test.dart
git commit -m "feat(tv): 增强设置项焦点反馈"
```

### Task 9: 版本迭代和用户可读发布资料

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/app_version.dart`
- Modify: `lib/utils/version_history.dart`
- Modify: `RELEASE_NOTES.md`
- Modify: `README.md`
- Modify: `UPDATE_DIALOG_COPY.md`
- Modify: `test/release_config_contract_test.dart`
- Modify: `test/version_consistency_test.dart`
- Modify: `test/identity_v2_zero_residue_test.dart`
- Modify: `test/android_tv_acceptance_contract_test.dart`
- Modify: `test/android_tv_release_contract_test.dart`
- Modify: other existing tests found by `rg -n "2\.1\.141|20141" test lib README.md RELEASE_NOTES.md UPDATE_DIALOG_COPY.md pubspec.yaml`

- [ ] **Step 1: 在任何版本文件修改前查询真实 Windows 安装状态**

```powershell
chcp 65001 > $null
$inno = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue |
  Where-Object { $_.DisplayName -eq '看影音' } |
  Select-Object DisplayName,DisplayVersion,InstallLocation,UninstallString
$exe = if ($inno.InstallLocation) { Join-Path $inno.InstallLocation 'kanyingyin.exe' } else { $null }
$exeVersion = if ($exe -and (Test-Path -LiteralPath $exe)) { (Get-Item -LiteralPath $exe).VersionInfo.ProductVersion } else { $null }
$msix = Get-AppxPackage -Name com.kanyingyin.player -ErrorAction SilentlyContinue |
  Select-Object Name,Version,PackageFullName,InstallLocation
[PSCustomObject]@{ Inno=$inno; ExePath=$exe; ExeProductVersion=$exeVersion; LegacyMsix=$msix } | Format-List
```

Expected: 明确记录 Inno 是否安装、实际安装路径、`kanyingyin.exe` 产品版本和旧 MSIX 是否仍存在。若任何实际版本高于 `2.1.141`，先把本任务中的目标版本改成严格更高的下一个补丁版本；不得降级或覆盖用户现有更高版本。

- [ ] **Step 2: 先更新版本契约测试为 2.1.142**

将版本测试期望统一改为：

```dart
const expectedVersion = '2.1.142';
expect(pubspec, contains('version: 2.1.142+20142'));
expect(pubspec, contains('msix_version: 2.1.142.0'));
```

Run: `D:\flutter\bin\flutter.bat test --no-pub test\release_config_contract_test.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\android_tv_acceptance_contract_test.dart test\android_tv_release_contract_test.dart`

Expected: FAIL，生产版本文件仍为 2.1.141。

- [ ] **Step 3: 同步生产版本和普通用户文案**

更新为：

```yaml
version: 2.1.142+20142
msix_version: 2.1.142.0
```

`AppVersion.current` 改为 `2.1.142`。`version_history.dart` 和 `RELEASE_NOTES.md` 的首条说明必须包括：

- TV 设置操作现在有清晰边框、浅色背景、勾选和确认提示。
- 手机扫码后电视会显示已连接、等待确认、写入和成功/失败状态。
- 手机可配置 OpenList、夸克、百度和迅雷已有凭据，新增非 OpenList 来源后仍需在电视选择媒体目录。
- 新增密码加密的 `.kyyconfig` 导入导出，只包含 TMDB Key 和个人网盘来源/凭据。
- 配置按来源 ID 合并且失败会恢复原配置；不迁移或删除视频、字幕、索引、缓存和播放历史。
- TV APK 仍为测试版；若没有 ADB/海信实机证据，明确写“构建与包验证通过，实机验收未完成”。

同步 README 当前版本、Android 版本和迁移入口说明，更新 `UPDATE_DIALOG_COPY.md`，保留 `msix_config` 仅作历史兼容，不生成 MSIX。

- [ ] **Step 4: 运行版本契约和发布文案测试**

Run: `D:\flutter\bin\flutter.bat test --no-pub test\release_config_contract_test.dart test\version_consistency_test.dart test\identity_v2_zero_residue_test.dart test\android_tv_acceptance_contract_test.dart test\android_tv_release_contract_test.dart test\version_history_current_test.dart`

Expected: PASS，版本号、构建号、历史和更新文案一致。

- [ ] **Step 5: 提交版本资料**

```powershell
git add pubspec.yaml lib/core/app_version.dart lib/utils/version_history.dart RELEASE_NOTES.md README.md UPDATE_DIALOG_COPY.md test/release_config_contract_test.dart test/version_consistency_test.dart test/identity_v2_zero_residue_test.dart test/android_tv_acceptance_contract_test.dart test/android_tv_release_contract_test.dart test/version_history_current_test.dart
git commit -m "chore: 发布 2.1.142 测试版"
```

### Task 10: 全量验证、Windows EXE 与 TV APK 交付

**Files:**
- Modify: `docs/android-tv-test-report.md`
- Generate: `build/windows/x64/runner/Release/kanyingyin.exe`
- Generate: `C:/Users/asus/Desktop/看影音-2.1.142-测试版-安装程序.exe`
- Generate: `build/app/outputs/flutter-apk/app-tvTest-release.apk`
- Generate: `C:/Users/asus/Desktop/看影音-2.1.142-TV测试版.apk`

- [ ] **Step 1: 检查工作区和本轮关键 diff**

```powershell
git status --short
git diff e3e1ed5..HEAD -- pubspec.yaml lib/features/configuration_transfer lib/features/tv_pairing lib/features/settings/presentation lib/pages/settings test RELEASE_NOTES.md lib/utils/version_history.dart
```

Expected: 仅包含本计划相关提交；不得覆盖用户并行修改，不得提交临时密码、配置文件、私有签名材料或 `tool/android/private-output` 日志。

- [ ] **Step 2: 运行格式、全量测试和静态分析**

```powershell
D:\flutter\bin\dart.bat format --output=none --set-exit-if-changed lib test
D:\flutter\bin\flutter.bat test --no-pub
D:\flutter\bin\flutter.bat analyze --no-pub
```

Expected: format exit 0；全部 Flutter 测试 PASS；analyze 输出 `No issues found!`。若失败，修复后重新运行完整三条命令，不把既有失败当作可交付结果。

- [ ] **Step 3: 生成并验证 Windows Release 和 Inno Setup 安装器**

```powershell
chcp 65001 > $null
powershell -ExecutionPolicy Bypass -File tool\windows\build_exe_release.ps1
Get-Item -LiteralPath 'build\windows\x64\runner\Release\kanyingyin.exe' |
  Select-Object FullName,Length,LastWriteTime,@{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}}
Get-Item -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.142-测试版-安装程序.exe" |
  Select-Object FullName,Length,LastWriteTime,@{Name='ProductVersion';Expression={$_.VersionInfo.ProductVersion}}
Get-FileHash -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.142-测试版-安装程序.exe" -Algorithm SHA256
Get-AuthenticodeSignature -LiteralPath "$env:USERPROFILE\Desktop\看影音-2.1.142-测试版-安装程序.exe"
```

Expected: Windows Release 和安装器产品版本都以 `2.1.142` 开头，桌面安装器名称准确且非空；记录 SHA-256 和实际签名状态。此步骤不自动安装、卸载或启动应用。

- [ ] **Step 4: 构建并独立验证 tvTest Release APK**

```powershell
chcp 65001 > $null
powershell -ExecutionPolicy Bypass -File tool\android\build_tv_test.ps1
$source = 'build\app\outputs\flutter-apk\app-tvTest-release.apk'
$desktop = "$env:USERPROFILE\Desktop\看影音-2.1.142-TV测试版.apk"
Copy-Item -LiteralPath $source -Destination $desktop -Force
Get-FileHash -LiteralPath $source,$desktop -Algorithm SHA256
```

Expected: 脚本确认包名 `com.kanyingyin.player.tvtest`、`versionName=2.1.142`、`versionCode=20142`、Leanback launcher、触摸屏非必需、APK v2 签名和 Full `libmpv`；源 APK 与桌面副本 SHA-256 完全相同。

- [ ] **Step 5: 尝试连接海信电视并限定实机结论**

```powershell
$adb = Join-Path $env:LOCALAPPDATA 'Android\Sdk\platform-tools\adb.exe'
& $adb devices -l
```

若存在已授权设备，安装桌面 TV APK并实测：本地媒体库向左进入侧栏；TMDB 测试连接焦点；扫码后 TV 连接状态；四类网盘添加/删除；TV 拒绝和确认；手机成功页；加密文件正确密码导入、错误密码不写入。若无设备或未授权，只在报告中写“自动化、构建与包验证通过，海信实机验收未完成”，不得声称实机通过。

- [ ] **Step 6: 更新 TV 测试报告并核对安装状态**

在 `docs/android-tv-test-report.md` 记录 2.1.142、测试总数、analyze、Windows EXE 路径/版本/SHA-256、TV APK 路径/版本/包名/SHA-256、ADB 输出和实机结论。再次执行 Task 9 Step 1 的注册表、EXE 和旧 MSIX查询；未执行安装时应明确写“已安装版本未由本次打包改变”。

- [ ] **Step 7: 提交验证报告和必要修复**

```powershell
git status --short
git diff --check
git add docs/android-tv-test-report.md
git commit -m "docs: 记录 2.1.142 交付验证"
git status --short
```

Expected: 报告提交成功，最终工作区干净；桌面同时存在 Inno EXE 和 TV APK。若验证过程产生代码修复，把修复文件和对应测试加入此提交前重新执行 Step 2 至 Step 4。

## 最终人工验收清单

- [ ] 海信电视本地媒体库内按左键可进入侧栏，搜索框按返回键先退出输入操作。
- [ ] “测试 TMDB 连接”等 TV 操作聚焦时能看到 3 px 边框、浅色背景、勾选和“当前选中 · 按确认执行”。
- [ ] 手机扫码后 TV 不再一直显示二维码，而是显示“手机已连接”。
- [ ] 手机添加 OpenList、夸克、百度、迅雷时立即出现可编辑卡片，删除和重新添加都正常。
- [ ] 手机提交后显示等待 TV 确认；TV 拒绝可修改重发，TV 确认后两端显示成功。
- [ ] 手机新建夸克、百度、迅雷来源后，TV 明确引导进入原生页面选择媒体目录。
- [ ] Windows、普通 Android 和 Android TV 均可导出/导入 `.kyyconfig`；错误密码和篡改文件零写入。
- [ ] 导入同 ID 来源会更新，不重复；未包含来源保留；空 TMDB Key 不清除目标设备 Key。
- [ ] 任何导入失败后原 TMDB、来源和凭据保持不变，不影响本地扫描与播放。
- [ ] 桌面安装器为 `看影音-2.1.142-测试版-安装程序.exe`，桌面 TV 包为 `看影音-2.1.142-TV测试版.apk`。

## 计划自检

- 配置模型、扫描状态清理、凭据脱敏和字段校验由 Task 1 覆盖。
- PBKDF2-HMAC-SHA256、AES-256-GCM、随机 Salt/Nonce、512 KiB 限制和版本错误由 Task 2 覆盖。
- 来源 ID 合并、空 TMDB 保留、写入失败回滚和刷新计数由 Task 3 覆盖。
- `.kyyconfig` 文件选择、密码确认、摘要确认、Android 分享回退和导入刷新由 Task 4 覆盖。
- 扫码协议复用公共模型、手机连接状态、电视确认、拒绝、超时和写入失败由 Task 5 至 Task 7 覆盖。
- 四类网盘字段、固定地址、非 OpenList 待选目录、稳定来源 ID、卡片新增/删除/聚焦和手机成功页由 Task 6 覆盖。
- TV 3 px 焦点表面、设置项/配对按钮覆盖、内层焦点隔离和普通平台回归由 Task 8 覆盖。
- 版本查询、发布说明、全量测试、静态分析、Windows Inno EXE、TV APK 和海信实机证据由 Task 9 至 Task 10 覆盖。
- 已扫描计划正文：不含 `TBD`、`TODO`、`implement later`、空代码块或 `HEAD~` 相对提交假设；所有后续引用的类型名和方法名均在更早任务中定义或指向现有代码。
