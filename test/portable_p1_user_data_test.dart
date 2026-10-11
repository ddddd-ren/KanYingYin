import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_user_data.dart';
import 'package:kanyingyin/features/configuration_transfer/domain/portable_app_configuration.dart';

Map<String, Object?> _data({int updated = 1, bool watched = true}) => {
      'timelineSegments': {
        'local|d:\\media\\a.mkv': {
          'fingerprint': 'file:1:2',
          'durationMillis': 100000,
          'segments': [
            {'kind': 'intro', 'startMillis': 0, 'endMillis': 10000}
          ]
        }
      },
      'watchStates': {
        'source|a': {
          'watched': watched,
          'positionMillis': 1000,
          'durationMillis': 100000,
          'updatedAtMillis': updated
        }
      },
      'trackPreferences': {
        'cloud|source|作品': {
          'audio': {'code': 'ja', 'kind': 'japanese', 'label': '日语'}
        }
      },
      'preferredAudioLanguage': 'ja',
    };
void main() {
  test('人工分类、手工清空与分类模式备份往返和重映射不丢失', () {
    final raw = <String, Object?>{
      'states': {
        r'local|d:\media\a.mkv': {
          'categoryOverride': ['电影', '动漫'],
          'genreOverride': <String>[],
          'mediaIds': [r'd:\media\a.mkv'],
        },
      },
      'classificationMode': 'manual',
    };
    final data = PortableUserData.fromJson(raw);
    expect(data.toJson()['states'], raw['states']);
    expect(data.toJson()['classificationMode'], 'manual');
    final mapped = data.remap(localRoots: {r'd:\media': r'e:\videos'});
    final state = mapped.states[r'local|e:\videos\a.mkv']!.toJson();
    expect(state['categoryOverride'], ['电影', '动漫']);
    expect(state['genreOverride'], <String>[]);
    expect(state['mediaIds'], [r'e:\videos\a.mkv']);
    expect(mapped.toJson()['classificationMode'], 'manual');
  });

  test('合并分类按字段保留，旧备份缺模式不抹现有选择', () {
    final existing = PortableUserData.fromJson({
      'states': {
        'work': {'categoryOverride': <String>[]}
      },
      'classificationMode': 'conservative',
    });
    final incoming = PortableUserData.fromJson({
      'states': {
        'work': {'genreOverride': ['科幻']}
      }
    });
    final merged = existing.merge(incoming).toJson();
    expect((merged['states'] as Map)['work']['categoryOverride'], <String>[]);
    expect((merged['states'] as Map)['work']['genreOverride'], ['科幻']);
    expect(merged['classificationMode'], 'conservative');
    expect(incoming.merge(existing).toJson()['states'], merged['states']);
    expect(
        existing
            .merge(PortableUserData.fromJson({'classificationMode': 'manual'}))
            .classificationMode,
        'manual');
  });

  test('备份人工分类冲突拒绝合并且原数据不变', () {
    for (final field in ['categoryOverride', 'genreOverride']) {
      final existing = PortableUserData.fromJson({
        'states': {
          'work': {field: ['电影']}
        }
      });
      final incoming = PortableUserData.fromJson({
        'states': {
          'work': {field: <String>[]}
        }
      });
      final before = existing.toJson();
      expect(() => existing.merge(incoming),
          throwsA(predicate<Object>((error) => error.toString().contains('冲突'))));
      expect(existing.toJson(), before);
    }
  });

  test('相同人工覆盖仅顺序不同仍可合并，手工清空不会变成自动', () {
    final existing = PortableUserData.fromJson({
      'states': {
        'work': {
          'categoryOverride': ['电影', '动漫'],
          'genreOverride': <String>[],
        }
      }
    });
    final incoming = PortableUserData.fromJson({
      'states': {
        'work': {
          'categoryOverride': ['动漫', '电影'],
          'genreOverride': <String>[],
        }
      }
    });
    final state = existing.merge(incoming).states['work']!;
    expect(state.categoryOverride, ['电影', '动漫']);
    expect(state.genreOverride, <String>[]);
  });

  test('备份拒绝未知分类模式和互斥人工分类', () {
    for (final raw in <Map<String, Object?>>[
      {'classificationMode': 'unknown'},
      {'classificationMode': 1},
      {
        'states': {
          'work': {'categoryOverride': ['动漫', '电视剧']}
        }
      },
    ]) {
      expect(() => PortableUserData.fromJson(raw), throwsFormatException);
    }
  });

  test('来源重新对应后稳定作品选轨键同步外层与作品来源身份', () {
    final raw = _data();
    (raw['trackPreferences'] as Map)['cloud-work|source|source|work|root'] = {
      'audio': {'code': 'ja', 'kind': 'japanese', 'label': '日语'}
    };
    final mapped = PortableUserData.fromJson(raw)
        .remap(cloudSources: {'source': 'target'}).toJson();
    expect((mapped['trackPreferences'] as Map).keys,
        contains('cloud-work|target|target|work|root'));
    expect((mapped['trackPreferences'] as Map).keys,
        isNot(contains('cloud-work|source|source|work|root')));
  });

  test('实际播放器的 file 媒体键可迁移到新目录', () {
    final raw = _data();
    final segments = raw['timelineSegments'] as Map;
    segments['local|file:d:\\media\\a.mkv'] =
        segments.remove('local|d:\\media\\a.mkv');
    (raw['trackPreferences'] as Map)['local-work|file:d:\\media|作品'] = {
      'audio': {'code': 'ja', 'kind': 'japanese', 'label': '日语'}
    };
    final mapped = PortableUserData.fromJson(raw)
        .remap(localRoots: {r'd:\media': r'e:\videos'}).toJson();
    expect((mapped['timelineSegments'] as Map).keys,
        ['local|file:e:\\videos\\a.mkv']);
    expect((mapped['trackPreferences'] as Map).keys,
        contains('local-work|file:e:\\videos|作品'));
  });
  test('本地稳定作品选轨键迁移目录时保留原始作品身份', () {
    final raw = _data();
    final title = Uri.encodeComponent('作品原名 s01');
    (raw['trackPreferences'] as Map)['local-work-id|file:d:\\media|$title'] = {
      'audio': {'code': 'ja', 'kind': 'japanese', 'label': '日语'}
    };
    final mapped = PortableUserData.fromJson(raw)
        .remap(localRoots: {r'd:\media': r'e:\videos'}).toJson();
    expect((mapped['trackPreferences'] as Map).keys,
        contains('local-work-id|file:e:\\videos|$title'));
    expect((mapped['trackPreferences'] as Map).keys,
        isNot(contains('local-work-id|file:d:\\media|$title')));
  });
  test('P1 数据往返与目录来源重映射，格式三兼容旧包', () {
    final data = PortableUserData.fromJson(_data());
    expect(data.toJson()['timelineSegments'], _data()['timelineSegments']);
    expect(data.toJson()['watchStates'], _data()['watchStates']);
    final mapped = data.remap(
        localRoots: {r'd:\media': r'e:\videos'},
        cloudSources: {'source': 'target'}).toJson();
    expect(
        (mapped['timelineSegments'] as Map).keys, ['local|e:\\videos\\a.mkv']);
    expect((mapped['watchStates'] as Map).keys, ['target|a']);
    expect((mapped['trackPreferences'] as Map).keys, ['cloud|target|作品']);
    final config = PortableAppConfiguration.create(
            exportedAt: DateTime(2026),
            appVersion: '2.1.220',
            tmdbApiKey: '',
            cloudSources: [],
            userData: data)
        .toJson();
    expect(config['formatVersion'], 3);
    for (final version in [1, 2]) {
      config['formatVersion'] = version;
      expect(PortableAppConfiguration.fromJson(config).userData, isNotNull);
    }
  });
  test('已看采用较新记录，标记冲突保留本机，坏区间拒绝整个导入', () {
    final existing =
        PortableUserData.fromJson(_data(updated: 2, watched: false));
    final incoming = PortableUserData.fromJson(_data());
    expect(
        (existing.merge(incoming).toJson()['watchStates'] as Map)['source|a']
            ['watched'],
        false);
    final bad = _data();
    ((bad['timelineSegments'] as Map).values.single['segments'] as List)
        .single['endMillis'] = 100001;
    expect(() => PortableUserData.fromJson(bad), throwsFormatException);
    final collide = _data();
    (collide['watchStates'] as Map)['target|a'] =
        (collide['watchStates'] as Map)['source|a'];
    expect(
        () => PortableUserData.fromJson(collide)
            .remap(cloudSources: {'source': 'target'}),
        throwsFormatException);
  });
}
