import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../tool/tv_preload/preload_validator.dart';

void main() {
  test('纯 Dart 预置校验器接受正确密码和有效迁移包', () async {
    final temporary = await Directory.systemTemp.createTemp('tv-validator-');
    addTearDown(() => temporary.delete(recursive: true));
    final configuration = File(
      '${temporary.path}${Platform.pathSeparator}config.kyyconfig',
    );
    final metadata = File(
      '${temporary.path}${Platform.pathSeparator}metadata.kyymeta',
    );
    await _writeConfigurationArchive(
      configuration,
      password: 'test-password',
      tmdbApiKey: 'test-key',
    );
    await _writeMetadataArchive(metadata);

    final result = await validatePreloadFiles(
      configuration: configuration,
      metadata: metadata,
      password: 'test-password',
    );

    expect(result.configurationBytes, await configuration.length());
    expect(result.metadataBytes, await metadata.length());
    expect(result.configurationSha256, hasLength(64));
    expect(result.metadataSha256, hasLength(64));
  });

  test('纯 Dart 预置校验器拒绝错误配置密码', () async {
    final temporary = await Directory.systemTemp.createTemp('tv-validator-');
    addTearDown(() => temporary.delete(recursive: true));
    final configuration = File(
      '${temporary.path}${Platform.pathSeparator}config.kyyconfig',
    );
    final metadata = File(
      '${temporary.path}${Platform.pathSeparator}metadata.kyymeta',
    );
    await _writeConfigurationArchive(
      configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(metadata);

    await expectLater(
      validatePreloadFiles(
        configuration: configuration,
        metadata: metadata,
        password: 'wrong-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器拒绝嵌套无效的网盘来源', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
      configuration: _validConfiguration(<Object?>[
        _portableCloudSource(
          id: 'source-1',
          type: 'quark',
          baseUrl: 'https://example.com',
        ),
      ]),
    );
    await _writeMetadataArchive(fixture.metadata);

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器拒绝重复网盘来源 ID', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
      configuration: _validConfiguration(<Object?>[
        _portableCloudSource(id: 'duplicate-source'),
        _portableCloudSource(id: 'duplicate-source'),
      ]),
    );
    await _writeMetadataArchive(fixture.metadata);

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器拒绝未在清单声明的必需文件', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(fixture.metadata, declareLocal: false);

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器拒绝包含不安全路径的 ZIP', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(fixture.metadata, includeUnsafePath: true);

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器要求清单使用精确的必需文件名', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(
      fixture.metadata,
      localManifestPath: 'LOCAL.JSON',
    );

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器要求 ZIP 使用精确的必需文件名', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(
      fixture.metadata,
      localArchivePath: 'LOCAL.JSON',
    );

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器拒绝清单文件大小不匹配', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(fixture.metadata, localLengthDelta: 1);

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器拒绝清单 SHA-256 不匹配', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(fixture.metadata, corruptLocalHash: true);

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器拒绝嵌套无效的本地刮削记录', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(
      fixture.metadata,
      localDocument: <String, Object?>{
        'localSources': <Object?>[
          <String, Object?>{
            'exportId': 'local-1',
            'name': '测试目录',
            'originalRoot': 'D:/Media',
            'records': <Object?>[
              <String, Object?>{'relativePath': 'invalid.mkv'},
            ],
          },
        ],
      },
    );

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器拒绝超过 25MB 的单张图片', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(
      fixture.metadata,
      images: <String, List<int>>{
        'images/oversized.jpg': List<int>.filled(
          25 * 1024 * 1024 + 1,
          0,
          growable: false,
        ),
      },
    );

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });

  test('纯 Dart 预置校验器拒绝清单中的非图片额外载荷', () async {
    final fixture = await _createFixture();
    addTearDown(() => fixture.directory.delete(recursive: true));
    await _writeConfigurationArchive(
      fixture.configuration,
      password: 'test-password',
    );
    await _writeMetadataArchive(
      fixture.metadata,
      extraFiles: <String, List<int>>{
        'payload.bin': <int>[1, 2, 3],
      },
    );

    await expectLater(
      validatePreloadFiles(
        configuration: fixture.configuration,
        metadata: fixture.metadata,
        password: 'test-password',
      ),
      throwsA(isA<PreloadValidationException>()),
    );
  });
}

