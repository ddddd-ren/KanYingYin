import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_bookmark.dart';
import 'package:kanyingyin/features/player/application/track_selection_preferences.dart';
import 'package:kanyingyin/pages/player/models/embedded_track_info.dart';
import 'package:media_kit/media_kit.dart';

void main() {
  test('同目录的不同作品不会共用跨集偏好', () {
    expect(localWorkTrackPreferenceKey('file:d:\\media', '作品一'),
        isNot(localWorkTrackPreferenceKey('file:d:\\media', '作品二')));
    expect(localWorkTrackPreferenceKey('file:d:\\media', '作品一'),
        'local-work|file:d:\\media|${Uri.encodeComponent('作品一')}');
  });
  test('来源作品改名后迁移精确旧键，保留音轨和关闭字幕偏好', () async {
    final storage = _Storage();
    final repo = TrackSelectionPreferences(storage);
    final audio =
        EmbeddedTrackInfo.fromAudio(const AudioTrack('old-id', null, 'ja'));
    await repo.save('cloud|source-a|旧剧名 S01', audio);
    await repo.saveSubtitleOff('cloud|source-a|旧剧名 S01');

    await repo.migrate('cloud-work|source-a|work-1',
        ['cloud|source-a|旧剧名 S01']);

    expect(repo.load('cloud-work|source-a|work-1', EmbeddedTrackType.audio)!.code,
        'ja');
    expect(
        repo.load('cloud-work|source-a|work-1', EmbeddedTrackType.subtitle)!.code,
        'off');
    expect(repo.load('cloud|source-a|旧剧名 S01', EmbeddedTrackType.audio)!.code,
        'ja');
    expect(repo.load('cloud-work|source-b|work-1', EmbeddedTrackType.audio),
        isNull);
  });
  test('稳定作品的新偏好优先，迁移补齐缺失类型并拒绝无效旧数据', () async {
    final storage = _Storage();
    final repo = TrackSelectionPreferences(storage);
    await repo.save('legacy',
        EmbeddedTrackInfo.fromAudio(const AudioTrack('1', null, 'ja')));
    await repo.saveSubtitleOff('legacy');
    await repo.save('work',
        EmbeddedTrackInfo.fromAudio(const AudioTrack('2', null, 'zh')));

    await repo.migrate('work', ['missing', 'legacy']);

    expect(repo.load('work', EmbeddedTrackType.audio)!.code, 'zh');
    expect(repo.load('work', EmbeddedTrackType.subtitle)!.code, 'off');
    storage.value = {
      'bad': {
        'audio': {'code': 'ja'}
      }
    };
    await repo.migrate('work', ['bad']);
    expect(repo.load('work', EmbeddedTrackType.audio), isNull);
    expect((storage.value! as Map).containsKey('work'), isFalse);
  });
  test('跨集只保存语言与类型，作品偏好缺失时回退全局再到底层默认', () async {
    final storage = _Storage();
    final repo = TrackSelectionPreferences(storage);
    final japanese =
        EmbeddedTrackInfo.fromAudio(const AudioTrack('old-id', null, 'ja'));
    await repo.save('work-a', japanese);
    expect(storage.value.toString(), isNot(contains('old-id')));
    final tracks = [
      EmbeddedTrackInfo.fromAudio(const AudioTrack('new-id', null, 'ja')),
      EmbeddedTrackInfo.fromAudio(const AudioTrack('zh-id', null, 'zh'))
    ];
    final global =
        trackLanguageFromMetadata('zh', '', type: EmbeddedTrackType.audio);
    expect(
        selectTrackByPreferences(tracks,
                series: repo.load('work-a', EmbeddedTrackType.audio),
                global: global,
                defaultTrackId: 'zh-id')!
            .id,
        'new-id');
    expect(
        selectTrackByPreferences([tracks.last],
                series: repo.load('work-a', EmbeddedTrackType.audio),
                global: global)!
            .id,
        'zh-id');
    expect(
        selectTrackByPreferences(tracks,
                global: trackLanguageFromMetadata('ko', '',
                    type: EmbeddedTrackType.audio),
                defaultTrackId: 'new-id')!
            .id,
        'new-id');
    expect(repo.load('work-b', EmbeddedTrackType.audio), isNull);
    expect(repo.load('work-a', EmbeddedTrackType.subtitle), isNull);
  });
  test('未识别语言不跨集复用，关闭字幕单独保存', () async {
    final repo = TrackSelectionPreferences(_Storage());
    await repo.save('work-a',
        EmbeddedTrackInfo.fromAudio(const AudioTrack('1', null, null)));
    expect(repo.load('work-a', EmbeddedTrackType.audio), isNull);
    await repo.saveSubtitleOff('work-a');
    expect(repo.load('work-a', EmbeddedTrackType.subtitle)!.code, 'off');
    final tracks = [
      EmbeddedTrackInfo.fromSubtitle(const SubtitleTrack('1', null, 'zh'))
    ];
    expect(
        selectTrackByPreferences(tracks,
            series: repo.load('work-a', EmbeddedTrackType.subtitle),
            defaultTrackId: '1'),
        isNull);
  });
}

class _Storage implements PlayerBookmarkStorage {
  Object? value;
  @override
  Object? read() => value;
  @override
  Future<void> write(Object value) async {
    this.value = value;
  }
}
