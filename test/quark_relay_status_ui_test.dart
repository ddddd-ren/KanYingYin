import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/pages/video/quark_relay_status_presenter.dart';
import 'package:kanyingyin/services/cloud/cloud_playback_transport.dart';

void main() {
  test('预缓冲状态显示实时速度', () {
    final presentation = QuarkRelayStatusPresenter.present(
      const QuarkRelayStatus(
        phase: QuarkRelayPhase.prefetching,
        bytesPerSecond: 12.3 * 1024 * 1024,
      ),
    );

    expect(presentation.text, '夸克预缓冲中 · 12.3 MB/s');
    expect(presentation.stable, isFalse);
  });

  test('速度低于媒体平均消耗时显示速度不足和缓存时长', () {
    final presentation = QuarkRelayStatusPresenter.present(
      const QuarkRelayStatus(
        phase: QuarkRelayPhase.ready,
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

  test('总时长未知时只显示速度且就绪状态可自动隐藏', () {
    final presentation = QuarkRelayStatusPresenter.present(
      const QuarkRelayStatus(
        phase: QuarkRelayPhase.ready,
        bytesPerSecond: 8 * 1024 * 1024,
      ),
    );

    expect(presentation.text, '夸克读取 8.0 MB/s');
    expect(presentation.warning, isFalse);
    expect(presentation.stable, isTrue);
  });

  test('重连和失败状态使用明确文案', () {
    expect(
      QuarkRelayStatusPresenter.present(
        const QuarkRelayStatus(phase: QuarkRelayPhase.reconnecting),
      ).text,
      '夸克正在重新连接',
    );
    expect(
      QuarkRelayStatusPresenter.present(
        const QuarkRelayStatus(phase: QuarkRelayPhase.failed),
      ).text,
      '夸克分段读取失败',
    );
  });

  test('播放器页面复用现有加载层并使用短暂状态提示', () {
    final page = File('lib/pages/video/video_page.dart').readAsStringSync();
    expect(page, contains('CircularProgressIndicator'));
    expect(page, contains('QuarkRelayStatusPresenter.present'));
    expect(page, contains('AnimatedOpacity'));
    expect(page, contains('StyleString.fastAnimationDuration'));
    expect(page, isNot(contains('夸克永久状态栏')));
  });
}
