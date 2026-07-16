import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/modules/bangumi/bangumi_item.dart';
import 'package:kanyingyin/modules/history/history_module.dart';

void main() {
  test('History defaults to online source type', () {
    final history = History(
      _bangumiItem(),
      1,
      '在线规则',
      DateTime(2026),
      '/online/source',
      '第1话',
    );

    expect(history.sourceType, HistorySourceType.online.value);
    expect(history.isLocal, isFalse);
  });

  test('History can mark local source type', () {
    final history = History(
      _bangumiItem(),
      1,
      '本地文件',
      DateTime(2026),
      r'D:\Anime\01.mkv',
      '01.mkv',
      sourceType: HistorySourceType.local.value,
    );

    expect(history.isLocal, isTrue);
  });
}

BangumiItem _bangumiItem() {
  return BangumiItem(
    id: 1,
    type: 0,
    name: 'Test',
    nameCn: '测试',
    summary: '',
    airDate: '',
    airWeekday: 0,
    rank: 0,
    images: {},
    tags: [],
    alias: [],
    ratingScore: 0,
    votes: 0,
    votesCount: [],
    info: '',
  );
}
