import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';

void main() {
  group('CloudSourceRepository', () {
    late MemoryCloudSourceStorage storage;
    late MemoryCloudCredentialStore credentials;
    late CloudSourceRepository repository;

    setUp(() {
      storage = MemoryCloudSourceStorage();
      credentials = MemoryCloudCredentialStore();
      repository = CloudSourceRepository(
        storage: storage,
        credentialStore: credentials,
      );
    });

    test('保存并读取非敏感来源配置', () async {
      final source = CloudSource(
        id: 'source-1',
        type: CloudSourceType.openList,
        name: '家庭媒体库',
        baseUrl: 'https://drive.example.com',
        rootPaths: const ['/动漫', '/电影'],
        enabled: true,
        lastScannedAt: DateTime.utc(2026, 7, 15),
        scanStatus: CloudScanStatus.completed,
      );

      await repository.save(source);

      expect(await repository.getById('source-1'), source);
      expect(await repository.getAll(), [source]);
    });

    test('敏感凭据按来源隔离保存和删除', () async {
      await credentials.write(
          'source-1',
          const CloudCredential(
            password: 'secret-password',
            token: 'secret-token',
          ));
      await credentials.write(
          'source-2',
          const CloudCredential(
            cookie: 'secret-cookie',
          ));

      expect((await credentials.read('source-1'))?.token, 'secret-token');
      expect((await credentials.read('source-2'))?.cookie, 'secret-cookie');

      await credentials.delete('source-1');

      expect(await credentials.read('source-1'), isNull);
      expect((await credentials.read('source-2'))?.cookie, 'secret-cookie');
    });

    test('百度来源类型与远程根目录可以安全往返', () async {
      const source = CloudSource(
        id: 'baidu-source',
        type: CloudSourceType.baidu,
        name: '我的百度网盘',
        baseUrl: 'https://pan.baidu.com',
        rootPaths: <String>['/影视'],
      );

      await repository.save(source);

      final restored = await repository.getById(source.id);
      expect(restored, source);
      expect(restored?.type, CloudSourceType.baidu);
    });

    test('导出 JSON 不包含秘密字段和值', () async {
      await repository.save(const CloudSource(
        id: 'source-1',
        type: CloudSourceType.quark,
        name: '夸克网盘',
        baseUrl: 'https://pan.quark.cn',
        rootPaths: ['/视频'],
      ));
      await credentials.write(
          'source-1',
          const CloudCredential(
            username: 'user@example.com',
            password: 'secret-password',
            cookie: 'secret-cookie',
            token: 'secret-token',
          ));

      final exported = await repository.exportJson();
      final decoded = jsonDecode(exported) as List<dynamic>;

      expect(decoded, hasLength(1));
      expect(exported, isNot(contains('password')));
      expect(exported, isNot(contains('cookie')));
      expect(exported, isNot(contains('token')));
      expect(exported, isNot(contains('secret-')));
    });

    test('删除来源时先删除凭据再删除配置', () async {
      final calls = <String>[];
      final orderedStorage = _RecordingSourceStorage(calls);
      final orderedCredentials = _RecordingCredentialStore(calls);
      final orderedRepository = CloudSourceRepository(
        storage: orderedStorage,
        credentialStore: orderedCredentials,
      );
      await orderedRepository.save(const CloudSource(
        id: 'source-1',
        type: CloudSourceType.openList,
        name: '媒体库',
        baseUrl: 'https://drive.example.com',
        rootPaths: ['/'],
      ));
      calls.clear();

      expect(await orderedRepository.delete('source-1'), isTrue);

      expect(calls, ['credential:delete', 'source:write']);
      expect(await orderedRepository.getById('source-1'), isNull);
    });

    test('并发保存不会覆盖其他来源', () async {
      final delayedStorage = _DelayedSourceStorage();
      final concurrentRepository = CloudSourceRepository(
        storage: delayedStorage,
        credentialStore: credentials,
      );

      await Future.wait([
        concurrentRepository.save(_source('source-1')),
        concurrentRepository.save(_source('source-2')),
      ]);

      expect(
        (await concurrentRepository.getAll()).map((source) => source.id),
        containsAll(['source-1', 'source-2']),
      );
    });

    test('并发删除和保存不会让已删除来源复现', () async {
      final delayedStorage = _DelayedSourceStorage();
      final concurrentRepository = CloudSourceRepository(
        storage: delayedStorage,
        credentialStore: credentials,
      );
      await concurrentRepository.save(_source('source-1'));

      await Future.wait([
        concurrentRepository.delete('source-1'),
        concurrentRepository.save(_source('source-2')),
      ]);

      expect(await concurrentRepository.getById('source-1'), isNull);
      expect(await concurrentRepository.getById('source-2'), isNotNull);
    });

    test('共享同一存储的两个仓库并发保存不会丢失来源', () async {
      final sharedStorage = _DelayedSourceStorage();
      final firstRepository = CloudSourceRepository(
        storage: sharedStorage,
        credentialStore: credentials,
      );
      final secondRepository = CloudSourceRepository(
        storage: sharedStorage,
        credentialStore: credentials,
      );

      await Future.wait([
        firstRepository.save(_source('source-1')),
        secondRepository.save(_source('source-2')),
      ]);

      expect(
        (await firstRepository.getAll()).map((source) => source.id),
        containsAll(['source-1', 'source-2']),
      );
    });

    test('共享同一存储的两个仓库并发删除和保存不会复现来源', () async {
      final sharedStorage = _DelayedSourceStorage();
      final firstRepository = CloudSourceRepository(
        storage: sharedStorage,
        credentialStore: credentials,
      );
      final secondRepository = CloudSourceRepository(
        storage: sharedStorage,
        credentialStore: credentials,
      );
      await firstRepository.save(_source('source-1'));

      await Future.wait([
        firstRepository.delete('source-1'),
        secondRepository.save(_source('source-2')),
      ]);

      expect(await firstRepository.getById('source-1'), isNull);
      expect(await firstRepository.getById('source-2'), isNotNull);
    });

    test('注入不同存储的仓库不会互相阻塞', () async {
      final blockingStorage = _BlockingSourceStorage();
      final independentStorage = MemoryCloudSourceStorage();
      final blockingRepository = CloudSourceRepository(
        storage: blockingStorage,
        credentialStore: credentials,
      );
      final independentRepository = CloudSourceRepository(
        storage: independentStorage,
        credentialStore: credentials,
      );

      final blockedSave = blockingRepository.save(_source('source-1'));
      await blockingStorage.writeStarted.future;
      await independentRepository
          .save(_source('source-2'))
          .timeout(const Duration(seconds: 1));
      blockingStorage.releaseWrite.complete();
      await blockedSave;

      expect(await independentRepository.getById('source-2'), isNotNull);
    });

    test('配置删除失败时恢复已删除的凭据', () async {
      final failingStorage = _FailingSourceStorage();
      final compensatingRepository = CloudSourceRepository(
        storage: failingStorage,
        credentialStore: credentials,
      );
      await compensatingRepository.save(_source('source-1'));
      await credentials.write(
        'source-1',
        const CloudCredential(token: 'secret-token'),
      );
      failingStorage.failNextWrite = true;

      await expectLater(
        compensatingRepository.delete('source-1'),
        throwsStateError,
      );

      expect((await credentials.read('source-1'))?.token, 'secret-token');
      expect(await compensatingRepository.getById('source-1'), isNotNull);
    });

    test('畸形来源字段采用安全默认值且坏记录彼此隔离', () async {
      await storage.write([
        <String, dynamic>{
          'id': <String>['invalid']
        },
        <String, dynamic>{
          'id': 'source-1',
          'type': 42,
          'name': true,
          'baseUrl': <String, String>{'secret': 'value'},
          'rootPaths': <Object>[1, '/视频'],
          'enabled': 'yes',
          'lastScannedAt': 123,
          'scanStatus': false,
        },
      ]);

      final sources = await repository.getAll();

      expect(sources, hasLength(1));
      expect(sources.single.id, 'source-1');
      expect(sources.single.type, CloudSourceType.openList);
      expect(sources.single.name, isEmpty);
      expect(sources.single.rootPaths, ['/视频']);
      expect(sources.single.enabled, isTrue);
      expect(sources.single.lastScannedAt, isNull);
    });
  });

  group('SecureCloudCredentialStore', () {
    test('百度 OAuth 凭据 JSON 往返保留强类型字段且不从 toString 泄漏', () async {
      final storage = _FakeSecureValueStorage(null);
      final store = SecureCloudCredentialStore(valueStorage: storage);
      final expiresAt = DateTime.utc(2026, 8, 1, 12);
      final credential = CloudCredential(
        clientId: 'client-fixture',
        clientSecret: 'secret-fixture',
        accessToken: 'access-fixture',
        refreshToken: 'refresh-fixture',
        accessTokenExpiresAt: expiresAt,
      );

      await store.write('baidu-source', credential);
      final restored = await store.read('baidu-source');

      expect(restored?.clientId, 'client-fixture');
      expect(restored?.clientSecret, 'secret-fixture');
      expect(restored?.accessToken, 'access-fixture');
      expect(restored?.refreshToken, 'refresh-fixture');
      expect(restored?.accessTokenExpiresAt, expiresAt);
      expect(restored.toString(), 'CloudCredential(<redacted>)');
    });

    test('安全存储中的损坏 JSON 转换为不泄密的凭据损坏异常', () async {
      final store = SecureCloudCredentialStore(
        valueStorage: _FakeSecureValueStorage('{secret-token'),
      );

      await expectLater(
        store.read('source-1'),
        throwsA(
          isA<CloudCredentialCorruptedException>().having(
            (error) => error.toString(),
            '错误文本',
            allOf(
              isNot(contains('secret-token')),
              contains('source-1'),
            ),
          ),
        ),
      );
    });

    test('安全存储中的畸形字段不会触发类型转换异常', () async {
      final store = SecureCloudCredentialStore(
        valueStorage: _FakeSecureValueStorage(
          '{"username":7,"password":"valid-password"}',
        ),
      );

      final credential = await store.read('source-1');

      expect(credential?.username, isNull);
      expect(credential?.password, 'valid-password');
    });
  });
}

