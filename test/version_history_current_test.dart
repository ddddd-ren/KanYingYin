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

  test('历史版本默认保持正式版兼容语义', () {
    const entry =
        VersionHistory(version: '1.0.0', date: '2026-01-01', changes: []);

    expect(entry.isPrerelease, isFalse);
    expect(entry.releaseLabel, '正式版');
  });
}
