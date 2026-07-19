import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/modules/cloud/cloud_file_entry.dart';
import 'package:kanyingyin/modules/cloud/cloud_media_index_item.dart';
import 'package:kanyingyin/modules/cloud/cloud_resource_tmdb_record.dart';
import 'package:kanyingyin/modules/cloud/cloud_series_match_rule.dart';
import 'package:kanyingyin/modules/local/tmdb_metadata.dart';
import 'package:kanyingyin/providers/cloud_library_controller.dart';
import 'package:kanyingyin/repositories/cloud_media_index_repository.dart';
import 'package:kanyingyin/repositories/cloud_resource_tmdb_repository.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/repositories/cloud_series_match_rule_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/cloud/cloud_drive_client.dart';
import 'package:kanyingyin/services/cloud/cloud_remote_ref.dart';

void main() {
  const source = CloudSource(
    id: 'source-1',
    type: CloudSourceType.openList,
    name: '家庭网盘',
    baseUrl: 'https://drive.example.com',
    rootPaths: ['/'],
  );

  test('批量扫描单个失败后继续按来源顺序扫描并返回成功数', () async {
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    final sources = <CloudSource>[
      source,
      const CloudSource(
        id: 'source-2',
        type: CloudSourceType.openList,
        name: '故障网盘',
        baseUrl: 'https://two.example.com',
        rootPaths: ['/'],
      ),
      const CloudSource(
        id: 'source-3',
        type: CloudSourceType.openList,
        name: '备用网盘',
        baseUrl: 'https://three.example.com',
        rootPaths: ['/'],
      ),
    ];
    for (final item in sources) {
      await repository.save(item);
    }
    final order = <String>[];
    final controller = CloudLibraryController(
      repository: repository,
      mediaIndexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      clientFactory: (source, _, __) {
        order.add(source.id);
        if (source.id == 'source-2') throw StateError('模拟扫描失败');
        return _OrderedScanClient();
      },
    );

    final successCount = await controller.scanAllSources();

    expect(successCount, 2);
    expect(order, ['source-1', 'source-2', 'source-3']);
    expect(controller.errorMessage, '部分网盘媒体扫描失败（1/3）');
  });

  test('批量扫描每次都读取最新的来源列表', () async {
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
    final order = <String>[];
    final controller = CloudLibraryController(
      repository: repository,
      mediaIndexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      clientFactory: (source, _, __) {
        order.add(source.id);
        return _OrderedScanClient();
      },
    );
    await controller.load();
    await repository.save(const CloudSource(
      id: 'source-2',
      type: CloudSourceType.openList,
      name: '新增网盘',
      baseUrl: 'https://two.example.com',
      rootPaths: ['/'],
    ));

    final successCount = await controller.scanAllSources();

    expect(successCount, 2);
    expect(order, ['source-1', 'source-2']);
  });

  test('批量扫描全部失败时仍依次尝试所有来源并返回零', () async {
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    final sources = <CloudSource>[
      source,
      const CloudSource(
        id: 'source-2',
        type: CloudSourceType.openList,
        name: '备用网盘',
        baseUrl: 'https://two.example.com',
        rootPaths: ['/'],
      ),
    ];
    for (final item in sources) {
      await repository.save(item);
    }
    final order = <String>[];
    final controller = CloudLibraryController(
      repository: repository,
      mediaIndexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      clientFactory: (source, _, __) {
        order.add(source.id);
        throw StateError('模拟扫描失败');
      },
    );

    final successCount = await controller.scanAllSources();

    expect(successCount, 0);
    expect(order, ['source-1', 'source-2']);
    expect(controller.errorMessage, '部分网盘媒体扫描失败（2/2）');
  });

  test('批量扫描来源加载失败时抛出明确异常', () async {
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: _FailingCloudSourceStorage(),
        credentialStore: MemoryCloudCredentialStore(),
      ),
    );

    await expectLater(
      controller.scanAllSources(),
      throwsA(isA<CloudSourcesLoadException>()),
    );
    expect(controller.sources, isEmpty);
    expect(controller.errorMessage, '网盘数据源加载失败');
  });

  test('批量扫描成功加载但没有来源时正常返回零', () async {
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: MemoryCloudCredentialStore(),
      ),
    );

    expect(await controller.scanAllSources(), 0);
    expect(controller.sources, isEmpty);
    expect(controller.errorMessage, isNull);
  });

  test('保存编辑来源时空密码保留已有密码并更新用户名', () async {
    final credentialStore = MemoryCloudCredentialStore();
    await credentialStore.write(
      source.id,
      const CloudCredential(
        username: 'old-user',
        password: 'existing-password',
        token: 'existing-token',
      ),
    );
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: credentialStore,
      ),
      credentialStore: credentialStore,
    );

    await controller.save(
      source,
      credential: const CloudCredential(username: 'new-user', password: ''),
    );

    final saved = await credentialStore.read(source.id);
    expect(saved?.username, 'new-user');
    expect(saved?.password, 'existing-password');
    expect(saved?.token, isNull);
    expect(controller.saving, isFalse);
  });

  test('保存编辑来源时空用户名保留已有用户名并更新密码', () async {
    final credentialStore = MemoryCloudCredentialStore();
    await credentialStore.write(
      source.id,
      const CloudCredential(
        username: 'existing-user',
        password: 'old-password',
        token: 'existing-token',
        cookie: 'existing-cookie',
      ),
    );
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: credentialStore,
      ),
      credentialStore: credentialStore,
    );

    await controller.save(
      source,
      credential: const CloudCredential(username: '', password: 'new-password'),
    );

    final saved = await credentialStore.read(source.id);
    expect(saved?.username, 'existing-user');
    expect(saved?.password, 'new-password');
    expect(saved?.token, isNull);
    expect(saved?.cookie, 'existing-cookie');
  });

  test('保存编辑来源时非空用户名和密码同时覆盖旧值', () async {
    final credentialStore = MemoryCloudCredentialStore();
    await credentialStore.write(
      source.id,
      const CloudCredential(
        username: 'old-user',
        password: 'old-password',
        token: 'existing-token',
        cookie: 'existing-cookie',
      ),
    );
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: credentialStore,
      ),
      credentialStore: credentialStore,
    );

    await controller.save(
      source,
      credential: const CloudCredential(
        username: 'new-user',
        password: 'new-password',
      ),
    );

    final saved = await credentialStore.read(source.id);
    expect(saved?.username, 'new-user');
    expect(saved?.password, 'new-password');
    expect(saved?.token, isNull);
    expect(saved?.cookie, 'existing-cookie');
  });

  test('用户名密码未变化时保留现有令牌', () async {
    final credentialStore = MemoryCloudCredentialStore();
    await credentialStore.write(
      source.id,
      const CloudCredential(
        username: 'same-user',
        password: 'same-password',
        token: 'existing-token',
        cookie: 'existing-cookie',
      ),
    );
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: credentialStore,
      ),
      credentialStore: credentialStore,
    );

    await controller.save(
      source,
      credential: const CloudCredential(
        username: 'same-user',
        password: 'same-password',
      ),
    );

    final saved = await credentialStore.read(source.id);
    expect(saved?.token, 'existing-token');
    expect(saved?.cookie, 'existing-cookie');
  });

  test('夸克来源可保存纯 Cookie 凭据', () async {
    final credentialStore = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentialStore,
    );
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: credentialStore,
    );
    const quarkSource = CloudSource(
      id: 'quark-source',
      type: CloudSourceType.quark,
      name: '夸克网盘',
      baseUrl: '',
      rootPaths: <String>['/影视'],
    );

    await controller.save(
      quarkSource,
      credential: const CloudCredential(cookie: 'cookie-fixture-new'),
    );

    expect(
      (await credentialStore.read(quarkSource.id))?.cookie,
      'cookie-fixture-new',
    );
    expect((await repository.getById(quarkSource.id))?.baseUrl,
        'https://pan.quark.cn');
  });

  test('夸克编辑留空保留 Cookie，输入新值则替换并清除会话', () async {
    final credentialStore = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentialStore,
    );
    const quarkSource = CloudSource(
      id: 'quark-source',
      type: CloudSourceType.quark,
      name: '夸克网盘',
      baseUrl: 'https://pan.quark.cn',
      rootPaths: <String>['/影视'],
    );
    await repository.save(quarkSource);
    await credentialStore.write(
      quarkSource.id,
      const CloudCredential(
        cookie: 'cookie-fixture-old',
        token: 'session-fixture-old',
      ),
    );
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: credentialStore,
    );

    await controller.save(
      quarkSource,
      credential: const CloudCredential(cookie: ''),
    );
    expect((await credentialStore.read(quarkSource.id))?.cookie,
        'cookie-fixture-old');

    await controller.save(
      quarkSource,
      credential: const CloudCredential(cookie: 'cookie-fixture-replaced'),
    );
    final replaced = await credentialStore.read(quarkSource.id);
    expect(replaced?.cookie, 'cookie-fixture-replaced');
    expect(replaced?.token, isNull);
  });

  test('测试连接只使用临时凭据存储', () async {
    final persistentStore = MemoryCloudCredentialStore();
    CloudCredentialStore? receivedStore;
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: persistentStore,
      ),
      credentialStore: persistentStore,
      clientFactory: (source, store, allowSelfSigned) {
        receivedStore = store;
        return _PersistingFakeClient(store);
      },
    );

    await controller.testConnection(
      source: source,
      credential: const CloudCredential(
        username: 'temporary-user',
        password: 'temporary-password',
      ),
      allowSelfSignedCertificate: false,
    );

    expect(receivedStore, isNot(same(persistentStore)));
    expect(await persistentStore.read(source.id), isNull);
  });

  test('编辑来源测试连接时空表单复用旧凭据且不持久化临时令牌', () async {
    final sourceStorage = MemoryCloudSourceStorage();
    final persistentStore = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: sourceStorage,
      credentialStore: persistentStore,
    );
    await repository.save(source);
    const existingCredential = CloudCredential(
      username: 'existing-user',
      password: 'existing-password',
      token: 'existing-token',
    );
    await persistentStore.write(source.id, existingCredential);
    _PersistingFakeClient? receivedClient;
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: persistentStore,
      clientFactory: (_, store, __) =>
          receivedClient = _PersistingFakeClient(store),
    );

    await controller.testConnection(
      source: source,
      credential: const CloudCredential(username: '', password: ''),
      allowSelfSignedCertificate: false,
    );

    expect(receivedClient?.receivedCredential?.username, 'existing-user');
    expect(receivedClient?.receivedCredential?.password, 'existing-password');
    expect(receivedClient?.receivedCredential?.token, 'existing-token');
    expect((await persistentStore.read(source.id))?.toJson(),
        existingCredential.toJson());
  });

  test('测试新地址时保留旧账号密码但不复用令牌且不持久化', () async {
    final sourceStorage = MemoryCloudSourceStorage();
    final persistentStore = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: sourceStorage,
      credentialStore: persistentStore,
    );
    await repository.save(source);
    const existingCredential = CloudCredential(
      username: 'existing-user',
      password: 'existing-password',
      token: 'existing-token',
    );
    await persistentStore.write(source.id, existingCredential);
    _PersistingFakeClient? receivedClient;
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: persistentStore,
      clientFactory: (_, store, __) =>
          receivedClient = _PersistingFakeClient(store),
    );
    const changedAddressSource = CloudSource(
      id: 'source-1',
      type: CloudSourceType.openList,
      name: '家庭网盘',
      baseUrl: 'https://new-drive.example.com',
      rootPaths: ['/'],
    );

    await controller.testConnection(
      source: changedAddressSource,
      credential: const CloudCredential(username: '', password: ''),
      allowSelfSignedCertificate: false,
    );

    expect(receivedClient?.receivedCredential?.username, 'existing-user');
    expect(receivedClient?.receivedCredential?.password, 'existing-password');
    expect(receivedClient?.receivedCredential?.token, isNull);
    expect((await persistentStore.read(source.id))?.toJson(),
        existingCredential.toJson());
  });

  test('编辑来源测试连接时非空表单覆盖旧值并使旧令牌失效', () async {
    final sourceStorage = MemoryCloudSourceStorage();
    final persistentStore = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: sourceStorage,
      credentialStore: persistentStore,
    );
    await repository.save(source);
    const existingCredential = CloudCredential(
      username: 'existing-user',
      password: 'existing-password',
      token: 'existing-token',
    );
    await persistentStore.write(source.id, existingCredential);
    _PersistingFakeClient? receivedClient;
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: persistentStore,
      clientFactory: (_, store, __) =>
          receivedClient = _PersistingFakeClient(store),
    );

    await controller.testConnection(
      source: source,
      credential: const CloudCredential(
        username: 'new-user',
        password: '',
      ),
      allowSelfSignedCertificate: false,
    );

    expect(receivedClient?.receivedCredential?.username, 'new-user');
    expect(receivedClient?.receivedCredential?.password, 'existing-password');
    expect(receivedClient?.receivedCredential?.token, isNull);
    expect((await persistentStore.read(source.id))?.toJson(),
        existingCredential.toJson());
  });

  test('测试连接构造客户端失败时恢复状态并显示地址错误', () async {
    final controller = CloudLibraryController(
      repository: CloudSourceRepository(
        storage: MemoryCloudSourceStorage(),
        credentialStore: MemoryCloudCredentialStore(),
      ),
      clientFactory: (_, __, ___) => throw const CloudDriveException(
        CloudDriveErrorType.invalidAddress,
      ),
    );

    await expectLater(
      controller.testConnection(
        source: source,
        credential: const CloudCredential(username: 'user', password: 'pass'),
        allowSelfSignedCertificate: false,
      ),
      throwsA(isA<CloudDriveException>()),
    );

    expect(controller.testing, isFalse);
    expect(controller.errorMessage, '服务器地址格式无效');
  });

  test('控制器释放后异步保存完成不会通知已释放监听器', () async {
    final repository = _BlockingRepository();
    final controller = CloudLibraryController(repository: repository);
    final operation = controller.save(source);
    await repository.saveStarted.future;

    controller.dispose();
    repository.releaseSave.complete();

    await expectLater(operation, completes);
  });

  test('保存期间设置 saving 并在完成后恢复', () async {
    final repository = _BlockingRepository();
    final controller = CloudLibraryController(repository: repository);

    final operation = controller.save(source);
    await repository.saveStarted.future;
    expect(controller.saving, isTrue);
    repository.releaseSave.complete();
    await operation;

    expect(controller.saving, isFalse);
    expect(controller.sources, contains(source));
  });

  test('删除期间设置 deleting，成功后刷新来源', () async {
    final repository = _BlockingRepository();
    await repository.seed(source);
    final controller = CloudLibraryController(
      repository: repository,
      mediaIndexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      posterCacheCleaner: (_) async {},
      subtitleCacheCleaner: (_) async {},
    );
    await controller.load();

    final operation = controller.delete(source.id);
    await repository.deleteStarted.future;
    expect(controller.deleting, isTrue);
    repository.releaseDelete.complete();
    await operation;

    expect(controller.deleting, isFalse);
    expect(controller.sources, isEmpty);
    expect(controller.errorMessage, isNull);
  });

  test('删除失败提供明确错误并恢复 deleting 状态', () async {
    final repository = _FailingDeleteRepository();
    await repository.save(source);
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    await indexRepository.replaceSource(
      source.id,
      [_indexItem(source.id)],
      const {'/': 'fingerprint'},
      const {'/': <CloudFileEntry>[]},
      const ['/'],
    );
    final tmdbRepository = CloudResourceTmdbRepository(
      storage: MemoryCloudResourceTmdbStorage(),
    );
    await tmdbRepository.upsert(
      CloudResourceTmdbRecord.unchecked(
        sourceId: source.id,
        remoteId: 'episode',
        remotePath: '/Show/Show.S01E01.mkv',
        displayName: 'Show.S01E01.mkv',
        resourceKind: CloudResourceKind.standaloneVideo,
        checkedAt: DateTime.utc(2026, 7, 20),
      ),
    );
    final ruleRepository = CloudSeriesMatchRuleRepository(
      storage: MemoryCloudSeriesMatchRuleStorage(),
    );
    await ruleRepository.upsert(_seriesRule(source.id));
    final controller = CloudLibraryController(
      repository: repository,
      mediaIndexRepository: indexRepository,
      resourceTmdbRepository: tmdbRepository,
      seriesMatchRuleRepository: ruleRepository,
      posterCacheCleaner: (_) async {},
      subtitleCacheCleaner: (_) async {},
    );
    await controller.load();

    await expectLater(controller.delete(source.id), throwsStateError);

    expect(controller.deleting, isFalse);
    expect(
      controller.errorMessage,
      '删除网盘数据源失败，原有索引、刮削信息和系列规则已恢复',
    );
    expect(controller.sources, contains(source));
    expect(await indexRepository.getBySource(source.id), hasLength(1));
    expect(await tmdbRepository.getBySource(source.id), hasLength(1));
    expect(await ruleRepository.getBySource(source.id), hasLength(1));
  });

  test('删除来源先清理目标索引和两类缓存且保留其他来源', () async {
    final credentialStore = MemoryCloudCredentialStore();
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: credentialStore,
    );
    const other = CloudSource(
      id: 'source-2',
      type: CloudSourceType.openList,
      name: '备用网盘',
      baseUrl: 'https://two.example.com',
      rootPaths: ['/'],
    );
    await repository.save(source);
    await repository.save(other);
    final indexRepository = CloudMediaIndexRepository(
      storage: MemoryCloudMediaIndexStorage(),
    );
    for (final itemSource in [source.id, other.id]) {
      await indexRepository.replaceSource(
        itemSource,
        [_indexItem(itemSource)],
        const {'/': 'fingerprint'},
        const {'/': <CloudFileEntry>[]},
        const ['/'],
      );
    }
    final ruleRepository = CloudSeriesMatchRuleRepository(
      storage: MemoryCloudSeriesMatchRuleStorage(),
    );
    await ruleRepository.upsert(_seriesRule(source.id));
    await ruleRepository.upsert(_seriesRule(other.id));
    final cleanups = <String>[];
    final controller = CloudLibraryController(
      repository: repository,
      credentialStore: credentialStore,
      mediaIndexRepository: indexRepository,
      seriesMatchRuleRepository: ruleRepository,
      posterCacheCleaner: (sourceId) async {
        expect(await indexRepository.getBySource(sourceId), isEmpty);
        cleanups.add('poster:$sourceId');
      },
      subtitleCacheCleaner: (sourceId) async {
        expect(await indexRepository.getBySource(sourceId), isEmpty);
        cleanups.add('subtitle:$sourceId');
      },
    );

    await controller.delete(source.id);

    expect(cleanups, ['poster:${source.id}', 'subtitle:${source.id}']);
    expect(await repository.getById(source.id), isNull);
    expect(await indexRepository.getBySource(source.id), isEmpty);
    expect(await ruleRepository.getBySource(source.id), isEmpty);
    expect(await repository.getById(other.id), other);
    expect(await indexRepository.getBySource(other.id), hasLength(1));
    expect(await ruleRepository.getBySource(other.id), hasLength(1));
    expect(controller.errorMessage, isNull);
  });

  test('缓存清理部分失败仍删除来源并提供明确反馈', () async {
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
    var subtitleCleaned = false;
    final controller = CloudLibraryController(
      repository: repository,
      mediaIndexRepository: CloudMediaIndexRepository(
        storage: MemoryCloudMediaIndexStorage(),
      ),
      posterCacheCleaner: (_) async => throw StateError('模拟海报清理失败'),
      subtitleCacheCleaner: (_) async => subtitleCleaned = true,
    );

    await controller.delete(source.id);

    expect(await repository.getById(source.id), isNull);
    expect(subtitleCleaned, isTrue);
    expect(controller.errorMessage, '网盘数据源已删除，但部分本地缓存清理失败');
  });

  test('索引清理失败时不删除来源并提供明确反馈', () async {
    final repository = CloudSourceRepository(
      storage: MemoryCloudSourceStorage(),
      credentialStore: MemoryCloudCredentialStore(),
    );
    await repository.save(source);
    final storage = _FailingCloudMediaIndexStorage();
    final indexRepository = CloudMediaIndexRepository(storage: storage);
    await indexRepository.replaceSource(
      source.id,
      [_indexItem(source.id)],
      const {},
      const {},
      const ['/'],
    );
    storage.failNextWrite = true;
    final controller = CloudLibraryController(
      repository: repository,
      mediaIndexRepository: indexRepository,
      posterCacheCleaner: (_) async {},
      subtitleCacheCleaner: (_) async {},
    );

    await expectLater(controller.delete(source.id), throwsStateError);

    expect(await repository.getById(source.id), source);
    expect(await indexRepository.getBySource(source.id), hasLength(1));
    expect(controller.errorMessage, '删除网盘数据源失败，原有数据未被删除');
  });
}

