import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_ce/hive.dart';
import 'package:kanyingyin/legacy/hive/legacy_bangumi_tag_adapter.dart';
import 'package:kanyingyin/legacy/hive/legacy_playback_media_item_adapter.dart';
import 'package:kanyingyin/modules/video/playback_media_item.dart';

void main() {
  late Directory temp;

  setUpAll(() {
    temp = Directory.systemTemp.createTempSync('kanyingyin-hive-');
    Hive.init(temp.path);
    Hive.registerAdapter(LegacyBangumiTagAdapter());
    Hive.registerAdapter(LegacyPlaybackMediaItemAdapter());
  });

  tearDownAll(() async {
    await Hive.close();
    await temp.delete(recursive: true);
  });

  test('兼容适配器继续占用已发布 typeId', () {
    expect(LegacyPlaybackMediaItemAdapter().typeId, 0);
    expect(LegacyBangumiTagAdapter().typeId, 4);
  });

  test('中性播放条目可以通过旧 typeId 往返', () async {
    final box = await Hive.openBox<Object?>('legacy-media');
    const item = PlaybackMediaItem(
      id: 42,
      title: '原始标题',
      displayTitle: '中文标题',
      summary: '简介',
      artworkUrl: 'poster.jpg',
    );
    await box.put('item', item);
    expect(box.get('item'), item);
  });
}