CloudSource _source(String id) => CloudSource(
      id: id,
      type: CloudSourceType.openList,
      name: id,
      baseUrl: 'https://drive.example.com',
      rootPaths: const ['/'],
    );

class _RecordingSourceStorage extends MemoryCloudSourceStorage {
  _RecordingSourceStorage(this.calls);

  final List<String> calls;

  @override
  Future<void> write(List<Map<String, dynamic>> sources) async {
    calls.add('source:write');
    await super.write(sources);
  }
}

class _RecordingCredentialStore extends MemoryCloudCredentialStore {
  _RecordingCredentialStore(this.calls);

  final List<String> calls;

  @override
  Future<void> delete(String sourceId) async {
    calls.add('credential:delete');
    await super.delete(sourceId);
  }
}

class _DelayedSourceStorage extends MemoryCloudSourceStorage {
  @override
  Future<List<Map<String, dynamic>>> read() async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return super.read();
  }

  @override
  Future<void> write(List<Map<String, dynamic>> sources) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    await super.write(sources);
  }
}

class _FailingSourceStorage extends MemoryCloudSourceStorage {
  bool failNextWrite = false;

  @override
  Future<void> write(List<Map<String, dynamic>> sources) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟配置写入失败');
    }
    await super.write(sources);
  }
}

class _BlockingSourceStorage extends MemoryCloudSourceStorage {
  final Completer<void> writeStarted = Completer<void>();
  final Completer<void> releaseWrite = Completer<void>();

  @override
  Future<void> write(List<Map<String, dynamic>> sources) async {
    writeStarted.complete();
    await releaseWrite.future;
    await super.write(sources);
  }
}

class _FakeSecureValueStorage implements SecureValueStorage {
  _FakeSecureValueStorage(this.value);

  String? value;

  @override
  Future<String?> read(String key) async => value;

  @override
  Future<void> write(String key, String value) async {
    this.value = value;
  }

  @override
  Future<void> delete(String key) async {
    value = null;
  }
}
