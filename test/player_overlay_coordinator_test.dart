import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kanyingyin/features/player/presentation/player_overlay_coordinator.dart';

void main() {
  test('浮层互斥并支持切换', () {
    final c = PlayerOverlayCoordinator();
    expect(c.visible, PlayerOverlay.none);
    c.openSubtitleSettings();
    expect(c.visible, PlayerOverlay.subtitleSettings);
    c.open(PlayerOverlay.videoInfo);
    expect(c.visible, PlayerOverlay.videoInfo);
    c.toggle(PlayerOverlay.videoInfo);
    expect(c.visible, PlayerOverlay.none);
    c.dispose();
  });

  test('视频信息浮层提供独立公开方法', () {
    final c = PlayerOverlayCoordinator();
    c.openVideoInfo();
    expect(c.visible, PlayerOverlay.videoInfo);
    c.toggleVideoInfo();
    expect(c.visible, PlayerOverlay.none);
    c.openVideoInfo();
    c.closeVideoInfo();
    expect(c.visible, PlayerOverlay.none);
    c.dispose();
  });

  test('dispose 后不再通知', () {
    final c = PlayerOverlayCoordinator();
    var count = 0;
    c.addListener(() => count++);
    c.dispose();
    c.openSubtitleSettings();
    expect(count, 0);
  });

  test('PlayerItem 实际使用浮层协调器', () {
    final source = File('lib/pages/player/player_item.dart').readAsStringSync();
    expect(source, contains('PlayerOverlayCoordinator'));
    expect(source, contains('_overlayCoordinator.openSubtitleSettings()'));
    expect(source, contains('_overlayCoordinator.openVideoInfo()'));
    expect(source, contains('_overlayCoordinator.closeVideoInfo()'));
  });
}
