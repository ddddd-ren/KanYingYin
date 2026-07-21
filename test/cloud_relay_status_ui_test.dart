import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/video/cloud_relay_status_presenter.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

void main() {
  test('公共状态展示百度提供方名称和速度', () {
    final presentation = CloudRelayStatusPresenter.present(
      const CloudRangeRelayStatus(
        providerName: '百度网盘',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: 2 * 1024 * 1024,
      ),
    );

    expect(presentation.text, contains('百度网盘'));
    expect(presentation.text, contains('2.0 MB/s'));
    expect(presentation.stable, isTrue);
  });

  test('速度低于媒体平均消耗时显示速度不足和缓存时长', () {
    final presentation = CloudRelayStatusPresenter.present(
      const CloudRangeRelayStatus(
        providerName: '夸克网盘',
        phase: CloudRangeRelayPhase.ready,
        bytesPerSecond: 5 * 1024 * 1024,
        cachedBytes: 20 * 1024 * 1024,
      ),
      totalBytes: 600 * 1024 * 1024,
      mediaDuration: const Duration(seconds: 60),
    );

    expect(presentation.text, contains('当前网盘读取速度不足'));
    expect(presentation.text, contains('缓存 2 秒'));
    expect(presentation.warning, isTrue);
    expect(presentation.stable, isFalse);
  });

  test('播放器页面使用公共中转状态提示', () {
    final page = File('lib/pages/video/video_page.dart').readAsStringSync();
    expect(page, contains('CloudRelayStatusPresenter.present'));
    expect(page, isNot(contains('QuarkRelayStatusPresenter.present')));
  });
}
