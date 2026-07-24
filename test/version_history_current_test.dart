import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:kanyingyin/pages/init_page.dart';
import 'package:kanyingyin/utils/version_history.dart';

void main() {
  test('二点一四十九说明 Anime4K 效率档使用官方快速组合', () {
    final entries = versionHistoryForCurrent('2.1.49');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('效率档'));
    expect(changes, contains('官方快速组合'));
    expect(changes, contains('动画画质增强'));
    expect(changes, contains('显卡'));
  });

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

  test('二点一十七说明按文件夹识别剧名和季度', () {
    final entries = versionHistoryForCurrent('2.1.17');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('文件夹'));
    expect(changes, contains('季度'));
    expect(changes, contains('文件名'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一十八说明每季海报虚拟名称和网盘安全边界', () {
    final entries = versionHistoryForCurrent('2.1.18');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('每一季'));
    expect(changes, contains('海报'));
    expect(changes, contains('剧名'));
    expect(changes, contains('纯数字'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一十九说明修复网盘集数和选集空白', () {
    final entries = versionHistoryForCurrent('2.1.19');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('内嵌中字'));
    expect(changes, contains('集数'));
    expect(changes, contains('选集'));
    expect(changes, contains('自动重新识别'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十说明修复媒体根目录识别', () {
    final entries = versionHistoryForCurrent('2.1.20');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('媒体根目录'));
    expect(changes, contains('高码率'));
    expect(changes, contains('第 3 季'));
    expect(changes, contains('重复卡片'));
    expect(changes, contains('自动重新识别'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十一说明多版本归并手动确认和固定海报尺寸', () {
    final entries = versionHistoryForCurrent('2.1.21');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('多版本'));
    expect(changes, contains('唯一集数'));
    expect(changes, contains('手动确认'));
    expect(changes, contains('海报尺寸'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十二说明重复集号和本地海报尺寸', () {
    final entries = versionHistoryForCurrent('2.1.22');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('同一集'));
    expect(changes, contains('本地海报墙'));
    expect(changes, contains('海报尺寸'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十三说明网盘目录实时刷新和旧资源隐藏', () {
    final entries = versionHistoryForCurrent('2.1.23');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('目录'));
    expect(changes, contains('实时'));
    expect(changes, contains('旧资源'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十五说明夸克播放和季度完整选集', () {
    final entries = versionHistoryForCurrent('2.1.25');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('夸克'));
    expect(changes, contains('播放'));
    expect(changes, contains('当前季度'));
    expect(changes, contains('完整选集'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十六说明夸克播放 Cookie 自动更新', () {
    final entries = versionHistoryForCurrent('2.1.26');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('夸克'));
    expect(changes, contains('播放'));
    expect(changes, contains('Cookie'));
    expect(changes, contains('刷新'));
    expect(changes, contains('官方'));
    expect(changes, contains('不会修改网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十七说明夸克分段预读和播放状态', () {
    final entries = versionHistoryForCurrent('2.1.27');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('分段预读'));
    expect(changes, contains('4K'));
    expect(changes, contains('重新连接'));
    expect(changes, contains('速度不足'));
    expect(changes, contains('256 MB'));
    expect(changes, contains('不会修改夸克文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十八说明百度官方授权分段播放和私人安装包', () {
    final entries = versionHistoryForCurrent('2.1.28');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('百度网盘'));
    expect(changes, contains('官方授权'));
    expect(changes, contains('分段播放'));
    expect(changes, contains('内置默认 TMDB Key'));
    expect(changes, contains('私人安装包'));
    expect(changes, contains('不会修改百度网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一二十九说明百度播放修复和本地分季海报', () {
    final entries = versionHistoryForCurrent('2.1.29');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('百度网盘视频'));
    expect(changes, contains('解析或加载失败'));
    expect(changes, contains('本地电视剧'));
    expect(changes, contains('对应季海报'));
    expect(changes, contains('不会修改百度网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十说明百度文件详情兼容和当前版本展示', () {
    final entries = versionHistoryForCurrent('2.1.30');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('百度网盘'));
    expect(changes, contains('文件详情'));
    expect(changes, contains('当前版本'));
    expect(changes, contains('清除缓存'));
    expect(changes, contains('不会修改百度网盘文件'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十一说明安全存储、日志缓存和Windows集成优化', () {
    final entries = versionHistoryForCurrent('2.1.31');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('TMDB Key'));
    expect(changes, contains('安全存储'));
    expect(changes, contains('日志'));
    expect(changes, contains('缓存'));
    expect(changes, contains('外部播放器'));
    expect(changes, contains('快捷方式'));
    expect(changes, contains('不会删除本地视频'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十二说明本地网盘刮削统一和旧结果保护', () {
    final entries = versionHistoryForCurrent('2.1.32');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('本地与网盘'));
    expect(changes, contains('TMDB'));
    expect(changes, contains('手动'));
    expect(changes, contains('需要确认'));
    expect(changes, contains('断网'));
    expect(changes, contains('不会修改'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十三说明季度海报、悬停标签和本地刮削对话框', () {
    final entries = versionHistoryForCurrent('2.1.33');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('季度海报'));
    expect(changes, contains('鼠标'));
    expect(changes, contains('TMDB 刮削'));
    expect(changes, contains('重新匹配'));
    expect(changes, contains('不会修改'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十四说明证书校验、发布流水线和依赖优化', () {
    final entries = versionHistoryForCurrent('2.1.34');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('证书校验'));
    expect(changes, contains('发布流水线'));
    expect(changes, contains('依赖'));
    expect(changes, contains('不会修改'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一三十五说明安装版本检查和安装包验证', () {
    final entries = versionHistoryForCurrent('2.1.35');

    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(changes, contains('已安装版本'));
    expect(changes, contains('签名 MSIX'));
    expect(changes, contains('清单版本'));
    expect(changes, contains('不会修改'));
    expect(entries.single.isPrerelease, isTrue);
  });

  test('二点一四十四说明夸克转存目录与扫描联动', () {
    final entries = versionHistoryForCurrent('2.1.44');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('转存目录'));
    expect(changes, contains('媒体根目录'));
    expect(changes, contains('扫描'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一四十五说明夸克旧转存目录扫描自愈', () {
    final entries = versionHistoryForCurrent('2.1.45');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('默认转存目录'));
    expect(changes, contains('下次扫描时自动补齐'));
    expect(changes, contains('不记录 Cookie'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一四十六继续修复夸克默认转存目录漏扫', () {
    final entries = versionHistoryForCurrent('2.1.46');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('默认转存目录'));
    expect(changes, contains('自动检查并补齐'));
    expect(changes, contains('不记录 Cookie'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一四十七修复夸克旧 ID 和取消状态', () {
    final entries = versionHistoryForCurrent('2.1.47');

    expect(entries, hasLength(1));
    final entry = entries.single;
    final changes = entry.changes.join('\n');
    expect(entry.isPrerelease, isTrue);
    expect(changes, contains('默认转存目录'));
    expect(changes, contains('旧远程 ID'));
    expect(changes, contains('不再残留“正在扫描”'));
    expect(changes, contains('不会修改网盘文件'));
  });

  test('二点一四十八收敛 Windows 网盘入口和 Anime4K', () {
    final entries = versionHistoryForCurrent('2.1.48');
    expect(entries, hasLength(1));
    final changes = entries.single.changes.join('\n');
    expect(entries.single.isPrerelease, isTrue);
    expect(changes, contains('百度'));
    expect(changes, contains('Windows'));
    expect(changes, contains('Anime4K'));
    expect(changes, contains('不会修改或删除'));
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
