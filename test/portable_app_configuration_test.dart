import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';
import 'package:kanyingyin/modules/cloud/cloud_source.dart';
import 'package:kanyingyin/services/cloud/cloud_credential_store.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_user_data.dart';

void main() {
  test('用户数据备份兼容旧包且目录重映射不误匹配相邻目录', () {
    final legacy = PortableAppConfiguration.create(
      exportedAt: DateTime.utc(2026),
      appVersion: '2.1.219',
      tmdbApiKey: '',
      cloudSources: [],
    ).toJson()
      ..['formatVersion'] = 1;
    legacy.remove('userData');
    expect(PortableAppConfiguration.fromJson(legacy).userData, isNull);
    final data = PortableUserData.fromJson({
      'states': {
        'old': {
          'favorite': true,
          'mediaIds': ['d:\\movies\\a.mp4']
        }
      },
      'bookmarks': {
        'local|d:\\movies\\a.mp4': [
          {'positionMillis': 1000, 'label': '书签'}
        ],
        'local|d:\\movies2\\b.mp4': [
          {'positionMillis': 2000}
        ],
      },
      'history': [],
      'localRoots': ['d:\\movies'],
    });
    final mapped = data.remap(localRoots: {'d:\\movies': 'e:\\videos'});
    expect(mapped.bookmarks.keys, contains('local|e:\\videos\\a.mp4'));
    expect(mapped.bookmarks.keys, contains('local|d:\\movies2\\b.mp4'));
    expect(mapped.states['old']!.mediaIds, ['e:\\videos\\a.mp4']);
    final cloud = PortableUserData.fromJson({
      'bookmarks': {
        'source|source|video': [
          {'positionMillis': 1000}
        ],
        'source|source:video:/folder/video.mp4': [
          {'positionMillis': 2000}
        ],
      }
    }).remap(cloudSources: {'source': 'target'});
    expect(
        cloud.bookmarks.keys,
        containsAll(
            ['target|target|video', 'target|target:video:/folder/video.mp4']));
  });

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
    expect(
        restored.cloudSources.single.source.scanStatus, CloudScanStatus.never);
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
