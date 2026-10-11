import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_user_data_store.dart';
import 'package:kanyingyin/features/configuration_transfer/application/configuration_importer.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_user_data.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state.dart';
import 'package:kanyingyin/features/library/application/media_library_user_state_repository.dart';
import 'package:kanyingyin/features/settings/application/typed_settings.dart';
import 'package:kanyingyin/repositories/cloud_source_repository.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/services/tmdb/tmdb_credential_manager.dart';

void main() {
  test('设置仓储保存、读取与恢复 P1 全部用户数据', () async {
    final root = await Directory.systemTemp.createTemp('kanyingyin-p1-backup-');
    Hive.init(root.path);
    final box = await Hive.openBox<Object?>('settings');
    addTearDown(() async {
      await Hive.close();
      await root.delete(recursive: true);
    });
    final store = SettingsConfigurationUserDataStore(TypedSettings(box));
    final changes = MediaLibraryUserStateRepository.changes.value;
    final initial = await store.capture();
    expect(initial.classificationMode, 'conservative');
    expect(box.get(SettingBoxKey.mediaClassificationMode), isNull);
    expect(MediaLibraryUserStateRepository.changes.value, changes);
    final data = PortableUserData.fromJson({
      'states': {
        'work': {
          'categoryOverride': ['电影', '动漫'],
          'genreOverride': <String>[],
        }
      },
      'classificationMode': 'manual',
      'timelineSegments': {
        'local|a': {
          'fingerprint': 'size:time',
          'durationMillis': 100000,
          'segments': [
            {'kind': 'intro', 'startMillis': 0, 'endMillis': 1000}
          ]
        }
      },
      'watchStates': {
        'source|a': {
          'watched': true,
          'positionMillis': 100000,
          'durationMillis': 100000,
          'updatedAtMillis': 1
        }
      },
      'trackPreferences': {
        'cloud|source|作品': {
          'subtitle': {'code': 'off', 'kind': 'other', 'label': '关闭字幕'}
        }
      },
      'preferredAudioLanguage': 'ja',
      'preferredSubtitleLanguage': 'auto',
    });
    await store.replace(data);
    expect((await store.capture()).toJson(), data.toJson());
    expect(MediaLibraryUserStateRepository.changes.value, changes + 1);
    await store.replace(initial);
    expect((await store.capture()).toJson(), initial.toJson());
    expect(MediaLibraryUserStateRepository.changes.value, changes + 2);
    expect(box.get(SettingBoxKey.preferredAudioLanguage), isNull);
  });

  test('旧包缺少分类模式时保留本机模式，显式替换允许覆盖人工分类', () async {
    final root = await Directory.systemTemp.createTemp('kanyingyin-mode-backup-');
    Hive.init(root.path);
    final box = await Hive.openBox<Object?>('settings');
    addTearDown(() async {
      await Hive.close();
      await root.delete(recursive: true);
    });
    final store = SettingsConfigurationUserDataStore(TypedSettings(box));
    await box.put(SettingBoxKey.mediaClassificationMode, 'manual');
    await box.put(SettingBoxKey.mediaLibraryUserStates, {
      'work': {'categoryOverride': ['电影']}
    });
    await store.replace(PortableUserData.fromJson({
      'states': {
        'work': {'categoryOverride': <String>[]}
      }
    }));
    expect((await store.capture()).classificationMode, 'manual');
    expect((await store.capture()).states['work']!.categoryOverride, <String>[]);
  });

  test('配置合并遇到人工分类冲突时中文报错且设置凭据均不变', () async {
    final root = await Directory.systemTemp.createTemp('kanyingyin-conflict-');
    Hive.init(root.path);
    final box = await Hive.openBox<Object?>('settings');
    addTearDown(() async {
      await Hive.close();
      await root.delete(recursive: true);
    });
    final store = SettingsConfigurationUserDataStore(TypedSettings(box));
    await store.replace(PortableUserData.fromJson({
      'states': {
        'work': {'categoryOverride': ['电影']}
      },
      'classificationMode': 'manual',
    }));
    final before = (await store.capture()).toJson();
    final credentials = _CountingTmdbStore();
    final tmdb = await _tmdbManager(credentials);
    final importer = ConfigurationImporter(
      sourceRepository: CloudSourceRepository(
          storage: MemoryCloudSourceStorage(),
          credentialStore: MemoryCloudCredentialStore()),
      tmdbCredentialManager: tmdb,
      userDataStore: store,
    );
    await expectLater(
        importer.apply(_configuration(PortableUserData.fromJson({
          'states': {
            'work': {'categoryOverride': <String>[]}
          },
          'classificationMode': 'standard',
        }))),
        throwsA(isA<MediaLibraryClassificationConflict>()));
    expect((await store.capture()).toJson(), before);
    expect(tmdb.read(), 'old-test-key');
    expect(credentials.writes, 0);
  });

  for (final classificationMode in [null, 'manual']) {
    test('部分写入失败回滚人工覆盖、清空状态与${classificationMode ?? '默认'}模式', () async {
      final root = await Directory.systemTemp.createTemp('kanyingyin-rollback-');
      Hive.init(root.path);
      final box = await Hive.openBox<Object?>('settings');
      addTearDown(() async {
        await Hive.close();
        await root.delete(recursive: true);
      });
      final settings = _FailOnceSettings(box);
      final store = SettingsConfigurationUserDataStore(settings);
      await store.replace(PortableUserData.fromJson({
        'states': {
          'work': {
            'categoryOverride': <String>[],
            'genreOverride': ['科幻']
          }
        },
        if (classificationMode != null) 'classificationMode': classificationMode,
      }));
      final before = (await store.capture()).toJson();
      expect(before['classificationMode'], classificationMode ?? 'conservative');
      final tmdb = await _tmdbManager();
      final importer = ConfigurationImporter(
        sourceRepository: CloudSourceRepository(
            storage: MemoryCloudSourceStorage(),
            credentialStore: MemoryCloudCredentialStore()),
        tmdbCredentialManager: tmdb,
        userDataStore: store,
      );
      settings.failKey = SettingBoxKey.mediaClassificationMode;
      await expectLater(
          importer.apply(_configuration(PortableUserData.fromJson({
            'states': {
              'other': {'categoryOverride': ['动漫']}
            },
            'classificationMode': 'standard',
          }))),
          throwsA(isA<ConfigurationImportException>()));
      expect((await store.capture()).toJson(), before);
      expect(tmdb.read(), 'old-test-key');
    });
  }
}

Future<TmdbCredentialManager> _tmdbManager([TmdbCredentialStore? store]) async {
  final manager = TmdbCredentialManager(
      store: store ?? MemoryTmdbCredentialStore('old-test-key'),
      legacyReader: () => '',
      legacyDelete: () async {},
      warningLogger: (_) {});
  await manager.initialize();
  return manager;
}

PortableAppConfiguration _configuration(PortableUserData data) =>
    PortableAppConfiguration.create(
        exportedAt: DateTime.utc(2026),
        appVersion: '2.1.220',
        tmdbApiKey: 'new-test-key',
        cloudSources: [],
        userData: data);

class _FailOnceSettings extends TypedSettings {
  _FailOnceSettings(super.box);

  String? failKey;

  @override
  Future<void> write<T>(String key, T value) async {
    await super.write(key, value);
    if (key == failKey) {
      failKey = null;
      throw StateError('模拟部分设置写入失败');
    }
  }
}

class _CountingTmdbStore extends MemoryTmdbCredentialStore {
  _CountingTmdbStore() : super('old-test-key');

  int writes = 0;

  @override
  Future<void> write(String value) async {
    writes++;
    await super.write(value);
  }
}
