import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/local/local_episode.dart';
import 'package:kanyingyin/modules/video/local_playback_session.dart';

void main() {
  test('会话使用本地剧集定位当前集', () {
    final episodes = [
      const LocalEpisode(
        id: 'e1',
        path: r'D:\Video\01.mkv',
        title: '第1集',
        episodeNumber: 1,
      ),
      const LocalEpisode(
        id: 'e2',
        path: r'D:\Video\02.mkv',
        title: '第2集',
        episodeNumber: 2,
      ),
    ];
    final session = LocalPlaybackSession(
      seriesId: 'series',
      seriesTitle: '测试动画',
      episodes: episodes,
      currentEpisodeId: 'e2',
    );

    expect(session.currentIndex, 1);
    expect(session.currentEpisode.path, r'D:\Video\02.mkv');
    expect(session.previousEpisode?.id, 'e1');
    expect(session.nextEpisode, isNull);
  });

  test('当前剧集必须存在于播放列表', () {
    expect(
      () => LocalPlaybackSession(
        seriesId: 'series',
        seriesTitle: '测试动画',
        episodes: const [
          LocalEpisode(id: 'e1', path: '01.mkv', title: '第1集'),
        ],
        currentEpisodeId: 'missing',
      ),
      throwsArgumentError,
    );
  });
}