Future<void> _writeConfigurationArchive(
  File output, {
  required String password,
  String tmdbApiKey = '',
  Map<String, Object?>? configuration,
}) async {
  final salt = List<int>.generate(16, (index) => index + 1);
  final nonce = List<int>.generate(12, (index) => index + 17);
  final key = await Pbkdf2.hmacSha256(
    iterations: 600000,
    bits: 256,
  ).deriveKeyFromPassword(password: password, nonce: salt);
  final cleartext = utf8.encode(jsonEncode(
    configuration ??
        <String, Object?>{
          'formatVersion': 1,
          'exportedAt': '2026-08-07T00:00:00.000Z',
          'appVersion': '2.1.146',
          'tmdbApiKey': tmdbApiKey,
          'cloudSources': <Object?>[],
        },
  ));
  final encrypted = await AesGcm.with256bits().encrypt(
    cleartext,
    secretKey: key,
    nonce: nonce,
  );
  await output.writeAsString(jsonEncode(<String, Object?>{
    'format': 'kyy-config',
    'envelopeVersion': 1,
    'kdf': <String, Object?>{
      'name': 'pbkdf2-hmac-sha256',
      'iterations': 600000,
      'salt': base64Encode(salt),
    },
    'cipher': <String, Object?>{
      'name': 'aes-256-gcm',
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(encrypted.cipherText),
      'mac': base64Encode(encrypted.mac.bytes),
    },
  }));
}

Future<void> _writeMetadataArchive(
  File output, {
  bool declareLocal = true,
  bool includeUnsafePath = false,
  String localManifestPath = 'local.json',
  String localArchivePath = 'local.json',
  int localLengthDelta = 0,
  bool corruptLocalHash = false,
  Map<String, Object?>? localDocument,
  Map<String, Object?>? cloudDocument,
  Map<String, List<int>> images = const <String, List<int>>{},
  Map<String, List<int>> extraFiles = const <String, List<int>>{},
}) async {
  final local = utf8.encode(jsonEncode(
    localDocument ?? <String, Object?>{'localSources': <Object?>[]},
  ));
  final cloud = utf8.encode(jsonEncode(
    cloudDocument ?? <String, Object?>{'cloudSources': <Object?>[]},
  ));
  final manifest = utf8.encode(jsonEncode(<String, Object?>{
    'format': 'kanyingyin-scraped-metadata',
    'formatVersion': 1,
    'appVersion': '2.1.146',
    'exportedAt': '2026-08-07T00:00:00.000Z',
    'localRecordCount': 0,
    'cloudRecordCount': 0,
    'imageCount': 0,
    'files': <Object?>[
      if (declareLocal)
        <String, Object?>{
          'path': localManifestPath,
          'length': local.length + localLengthDelta,
          'sha256': corruptLocalHash
              ? List<String>.filled(64, '0').join()
              : sha256.convert(local).toString(),
        },
      <String, Object?>{
        'path': 'cloud.json',
        'length': cloud.length,
        'sha256': sha256.convert(cloud).toString(),
      },
      for (final image in images.entries)
        <String, Object?>{
          'path': image.key,
          'length': image.value.length,
          'sha256': sha256.convert(image.value).toString(),
        },
      for (final file in extraFiles.entries)
        <String, Object?>{
          'path': file.key,
          'length': file.value.length,
          'sha256': sha256.convert(file.value).toString(),
        },
    ],
  }));
  final archive = Archive()
    ..addFile(ArchiveFile.bytes('manifest.json', manifest))
    ..addFile(ArchiveFile.bytes(localArchivePath, local))
    ..addFile(ArchiveFile.bytes('cloud.json', cloud));
  for (final image in images.entries) {
    archive.addFile(ArchiveFile.bytes(image.key, image.value));
  }
  for (final file in extraFiles.entries) {
    archive.addFile(ArchiveFile.bytes(file.key, file.value));
  }
  if (includeUnsafePath) {
    archive.addFile(ArchiveFile.string('../outside.txt', 'unsafe'));
  }
  await output.writeAsBytes(ZipEncoder().encodeBytes(archive));
}

Future<_Fixture> _createFixture() async {
  final directory = await Directory.systemTemp.createTemp('tv-validator-');
  return _Fixture(
    directory,
    File('${directory.path}${Platform.pathSeparator}config.kyyconfig'),
    File('${directory.path}${Platform.pathSeparator}metadata.kyymeta'),
  );
}

final class _Fixture {
  const _Fixture(this.directory, this.configuration, this.metadata);

  final Directory directory;
  final File configuration;
  final File metadata;
}

Map<String, Object?> _validConfiguration(List<Object?> cloudSources) =>
    <String, Object?>{
      'formatVersion': 1,
      'exportedAt': '2026-08-07T00:00:00.000Z',
      'appVersion': '2.1.146',
      'tmdbApiKey': '',
      'cloudSources': cloudSources,
    };

Map<String, Object?> _portableCloudSource({
  required String id,
  String type = 'openList',
  String baseUrl = 'https://media.example.com',
}) =>
    <String, Object?>{
      'source': <String, Object?>{
        'id': id,
        'type': type,
        'name': '测试来源',
        'baseUrl': baseUrl,
        'rootPaths': <String>[],
        'enabled': true,
        'allowSelfSignedCertificate': false,
        'lastScannedAt': null,
        'scanStatus': 'never',
        'indexedVideoCount': 0,
        'matchedSubtitleCount': 0,
        'lastScanFailureCount': 0,
      },
    };