CloudMediaIndexItem _indexItem(String sourceId) => CloudMediaIndexItem(
      sourceId: sourceId,
      remoteId: '$sourceId-episode',
      remotePath: '/Show/E01.mkv',
      name: 'E01.mkv',
      size: 1024,
      modifiedAt: DateTime(2026),
      seriesName: 'Show',
      seasonNumber: 1,
      episodeNumber: 1,
      mediaType: CloudMediaType.episode,
    );

CloudSeriesMatchRule _seriesRule(String sourceId) => CloudSeriesMatchRule(
      sourceId: sourceId,
      parentPath: '/Show',
      normalizedSeriesName: 'show',
      metadata: TmdbMetadata(
        id: 42,
        mediaType: TmdbMediaType.tv,
        title: '剧集',
        language: 'zh-CN',
        matchedAt: DateTime.utc(2026, 7, 20),
        matchConfidence: 1,
      ),
      updatedAt: DateTime.utc(2026, 7, 20),
    );

class _FailingCloudMediaIndexStorage extends MemoryCloudMediaIndexStorage {
  bool failNextWrite = false;

  @override
  Future<void> write(Map<String, Object?> value) async {
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟索引写入失败');
    }
    await super.write(value);
  }
}

class _FailingCloudSourceStorage implements CloudSourceStorage {
  @override
  Object get synchronizationIdentity => this;

