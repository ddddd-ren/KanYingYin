import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/application/player_chapter.dart';

void main() {
  test('从 mpv 章节属性解析标题和时间', () {
    final chapter = PlayerChapter.fromMpvValues(
      index: 1,
      title: '  第二章  ',
      time: '61.25',
    );

    expect(chapter.index, 1);
    expect(chapter.title, '第二章');
    expect(chapter.position, const Duration(seconds: 61, milliseconds: 250));
  });

  test('章节标题为空时使用序号，时间非法时隔离记录', () {
    final chapter = PlayerChapter.fromMpvValues(
      index: 0,
      title: '',
      time: '0',
    );
    expect(chapter.title, '第 1 章');
    expect(chapter.position, Duration.zero);

    expect(
      () => PlayerChapter.fromMpvValues(
        index: 2,
        title: '损坏',
        time: 'not-a-time',
      ),
      throwsFormatException,
    );
  });
}
