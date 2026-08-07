import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/utils/version_history.dart';

void main() {
  test('当前版本文案说明 Android TV 布局、焦点、返回和文件识别', () {
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final currentSection = _markdownVersionSection(
      releaseNotes,
      '2.1.144+20144',
    );
    final currentHistory = versionHistoryForCurrent('2.1.144');

    expect(currentHistory, hasLength(1));
    final historyText = currentHistory.single.changes.join('\n');
    for (final text in <String>[
      'Android TV/Google TV',
      'tvTest',
      '遥控器',
      '焦点',
      '同一局域网',
      '手机扫码配置',
      'OpenList',
      '夸克',
      '百度',
      '迅雷',
      '.kyyconfig',
      '.kyymeta',
      '系统文件选择器',
      '海报墙',
      '侧边导航栏',
      '闭环焦点组',
      '弹窗',
      '播放控制层',
      '文件显示名',
      '文档 URI',
      '实机验收未完成',
    ]) {
      expect(currentSection, contains(text), reason: 'RELEASE_NOTES 缺少 $text');
      expect(historyText, contains(text), reason: '版本历史缺少 $text');
    }
    expect(currentSection, isNot(contains('所有安卓电视')));
    expect(currentSection, isNot(contains('无需同一网络')));
  });

  test('设备矩阵包含完整字段并保留海信待识别状态', () {
    final matrix = File('docs/android-tv-test-matrix.md').readAsStringSync();

    for (final field in <String>[
      '设备型号',
      '系统类型',
      'API',
      'ABI',
      'Leanback',
      'WebView',
      '安装方式',
      '遥控器',
      'SAF',
      '1080p',
      '4K HEVC',
      '字幕',
      '音轨',
      '网盘',
      '息屏恢复',
      '结果',
      '日志路径',
    ]) {
      expect(matrix, contains(field), reason: field);
    }
    expect(matrix, contains('海信'));
    expect(matrix, contains('not_android_verified'));
    expect(matrix, contains('ADB'));
    expect(matrix, isNot(contains('海信电视 | 兼容通过')));
  });
}

String _markdownVersionSection(String source, String version) {
  final marker = '## $version';
  final start = source.indexOf(marker);
  if (start < 0) return '';
  final next = source.indexOf('\n## ', start + marker.length);
  return source.substring(start, next < 0 ? source.length : next);
}
