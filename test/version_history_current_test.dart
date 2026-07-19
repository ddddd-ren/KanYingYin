import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/pages/init_page.dart';
import 'package:kanyingyin/utils/version_history.dart';

void main() {
  test('更新弹窗只返回当前运行版本的文案', () {
    final entries = versionHistoryForCurrent('1.4.10');

    expect(entries, hasLength(1));
    expect(entries.single.version, '1.4.10');
  });

  test('二点零点八说明升级不删除视频文件', () {
    final entries = versionHistoryForCurrent('2.0.8');

    expect(entries, hasLength(1));
    expect(entries.single.changes.join('\n'), contains('不会删除用户的原始视频文件'));
  });

  test('二点零点九显示桌面快捷方式图标修复', () {
    final entries = versionHistoryForCurrent('2.0.9');

    expect(entries, hasLength(1));
    expect(entries.single.changes.join('\n'), contains('桌面快捷方式'));
    expect(entries.single.changes.join('\n'), contains('空白图标'));
    expect(entries.single.changes.join('\n'), contains('自动修复'));
  });

  test('版本历史不存在当前版本时不显示错误的旧版本', () {
    expect(versionHistoryForCurrent('9.9.9'), isEmpty);
  });

  test('二点一十五说明系列继承海报墙过滤和网盘安全边界', () {
    final entries = versionHistoryForCurrent('2.1.15');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('手动匹配'));
    expect(changes, contains('自动继承'));
    expect(changes, contains('海报墙'));
    expect(changes, contains('识别大小'));
    expect(changes, contains('不会修改网盘文件'));
    expect(changes, contains('播放路径'));
  });

  test('二点一十六说明网盘全量海报墙和季度海报', () {
    final entries = versionHistoryForCurrent('2.1.16');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('网盘'));
    expect(changes, contains('海报墙'));
    expect(changes, contains('季度海报'));
    expect(changes, contains('后台扫描'));
    expect(changes, contains('识别大小'));
    expect(changes, contains('不会修改网盘文件'));
  });

  testWidgets('二点一七更新弹窗明确显示自定义剧名安全边界', (tester) async {
    final entries = versionHistoryForCurrent('2.1.7');

    expect(entries.single.isPrerelease, isTrue);
    expect(entries.single.releaseLabel, '测试版');
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.7  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('TMDB'));
    expect(entries.single.changes.join('\n'), contains('网盘'));
    expect(entries.single.changes.join('\n'), contains('修改剧名'));
    expect(entries.single.changes.join('\n'), contains('不会重命名'));
    for (final change in entries.single.changes) {
      expect(find.textContaining(change), findsOneWidget);
    }
  });

  testWidgets('二点一八更新弹窗说明夸克直连播放修复', (tester) async {
    final entries = versionHistoryForCurrent('2.1.8');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.8  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('夸克'));
    expect(entries.single.changes.join('\n'), contains('直连'));
    expect(entries.single.changes.join('\n'), contains('自动刷新'));
    expect(entries.single.changes.join('\n'), contains('OpenList'));
  });

  testWidgets('二点一九更新弹窗说明使用夸克专用播放地址', (tester) async {
    final entries = versionHistoryForCurrent('2.1.9');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.9  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('夸克'));
    expect(entries.single.changes.join('\n'), contains('专用播放接口'));
    expect(entries.single.changes.join('\n'), contains('最高可用清晰度'));
    expect(entries.single.changes.join('\n'), contains('下载直链'));
  });

  testWidgets('二点一十更新弹窗说明季目录可进行 TMDB 刮削', (tester) async {
    final entries = versionHistoryForCurrent('2.1.10');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.10  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('TMDB'));
    expect(entries.single.changes.join('\n'), contains('季目录'));
    expect(entries.single.changes.join('\n'), contains('单集文件名'));
    expect(entries.single.changes.join('\n'), contains('当前目录'));
  });

  testWidgets('二点一十一更新弹窗说明 TMDB 匹配可先确认', (tester) async {
    final entries = versionHistoryForCurrent('2.1.11');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.11  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('搜索词'));
    expect(entries.single.changes.join('\n'), contains('候选'));
    expect(entries.single.changes.join('\n'), contains('不会修改网盘文件'));
    expect(entries.single.changes.join('\n'), contains('批量刮削'));
  });

  testWidgets('二点一十二更新弹窗说明网盘沉浸式海报卡', (tester) async {
    final entries = versionHistoryForCurrent('2.1.12');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.12  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('沉浸式大海报卡片'));
    expect(entries.single.changes.join('\n'), contains('真实网盘名称'));
    expect(entries.single.changes.join('\n'), contains('已确认的字幕状态'));
    expect(entries.single.changes.join('\n'), contains('不会修改任何网盘文件'));
  });

  testWidgets('二点一十三更新弹窗说明过滤发布规格尾缀', (tester) async {
    final entries = versionHistoryForCurrent('2.1.13');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.13  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('2160p'));
    expect(entries.single.changes.join('\n'), contains('HEVC'));
    expect(entries.single.changes.join('\n'), contains('DDP 5.1'));
    expect(entries.single.changes.join('\n'), contains('不会修改网盘文件名'));
  });

  testWidgets('二点一十四更新弹窗说明来源级自动批量整理', (tester) async {
    final entries = versionHistoryForCurrent('2.1.14');

    expect(entries.single.isPrerelease, isTrue);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: VersionChangelogContent(versions: entries)),
    ));

    expect(find.text('v2.1.14  测试版  2026-07-19'), findsOneWidget);
    expect(entries.single.changes.join('\n'), contains('自动整理当前来源'));
    expect(entries.single.changes.join('\n'), contains('递归发现'));
    expect(entries.single.changes.join('\n'), contains('歧义资源保持原名'));
    expect(entries.single.changes.join('\n'), contains('不会修改网盘文件'));
  });

  test('历史版本默认保持正式版兼容语义', () {
    const entry =
        VersionHistory(version: '1.0.0', date: '2026-01-01', changes: []);

    expect(entry.isPrerelease, isFalse);
    expect(entry.releaseLabel, '正式版');
  });
}
