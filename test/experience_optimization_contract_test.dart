import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('设置页返回时使用导航配置解析媒体库索引', () {
    final source = File('lib/pages/my/my_page.dart').readAsStringSync();

    expect(
      source,
      matches(
        RegExp(
          r'updateSelectedIndex\(\s*resolveNavigationIndex\(defaultStartupPage\),?\s*\)',
        ),
      ),
    );
    expect(source, isNot(contains('updateSelectedIndex(0)')));
  });

  test('播放器失败状态提供明确重试动作且顶部图标含语义', () {
    final source = File('lib/pages/video/video_page.dart').readAsStringSync();

    expect(
      source,
      matches(
        RegExp(r"ValueKey<String>\(\s*'video-playback-retry'\s*\)"),
      ),
    );
    expect(source, contains("Text('重试播放')"));
    for (final tooltip in <String>['返回', '重新加载', '选集']) {
      expect(source, contains("tooltip: '$tooltip'"));
    }
    expect(source, isNot(contains('Icons.bug_report')));
  });

  test('播放器构建过程不重复调度选集定位', () {
    final source = File('lib/pages/video/video_page.dart').readAsStringSync();
    final buildStart = source.indexOf('Widget build(BuildContext context)');
    final bodyStart =
        source.indexOf('return AndroidPlaybackSystemUiSurface', buildStart);
    final buildPreamble = source.substring(buildStart, bodyStart);

    expect(buildPreamble, isNot(contains('addPostFrameCallback')));
  });

  test('集合首次加载复用与最终布局对应的骨架', () {
    final category = File(
      'lib/features/library/presentation/media_category_page.dart',
    ).readAsStringSync();
    final cloud = File(
      'lib/pages/cloud/resources/cloud_resources_page.dart',
    ).readAsStringSync();
    final history = File(
      'lib/features/history/presentation/history_page.dart',
    ).readAsStringSync();
    final cloudSettings = File(
      'lib/pages/settings/cloud_sources_settings.dart',
    ).readAsStringSync();

    expect(category, contains('MediaCardSkeletonGrid('));
    expect(cloud, contains('MediaCardSkeletonGrid('));
    expect(history, contains('ListTileSkeleton('));
    expect(cloudSettings, contains('ListTileSkeleton('));
  });

  test('异步移除和清空操作在确认弹窗内完成', () {
    final dialog = File(
      'lib/bean/dialog/async_confirmation_dialog.dart',
    );
    final local = File('lib/pages/local/local_page.dart').readAsStringSync();
    final cloud = File(
      'lib/pages/cloud/resources/cloud_resources_page.dart',
    ).readAsStringSync();
    final history = File(
      'lib/features/history/presentation/history_page.dart',
    ).readAsStringSync();

    expect(dialog.existsSync(), isTrue);
    expect(local, contains('AsyncConfirmationDialog('));
    expect(cloud, contains('AsyncConfirmationDialog('));
    expect(history, contains('AsyncConfirmationDialog('));
  });
}
