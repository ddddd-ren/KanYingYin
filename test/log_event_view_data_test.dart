import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/logs/presentation/log_event_view_data.dart';

void main() {
  const content = '''
[2026-07-23T10:00:00.000] INFO
[i] 10:00:00 INFO    媒体库扫描完成
[2026-07-23T10:01:00.000] WARNING
┌────────────────
│ 海报请求超时
└────────────────
[2026-07-23T10:02:00.000] ERROR
│ Player failed to open file
│ stack line
[2026-07-23T10:03:00.000] PLAYER
播放器资源已释放
''';

  test('按头部解析、分类并按时间倒序', () {
    final events = LogEventParser.parse(content);

    expect(events, hasLength(4));
    expect(events.map((event) => event.level), [
      'PLAYER',
      'ERROR',
      'WARNING',
      'INFO',
    ]);
    expect(events[0].category, LogEventCategory.normal);
    expect(events[1].category, LogEventCategory.error);
    expect(events[2].category, LogEventCategory.warning);
    expect(events[3].summary, '媒体库扫描完成');
  });

  test('多行事件保留完整脱敏原文', () {
    final warning = LogEventParser.parse(content)[2];

    expect(warning.summary, '海报请求超时');
    expect(warning.rawText, contains('[2026-07-23T10:01:00.000] WARNING'));
    expect(warning.rawText, contains('┌────────────────'));
    expect(warning.rawText, contains('│ 海报请求超时'));
  });

  test('未知格式形成其他记录且不丢失原文', () {
    final events = LogEventParser.parse('孤立记录\n第二行');

    expect(events, hasLength(1));
    expect(events.single.category, LogEventCategory.other);
    expect(events.single.summary, '孤立记录');
    expect(events.single.rawText, '孤立记录\n第二行');
  });

  test('无效时间保留原始相对顺序', () {
    const invalid = '''
[invalid-one] INFO
第一条
[invalid-two] ERROR
第二条
''';
    final events = LogEventParser.parse(invalid);

    expect(events.map((event) => event.summary), ['第一条', '第二条']);
  });

  test('关键词搜索摘要和原文且英文不区分大小写', () {
    final events = LogEventParser.parse(content);

    expect(LogEventQuery.apply(events, query: 'player'), hasLength(2));
    expect(LogEventQuery.apply(events, query: ' 海报请求 '), hasLength(1));
  });

  test('等级筛选与关键词搜索叠加', () {
    final events = LogEventParser.parse(content);

    expect(
      LogEventQuery.apply(
        events,
        filter: LogEventFilter.errors,
        query: 'open file',
      ).single.category,
      LogEventCategory.error,
    );
    expect(
      LogEventQuery.apply(
        events,
        filter: LogEventFilter.warnings,
        query: 'open file',
      ),
      isEmpty,
    );
  });
}
