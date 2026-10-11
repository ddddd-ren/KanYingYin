import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_user_data_store.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_user_data.dart';
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

  test('用户数据合并保留缺失媒体，失败时恢复全部用户数据和 TMDB', () async {
    final previous = PortableUserData.fromJson({
      'states': {
        'missing': {'favorite': true}
      },
      'bookmarks': {
        'local|missing.mp4': [
          {'positionMillis': 1000}
        ]
      },
    });
    final store = _UserDataStore(previous);
    final configuration = PortableAppConfiguration.create(
      exportedAt: DateTime.utc(2026),
      appVersion: '2.1.219',
      tmdbApiKey: 'new-key',
      cloudSources: [],
      userData: PortableUserData.fromJson({
        'states': {
          'new': {'watchLater': true}
        }
      }),
    );
    final subject = ConfigurationImporter(
        sourceRepository: repository,
        tmdbCredentialManager: tmdbManager,
        userDataStore: store);
    expect((await subject.preview(configuration)).userStateCount, 1);
    store.failNextWrite = true;
    await expectLater(subject.apply(configuration),
        throwsA(isA<ConfigurationImportException>()));
    expect(store.value.toJson(), previous.toJson());
    expect(tmdbManager.read(), 'old-key');
    await subject.apply(configuration);
    expect(store.value.states.keys, containsAll(['missing', 'new']));
    expect(store.value.bookmarks.keys, contains('local|missing.mp4'));
  });

  test('来源写入失败也回滚已写入的用户数据', () async {
    final previous = PortableUserData.fromJson({
      'states': {
        'old': {'favorite': true}
      },
      'watchStates': {
        'source|old': {
          'watched': true,
          'positionMillis': 1,
          'durationMillis': 2,
          'updatedAtMillis': 1
        }
      },
      'timelineSegments': {
        'local|old': {
          'fingerprint': 'file:1:2',
          'durationMillis': 100000,
          'segments': [
            {'kind': 'intro', 'startMillis': 0, 'endMillis': 1000}
          ]
        }
      },
    });
    final store = _UserDataStore(previous);
    final sources = CloudSourceRepository(
        storage: sourceStorage,
        credentialStore: _FailOnCredentialStore('added'));
    final base = _configurationWithTwoSourcesAndTmdb();
    final config = PortableAppConfiguration.create(
        exportedAt: base.exportedAt,
        appVersion: base.appVersion,
        tmdbApiKey: base.tmdbApiKey,
        cloudSources: base.cloudSources,
        userData: PortableUserData.fromJson({
          'states': {
            'new': {'watchLater': true}
          },
          'watchStates': {
            'source|new': {
              'watched': true,
              'positionMillis': 1,
              'durationMillis': 2,
              'updatedAtMillis': 1
            }
          },
          'timelineSegments': {
            'local|new': {
              'fingerprint': 'file:1:2',
              'durationMillis': 100000,
              'segments': [
                {'kind': 'intro', 'startMillis': 0, 'endMillis': 1000}
              ]
            }
          },
        }));
    await expectLater(
        ConfigurationImporter(
                sourceRepository: sources,
                tmdbCredentialManager: tmdbManager,
                userDataStore: store)
            .apply(config),
        throwsA(isA<ConfigurationImportException>()));
    expect(store.value.toJson(), previous.toJson());
    expect(tmdbManager.read(), 'old-key');
  });
}

class _UserDataStore implements ConfigurationUserDataStore {
  _UserDataStore(this.value);
  PortableUserData value;
  bool failNextWrite = false;
  @override
  Future<PortableUserData> capture() async => value;
  @override
  Future<void> replace(PortableUserData data) async {
    value = data;
    if (failNextWrite) {
      failNextWrite = false;
      throw StateError('模拟部分写入失败');
    }
  }
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
