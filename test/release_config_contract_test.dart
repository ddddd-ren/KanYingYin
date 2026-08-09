import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _posterProxyCopy =
    '改善 TMDB 海报的网络连接。部分网络可以正常获取影片资料，但无法直接下载海报；遇到这种情况时，可保持 Clash Verge 等本机代理在后台运行，并选择能够访问 TMDB 图片的节点。关闭系统代理不影响已经运行的本机代理，但完全退出代理软件后，海报可能再次无法加载。';

void main() {
  test('当前发布配置为 Windows 一点零八正式版且 Android 本轮不打包', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final releaseNotes = File('RELEASE_NOTES.md').readAsStringSync();
    final updateDialogCopy = File('UPDATE_DIALOG_COPY.md').readAsStringSync();
    final releaseNotesStart = releaseNotes.indexOf('## 1.0.8+10008');
    final releaseNotesEnd = releaseNotes.indexOf('\n## 2.1.158+20158');
    final currentReleaseNotes =
        releaseNotesStart >= 0 && releaseNotesEnd > releaseNotesStart
            ? releaseNotes.substring(releaseNotesStart, releaseNotesEnd)
            : '';

    expect(pubspec, contains('version: 1.0.8+10008'));
    expect(pubspec, contains('msix_version: 1.0.8.0'));
    expect(currentReleaseNotes, contains('Windows 正式版'));
    expect(currentReleaseNotes, contains('1.0.8'));
    expect(currentReleaseNotes, contains('1.0.4'));
    expect(
      currentReleaseNotes,
      contains('Android 当前版本：1.0.4 (10004，本轮不打包)'),
    );
    expect(currentReleaseNotes, contains('Windows'));
    expect(currentReleaseNotes, contains('TMDB 海报'));
    expect(currentReleaseNotes, contains('手动匹配'));
    expect(currentReleaseNotes, contains('代理'));
    expect(currentReleaseNotes, contains('不会修改、删除、改名或移动'));
    expect(currentReleaseNotes, contains('EXE'));
    expect(currentReleaseNotes, contains(_posterProxyCopy));
    expect(updateDialogCopy, contains('Windows 正式版 EXE'));
    expect(
      updateDialogCopy,
      contains('本轮交付：仅 Windows 正式版 EXE；不打包 Android'),
    );
    expect(updateDialogCopy, contains('1.0.8'));
    expect(updateDialogCopy, contains('1.0.4'));
    expect(updateDialogCopy, contains('10004'));
    expect(updateDialogCopy, contains(_posterProxyCopy));
    for (final tvOnlyText in <String>[
      'Android TV',
      'tvTest',
      '遥控器',
      '手机扫码配置',
      '海信',
    ]) {
      expect(currentReleaseNotes, isNot(contains(tvOnlyText)));
    }
  });

  test('直接依赖使用与锁文件兼容的明确约束', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();

    expect(pubspec, contains('synchronized: ^3.4.0'));
    expect(pubspec, contains('material_color_utilities: ^0.13.0'));
    expect(pubspec, contains('path: ^1.9.1'));
    expect(
      RegExp(
        r'^\s+(synchronized|material_color_utilities|path):\s+any\s*$',
        multiLine: true,
      ).hasMatch(pubspec),
      isFalse,
    );
  });

  test('分析器启用全部严格类型检查', () {
    final options = File('analysis_options.yaml').readAsStringSync();

    expect(options, contains('strict-casts: true'));
    expect(options, contains('strict-inference: true'));
    expect(options, contains('strict-raw-types: true'));
  });

  test('仓库不保存本机证书路径且默认发布使用 EXE 构建脚本', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final readme = File('README.md').readAsStringSync();

    expect(pubspec, isNot(contains('certificate_path:')));
    expect(pubspec, contains('sign_msix: false'));
    expect(readme, contains('tool\\windows\\build_exe_release.ps1'));
    expect(readme, isNot(contains('--certificate-password')));
  });
}
