import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/services/cloud/cloud_media_library.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_resolver.dart';
import 'package:kanyingyin/bean/card/bangumi_history_card.dart';

void main() {
  final availableEpisode = MediaLibraryEpisode.cloud(
    stableId: 'episode-1',
    name: 'E01',
    sourceId: 'source-a',
    sourceName: '家庭网盘',
    isAvailable: true,
    remotePath: '/Show/E01.mkv',
  );
  final availableSeries = MediaLibrarySeries(
    key: 'source-a|show',
    seriesKey: 'Show',
    title: 'Show',
    sourceKind: MediaSourceKind.cloud,
    sourceId: 'source-a',
    sourceName: '家庭网盘',
    isAvailable: true,
    episodes: [availableEpisode],
  );

  test('云历史根据来源和索引显示可用而不检查本地文件', () {
    final status = resolveHistoryMediaAvailability(
      sourceType: 'cloud',
      sourceIdentity: cloudHistoryIdentity('source-a', '/Show/E01.mkv'),
      cloudSeries: [availableSeries],
    );

    expect(status, HistoryMediaAvailability.cloudAvailable);
    expect(historyMediaAvailabilityLabel(status), '网盘文件');
  });

  test('云来源不可用时显示网盘离线而不是文件丢失', () {
    final status = resolveHistoryMediaAvailability(
      sourceType: 'cloud',
      sourceIdentity: cloudHistoryIdentity('source-b', '/Show/E01.mkv'),
      cloudSeries: [availableSeries],
    );

    expect(status, HistoryMediaAvailability.cloudOffline);
    expect(historyMediaAvailabilityLabel(status), '网盘离线');
  });

  test('旧记录即使来源类型缺失也按 cloud 身份判断而不检查本地文件', () {
    final status = resolveHistoryMediaAvailability(
      sourceType: 'online',
      sourceIdentity: cloudHistoryIdentity('source-a', '/Show/E01.mkv'),
      cloudSeries: [availableSeries],
    );

    expect(status, HistoryMediaAvailability.cloudAvailable);
    expect(historyMediaAvailabilityLabel(status), '网盘文件');
  });
}
