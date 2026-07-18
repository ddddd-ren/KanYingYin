import 'dart:io';

import 'package:flutter/material.dart';
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
    expect(source, contains('PlayerOverlayPresenter'));
    expect(source, contains('_overlayCoordinator.openVideoInfo()'));
    expect(source, isNot(contains('showModalBottomSheet<void>')));
  });

  testWidgets('打开视频信息状态后显示 BottomSheet', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    expect(find.text('视频详情'), findsOneWidget);
    c.dispose();
  });

  testWidgets('打开字幕设置时自动关闭视频信息 BottomSheet', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    c.openSubtitleSettings();
    await tester.pumpAndSettle();
    expect(find.text('视频详情'), findsNothing);
    expect(c.visible, PlayerOverlay.subtitleSettings);
    c.dispose();
  });

  testWidgets('用户关闭 BottomSheet 后状态同步为 none', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.text('视频详情'))).pop();
    await tester.pumpAndSettle();
    expect(c.visible, PlayerOverlay.none);
    c.dispose();
  });

  testWidgets('presenter dispose 时 BottomSheet future 安全完成', (tester) async {
    final c = PlayerOverlayCoordinator();
    await tester.pumpWidget(_presenterHost(c));
    c.openVideoInfo();
    await tester.pumpAndSettle();
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    c.dispose();
  });
}

Widget _presenterHost(PlayerOverlayCoordinator coordinator) {
  return MaterialApp(
    home: Scaffold(
      body: PlayerOverlayPresenter(
        coordinator: coordinator,
        videoInfoBuilder: (_) => const Text('视频详情'),
        child: const Text('播放器'),
      ),
    ),
  );
}