  @override
  Future<List<Map<String, dynamic>>> read() async {
    throw StateError('模拟来源加载失败');
  }

  @override
  Future<void> write(List<Map<String, dynamic>> sources) async {}
}

class _PersistingFakeClient implements CloudDriveClient {
  _PersistingFakeClient(this.store);

  final CloudCredentialStore store;
  CloudCredential? receivedCredential;

  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {
    receivedCredential = credential;
    await store.write(
      source.id,
      CloudCredential(
        username: credential.username,
        password: credential.password,
        token: 'temporary-token',
      ),
    );
  }

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async =>
      const <CloudFileEntry>[];

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}

class _OrderedScanClient implements CloudDriveClient {
  @override
  Future<void> authenticate(
    CloudSource source,
    CloudCredential credential,
  ) async {}

  @override
  Future<void> close() async {}

  @override
  Future<CloudFileEntry> getFile(CloudRemoteRef file) =>
      throw UnimplementedError();

  @override
  Future<List<CloudFileEntry>> listDirectory(CloudRemoteRef directory) async =>
      const <CloudFileEntry>[];

  @override
  Future<CloudPlaybackResource> resolvePlayback(CloudRemoteRef file) =>
      throw UnimplementedError();
}

class _BlockingRepository extends CloudSourceRepository {
  _BlockingRepository()
      : super(
          storage: MemoryCloudSourceStorage(),
          credentialStore: MemoryCloudCredentialStore(),
        );

  final Completer<void> saveStarted = Completer<void>();
  final Completer<void> releaseSave = Completer<void>();
  final Completer<void> deleteStarted = Completer<void>();
  final Completer<void> releaseDelete = Completer<void>();

  Future<void> seed(CloudSource source) => super.save(source);

  @override
  Future<void> save(CloudSource source) async {
    saveStarted.complete();
    await releaseSave.future;
    await super.save(source);
  }

  @override
  Future<bool> delete(String sourceId) async {
    deleteStarted.complete();
    await releaseDelete.future;
    return super.delete(sourceId);
  }
}

class _FailingDeleteRepository extends CloudSourceRepository {
  _FailingDeleteRepository()
      : super(
          storage: MemoryCloudSourceStorage(),
          credentialStore: MemoryCloudCredentialStore(),
        );

  @override
  Future<bool> delete(String sourceId) async {
    throw StateError('模拟删除失败');
  }
}
