import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/player/application/embedded_track_language_preferences.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:kanyingyin/utils/storage.dart';

void main() {
  late Directory directory;
  late Box<Object?> box;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('track-language');
    Hive.init(directory.path);
    box = await Hive.openBox<Object?>('settings');
  });

  tearDown(() async {
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test('轨道语言指纹稳定且不包含原始路径', () {
    final key = embeddedTrackLanguageFingerprint(
      mediaKey: r'D:\私密\电影.mkv',
      type: EmbeddedTrackType.subtitle,
      trackId: '1',
      codec: 'ass',
      title: '简中',
    );
    expect(key, hasLength(64));
    expect(key, isNot(contains('私密')));
    expect(
      key,
      embeddedTrackLanguageFingerprint(
        mediaKey: r'D:\私密\电影.mkv',
        type: EmbeddedTrackType.subtitle,
        trackId: '1',
        codec: 'ass',
        title: '简中',
      ),
    );
  });

  test('保存加载自定义语言并忽略损坏记录', () async {
    final preferences = EmbeddedTrackLanguagePreferences(storage: box);
    const choice = TrackLanguageChoice(
      code: 'custom:elvish',
      label: '精灵语',
      kind: TrackLanguageKind.other,
      source: TrackLanguageSource.user,
    );
    await preferences.save('fingerprint', choice);
    expect(preferences.load('fingerprint')?.label, '精灵语');

    await box.put(
      SettingBoxKey.embeddedTrackLanguageOverrides,
      <String, Object?>{'broken': 1},
    );
    expect(preferences.load('broken'), isNull);
  });
}
