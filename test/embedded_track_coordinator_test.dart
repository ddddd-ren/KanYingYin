import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/features/player/application/embedded_track_coordinator.dart';
import 'package:kanyingyin/features/player/application/embedded_track_language_preferences.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';

void main() {
  late Directory directory;
  late Box<Object?> box;

  setUpAll(() async {
    directory = await Directory.systemTemp.createTemp('track-coordinator');
    Hive.init(directory.path);
    box = await Hive.openBox<Object?>('settings');
  });

  tearDownAll(() async {
    await box.close();
    await directory.delete(recursive: true);
  });

  setUp(() => box.clear());

  test('旧媒体生命周期的语言确认不会写入新媒体', () async {
    final coordinator = EmbeddedTrackCoordinator(
      EmbeddedTrackLanguagePreferences(storage: box),
    );
    final oldSession = coordinator.beginMedia('old-media');
    coordinator.beginMedia('new-media');

    final saved = await coordinator.saveChoice(
      session: oldSession,
      track: _track,
      choice: const TrackLanguageChoice(
        code: 'zh',
        label: '中文',
        kind: TrackLanguageKind.simplifiedChinese,
        source: TrackLanguageSource.user,
      ),
    );

    expect(saved, isFalse);
    expect(coordinator.loadChoice(_track), isNull);
  });

  test('当前媒体语言确认可按指纹读取', () async {
    final coordinator = EmbeddedTrackCoordinator(
      EmbeddedTrackLanguagePreferences(storage: box),
    );
    final session = coordinator.beginMedia('media');
    const choice = TrackLanguageChoice(
      code: 'ja',
      label: '日语',
      kind: TrackLanguageKind.japanese,
      source: TrackLanguageSource.user,
    );

    expect(
      await coordinator.saveChoice(
        session: session,
        track: _track,
        choice: choice,
      ),
      isTrue,
    );
    expect(coordinator.loadChoice(_track)?.code, 'ja');
  });
}

const _track = EmbeddedTrackInfo(
  id: '1',
  type: EmbeddedTrackType.audio,
  kind: TrackLanguageKind.unknown,
  language: TrackLanguageChoice(
    code: 'und',
    label: '未知',
    kind: TrackLanguageKind.unknown,
    source: TrackLanguageSource.unresolved,
  ),
  primaryLabel: '音轨 1',
  detailLabel: 'AAC',
  originalTitle: 'Main',
  originalCodec: 'aac',
);
