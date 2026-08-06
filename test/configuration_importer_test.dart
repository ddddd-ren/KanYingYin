import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

void main() {
  late MemoryCloudSourceStorage sourceStorage;
  late MemoryCloudCredentialStore credentialStore;
  late CloudSourceRepository repository;
  late TmdbCredentialManager tmdbManager;
  late ConfigurationImporter importer;

  setUp(() async {
    sourceStorage = MemoryCloudSourceStorage();
    credentialStore = MemoryCloudCredentialStore();
    repository = CloudSourceRepository(
      storage: sourceStorage,
      credentialStore: credentialStore,
    );
    tmdbManager = TmdbCredentialManager(
      store: MemoryTmdbCredentialStore('old-key'),
      legacyReader: () => '',
      legacyDelete: () async {},
      warningLogger: (_) {},
    );
    await tmdbManager.initialize();
    importer = ConfigurationImporter(
      sourceRepository: repository,
      tmdbCredentialManager: tmdbManager,
    );
  });

  test('同 ID 更新、新 ID 新增、未出现来源保留且空 TMDB 不覆盖', () async {
    await repository.save(_source('existing', '旧名称'));
    await repository.save(_source('preserved', '保留来源'));
    await credentialStore.write(
      'existing',
      const CloudCredential(password: 'old-password'),
    );

    final configuration = PortableAppConfiguration.create(
      exportedAt: DateTime.utc(2026, 8, 7),
      appVersion: '2.1.142',
      tmdbApiKey: '',
      cloudSources: <PortableCloudSourceConfiguration>[
        PortableCloudSourceConfiguration.fromSource(
          source: _source('existing', '新名称'),
          credential: const CloudCredential(password: 'new-password'),
        ),
        PortableCloudSourceConfiguration.fromSource(
          source: const CloudSource(
            id: 'added',
            type: CloudSourceType.quark,
            name: '新增夸克',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>[],
          ),
          credential: const CloudCredential(cookie: 'new-cookie'),
        ),
      ],
    );

    final preview = await importer.preview(configuration);
    expect(preview.added, 1);
    expect(preview.updated, 1);
    expect(preview.preserved, 1);
    expect(preview.tmdbWillUpdate, isFalse);
    expect(preview.requiresRootSelection, 1);

    final result = await importer.apply(configuration);
    expect(result.added, 1);
    expect(result.updated, 1);
    expect(result.preserved, 1);
    expect(tmdbManager.read(), 'old-key');
    expect((await repository.getById('existing'))?.name, '新名称');
    expect((await repository.getById('preserved'))?.name, '保留来源');
    expect((await credentialStore.read('existing'))?.password, 'new-password');
    expect((await credentialStore.read('added'))?.cookie, 'new-cookie');
  });

  test('来源凭据写入失败时恢复 TMDB、来源和所有涉及凭据', () async {
    await repository.save(_source('existing', '旧名称'));
    await credentialStore.write(
      'existing',
      const CloudCredential(password: 'old-password'),
    );
    final previousSources = await sourceStorage.read();
    final failingStore = _FailOnCredentialStore('added');
    final failingRepository = CloudSourceRepository(
      storage: sourceStorage,
      credentialStore: failingStore,
    );
    await failingStore.write(
      'existing',
      const CloudCredential(password: 'old-password'),
    );
    final failingImporter = ConfigurationImporter(
      sourceRepository: failingRepository,
      tmdbCredentialManager: tmdbManager,
    );

    final configuration = _configurationWithTwoSourcesAndTmdb();
    await expectLater(
      failingImporter.apply(configuration),
      throwsA(isA<ConfigurationImportException>()),
    );

    expect(tmdbManager.read(), 'old-key');
    expect(await sourceStorage.read(), previousSources);
    expect((await failingStore.read('existing'))?.password, 'old-password');
    expect(await failingStore.read('added'), isNull);
  });

  test('回滚失败返回稳定错误且不泄漏配置值', () async {
    final failingStore = _FailOnCredentialStore('added')..failRollback = true;
    final failingRepository = CloudSourceRepository(
      storage: sourceStorage,
      credentialStore: failingStore,
    );
    final failingImporter = ConfigurationImporter(
      sourceRepository: failingRepository,
      tmdbCredentialManager: tmdbManager,
    );

    await expectLater(
      failingImporter.apply(_configurationWithTwoSourcesAndTmdb()),
      throwsA(
        predicate<Object>(
          (error) =>
              error is ConfigurationRollbackException &&
              !error.toString().contains('tmdb-secret'),
        ),
      ),
    );
  });
}

CloudSource _source(String id, String name) => CloudSource(
      id: id,
      type: CloudSourceType.openList,
      name: name,
      baseUrl: 'https://drive.example.com',
      rootPaths: const <String>['/'],
    );

PortableAppConfiguration _configurationWithTwoSourcesAndTmdb() =>
    PortableAppConfiguration.create(
      exportedAt: DateTime.utc(2026, 8, 7),
      appVersion: '2.1.142',
      tmdbApiKey: 'tmdb-secret',
      cloudSources: <PortableCloudSourceConfiguration>[
        PortableCloudSourceConfiguration.fromSource(
          source: _source('existing', '更新名称'),
          credential: const CloudCredential(password: 'new-password'),
        ),
        PortableCloudSourceConfiguration.fromSource(
          source: const CloudSource(
            id: 'added',
            type: CloudSourceType.quark,
            name: '新增夸克',
            baseUrl: 'https://pan.quark.cn',
            rootPaths: <String>[],
          ),
          credential: const CloudCredential(cookie: 'new-cookie'),
        ),
      ],
    );

class _FailOnCredentialStore extends MemoryCloudCredentialStore {
  _FailOnCredentialStore(this.failedSourceId);

  final String failedSourceId;
  bool failRollback = false;
  bool _failedOnce = false;

  @override
  Future<void> write(String sourceId, CloudCredential credential) async {
    if (sourceId == failedSourceId && (!_failedOnce || failRollback)) {
      _failedOnce = true;
      throw StateError('模拟凭据写入失败');
    }
    await super.write(sourceId, credential);
  }

  @override
  Future<void> delete(String sourceId) async {
    if (sourceId == failedSourceId && failRollback && _failedOnce) {
      throw StateError('模拟凭据回滚失败');
    }
    await super.delete(sourceId);
  }
}
